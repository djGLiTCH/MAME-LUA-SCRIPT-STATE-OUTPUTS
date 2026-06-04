--
-- MAME STATE OUTPUT PLUGIN CORE
-- Version: 8.0.6
-- Last Modified Date (YYYY.MM.DD): 2026.05.23
-- Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
-- License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
-- Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
-- Created by DJ GLiTCH, with additional testing by Muggins
--

local exports = {
    name = "stateoutput",
    version = "8.0.6",
    description = "Universal Hardware State Output",
    license = "GNU GPL-v3.0",
    author = "Jacob Simpson (DJ GLiTCH)"
}

local stateoutput = exports

-- =========================================================================
-- USER SETTINGS
-- =========================================================================
-- Set to false to hide "[StateOutput]" messages in the MAME console and OSD.
local ENABLE_DEBUG_LOGS = true 

-- =========================================================================
-- CORE PLUGIN ENGINE
-- =========================================================================
function stateoutput.startplugin()
    
    -- Safe Loading: Try finding the database regardless of the exact folder name
    local success, db = pcall(require, "stateoutput/database")
    if not success then
        success, db = pcall(require, "database")
        if not success then db = {} end -- Prevent crash if missing
    end
    
    local CFG = nil
    
    -- Engine Variables
    local _Taps = {}
    local _HasCoinedUp = false
    local _IsShuttingDown = false
    local _GameActiveTick
    local _GameInactiveTick
    local _LastGlobalCredits = 0
    local _GlobalCreditsInserted = 0
    local _PendingGlobalCreditDrops = 0
    
    -- Hardware Caching Arrays
    local _MemConfig = {}
    local _MemHandles = {}
    local _HardwareBound = false
    
    local _UniqueMemTargets = {}
    local _PlayerCFG = {}
    local _OutputNames = {}
    local _GlobalOutputs = {}
    
    -- Timers (Instantiated after machine boots)
    local _RecoilDuration, _RecoilAltDuration, _RecoilGrenadeDuration, _MinRecoilInterval
    local _RecoilHoldInterval, _ReloadDuration, _DamageDuration, _RumbleDuration
    local _StartupTime, _ZeroTime
    
    local _Player = {}
    local _GlobalLastOutputs = {}
    local _InitTimer = 60
    local gamestatus = 0 
    
    -- MAME API Subscription Pointers (CRITICAL: Prevents Garbage Collection)
    local _reset_sub = nil
    local _stop_sub = nil
    local _frame_sub = nil

    -- -------------------------------------------------------------------------
    -- dbg_print() & dbg_osd()
    -- Handles conditional debug logging based on the ENABLE_DEBUG_LOGS toggle.
    -- -------------------------------------------------------------------------
    local function dbg_print(msg)
        if ENABLE_DEBUG_LOGS then print("[StateOutput] " .. tostring(msg)) end
    end
    local function dbg_osd(msg)
        if ENABLE_DEBUG_LOGS and manager and manager.machine then manager.machine:popmessage(tostring(msg)) end
    end

    -- -------------------------------------------------------------------------
    -- deep_merge()
    -- Recursively layers a specific game's ROM values on top of the _default template
    -- so that every required key is guaranteed to exist.
    -- -------------------------------------------------------------------------
    local function deep_merge(default_cfg, game_cfg)
        local result = {}
        for k, v in pairs(default_cfg) do
            if type(v) == "table" then result[k] = deep_merge(v, {})
            else result[k] = v end
        end
        for k, v in pairs(game_cfg) do
            if type(v) == "table" and type(result[k]) == "table" then result[k] = deep_merge(result[k], v)
            else result[k] = v end
        end
        return result
    end

    -- -------------------------------------------------------------------------
    -- normalize_variables()
    -- Standardizes legacy variable names to prevent crashes if old JSON templates are used.
    -- -------------------------------------------------------------------------
    local function normalize_variables(config)
        for i = 1, config.MAX_PLAYERS do
            local p_cfg = config["P"..i]
            if p_cfg then
                if p_cfg.LAMP_START ~= nil and p_cfg.LAMPSTART == nil then p_cfg.LAMPSTART = p_cfg.LAMP_START end
                if p_cfg.RECOIL ~= nil and p_cfg.DAMAGE == nil then p_cfg.DAMAGE = p_cfg.RECOIL end
            end
        end
        return config
    end

    -- -------------------------------------------------------------------------
    -- Resolve_Addresses_And_Strings()
    -- Evaluates all string paths, calculates offset hex math, and pre-caches 
    -- data widths and string prefixes to prevent GC stuttering during gameplay.
    -- -------------------------------------------------------------------------
    local function Resolve_Addresses_And_Strings()
        CFG.AMMO_DIRECTION             = string.lower(tostring(CFG.AMMO_DIRECTION or ""))
        CFG.AMMO_ALT_DIRECTION         = string.lower(tostring(CFG.AMMO_ALT_DIRECTION or ""))
        CFG.AMMO_GRENADE_DIRECTION     = string.lower(tostring(CFG.AMMO_GRENADE_DIRECTION or ""))
        CFG.LIFE_DIRECTION             = string.lower(tostring(CFG.LIFE_DIRECTION or ""))
        CFG.LIFE_ALT_DIRECTION         = string.lower(tostring(CFG.LIFE_ALT_DIRECTION or ""))
        CFG.SHOTS_FIRED_METHOD         = string.lower(tostring(CFG.SHOTS_FIRED_METHOD or "trigger"))
        CFG.FORCE_FEEDBACK_ENABLER     = string.lower(tostring(CFG.FORCE_FEEDBACK_ENABLER or "both"))
        CFG.RECOIL_METHOD              = string.lower(tostring(CFG.RECOIL_METHOD or "pulse"))
        CFG.RECOIL_PRIORITY            = string.lower(tostring(CFG.RECOIL_PRIORITY or "ammo"))

        -- OPTIMIZATION: Pre-lower data width strings to bypass string.lower() in the 60fps loop
        if CFG.DATA_WIDTHS then
            for k, v in pairs(CFG.DATA_WIDTHS) do
                if type(v) == "string" then CFG.DATA_WIDTHS[k] = string.lower(v) end
            end
        end

        local data_types = {
            "SCREEN_FLASH", "GLOBAL_ATTRACT_STATUS", "GLOBAL_CREDITS", "GLOBAL_GAME_STATUS",
            "CREDITS", "STATUS", "STATUS_ALT", "AMMO", "AMMO_ALT", "AMMO_GRENADE", "LIFE", "LIFE_ALT",
            "RECOIL", "RELOAD", "DAMAGE", "RUMBLE", "LAMPSTART", "LAMP_START",
            "SHOTS_FIRED_PRIMARY", "SHOTS_FIRED_ALT", "SHOTS_FIRED_GRENADE", "LIFE_LOST", "DAMAGE_TAKEN"
        }

        local function Resolve_Mem_Path(val, global_val)
            if val == nil or val == false or val == "" or string.lower(tostring(val)) == "auto" then return global_val end
            return tostring(val)
        end

        for _, key in ipairs(data_types) do
            local t = Resolve_Mem_Path(CFG.CPU_TAGS and CFG.CPU_TAGS[key], CFG.CPU_TAG or ":maincpu")
            local s = Resolve_Mem_Path(CFG.MEMORY_SPACES and CFG.MEMORY_SPACES[key], CFG.MEMORY_SPACE or "program")
            _MemConfig[key] = { tag = t, space = s }
        end

        -- Cache output strings
        for i = 1, CFG.MAX_PLAYERS do
            _OutputNames[i] = {}
            for key, suffix in pairs(CFG.OUTPUT_SUFFIXES) do
                if not string.match(key, "^GLOBAL_") then
                    local target_p = i
                    if not CFG.SIMULTANEOUS_PLAY and (key == "RECOIL" or key == "RELOAD" or key == "DAMAGE" or key == "RUMBLE" or key == "LAMP_START") then target_p = 1 end
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

        local all_players = { CFG.P1, CFG.P2, CFG.P3, CFG.P4 }
        for _, p_cfg in ipairs(all_players) do
            for k, val in pairs(p_cfg) do
                if type(val) == "string" and string.lower(val) == "auto" then p_cfg[k] = "auto" end
            end
        end

        -- Convert hex strings to numbers for offset calculations
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
                    elseif p1_val == "auto" then 
                        p_cfg[key] = "auto"
                        if CFG.P1[key] == false then p_cfg[key] = false end
                    else 
                        p_cfg[key] = false 
                    end
                end
            end
        end
        _PlayerCFG = { CFG.P1, CFG.P2, CFG.P3, CFG.P4 }
    end

    local function Is_Warmup_Complete() return manager.machine.time > _StartupTime end

    -- -------------------------------------------------------------------------
    -- Read_Data_Safe()
    -- Accesses native MAME memory blocks dynamically based on user-defined bit widths.
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
    -- Register_Outputs_Safe()
    -- Pushes all defined hardware outputs to 0 upon boot to initialize hardware cleanly.
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
                    if k == "DAMAGE" and CFG.DEMULSHOOTER_COMPATIBILITY then out_handle:set_value(_OutputNames[i]["CtmRecoil"], 0) end
                end
            end
        end
    end

    -- =========================================================================
    -- THE FRAME LOOP ENGINE
    -- Extracted into a standalone function to entirely eliminate closure
    -- memory allocations (GC spikes) during the 60fps runtime loop.
    -- =========================================================================
    local function Frame_Logic()
        local machine = manager.machine
        if not machine then _IsShuttingDown = true; return end
        
        local out = machine.output
        local current_time = machine.time
        if not out then return end
        
        -- OPTIMIZATION: One-Time Hardware Cache Binding
        -- Binds memory buses on frame 1 to permanently avoid device tree traversal.
        if not _HardwareBound then
            for key, conf in pairs(_MemConfig) do
                local dev = machine.devices[conf.tag]
                if dev and dev.spaces[conf.space] then
                    _MemHandles[key] = dev.spaces[conf.space]
                end
            end
            _HardwareBound = true
        end
        
        -- Output Spam Wrapper (Only talks to MAME API if value has changed)
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
        -- ATTRACT & GLOBAL CREDITS
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

        -- ----------------------------------------------
        -- GAME STATUS DEDICATED TRACKER
        -- ----------------------------------------------
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
        -- PLAYER LOOP & PRIORITY ENFORCEMENT
        -- ----------------------------------------------
        local any_player_active = false
        for i = 1, CFG.MAX_PLAYERS do
            local cfg = _PlayerCFG[i]
            local p = _Player[i]
            
            if is_attract_mode then p.PendingCreditDrops = 0 end
            
            local curr_ammo, curr_ammo_alt, curr_ammo_grenade, curr_life, curr_life_alt = 0, 0, 0, 0, 0
            
            if cfg.AMMO then 
                curr_ammo = Read_Data_Safe(_MemHandles["AMMO"], cfg.AMMO, CFG.DATA_WIDTHS.AMMO) + (CFG.AMMO_OFFSET or 0)
                if CFG.AMMO_MAX and curr_ammo > CFG.AMMO_MAX then curr_ammo = 0 end
            end
            if cfg.AMMO_ALT then 
                curr_ammo_alt = Read_Data_Safe(_MemHandles["AMMO_ALT"], cfg.AMMO_ALT, CFG.DATA_WIDTHS.AMMO_ALT) + (CFG.AMMO_ALT_OFFSET or 0)
                if CFG.AMMO_ALT_MAX and curr_ammo_alt > CFG.AMMO_ALT_MAX then curr_ammo_alt = 0 end
            end
            if cfg.LIFE then 
                curr_life = Read_Data_Safe(_MemHandles["LIFE"], cfg.LIFE, CFG.DATA_WIDTHS.LIFE) + (CFG.LIFE_OFFSET or 0)
                if CFG.LIFE_MAX and curr_life > CFG.LIFE_MAX then curr_life = 0 end
            end

            local p_credits = 0
            local p_credits_known = false
            if cfg.CREDITS then
                if type(cfg.CREDITS) == "number" then 
                    local raw = Read_Data_Safe(_MemHandles["CREDITS"], cfg.CREDITS, CFG.DATA_WIDTHS.CREDITS)
                    p_credits = math.floor(raw / divisor)
                    p_credits_known = true
                    Set_Output(i, "CREDITS", warmup_ok and p_credits or 0)
                elseif cfg.CREDITS == "auto" and CFG.CREDITS then 
                    p_credits = Read_Data_Safe(_MemHandles["GLOBAL_CREDITS"], CFG.CREDITS, CFG.DATA_WIDTHS.GLOBAL_CREDITS) 
                end
            end
            
            if cfg.LAMPSTART then 
                Set_Output(i, "LAMP_START", warmup_ok and Read_Data_Safe(_MemHandles["LAMPSTART"], cfg.LAMPSTART, CFG.DATA_WIDTHS.LAMP_START) or 0)
            end

            local is_player_active = false
            local out_status_val = 0

            if not is_attract_mode then
                local p_stat_active = false
                if cfg.STATUS and cfg.STATUS ~= "auto" then
                    local val = Read_Data_Safe(_MemHandles["STATUS"], cfg.STATUS, CFG.DATA_WIDTHS.STATUS)
                    local act = cfg.STATUS_ACTIVE_VALUE or CFG.STATUS_ACTIVE_VALUE
                    p_stat_active = (type(act) == "table") and (function() for _,v in ipairs(act) do if val == v then return true end end return false end)() or ((type(act) == "number" and val == act) or (not act and val > 0))
                end
                
                if p_stat_active then
                    is_player_active = true
                    out_status_val = 1
                elseif gamestatus > 0 then
                    is_player_active = true
                    out_status_val = 1
                elseif (curr_life > 0 or curr_life_alt > 0) then
                    if not global_exists then
                        if _HasCoinedUp and ((not p_credits_known) or p_credits > 0) then 
                            is_player_active = true
                            out_status_val = 1 
                        end
                    end
                end
            end
            
            if not warmup_ok then is_player_active = false; out_status_val = 0 end
            
            if is_player_active then
                if p.ActiveTick == _ZeroTime then p.ActiveTick = current_time end
                if (current_time - p.ActiveTick) <= emu.attotime.from_msec(CFG.STATUS_DEBOUNCE_MS or 0) then is_player_active = false; out_status_val = 0 end
            else p.ActiveTick = _ZeroTime; out_status_val = 0 end
            
            p.IsActive = is_player_active
            if is_player_active then any_player_active = true end
            p.IsFFBAllowed = (CFG.FORCE_FEEDBACK_ENABLER == "status") and (out_status_val == 1) or (CFG.FORCE_FEEDBACK_ENABLER == "life") and (curr_life > 0 or curr_life_alt > 0) or (CFG.FORCE_FEEDBACK_ENABLER == "gamestatus") and is_game_active or is_player_active
            
            if cfg.STATUS then Set_Output(i, "STATUS", out_status_val) end
            local just_died = (not is_player_active and p.WasActive)
            
            local auto_recoil_triggered_this_frame = false
            local t_ammo = CFG.AMMO_THRESHOLD or 254
            
            if p.IsFFBAllowed then
                  local trigger = 0
                  if CFG.ENABLE_RECOIL_AMMO ~= false and cfg.AMMO then
                      if CFG.AMMO_DIRECTION == "decrease" then if curr_ammo < p.LastAmmo and p.LastAmmo <= t_ammo then trigger = 1 end
                      elseif CFG.AMMO_DIRECTION == "change" then if curr_ammo ~= p.LastAmmo then trigger = 1 end
                      elseif curr_ammo > p.LastAmmo then trigger = 1 end
                  end
                  
                  local trigger_source = cfg.DAMAGE or cfg.RECOIL 
                  
                  if trigger > 0 and (trigger_source == "auto" or (type(trigger_source) == "number" and CFG.RECOIL_PRIORITY == "ammo")) then
                      if current_time - p.RecoilTick > _MinRecoilInterval then
                          p.CurrentRecoilDuration = _RecoilDuration
                          Set_Output(i, "RECOIL", 1); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(i, "CtmRecoil", 1) end
                          p.RecoilTick = current_time
                          p.IsRecoilActive = true
                          auto_recoil_triggered_this_frame = true
                          if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].RecoilTick = current_time; _Player[1].IsRecoilActive = true end
                      end
                  end
                  
                  if not auto_recoil_triggered_this_frame and type(trigger_source) == "number" then
                      local val = Read_Data_Safe(_MemHandles["RECOIL"], trigger_source, CFG.DATA_WIDTHS.RECOIL)
                      if (CFG.RECOIL_PRIORITY ~= "ammo" or curr_ammo == 0) then
                          local manual_trigger = (CFG.RECOIL_METHOD == "hold") and (val > 0) or (val > p.LastRecoilVal)
                          local active_interval = (CFG.RECOIL_METHOD == "hold") and _RecoilHoldInterval or _MinRecoilInterval
                          
                          if manual_trigger and (current_time - p.RecoilTick > active_interval) then
                              p.CurrentRecoilDuration = _RecoilDuration; Set_Output(i, "RECOIL", 1)
                              if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(i, "CtmRecoil", 1) end
                              p.RecoilTick = current_time; p.IsRecoilActive = true
                          end
                      end
                      p.LastRecoilVal = val
                  end
            end

            if is_player_active or just_died then
                if cfg.AMMO then Set_Output(i, "AMMO", warmup_ok and curr_ammo or 0) end
                if cfg.LIFE then Set_Output(i, "LIFE", warmup_ok and curr_life or 0) end
            else
                if cfg.AMMO then Set_Output(i, "AMMO", 0) end
                if cfg.LIFE then Set_Output(i, "LIFE", 0) end
            end

            p.LastAmmo = curr_ammo
            p.LastLife = curr_life
            p.WasActive = p.IsActive
            p.WasFFBAllowed = p.IsFFBAllowed

            if CFG.SIMULTANEOUS_PLAY or i == 1 then
                if p.IsRecoilActive and (current_time - p.RecoilTick > p.CurrentRecoilDuration) then Set_Output(i, "RECOIL", 0); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(i, "CtmRecoil", 0) end; p.IsRecoilActive = false end
                if p.IsReloadActive and (current_time - p.ReloadTick > _ReloadDuration) then Set_Output(i, "RELOAD", 0); p.IsReloadActive = false end
            end
        end
        
        local final_game_active = ((global_exists and is_game_active) or (not global_exists and any_player_active))
        Set_Global_Output("GLOBAL_GAME_STATUS", warmup_ok and final_game_active and 1 or 0)
        
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
    end

    -- Pcall execution wrapper handles the frame safely without closure allocation
    local function Compute_Outputs()
        if _IsShuttingDown or not CFG then return end
        local status, err = pcall(Frame_Logic)
        if not status then
            dbg_print("CRITICAL FRAME ERROR: " .. tostring(err))
        end
    end

    -- -------------------------------------------------------------------------
    -- on_machine_stop()
    -- Safely halts processing and destroys subscriptions to prevent memory leaks
    -- -------------------------------------------------------------------------
    local function on_machine_stop()
        _IsShuttingDown = true
        if _frame_sub then
            _frame_sub = nil
        elseif emu.remove_machine_frame_notifier then
            emu.remove_machine_frame_notifier(Compute_Outputs)
        else
            emu.register_frame_done(nil, "frame")
        end
    end
    
    -- =========================================================================
    -- THE BOOT HOOK
    -- This fires exactly once when the specific ROM starts.
    -- =========================================================================
    local function on_start()
        if not manager or not manager.machine then return end
        
        local rom_name = manager.machine.system.name
        dbg_print("Checking ROM: " .. tostring(rom_name))
        
        if db and type(db) == "table" and db[rom_name] then
            dbg_print("SUCCESS: ROM [" .. rom_name .. "] found in database!")
            dbg_osd("State Output Plugin: Activated for ROM [" .. rom_name .. "]")
            
            local merged = deep_merge(db["_default"], db[rom_name])
            CFG = normalize_variables(merged)
            
            _IsShuttingDown = false
            gamestatus = 0
            _HasCoinedUp = not CFG.CREDITS
            
            _LastGlobalCredits = 0
            _GlobalCreditsInserted = 0
            _PendingGlobalCreditDrops = 0
            
            -- Reset cache for new ROM
            _MemConfig = {}
            _MemHandles = {}
            _HardwareBound = false
            _UniqueMemTargets = {}
            _OutputNames = {}
            _GlobalOutputs = {}
            
            _RecoilDuration = emu.attotime.from_msec(CFG.RECOIL_DURATION_MS or 40)
            _RecoilAltDuration = emu.attotime.from_msec(CFG.RECOIL_ALT_DURATION_MS or 80)
            _RecoilGrenadeDuration = emu.attotime.from_msec(CFG.RECOIL_GRENADE_DURATION_MS or 150)
            _MinRecoilInterval = emu.attotime.from_msec(CFG.MIN_RECOIL_INTERVAL_MS or 0)
            _RecoilHoldInterval = CFG.RECOIL_HOLD_MS and emu.attotime.from_msec(CFG.RECOIL_HOLD_MS) or _MinRecoilInterval
            _ReloadDuration = emu.attotime.from_msec(CFG.RELOAD_DURATION_MS or 40)
            _DamageDuration = emu.attotime.from_msec(CFG.DAMAGE_DURATION_MS or 250)
            _RumbleDuration = emu.attotime.from_msec(CFG.RUMBLE_DURATION_MS or CFG.DAMAGE_DURATION_MS or 250)
            _StartupTime = emu.attotime.from_msec(CFG.STARTUP_DELAY_MS or 0)
            _ZeroTime = emu.attotime.from_seconds(0)
            
            _GameActiveTick = _ZeroTime
            _GameInactiveTick = _ZeroTime
            
            for i = 1, 4 do
                _Player[i] = { 
                    LastOutputs={}, LastAmmo=0, LastAmmoAlt=0, LastAmmoGrenade=0, LastLife=0, LastLifeAlt=0, LastDmgMem=0, LastCredits=0,
                    RecoilTick=_ZeroTime, ReloadTick=_ZeroTime, DamageTick=_ZeroTime, RumbleTick=_ZeroTime,
                    CurrentRecoilDuration=_RecoilDuration, LastRecoilVal=0, LastDamageVal=0, LastRumbleEventVal=0,
                    ShotCountPrimary=0, ShotCountAlt=0, ShotCountGrenade=0, DamageCount=0, LifeLostCount=0, CreditsInserted=0, CreditsConsumed=0, PendingCreditDrops=0,
                    IsActive=false, WasActive=false, ActiveTick=_ZeroTime,
                    IsRecoilActive=false, IsReloadActive=false, IsDamageActive=false, IsRumbleActive=false,
                    IsFFBAllowed=false, WasFFBAllowed=false
                }
            end
            
            Resolve_Addresses_And_Strings()
            
            -- Lock the frame loop to a persistent subscription pointer
            if emu.add_machine_frame_notifier then
                _frame_sub = emu.add_machine_frame_notifier(Compute_Outputs)
            else
                emu.register_frame_done(Compute_Outputs, "frame")
            end
        else
            dbg_print("DORMANT: ROM [" .. rom_name .. "] not supported in database.")
            dbg_osd("State Output: Dormant (ROM " .. rom_name .. " not supported)")
            CFG = nil
            
            if _frame_sub then
                _frame_sub = nil
            elseif emu.register_frame_done then
                emu.register_frame_done(nil, "frame")
            end
        end
    end
    
    -- =========================================================================
    -- COMPATIBILITY API REGISTRATION
    -- Subscriptions MUST be assigned to local variables, otherwise Lua destroys them.
    -- =========================================================================
    if emu.add_machine_reset_notifier then
        _reset_sub = emu.add_machine_reset_notifier(on_start)
    else
        emu.register_start(on_start)
    end
    
    if emu.add_machine_stop_notifier then
        _stop_sub = emu.add_machine_stop_notifier(on_machine_stop)
    else
        emu.register_stop(on_machine_stop)
    end
end

return exports