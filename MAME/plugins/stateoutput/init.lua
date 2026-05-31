-- =========================================================================================
-- MAME STATE OUTPUT PLUGIN CORE
-- Version: 8.2.0
-- Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
-- License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
-- Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
-- =========================================================================================
-- ARCHITECTURE OVERVIEW:
-- This script operates as a native MAME plugin. Unlike standalone Lua scripts, plugins 
-- are loaded once when MAME starts. They run in the background and must actively "hook" 
-- into MAME's event system (like when a game boots, or when a frame renders) to function.
-- =========================================================================================

local exports = {
    name = "stateoutput",
    version = "8.2.0",
    description = "State Output (for 'Hooker' Output Programs)",
    license = "GNU GPL-v3.0",
    author = "Jacob Simpson (DJ GLiTCH)",
    
    -- [ CRITICAL MAME CONCEPT: Persistent Subscriptions ]
    -- In MAME's modern API, event hooks (like add_machine_reset_notifier) return a 
    -- "subscription object". If Lua's Garbage Collector deletes this object, MAME 
    -- instantly stops triggering the hook. By storing them in this global `exports` 
    -- table, we protect them from being deleted while MAME is running.
    subscriptions = {} 
}

local stateoutput = exports

-- =========================================================================
-- USER SETTINGS
-- =========================================================================
local ENABLE_DEBUG_LOGS = false -- Toggles "[StateOutput]" console/OSD messages

-- =========================================================================
-- CORE PLUGIN ENGINE
-- =========================================================================
function stateoutput.startplugin()
    
    -- -------------------------------------------------------------------------
    -- SAFE MODULE LOADING
    -- pcall (Protected Call) is used to load the database safely. If the 
    -- database.lua file is missing or has a syntax error, pcall prevents 
    -- MAME from crashing and instead gracefully handles the failure.
    -- -------------------------------------------------------------------------
    local success, db = pcall(require, "stateoutput/database")
    if not success then
        success, db = pcall(require, "database") -- Fallback for flat directories
        if not success then db = {} end 
    end
    
    -- The currently active game's configuration dictionary
    local CFG = nil
    
    -- -------------------------------------------------------------------------
    -- ENGINE STATE VARIABLES
    -- These variables persist across all 60 frames of a single second, tracking 
    -- what happened in the past to calculate triggers in the present.
    -- -------------------------------------------------------------------------
    local _HasCoinedUp = false
    local _IsShuttingDown = false
    local _GameActiveTick
    local _GameInactiveTick
    local _LastGlobalCredits = 0
    local _GlobalCreditsInserted = 0
    local _PendingGlobalCreditDrops = 0
    
    -- Hardware Caching Arrays (Performance Optimization)
    -- Instead of searching MAME's entire device tree 60 times a second, we 
    -- find the memory addresses ONCE at boot and store direct pointers here.
    local _MemConfig = {}
    local _MemHandles = {}
    local _HardwareBound = false
    
    local _UniqueMemTargets = {}
    local _PlayerCFG = {}
    local _OutputNames = {}
    local _GlobalOutputs = {}
    
    -- Hardware Timers (FFB active duration tracking)
    local _RecoilDuration, _RecoilAltDuration, _RecoilGrenadeDuration, _MinRecoilInterval
    local _RecoilHoldInterval, _ReloadDuration, _DamageDuration, _RumbleDuration
    local _StartupTime, _ZeroTime
    
    local _Player = {}
    local _GlobalLastOutputs = {}
    local _InitTimer = 60
    local gamestatus = 0 

    -- -------------------------------------------------------------------------
    -- LOGGING HELPERS
    -- Standardized functions to push text to the console or MAME's On-Screen Display.
    -- -------------------------------------------------------------------------
    local function dbg_print(msg)
        if ENABLE_DEBUG_LOGS then print("[StateOutput] " .. tostring(msg)) end
    end
    local function dbg_osd(msg)
        local use_osd = ENABLE_DEBUG_LOGS or (CFG and CFG.ENABLE_OSD)
        if use_osd and manager and manager.machine then manager.machine:popmessage(tostring(msg)) end
    end

    -- -------------------------------------------------------------------------
    -- deep_merge(default_cfg, game_cfg)
    -- @description: Layers a specific ROM's values over the '_default' template.
    -- @purpose: Ensures that `CFG` always contains every required key, preventing 
    --           "nil value" crashes during the frame loop if a ROM JSON was sparse.
    -- -------------------------------------------------------------------------
    local function deep_merge(default_cfg, game_cfg)
        local result = {}
        for k, v in pairs(default_cfg) do
            if type(v) == "table" then result[k] = deep_merge(v, {}) else result[k] = v end
        end
        for k, v in pairs(game_cfg) do
            if type(v) == "table" and type(result[k]) == "table" then result[k] = deep_merge(result[k], v)
            else result[k] = v end
        end
        return result
    end

    -- -------------------------------------------------------------------------
    -- normalize_variables(config)
    -- @description: Translates legacy variable names to modern internal names.
    -- @purpose: Unifies LAMP_START and RECOIL into the standardized LAMPSTART and
    --           DAMAGE structures across all sub-tables automatically.
    -- -------------------------------------------------------------------------
    local function normalize_variables(config)
        for i = 1, config.MAX_PLAYERS do
            local p_cfg = config["P"..i]
            if p_cfg then
                if p_cfg.LAMP_START ~= nil and p_cfg.LAMPSTART == nil then p_cfg.LAMPSTART = p_cfg.LAMP_START end
                if p_cfg.RECOIL ~= nil and p_cfg.DAMAGE == nil then p_cfg.DAMAGE = p_cfg.RECOIL end
            end
        end
        if config.DATA_WIDTHS then
            if config.DATA_WIDTHS.LAMP_START ~= nil and config.DATA_WIDTHS.LAMPSTART == nil then config.DATA_WIDTHS.LAMPSTART = config.DATA_WIDTHS.LAMP_START end
            if config.DATA_WIDTHS.RECOIL ~= nil and config.DATA_WIDTHS.DAMAGE == nil then config.DATA_WIDTHS.DAMAGE = config.DATA_WIDTHS.RECOIL end
        end
        if config.OUTPUT_SUFFIXES then
            if config.OUTPUT_SUFFIXES.LAMP_START ~= nil and config.OUTPUT_SUFFIXES.LAMPSTART == nil then config.OUTPUT_SUFFIXES.LAMPSTART = config.OUTPUT_SUFFIXES.LAMP_START end
            if config.OUTPUT_SUFFIXES.RECOIL ~= nil and config.OUTPUT_SUFFIXES.DAMAGE == nil then config.OUTPUT_SUFFIXES.DAMAGE = config.OUTPUT_SUFFIXES.RECOIL end
        end
        if config.CPU_TAGS then
            if config.CPU_TAGS.LAMP_START ~= nil and config.CPU_TAGS.LAMPSTART == nil then config.CPU_TAGS.LAMPSTART = config.CPU_TAGS.LAMP_START end
        end
        if config.MEMORY_SPACES then
            if config.MEMORY_SPACES.LAMP_START ~= nil and config.MEMORY_SPACES.LAMPSTART == nil then config.MEMORY_SPACES.LAMPSTART = config.MEMORY_SPACES.LAMP_START end
        end
        return config
    end

    -- -------------------------------------------------------------------------
    -- convert_hex_strings_to_numbers(t)
    -- @description: Recursively converts JSON hex strings ("0x00FF") to integers.
    -- @purpose: JSON files cannot store hexadecimal numbers. They must be saved 
    --           as strings. But MAME's memory reader requires raw numbers. This 
    --           function fixes that translation limitation automatically at boot.
    -- -------------------------------------------------------------------------
    local function convert_hex_strings_to_numbers(t)
        for k, v in pairs(t) do
            if type(v) == "table" then convert_hex_strings_to_numbers(v)
            elseif type(v) == "string" and string.match(v, "^0x%x+$") then
                local num = tonumber(v)
                if num then t[k] = num end
            end
        end
    end

    -- -------------------------------------------------------------------------
    -- Resolve_Addresses_And_Strings()
    -- @description: Pre-calculates heavy string/math operations before the game starts.
    -- @purpose: String manipulation (e.g., string.lower) is very CPU intensive in Lua. 
    --           By doing it once here, we save thousands of CPU cycles per second.
    --           It also automatically generates P2/P3/P4 memory addresses based on 
    --           P1's offset math.
    -- -------------------------------------------------------------------------
    local function Resolve_Addresses_And_Strings()
        -- Normalize logical evaluation strings
        CFG.AMMO_DIRECTION             = string.lower(tostring(CFG.AMMO_DIRECTION or ""))
        CFG.AMMO_ALT_DIRECTION         = string.lower(tostring(CFG.AMMO_ALT_DIRECTION or ""))
        CFG.AMMO_GRENADE_DIRECTION     = string.lower(tostring(CFG.AMMO_GRENADE_DIRECTION or ""))
        CFG.LIFE_DIRECTION             = string.lower(tostring(CFG.LIFE_DIRECTION or ""))
        CFG.LIFE_ALT_DIRECTION         = string.lower(tostring(CFG.LIFE_ALT_DIRECTION or ""))
        CFG.SHOTS_FIRED_METHOD         = string.lower(tostring(CFG.SHOTS_FIRED_METHOD or "trigger"))
        CFG.SHOTS_FIRED_ALT_METHOD     = string.lower(tostring(CFG.SHOTS_FIRED_ALT_METHOD or "trigger"))
        CFG.SHOTS_FIRED_GRENADE_METHOD = string.lower(tostring(CFG.SHOTS_FIRED_GRENADE_METHOD or "trigger"))
        CFG.FORCE_FEEDBACK_ENABLER     = string.lower(tostring(CFG.FORCE_FEEDBACK_ENABLER or "both"))
        CFG.RECOIL_METHOD              = string.lower(tostring(CFG.RECOIL_METHOD or "pulse"))
        CFG.RECOIL_PRIORITY            = string.lower(tostring(CFG.RECOIL_PRIORITY or "ammo"))

        if CFG.DATA_WIDTHS then
            for k, v in pairs(CFG.DATA_WIDTHS) do
                if type(v) == "string" then CFG.DATA_WIDTHS[k] = string.lower(v) end
            end
        end

        local data_types = {
            "SCREEN_FLASH", "GLOBAL_ATTRACT_STATUS", "GLOBAL_CREDITS", "GLOBAL_GAME_STATUS",
            "CREDITS", "STATUS", "STATUS_ALT", "AMMO", "AMMO_ALT", "AMMO_GRENADE", "LIFE", "LIFE_ALT",
            "RECOIL", "RELOAD", "DAMAGE", "RUMBLE", "LAMPSTART",
            "SHOTS_FIRED_PRIMARY", "SHOTS_FIRED_ALT", "SHOTS_FIRED_GRENADE", "LIFE_LOST", "DAMAGE_TAKEN"
        }

        local function Resolve_Mem_Path(val, global_val)
            if val == nil or val == false or val == "" or string.lower(tostring(val)) == "auto" then return global_val end
            return tostring(val)
        end

        -- Map CPU paths
        for _, key in ipairs(data_types) do
            local t = Resolve_Mem_Path(CFG.CPU_TAGS and CFG.CPU_TAGS[key], CFG.CPU_TAG or ":maincpu")
            local s = Resolve_Mem_Path(CFG.MEMORY_SPACES and CFG.MEMORY_SPACES[key], CFG.MEMORY_SPACE or "program")
            _MemConfig[key] = { tag = t, space = s }
        end

        -- Pre-compile the MAME output broadcast strings (e.g., "P1_Ammo")
        for i = 1, CFG.MAX_PLAYERS do
            _OutputNames[i] = {}
            for key, suffix in pairs(CFG.OUTPUT_SUFFIXES) do
                if not string.match(key, "^GLOBAL_") then
                    local target_p = i
                    if not CFG.SIMULTANEOUS_PLAY and (key == "RECOIL" or key == "RELOAD" or key == "DAMAGE" or key == "RUMBLE" or key == "LAMPSTART") then target_p = 1 end
                    _OutputNames[i][key] = "P" .. target_p .. "_" .. tostring(suffix)
                end
            end
            local target_p_ctm = (not CFG.SIMULTANEOUS_PLAY) and 1 or i
            _OutputNames[i]["CtmRecoil"] = "P" .. target_p_ctm .. "_CtmRecoil" 
            _OutputNames[i]["Damaged"]   = "P" .. target_p_ctm .. "_Damaged"
        end
        
        for key, suffix in pairs(CFG.OUTPUT_SUFFIXES) do
            if string.match(key, "^GLOBAL_") then _GlobalOutputs[key] = tostring(suffix) end
        end

        -- Process "auto" variables
        local all_players = { CFG.P1, CFG.P2, CFG.P3, CFG.P4 }
        for _, p_cfg in ipairs(all_players) do
            for k, val in pairs(p_cfg) do
                if type(val) == "string" and string.lower(val) == "auto" then p_cfg[k] = "auto" end
            end
        end

        -- Ensure hardware "auto" states gracefully disable if they have no underlying Ammo/Life data to track
        local p1_hardware = { "RECOIL", "RELOAD", "DAMAGE", "RUMBLE", "LAMPSTART", "STATUS", "STATUS_ALT" }
        for _, key in ipairs(p1_hardware) do
            if CFG.P1[key] == "auto" then
                if key == "STATUS" or key == "STATUS_ALT" then -- leave as auto
                elseif key == "RECOIL" and (CFG.P1.AMMO or CFG.P1.AMMO_ALT or CFG.P1.AMMO_GRENADE) then
                elseif key == "RELOAD" and (CFG.P1.AMMO or CFG.P1.AMMO_ALT or CFG.P1.AMMO_GRENADE) then
                elseif key == "DAMAGE" and (CFG.P1.LIFE or CFG.P1.LIFE_ALT) then
                elseif key == "LAMPSTART" then
                else CFG.P1[key] = false end
            end
        end

        -- Execute math to generate P2/P3/P4 hex strings based on the multiplier offset
        local standard_offset = tonumber(CFG.PLAYER_MEMORY_OFFSET) or 0
        local credit_offset = tonumber(CFG.PLAYER_CREDIT_MEMORY_OFFSET) or standard_offset
        local player_tables = { CFG.P2, CFG.P3, CFG.P4 }

        for i, p_cfg in ipairs(player_tables) do
            local multiplier = i 
            for key, val in pairs(p_cfg) do
                if val == "auto" then
                    local p1_val = CFG.P1[key]
                    local offset_to_use = (key == "CREDITS") and credit_offset or standard_offset
                    if type(p1_val) == "number" then
                        p_cfg[key] = p1_val + (offset_to_use * multiplier)
                    elseif type(p1_val) == "string" and string.match(p1_val, "^0x") then
                        local p1_num = tonumber(p1_val)
                        if p1_num then p_cfg[key] = string.format("0x%08X", p1_num + (offset_to_use * multiplier)) end
                    elseif p1_val == "auto" then p_cfg[key] = "auto"; if CFG.P1[key] == false then p_cfg[key] = false end
                    else p_cfg[key] = false end
                end
            end
        end
        _PlayerCFG = { CFG.P1, CFG.P2, CFG.P3, CFG.P4 }
    end

    local function Is_Warmup_Complete() return manager.machine.time > _StartupTime end

    -- -------------------------------------------------------------------------
    -- Read_Data_Safe(mem_handle, source, width)
    -- @description: Universal memory polling adapter. 
    -- @options:
    --    8, 16, 32    -> Reads standard Unsigned Integers
    --    "float32"    -> Reads 32-bit Little Endian Floats (Modern 3D games)
    --    "float32be"  -> Reads 32-bit Big Endian Floats (Sega Model 2/3)
    --    "output"     -> Reads an existing MAME software output instead of RAM
    -- -------------------------------------------------------------------------
    local function Read_Data_Safe(mem_handle, source, width)
        if not source then return 0 end
        if type(width) == "string" then
            if width == "output" then
                if type(source) == "string" and manager.machine.output then
                    local native_val = manager.machine.output:get_value(source)
                    return type(native_val) == "number" and native_val or (native_val and 1 or 0)
                end
                return 0
            elseif width == "float32" and mem_handle then
                local val = mem_handle:read_u32(source)
                return string.unpack("f", string.pack("I4", val))
            elseif width == "float32be" and mem_handle then
                local val = mem_handle:read_u32(source)
                val = ((val & 0xFF) << 24) | ((val & 0xFF00) << 8) | ((val & 0xFF0000) >> 8) | ((val & 0xFF000000) >> 24)
                return string.unpack("f", string.pack("I4", val))
            end
            return 0
        end
        if not mem_handle then return 0 end
        if width == 16 then return mem_handle:read_u16(source) end
        if width == 32 then return mem_handle:read_u32(source) end
        return mem_handle:read_u8(source)
    end
    
    -- -------------------------------------------------------------------------
    -- Write_Data_Safe(mem_handle, source, width, value)
    -- @description: Active memory patching adapter. Injects values into RAM.
    -- @purpose: Used primarily to disable visual hazards (like white flashes)
    --           by hard-locking memory addresses to a specific value.
    -- -------------------------------------------------------------------------
    local function Write_Data_Safe(mem_handle, source, width, value)
        if not source or not mem_handle or not value then return end
        if type(width) == "string" then return end -- Outputs/Floats not supported for memory patching
        if width == 16 then mem_handle:write_u16(source, value)
        elseif width == 32 then mem_handle:write_u32(source, value)
        else mem_handle:write_u8(source, value) end
    end

    -- -------------------------------------------------------------------------
    -- Register_Outputs_Safe(out_handle)
    -- @description: Flushes outputs to zero at boot.
    -- @purpose: Prevents external hardware (like DemulShooter or lighting apps) 
    --           from sticking 'ON' if a previous game crashed or ended abruptly.
    -- -------------------------------------------------------------------------
    local function Register_Outputs_Safe(out_handle)
        if not out_handle then return end
        out_handle:set_value(_GlobalOutputs["GLOBAL_GAME_STATUS"], 0)
        if CFG.ATTRACT_STATUS then out_handle:set_value(_GlobalOutputs["GLOBAL_ATTRACT_STATUS"], 0) end
        out_handle:set_value(_GlobalOutputs["GLOBAL_LUA_VERSION"], CFG.LUA_VERSION)
        out_handle:set_value(_GlobalOutputs["GLOBAL_LUA_DATE"], CFG.LUA_DATE)
        out_handle:set_value(_GlobalOutputs["GLOBAL_LUA_ROM_ID"], CFG.LUA_ROM_ID)
        if CFG.CREDITS then 
            out_handle:set_value(_GlobalOutputs["GLOBAL_CREDITS"], 0)
            out_handle:set_value(_GlobalOutputs["GLOBAL_CREDITS_INSERTED"], 0)
        end
        
        for i = 1, CFG.MAX_PLAYERS do
            local p_cfg = _PlayerCFG[i] 
            if p_cfg.STATUS then out_handle:set_value(_OutputNames[i]["STATUS"], 0) end
            if p_cfg.STATUS_ALT then out_handle:set_value(_OutputNames[i]["STATUS_ALT"], 0) end
            if p_cfg.CREDITS then 
                out_handle:set_value(_OutputNames[i]["CREDITS"], 0) 
                out_handle:set_value(_OutputNames[i]["CREDITS_INSERTED"], 0)
                out_handle:set_value(_OutputNames[i]["CREDITS_CONSUMED"], 0)
            end
            local keys = {"AMMO", "AMMO_ALT", "AMMO_GRENADE", "LIFE", "LIFE_ALT", "DAMAGE", "RECOIL", "RELOAD", "RUMBLE", "LAMPSTART"}
            for _, k in ipairs(keys) do
                if p_cfg[k] and _OutputNames[i][k] then 
                    out_handle:set_value(_OutputNames[i][k], 0) 
                end
            end
            
            -- Move DemulShooter overrides outside the loop to guarantee MAME registers them
            if CFG.DEMULSHOOTER_COMPATIBILITY then 
                out_handle:set_value(_OutputNames[i]["CtmRecoil"], 0)
                out_handle:set_value(_OutputNames[i]["Damaged"], 0)
                
                -- CRITICAL FIX: Sync the local spam-filter cache with the boot state
                _Player[i].LastOutputs["CtmRecoil"] = 0
                _Player[i].LastOutputs["Damaged"] = 0
            end
            if CFG.ENABLE_DAMAGE_COUNT and p_cfg.DAMAGE_TAKEN then out_handle:set_value(_OutputNames[i]["DAMAGE_TAKEN"], 0) end
            if CFG.ENABLE_SHOT_COUNT and p_cfg.SHOTS_FIRED then out_handle:set_value(_OutputNames[i]["SHOTS_FIRED"], 0) end
            if CFG.ENABLE_SHOT_COUNT and p_cfg.SHOTS_FIRED_PRIMARY then out_handle:set_value(_OutputNames[i]["SHOTS_FIRED_PRIMARY"], 0) end
            if CFG.ENABLE_SHOT_COUNT and p_cfg.SHOTS_FIRED_ALT then out_handle:set_value(_OutputNames[i]["SHOTS_FIRED_ALT"], 0) end
            if CFG.ENABLE_SHOT_COUNT and p_cfg.SHOTS_FIRED_GRENADE then out_handle:set_value(_OutputNames[i]["SHOTS_FIRED_GRENADE"], 0) end
            if CFG.ENABLE_LIFE_LOST and p_cfg.LIFE_LOST then out_handle:set_value(_OutputNames[i]["LIFE_LOST"], 0) end
        end
    end

    -- =========================================================================
    -- THE FRAME LOOP ENGINE (Frame_Logic)
    -- @description: This is the heartbeat of the plugin. It evaluates memory 
    --               conditions 60 times a second. It is isolated from the `pcall` 
    --               wrapper below to prevent closure memory allocation (GC Spikes).
    -- =========================================================================
    local function Frame_Logic()
        local machine = manager.machine
        if not machine then _IsShuttingDown = true; return end
        
        local out = machine.output
        local current_time = machine.time
        if not out then return end
        
        -- PERFORMANCE OPTIMIZATION: One-Time Bus Binding Cache
        -- Finds the specific MAME CPU context only on frame 1, storing it locally.
        if not _HardwareBound then
            for key, conf in pairs(_MemConfig) do
                local dev = machine.devices[conf.tag]
                if dev and dev.spaces[conf.space] then _MemHandles[key] = dev.spaces[conf.space] end
            end
            _HardwareBound = true
        end
        
        -- OUTPUT SPAM WRAPPERS:
        -- Only sends a command to MAME's output system if the value has actually changed.
        -- This drastically reduces TCP server load.
        local function Set_Output(p_idx, key, value)
            local p = _Player[p_idx]
            if p.LastOutputs[key] ~= value and _OutputNames[p_idx][key] then
                out:set_value(_OutputNames[p_idx][key], value)
                p.LastOutputs[key] = value
            end
        end
        
        local function Set_Global_Output(key, value)
            if _GlobalLastOutputs[key] ~= value then
                out:set_value(_GlobalOutputs[key], value)
                _GlobalLastOutputs[key] = value
            end
        end
        
        if _InitTimer > 0 then
            _InitTimer = _InitTimer - 1
            if _InitTimer == 0 then Register_Outputs_Safe(out) end
        end
        
        local warmup_ok = Is_Warmup_Complete()
        local divisor = CFG.COINS_PER_CREDIT or 1
        if divisor < 1 then divisor = 1 end

        -- ----------------------------------------------
        -- PHASE 1: GLOBAL STATUS & ATTRACT MODE
        -- ----------------------------------------------
        local is_attract_mode = false
        if CFG.ATTRACT_STATUS and type(CFG.ATTRACT_STATUS) == "number" then
            local val = Read_Data_Safe(_MemHandles["GLOBAL_ATTRACT_STATUS"], CFG.ATTRACT_STATUS, CFG.DATA_WIDTHS.GLOBAL_ATTRACT_STATUS or 8)
            local active = CFG.ATTRACT_STATUS_ACTIVE_VALUE
            is_attract_mode = (type(active) == "number") and (val == active) or (val > 0)
            Set_Global_Output("GLOBAL_ATTRACT_STATUS", warmup_ok and (is_attract_mode and 1 or 0) or 0)
            if is_attract_mode then _PendingGlobalCreditDrops = 0 end
        end

        if CFG.CREDITS and type(CFG.CREDITS) == "number" then 
            local raw = Read_Data_Safe(_MemHandles["GLOBAL_CREDITS"], CFG.CREDITS, CFG.DATA_WIDTHS.GLOBAL_CREDITS)
            local current_credits = math.floor(raw / divisor)
            Set_Global_Output("GLOBAL_CREDITS", warmup_ok and current_credits or 0)
            if warmup_ok then
                if current_credits > _LastGlobalCredits then
                    _GlobalCreditsInserted = _GlobalCreditsInserted + (current_credits - _LastGlobalCredits)
                    if CFG.ENABLE_CREDIT_COUNT then Set_Global_Output("GLOBAL_CREDITS_INSERTED", _GlobalCreditsInserted) end
                elseif current_credits < _LastGlobalCredits then
                    _PendingGlobalCreditDrops = _PendingGlobalCreditDrops + (_LastGlobalCredits - current_credits)
                end
            end
            _LastGlobalCredits = current_credits
            if current_credits > 0 and warmup_ok then _HasCoinedUp = true end
        end

        local is_game_active = false
        local global_exists = false
        gamestatus = 0 
        
        if CFG.GAME_STATUS and type(CFG.GAME_STATUS) == "number" then 
            global_exists = true
            if not is_attract_mode then
                local val = Read_Data_Safe(_MemHandles["GLOBAL_GAME_STATUS"], CFG.GAME_STATUS, CFG.DATA_WIDTHS.GLOBAL_GAME_STATUS)
                local active = CFG.GAME_STATUS_ACTIVE_VALUE
                is_game_active = (type(active) == "number") and (val == active) or (val > 0)
            end
        end
        
        if is_game_active then
            if _GameActiveTick == _ZeroTime then _GameActiveTick = current_time end
            if (current_time - _GameActiveTick) <= emu.attotime.from_msec(CFG.STATUS_DEBOUNCE_MS or 0) then is_game_active = false end
        else
            _GameActiveTick = _ZeroTime; is_game_active = false
        end
        
        if is_game_active then gamestatus = 1 end

-- ----------------------------------------------
        -- PHASE 2: CORE PLAYER ITERATION
        -- Loops through P1, P2, P3, P4 sequentially.
        -- ----------------------------------------------
        local any_player_active = false
        local aggregated_credits = 0
        local using_individual_credits = false
        for i = 1, CFG.MAX_PLAYERS do
            local cfg = _PlayerCFG[i]
            local p = _Player[i]
            
            if is_attract_mode then p.PendingCreditDrops = 0 end
            
            -- Memory Polling Block
            local curr_ammo, curr_ammo_alt, curr_ammo_grenade, curr_life, curr_life_alt = 0, 0, 0, 0, 0
            
            if cfg.AMMO then 
                curr_ammo = Read_Data_Safe(_MemHandles["AMMO"], cfg.AMMO, CFG.DATA_WIDTHS.AMMO) + (CFG.AMMO_OFFSET or 0)
                if CFG.AMMO_MAX and curr_ammo > CFG.AMMO_MAX then curr_ammo = 0 end
            end
            if cfg.AMMO_ALT then 
                curr_ammo_alt = Read_Data_Safe(_MemHandles["AMMO_ALT"], cfg.AMMO_ALT, CFG.DATA_WIDTHS.AMMO_ALT) + (CFG.AMMO_ALT_OFFSET or 0)
                if CFG.AMMO_ALT_MAX and curr_ammo_alt > CFG.AMMO_ALT_MAX then curr_ammo_alt = 0 end
            end
            if cfg.AMMO_GRENADE then 
                curr_ammo_grenade = Read_Data_Safe(_MemHandles["AMMO_GRENADE"], cfg.AMMO_GRENADE, CFG.DATA_WIDTHS.AMMO_GRENADE) + (CFG.AMMO_GRENADE_OFFSET or 0)
                if CFG.AMMO_GRENADE_MAX and curr_ammo_grenade > CFG.AMMO_GRENADE_MAX then curr_ammo_grenade = 0 end
            end
            if cfg.LIFE then 
                curr_life = Read_Data_Safe(_MemHandles["LIFE"], cfg.LIFE, CFG.DATA_WIDTHS.LIFE) + (CFG.LIFE_OFFSET or 0)
                if CFG.LIFE_MAX and curr_life > CFG.LIFE_MAX then curr_life = 0 end
            end
            if cfg.LIFE_ALT then 
                curr_life_alt = Read_Data_Safe(_MemHandles["LIFE_ALT"], cfg.LIFE_ALT, CFG.DATA_WIDTHS.LIFE_ALT) + (CFG.LIFE_ALT_OFFSET or 0)
                if CFG.LIFE_ALT_MAX and curr_life_alt > CFG.LIFE_ALT_MAX then curr_life_alt = 0 end
            end

            -- Per-Player Credits processing
            local p_credits = 0
            local p_credits_known = false
            if cfg.CREDITS then
                if type(cfg.CREDITS) == "number" then 
                    local raw = Read_Data_Safe(_MemHandles["CREDITS"], cfg.CREDITS, CFG.DATA_WIDTHS.CREDITS)
                    p_credits = math.floor(raw / divisor)
                    p_credits_known = true
                    Set_Output(i, "CREDITS", warmup_ok and p_credits or 0)
                    
                    -- Aggregate individual credits for global override
                    aggregated_credits = aggregated_credits + p_credits
                    using_individual_credits = true
                    
                    if warmup_ok then
                        if p_credits > p.LastCredits then
                            p.CreditsInserted = p.CreditsInserted + (p_credits - p.LastCredits)
                            if CFG.ENABLE_CREDIT_COUNT then Set_Output(i, "CREDITS_INSERTED", p.CreditsInserted) end
                        elseif p_credits < p.LastCredits then
                            p.PendingCreditDrops = p.PendingCreditDrops + (p.LastCredits - p_credits)
                        end
                    end
                    p.LastCredits = p_credits
                elseif cfg.CREDITS == "auto" and CFG.CREDITS then 
                    p_credits = Read_Data_Safe(_MemHandles["GLOBAL_CREDITS"], CFG.CREDITS, CFG.DATA_WIDTHS.GLOBAL_CREDITS) 
                    p_credits_known = true
                    Set_Output(i, "CREDITS", warmup_ok and p_credits or 0)
                    
                    if warmup_ok then
                        if p_credits > p.LastCredits then
                            p.CreditsInserted = p.CreditsInserted + (p_credits - p.LastCredits)
                            if CFG.ENABLE_CREDIT_COUNT then Set_Output(i, "CREDITS_INSERTED", p.CreditsInserted) end
                        elseif p_credits < p.LastCredits then
                            p.PendingCreditDrops = p.PendingCreditDrops + (p.LastCredits - p_credits)
                        end
                    end
                    p.LastCredits = p_credits
                end
            end
            
            if CFG.ENABLE_CREDIT_COUNT and warmup_ok then
                local spawned = false
                if cfg.LIFE then
                    if CFG.LIFE_DIRECTION == "decrease" and curr_life > p.LastLife and p.LastLife == 0 then spawned = true
                    elseif CFG.LIFE_DIRECTION == "increase" and curr_life < p.LastLife and curr_life == 0 then spawned = true end
                end
                if spawned then
                    if p.PendingCreditDrops > 0 then
                        p.CreditsConsumed = p.CreditsConsumed + 1; p.PendingCreditDrops = p.PendingCreditDrops - 1
                        Set_Output(i, "CREDITS_CONSUMED", p.CreditsConsumed)
                    elseif _PendingGlobalCreditDrops > 0 then
                        p.CreditsConsumed = p.CreditsConsumed + 1; _PendingGlobalCreditDrops = _PendingGlobalCreditDrops - 1
                        Set_Output(i, "CREDITS_CONSUMED", p.CreditsConsumed)
                    end
                end
            end
            
            if cfg.LAMPSTART then Set_Output(i, "LAMPSTART", warmup_ok and Read_Data_Safe(_MemHandles["LAMPSTART"], cfg.LAMPSTART, CFG.DATA_WIDTHS.LAMPSTART) or 0) end

            local is_player_active = false
            local out_status_val = 0
            local out_status_alt_val = 0

            -- Priority Evaluation Hierarchy
            if not is_attract_mode then
                if (cfg.STATUS and cfg.STATUS ~= "auto") or (cfg.STATUS_ALT and cfg.STATUS_ALT ~= "auto") then
                    local p_stat_active = false
                    local p_stat_alt_active = false
                    if cfg.STATUS and cfg.STATUS ~= "auto" then
                        local val = Read_Data_Safe(_MemHandles["STATUS"], cfg.STATUS, CFG.DATA_WIDTHS.STATUS)
                        local act = cfg.STATUS_ACTIVE_VALUE or CFG.STATUS_ACTIVE_VALUE
                        p_stat_active = (type(act) == "table") and (function() for _,v in ipairs(act) do if val == v then return true end end return false end)() or ((type(act) == "number" and val == act) or (not act and val > 0))
                    end
                    if cfg.STATUS_ALT and cfg.STATUS_ALT ~= "auto" then
                        local val = Read_Data_Safe(_MemHandles["STATUS_ALT"], cfg.STATUS_ALT, CFG.DATA_WIDTHS.STATUS_ALT)
                        local act = cfg.STATUS_ALT_ACTIVE_VALUE or CFG.STATUS_ALT_ACTIVE_VALUE
                        p_stat_alt_active = (type(act) == "table") and (function() for _,v in ipairs(act) do if val == v then return true end end return false end)() or ((type(act) == "number" and val == act) or (not act and val > 0))
                    end
                    if global_exists then
                        if is_game_active and p_stat_active then out_status_val = 1 end
                        if is_game_active and p_stat_alt_active then out_status_alt_val = 1 end
                    else
                        if p_stat_active then out_status_val = 1 end
                        if p_stat_alt_active then out_status_alt_val = 1 end
                    end
                    if out_status_val == 1 or out_status_alt_val == 1 then is_player_active = true end
                elseif global_exists then
                    if is_game_active and (curr_life > 0 or curr_life_alt > 0) then is_player_active = true; out_status_val = 1; out_status_alt_val = 1 end
                else
                    if _HasCoinedUp and (curr_life > 0 or curr_life_alt > 0) and ((not p_credits_known) or p_credits > 0) then is_player_active = true; out_status_val = 1; out_status_alt_val = 1 end
                end
            end
            
            if not warmup_ok then is_player_active = false; out_status_val = 0; out_status_alt_val = 0 end
            
            if is_player_active then
                if p.ActiveTick == _ZeroTime then p.ActiveTick = current_time end
                if (current_time - p.ActiveTick) <= emu.attotime.from_msec(CFG.STATUS_DEBOUNCE_MS or 0) then is_player_active = false; out_status_val = 0; out_status_alt_val = 0 end
            else p.ActiveTick = _ZeroTime; out_status_val = 0; out_status_alt_val = 0 end
            
            p.IsActive = is_player_active
            if is_player_active then any_player_active = true end
            p.IsFFBAllowed = (CFG.FORCE_FEEDBACK_ENABLER == "status") and (out_status_val == 1 or out_status_alt_val == 1) or (CFG.FORCE_FEEDBACK_ENABLER == "life") and (curr_life > 0 or curr_life_alt > 0) or (CFG.FORCE_FEEDBACK_ENABLER == "gamestatus") and is_game_active or is_player_active
            
            if cfg.STATUS then Set_Output(i, "STATUS", out_status_val) end
            if cfg.STATUS_ALT then Set_Output(i, "STATUS_ALT", out_status_alt_val) end

            local just_died = (not is_player_active and p.WasActive)
            local primary_active = (out_status_val == 1)
            local alternate_active = (cfg.STATUS_ALT and cfg.STATUS_ALT ~= "auto") and (out_status_alt_val == 1) or primary_active

            -- ----------------------------------------------
            -- PHASE 3: HARDWARE TRIGGERS (Recoil & Reload)
            -- ----------------------------------------------
            local auto_recoil_triggered_this_frame = false
            local t_ammo = CFG.AMMO_THRESHOLD or 254
            local t_alt = CFG.AMMO_ALT_THRESHOLD or 254
            local t_grenade = CFG.AMMO_GRENADE_THRESHOLD or 254
            
            if p.IsFFBAllowed then
                  local trigger = 0
                  if CFG.ENABLE_RECOIL_AMMO ~= false and cfg.AMMO then
                      if CFG.AMMO_DIRECTION == "decrease" then if curr_ammo < p.LastAmmo and p.LastAmmo <= t_ammo then trigger = 1 end
                      elseif CFG.AMMO_DIRECTION == "change" then if curr_ammo ~= p.LastAmmo then trigger = 1 end
                      elseif curr_ammo > p.LastAmmo then trigger = 1 end
                  end
                  if CFG.ENABLE_RECOIL_AMMO_ALT ~= false and cfg.AMMO_ALT then
                      if CFG.AMMO_ALT_DIRECTION == "decrease" then if curr_ammo_alt < p.LastAmmoAlt and p.LastAmmoAlt <= t_alt then trigger = 2 end
                      elseif CFG.AMMO_ALT_DIRECTION == "change" then if curr_ammo_alt ~= p.LastAmmoAlt then trigger = 2 end
                      elseif curr_ammo_alt > p.LastAmmoAlt then trigger = 2 end
                  end
                  if CFG.ENABLE_RECOIL_AMMO_GRENADE ~= false and cfg.AMMO_GRENADE then
                      if CFG.AMMO_GRENADE_DIRECTION == "decrease" then if curr_ammo_grenade < p.LastAmmoGrenade and p.LastAmmoGrenade <= t_grenade then trigger = 3 end
                      elseif CFG.AMMO_GRENADE_DIRECTION == "change" then if curr_ammo_grenade ~= p.LastAmmoGrenade then trigger = 3 end
                      elseif curr_ammo_grenade > p.LastAmmoGrenade then trigger = 3 end
                  end
                  
                  -- Fire Recoil based on Ammo Math
                  if trigger > 0 and (cfg.RECOIL == "auto" or (type(cfg.RECOIL) == "number" and CFG.RECOIL_PRIORITY == "ammo")) then
                      if current_time - p.RecoilTick > _MinRecoilInterval then
                          if trigger == 1 then p.CurrentRecoilDuration = _RecoilDuration
                          elseif trigger == 2 then p.CurrentRecoilDuration = _RecoilAltDuration
                          elseif trigger == 3 then p.CurrentRecoilDuration = _RecoilGrenadeDuration end
                          
                          Set_Output(i, "RECOIL", 1); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(i, "CtmRecoil", 1) end
                          p.RecoilTick = current_time; p.IsRecoilActive = true; auto_recoil_triggered_this_frame = true
                          if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].RecoilTick = current_time; _Player[1].IsRecoilActive = true end
                      end
                  end
                  
                  -- Fire Reload based on Ammo Math
                  if CFG.ENABLE_RELOAD_AMMO ~= false and cfg.AMMO then
                      if (CFG.AMMO_DIRECTION == "decrease" and curr_ammo > p.LastAmmo) or (CFG.AMMO_DIRECTION == "increase" and curr_ammo < p.LastAmmo) then
                          if cfg.RELOAD then Set_Output(i, "RELOAD", 1); p.ReloadTick = current_time; p.IsReloadActive = true; if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].ReloadTick = current_time; _Player[1].IsReloadActive = true end end
                      end
                  end
                  if CFG.ENABLE_RELOAD_AMMO_ALT ~= false and cfg.AMMO_ALT then
                      if (CFG.AMMO_ALT_DIRECTION == "decrease" and curr_ammo_alt > p.LastAmmoAlt) or (CFG.AMMO_ALT_DIRECTION == "increase" and curr_ammo_alt < p.LastAmmoAlt) then
                          if cfg.RELOAD then Set_Output(i, "RELOAD", 1); p.ReloadTick = current_time; p.IsReloadActive = true; if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].ReloadTick = current_time; _Player[1].IsReloadActive = true end end
                      end
                  end
                  if CFG.ENABLE_RELOAD_AMMO_GRENADE ~= false and cfg.AMMO_GRENADE then
                      if (CFG.AMMO_GRENADE_DIRECTION == "decrease" and curr_ammo_grenade > p.LastAmmoGrenade) or (CFG.AMMO_GRENADE_DIRECTION == "increase" and curr_ammo_grenade < p.LastAmmoGrenade) then
                          if cfg.RELOAD then Set_Output(i, "RELOAD", 1); p.ReloadTick = current_time; p.IsReloadActive = true; if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].ReloadTick = current_time; _Player[1].IsReloadActive = true end end
                      end
                  end
                  
                  -- Fire Reload manually (based on Memory Address polling)
                  if cfg.RELOAD and type(cfg.RELOAD) == "number" then
                      local val = Read_Data_Safe(_MemHandles["RELOAD"], cfg.RELOAD, CFG.DATA_WIDTHS.RELOAD)
                      local manual_trigger = false
                      if type(CFG.RELOAD_MEM_ADD_VALUE) == "number" then
                          manual_trigger = (val == CFG.RELOAD_MEM_ADD_VALUE and p.LastReloadVal ~= CFG.RELOAD_MEM_ADD_VALUE)
                      else
                          manual_trigger = (val > p.LastReloadVal)
                      end
                      
                      if manual_trigger then
                          Set_Output(i, "RELOAD", 1)
                          p.ReloadTick = current_time; p.IsReloadActive = true
                          if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].ReloadTick = current_time; _Player[1].IsReloadActive = true end
                      end
                      p.LastReloadVal = val
                  end
                  
                  -- Fire Recoil manually (based on Memory Address polling)
                  if not auto_recoil_triggered_this_frame then
                      if cfg.RECOIL and type(cfg.RECOIL) == "number" then
                          local val = Read_Data_Safe(_MemHandles["RECOIL"], cfg.RECOIL, CFG.DATA_WIDTHS.RECOIL)
                          if (CFG.RECOIL_PRIORITY ~= "ammo" or curr_ammo == 0) then
                              local manual_trigger = false
                              if type(CFG.RECOIL_MEM_ADD_VALUE) == "number" then
                                  if CFG.RECOIL_METHOD == "hold" then manual_trigger = (val == CFG.RECOIL_MEM_ADD_VALUE) else manual_trigger = (val == CFG.RECOIL_MEM_ADD_VALUE and p.LastRecoilVal ~= CFG.RECOIL_MEM_ADD_VALUE) end
                              else
                                  manual_trigger = (CFG.RECOIL_METHOD == "hold") and (val > 0) or (CFG.RECOIL_METHOD == "change") and (val ~= p.LastRecoilVal and val > 0) or (CFG.RECOIL_METHOD == "latch") and (val > 0 and p.LastRecoilVal == 0) or (val > p.LastRecoilVal)
                              end
                              
                              local active_interval = (CFG.RECOIL_METHOD == "hold") and _RecoilHoldInterval or _MinRecoilInterval
                              if manual_trigger and (current_time - p.RecoilTick > active_interval) then
                                  p.CurrentRecoilDuration = _RecoilDuration; Set_Output(i, "RECOIL", 1)
                                  if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(i, "CtmRecoil", 1) end
                                  
                                  -- Only use hardware fallback for primary shots if AMMO is unmapped
                                  if CFG.ENABLE_SHOT_COUNT and warmup_ok and not cfg.AMMO then
                                      p.ShotCountPrimary = p.ShotCountPrimary + 1
                                      Set_Output(i, "SHOTS_FIRED_PRIMARY", p.ShotCountPrimary)
                                  end
                                  p.RecoilTick = current_time; p.IsRecoilActive = true
                                  if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].RecoilTick = current_time; _Player[1].IsRecoilActive = true end
                              end
                          end
                          p.LastRecoilVal = val
                      end
                  end
            end

            -- ----------------------------------------------
            -- PHASE 4: STATISTICAL BROADCASTS & HIT DAMAGE
            -- Pushes live Ammo/Life numbers to external apps.
            -- ----------------------------------------------
            if is_player_active or just_died then
                if primary_active then
                    if cfg.AMMO then Set_Output(i, "AMMO", warmup_ok and curr_ammo or 0) end
                    if cfg.LIFE then Set_Output(i, "LIFE", warmup_ok and curr_life or 0) end
                    
                    if CFG.ENABLE_SHOT_COUNT and cfg.SHOTS_FIRED_PRIMARY and warmup_ok then
                        if type(cfg.SHOTS_FIRED_PRIMARY) == "number" then 
                             local val = Read_Data_Safe(_MemHandles["SHOTS_FIRED_PRIMARY"], cfg.SHOTS_FIRED_PRIMARY, CFG.DATA_WIDTHS.SHOTS_FIRED_PRIMARY)
                             Set_Output(i, "SHOTS_FIRED_PRIMARY", val); p.ShotCountPrimary = val
                        elseif cfg.SHOTS_FIRED_PRIMARY == "auto" and cfg.AMMO and p.WasActive then
                            local diff = (CFG.AMMO_DIRECTION == "decrease") and (curr_ammo < p.LastAmmo and p.LastAmmo <= t_ammo and p.LastAmmo - curr_ammo or 0) or ((curr_ammo > p.LastAmmo) and (curr_ammo - p.LastAmmo) or 0)
                            if diff > 0 or (CFG.AMMO_DIRECTION == "change" and curr_ammo ~= p.LastAmmo) then
                                p.ShotCountPrimary = p.ShotCountPrimary + (CFG.SHOTS_FIRED_METHOD == "bullets" and diff or 1)
                                Set_Output(i, "SHOTS_FIRED_PRIMARY", p.ShotCountPrimary)
                            end
                        end
                    end
                else
                    if cfg.AMMO then Set_Output(i, "AMMO", 0) end
                    if cfg.LIFE then Set_Output(i, "LIFE", 0) end
                end

                if alternate_active then
                    if cfg.AMMO_ALT then Set_Output(i, "AMMO_ALT", warmup_ok and curr_ammo_alt or 0) end
                    if cfg.LIFE_ALT then Set_Output(i, "LIFE_ALT", warmup_ok and curr_life_alt or 0) end
                    
                    if CFG.ENABLE_SHOT_COUNT and cfg.SHOTS_FIRED_ALT and warmup_ok then
                        if type(cfg.SHOTS_FIRED_ALT) == "number" then
                            local val = Read_Data_Safe(_MemHandles["SHOTS_FIRED_ALT"], cfg.SHOTS_FIRED_ALT, CFG.DATA_WIDTHS.SHOTS_FIRED_ALT)
                            Set_Output(i, "SHOTS_FIRED_ALT", val); p.ShotCountAlt = val
                        elseif cfg.SHOTS_FIRED_ALT == "auto" and cfg.AMMO_ALT and p.WasActive then
                            local diff = (CFG.AMMO_ALT_DIRECTION == "decrease") and (curr_ammo_alt < p.LastAmmoAlt and p.LastAmmoAlt <= t_alt and p.LastAmmoAlt - curr_ammo_alt or 0) or ((curr_ammo_alt > p.LastAmmoAlt) and (curr_ammo_alt - p.LastAmmoAlt) or 0)
                            if diff > 0 or (CFG.AMMO_ALT_DIRECTION == "change" and curr_ammo_alt ~= p.LastAmmoAlt) then
                                p.ShotCountAlt = p.ShotCountAlt + (CFG.SHOTS_FIRED_ALT_METHOD == "bullets" and diff or 1)
                                Set_Output(i, "SHOTS_FIRED_ALT", p.ShotCountAlt)
                            end
                        end
                    end
                    
                    if cfg.AMMO_GRENADE then Set_Output(i, "AMMO_GRENADE", warmup_ok and curr_ammo_grenade or 0) end
                    if CFG.ENABLE_SHOT_COUNT and cfg.SHOTS_FIRED_GRENADE and warmup_ok then
                        if type(cfg.SHOTS_FIRED_GRENADE) == "number" then
                            local val = Read_Data_Safe(_MemHandles["SHOTS_FIRED_GRENADE"], cfg.SHOTS_FIRED_GRENADE, CFG.DATA_WIDTHS.SHOTS_FIRED_GRENADE)
                            Set_Output(i, "SHOTS_FIRED_GRENADE", val); p.ShotCountGrenade = val
                        elseif cfg.SHOTS_FIRED_GRENADE == "auto" and cfg.AMMO_GRENADE and p.WasActive then
                            local diff = (CFG.AMMO_GRENADE_DIRECTION == "decrease") and (curr_ammo_grenade < p.LastAmmoGrenade and p.LastAmmoGrenade <= t_grenade and p.LastAmmoGrenade - curr_ammo_grenade or 0) or ((curr_ammo_grenade > p.LastAmmoGrenade) and (curr_ammo_grenade - p.LastAmmoGrenade) or 0)
                            if diff > 0 or (CFG.AMMO_GRENADE_DIRECTION == "change" and curr_ammo_grenade ~= p.LastAmmoGrenade) then
                                p.ShotCountGrenade = p.ShotCountGrenade + (CFG.SHOTS_FIRED_GRENADE_METHOD == "bullets" and diff or 1)
                                Set_Output(i, "SHOTS_FIRED_GRENADE", p.ShotCountGrenade)
                            end
                        end
                    end
                else
                    if cfg.AMMO_ALT then Set_Output(i, "AMMO_ALT", 0) end
                    if cfg.LIFE_ALT then Set_Output(i, "LIFE_ALT", 0) end
                    if cfg.AMMO_GRENADE then Set_Output(i, "AMMO_GRENADE", 0) end
                end
            else
                if cfg.AMMO then Set_Output(i, "AMMO", 0) end
                if cfg.LIFE then Set_Output(i, "LIFE", 0) end
                if cfg.AMMO_ALT then Set_Output(i, "AMMO_ALT", 0) end
                if cfg.LIFE_ALT then Set_Output(i, "LIFE_ALT", 0) end
                if cfg.AMMO_GRENADE then Set_Output(i, "AMMO_GRENADE", 0) end
            end
            
            if CFG.ENABLE_SHOT_COUNT and warmup_ok then
                local total_shots = p.ShotCountPrimary + p.ShotCountAlt + p.ShotCountGrenade
                Set_Output(i, "SHOTS_FIRED", total_shots)
            end

            -- Hit Damage, Environmental Rumble, and Life Lost processing
            if is_player_active or just_died then
                local hit_triggered = false
                
                -- Calculate Damage Taken
                if type(cfg.DAMAGE_TAKEN) == "number" then
                    local val = Read_Data_Safe(_MemHandles["DAMAGE_TAKEN"], cfg.DAMAGE_TAKEN, CFG.DATA_WIDTHS.DAMAGE_TAKEN)
                    if val > p.LastDmgMem and warmup_ok then
                        if CFG.ENABLE_DAMAGE_COUNT then p.DamageCount = p.DamageCount + 1; Set_Output(i, "DAMAGE_TAKEN", p.DamageCount) end
                        hit_triggered = true
                    end
                    p.LastDmgMem = val
                elseif cfg.DAMAGE_TAKEN == "auto" and (cfg.LIFE or cfg.LIFE_ALT) and p.WasActive then
                    local hit = (cfg.LIFE and ((CFG.LIFE_DIRECTION == "decrease" and curr_life < p.LastLife) or (curr_life > p.LastLife))) or (cfg.LIFE_ALT and ((CFG.LIFE_ALT_DIRECTION == "decrease" and curr_life_alt < p.LastLifeAlt) or (curr_life_alt > p.LastLifeAlt)))
                    if hit and warmup_ok then 
                        if CFG.ENABLE_DAMAGE_COUNT then p.DamageCount = p.DamageCount + 1; Set_Output(i, "DAMAGE_TAKEN", p.DamageCount) end
                        hit_triggered = true
                    end
                end

                local ffb_now = p.IsFFBAllowed or (just_died and p.WasFFBAllowed)
                
                -- Trigger Damage (Hit) FFB
                if cfg.DAMAGE and ffb_now then
                    if type(cfg.DAMAGE) == "number" then
                        local val = Read_Data_Safe(_MemHandles["DAMAGE"], cfg.DAMAGE, CFG.DATA_WIDTHS.DAMAGE)
                        if val > p.LastDamageVal then
                            Set_Output(i, "DAMAGE", 1); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(i, "Damaged", 1) end
                            p.DamageTick = current_time; p.IsDamageActive = true
                            if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].DamageTick = current_time; _Player[1].IsDamageActive = true end
                        end
                        p.LastDamageVal = val
                    elseif cfg.DAMAGE == "auto" and hit_triggered then
                        Set_Output(i, "DAMAGE", 1); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(i, "Damaged", 1) end
                        p.DamageTick = current_time; p.IsDamageActive = true
                        if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].DamageTick = current_time; _Player[1].IsDamageActive = true end
                    end
                end
                
                -- Trigger Environmental Rumble FFB
                if cfg.RUMBLE and ffb_now then
                    if type(cfg.RUMBLE) == "number" then
                        local val = Read_Data_Safe(_MemHandles["RUMBLE"], cfg.RUMBLE, CFG.DATA_WIDTHS.RUMBLE)
                        if val > p.LastRumbleEventVal then
                            Set_Output(i, "RUMBLE", 1)
                            p.RumbleTick = current_time; p.IsRumbleActive = true
                            if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].RumbleTick = current_time; _Player[1].IsRumbleActive = true end
                        end
                        p.LastRumbleEventVal = val
                    end
                end
                
                -- Calculate "Lives Lost" (Difference in life bar drops across the whole play session)
                if CFG.ENABLE_LIFE_LOST then
                    if cfg.LIFE_LOST == "auto" and (cfg.LIFE or cfg.LIFE_ALT) and warmup_ok and p.WasActive then
                         local lost = false
                         local diff = 0
                         if cfg.LIFE then
                             if CFG.LIFE_DIRECTION == "decrease" then
                                 if curr_life < p.LastLife then lost = true; diff = p.LastLife - curr_life end
                             else
                                 if curr_life > p.LastLife then lost = true; diff = curr_life - p.LastLife end
                             end
                         end
                         if cfg.LIFE_ALT then
                             if CFG.LIFE_ALT_DIRECTION == "decrease" then
                                 if curr_life_alt < p.LastLifeAlt then lost = true; diff = p.LastLifeAlt - curr_life_alt end
                             else
                                 if curr_life_alt > p.LastLifeAlt then lost = true; diff = curr_life_alt - p.LastLifeAlt end
                             end
                         end
                         if lost then
                             p.LifeLostCount = p.LifeLostCount + diff
                             Set_Output(i, "LIFE_LOST", p.LifeLostCount)
                         end
                    elseif type(cfg.LIFE_LOST) == "number" then
                         local val = Read_Data_Safe(_MemHandles["LIFE_LOST"], cfg.LIFE_LOST, CFG.DATA_WIDTHS.LIFE_LOST)
                         Set_Output(i, "LIFE_LOST", val)
                    end
                end
            end

            -- Update Frame History Cache (Used for Math on the NEXT frame)
            p.LastAmmo = curr_ammo; p.LastAmmoAlt = curr_ammo_alt; p.LastAmmoGrenade = curr_ammo_grenade
            p.LastLife = curr_life; p.LastLifeAlt = curr_life_alt; p.WasActive = p.IsActive; p.WasFFBAllowed = p.IsFFBAllowed

            -- Cleanup Hardware Timers (Shuts hardware off when time is up)
            if CFG.SIMULTANEOUS_PLAY or i == 1 then
                if p.IsRecoilActive and (current_time - p.RecoilTick > p.CurrentRecoilDuration) then Set_Output(i, "RECOIL", 0); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(i, "CtmRecoil", 0) end; p.IsRecoilActive = false end
                if p.IsReloadActive and (current_time - p.ReloadTick > _ReloadDuration) then Set_Output(i, "RELOAD", 0); p.IsReloadActive = false end
                if p.IsDamageActive and (current_time - p.DamageTick > _DamageDuration) then Set_Output(i, "DAMAGE", 0); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(i, "Damaged", 0) end; p.IsDamageActive = false end
                if p.IsRumbleActive and (current_time - p.RumbleTick > _RumbleDuration) then Set_Output(i, "RUMBLE", 0); p.IsRumbleActive = false end
            end
        end
        
        -- Override Global Credits if individual credits are actively mapped
        if using_individual_credits then
            Set_Global_Output("GLOBAL_CREDITS", warmup_ok and aggregated_credits or 0)
            if warmup_ok then
                if aggregated_credits > _LastGlobalCredits then
                    _GlobalCreditsInserted = _GlobalCreditsInserted + (aggregated_credits - _LastGlobalCredits)
                    if CFG.ENABLE_CREDIT_COUNT then Set_Global_Output("GLOBAL_CREDITS_INSERTED", _GlobalCreditsInserted) end
                elseif aggregated_credits < _LastGlobalCredits then
                    _PendingGlobalCreditDrops = _PendingGlobalCreditDrops + (_LastGlobalCredits - aggregated_credits)
                end
            end
            _LastGlobalCredits = aggregated_credits
            if aggregated_credits > 0 and warmup_ok then _HasCoinedUp = true end
        end
        
        local final_game_active = ((global_exists and is_game_active) or (not global_exists and any_player_active))
        Set_Global_Output("GLOBAL_GAME_STATUS", warmup_ok and final_game_active and 1 or 0)
        
        -- Walk-away protection: Clear session stats if inactive for a long time
        if not final_game_active then
            if _GameInactiveTick == _ZeroTime then 
                _GameInactiveTick = current_time 
            elseif CFG.CREDITS_CLEAR_TIMEOUT_SEC and (current_time - _GameInactiveTick > emu.attotime.from_seconds(CFG.CREDITS_CLEAR_TIMEOUT_SEC)) then
                _PendingGlobalCreditDrops = 0
                for i = 1, CFG.MAX_PLAYERS do _Player[i].PendingCreditDrops = 0 end
            end
        else
            _GameInactiveTick = _ZeroTime
        end

        -- ----------------------------------------------
        -- PHASE 5: MEMORY PATCHING (Anti-Seizure)
        -- Actively overwrites MAME memory to disable blinding flashes.
        -- ----------------------------------------------
        if warmup_ok and CFG.SCREEN_FLASH and CFG.SCREEN_FLASH_MEMORY_ADDRESS and CFG.SCREEN_FLASH_DISABLE_VALUE then
            Write_Data_Safe(_MemHandles["SCREEN_FLASH"], CFG.SCREEN_FLASH_MEMORY_ADDRESS, CFG.DATA_WIDTHS.SCREEN_FLASH or 8, CFG.SCREEN_FLASH_DISABLE_VALUE)
        end
    end

    -- -------------------------------------------------------------------------
    -- Compute_Outputs()
    -- @description: Safe execution wrapper for the Frame_Logic engine.
    -- @purpose: Runs `pcall(Frame_Logic)` instead of an anonymous function. 
    --           This is a massive performance optimization that prevents Lua's 
    --           Garbage Collector from allocating/destroying memory every single 
    --           frame (which causes micro-stutters).
    -- -------------------------------------------------------------------------
    local function Compute_Outputs()
        if _IsShuttingDown or not CFG then return end
        local status, err = pcall(Frame_Logic)
        if not status then dbg_print("CRITICAL FRAME ERROR: " .. tostring(err)) end
    end

    -- -------------------------------------------------------------------------
    -- on_machine_stop()
    -- @description: Cleanup hook. Halts processing and destroys subscriptions.
    -- -------------------------------------------------------------------------
    local function on_machine_stop()
        _IsShuttingDown = true
        
        -- Safely restore modified memory values before shutting down
        if CFG and CFG.SCREEN_FLASH and CFG.SCREEN_FLASH_MEMORY_ADDRESS and CFG.SCREEN_FLASH_RESTORE_VALUE then
            local conf = _MemConfig["SCREEN_FLASH"]
            if conf and manager and manager.machine and manager.machine.devices[conf.tag] then
                local dev = manager.machine.devices[conf.tag]
                if dev.spaces[conf.space] then
                    Write_Data_Safe(dev.spaces[conf.space], CFG.SCREEN_FLASH_MEMORY_ADDRESS, CFG.DATA_WIDTHS.SCREEN_FLASH or 8, CFG.SCREEN_FLASH_RESTORE_VALUE)
                end
            end
        end

        if exports.subscriptions.frame then
            exports.subscriptions.frame = nil -- Forces GC cleanup of the hook
        elseif emu.remove_machine_frame_notifier then
            emu.remove_machine_frame_notifier(Compute_Outputs)
        else
            emu.register_frame_done(nil, "frame")
        end
    end
    
    -- =========================================================================
    -- THE BOOT HOOK (on_start)
    -- This fires exactly once when a specific ROM finishes launching.
    -- Initializes arrays, validates DB config, and sets up timers.
    -- =========================================================================
    local function on_start()
        if not manager or not manager.machine then return end
        
        local rom_name = manager.machine.system.name
        dbg_print("Checking ROM: " .. tostring(rom_name))
        
        if db and type(db) == "table" and db[rom_name] then
            dbg_print("SUCCESS: ROM [" .. rom_name .. "] found in database!")
            dbg_osd("State Output Plugin: Activated for ROM [" .. rom_name .. "]")
            
            -- Merge game data with default template to ensure stability
            local merged = deep_merge(db["_default"], db[rom_name])
            CFG = normalize_variables(merged)
            
            -- Fix JSON limitations for hex strings
            convert_hex_strings_to_numbers(CFG) 
            
            -- Reset Engine Tracking
            _IsShuttingDown = false
            gamestatus = 0
            _HasCoinedUp = not CFG.CREDITS
            
            _LastGlobalCredits = 0
            _GlobalCreditsInserted = 0
            _PendingGlobalCreditDrops = 0
            
            -- Reset Memory Hardware Cache
            _MemConfig = {}
            _MemHandles = {}
            _HardwareBound = false
            _UniqueMemTargets = {}
            _OutputNames = {}
            _GlobalOutputs = {}
            
            -- Establish exact attotime durations for the specific machine
            _RecoilDuration = emu.attotime.from_msec(CFG.RECOIL_DURATION_MS or 40)
            _RecoilAltDuration = emu.attotime.from_msec(CFG.RECOIL_ALT_DURATION_MS or 80)
            _RecoilGrenadeDuration = emu.attotime.from_msec(CFG.RECOIL_GRENADE_DURATION_MS or 150)
            _MinRecoilInterval = emu.attotime.from_msec(CFG.MIN_RECOIL_INTERVAL_MS or 0)
            _RecoilHoldInterval = CFG.RECOIL_HOLD_MS and emu.attotime.from_msec(CFG.RECOIL_HOLD_MS) or _MinRecoilInterval
			-- SAFETY CLAMP: Prevent machine-gun freeze by forcing interval > duration
			if _MinRecoilInterval <= _RecoilDuration then _MinRecoilInterval = emu.attotime.from_msec((CFG.RECOIL_DURATION_MS or 40) + 20) end
			if _RecoilHoldInterval <= _RecoilDuration then _RecoilHoldInterval = emu.attotime.from_msec((CFG.RECOIL_DURATION_MS or 40) + 20) end
            _ReloadDuration = emu.attotime.from_msec(CFG.RELOAD_DURATION_MS or 40)
            _DamageDuration = emu.attotime.from_msec(CFG.DAMAGE_DURATION_MS or 250)
            _RumbleDuration = emu.attotime.from_msec(CFG.RUMBLE_DURATION_MS or CFG.DAMAGE_DURATION_MS or 250)
            _StartupTime = emu.attotime.from_msec(CFG.STARTUP_DELAY_MS or 0)
            _ZeroTime = emu.attotime.from_seconds(0)
            
            _GameActiveTick = _ZeroTime
            _GameInactiveTick = _ZeroTime
            
            -- Reset all multi-player arrays (prevents "dirty RAM" carrying over from past games)
            for i = 1, 4 do
                _Player[i] = { 
                    LastOutputs={}, LastAmmo=0, LastAmmoAlt=0, LastAmmoGrenade=0, LastLife=0, LastLifeAlt=0, LastDmgMem=0, LastCredits=0, LastReloadVal=0,
                    RecoilTick=_ZeroTime, ReloadTick=_ZeroTime, DamageTick=_ZeroTime, RumbleTick=_ZeroTime,
                    CurrentRecoilDuration=_RecoilDuration, LastRecoilVal=0, LastDamageVal=0, LastRumbleEventVal=0,
                    ShotCountPrimary=0, ShotCountAlt=0, ShotCountGrenade=0, DamageCount=0, LifeLostCount=0, CreditsInserted=0, CreditsConsumed=0, PendingCreditDrops=0,
                    IsActive=false, WasActive=false, ActiveTick=_ZeroTime,
                    IsRecoilActive=false, IsReloadActive=false, IsDamageActive=false, IsRumbleActive=false,
                    IsFFBAllowed=false, WasFFBAllowed=false
                }
            end
            
            -- Generate strings and math offsets
            Resolve_Addresses_And_Strings()
            
            -- [ ENGAGE THE FRAME LOOP ]
            if emu.add_machine_frame_notifier then
                exports.subscriptions.frame = emu.add_machine_frame_notifier(Compute_Outputs)
            else
                emu.register_frame_done(Compute_Outputs, "frame")
            end
        else
            dbg_print("DORMANT: ROM [" .. rom_name .. "] not supported in database.")
            dbg_osd("State Output: Dormant (ROM " .. rom_name .. " not supported)")
            CFG = nil
            
            if exports.subscriptions.frame then
                exports.subscriptions.frame = nil
            elseif emu.register_frame_done then
                emu.register_frame_done(nil, "frame")
            end
        end
    end
    
    -- =========================================================================
    -- COMPATIBILITY API REGISTRATION
    -- Associates our hooks with MAME events upon the plugin first loading.
    -- Subscriptions MUST be persistently stored in the exports table.
    -- =========================================================================
    if emu.add_machine_reset_notifier then
        exports.subscriptions.reset = emu.add_machine_reset_notifier(on_start)
    else
        emu.register_start(on_start)
    end
    
    if emu.add_machine_stop_notifier then
        exports.subscriptions.stop = emu.add_machine_stop_notifier(on_machine_stop)
    else
        emu.register_stop(on_machine_stop)
    end
end

return exports