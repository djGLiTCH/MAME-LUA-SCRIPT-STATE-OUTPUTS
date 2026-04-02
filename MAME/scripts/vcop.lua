------------------------------------------------------
-- UNIVERSAL MAME LUA SCRIPT FOR STATE OUTPUTS (DESIGNED FOR LIGHT GUNS)
-- GitHub: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
-- Universal Script Version: 5.4.4
-- Last Modified Date (YYYY.MM.DD): 2026.04.02
-- Created by DJ GLiTCH, with testing help from Muggins
-- License: GNU GENERAL PUBLIC LICENSE 3.0
-- MAME ROM: vcop
------------------------------------------------------

local CFG = {
    --------------------------------------------------
    -- SCRIPT METADATA                              --
    --------------------------------------------------
    -- MAME state outputs only support integers (no decimals or text strings)
    -- LUA Version represents the version of the universal MAME LUA script used as the baseline code
    -- LUA Version can only be integer numbers (e.g. 543 = v5.4.3)
    -- LUA Date represents the date that the script was last modified (since this is often later than when the LUA Version was created)
    -- LUA Date can only be integer numbers (e.g. 20260402 = 2026.04.02)
    LUA_VERSION = 544,
    LUA_DATE    = 20260402,
    
    --------------------------------------------------
    -- SYSTEM SETTINGS                              --
    --------------------------------------------------
    -- STARTUP_DELAY_MS: Time to wait before tracking stats (in ms)
    -- Prevents false "shots fired" events and blocks "Dirty RAM" on boot
    -- Default: 5000 (5 seconds)
    STARTUP_DELAY_MS = 15000,
    
    -- STATUS_DEBOUNCE_MS: Time (in ms) to wait before validating an "Active" state
    -- Prevents 1-frame flashes if a game updates its GameStatus memory a frame BEFORE its AttractStatus / Attract Mode memory
    -- Default: 34 (Approx 2 frames at 60fps)
    STATUS_DEBOUNCE_MS = 34,
    
    -- COINS_PER_CREDIT: How many coins make 1 Credit?
    -- Used to calculate the correct "Credits" value for state outputs
    -- Logic: math.floor(Coins / COINS_PER_CREDIT)
    -- Example: Set COINS_PER_CREDIT = 2. If you insert 3 coins, output is 1 Credit (1.5 credits rounds down to 1 credit)
    -- Default: 1 (1 Coin = 1 Credit)
    COINS_PER_CREDIT = 1,
    
    -- MAX_PLAYERS: Set the number of players to track (1 to 4)
    -- Default: 2
    MAX_PLAYERS = 2,
    
    -- SIMULTANEOUS_PLAY: Controls how outputs are routed
    -- true  = Standard Arcade Mode (Simultaneous)
    --          Each player has their own outputs (P1 triggers P1_Recoil, P2 triggers P2_Recoil)
    -- false = Shared Hardware Mode (Turn Based)
    --          All players route to P1 outputs (P2 memory events trigger P1_Recoil)
    SIMULTANEOUS_PLAY = true,
    
    --------------------------------------------------
    -- STATE OUTPUT NAMES (SUFFIXES)                --
    --------------------------------------------------
    -- Customize the string names sent to external software
    -- The script will automatically prepend the player number (e.g. "P1_")
    -- Change these if your hardware software expects different names
    OUTPUT_SUFFIXES = {
        GLOBAL_LUA_VERSION    = "LUA_VERSION",
        GLOBAL_LUA_DATE       = "LUA_DATE",
        GLOBAL_CREDITS        = "Credits",
        GLOBAL_GAME_STATUS    = "GameStatus",
        GLOBAL_ATTRACT_STATUS = "AttractStatus",
        CREDITS               = "Credits",
        STATUS                = "Status",
        STATUS_ALT            = "StatusAlt",
        AMMO                  = "Ammo",
        AMMO_ALT              = "AmmoAlt",
        LIFE                  = "Life",
        LIFE_ALT              = "LifeAlt",
        RECOIL                = "Recoil",
        RELOAD                = "Reload",
        DAMAGE                = "Damage",
        LAMP_START            = "LampStart",
        SHOTS_FIRED           = "ShotsFired",
        SHOTS_FIRED_ALT       = "ShotsFiredAlt",
        DAMAGE_TAKEN          = "DamageTaken",
        LIFE_LOST             = "LifeLost",
    },
    
    --------------------------------------------------
    -- HARDWARE CONFIGURATION                       --
    --------------------------------------------------
    
    -- MEMORY READ WIDTHS (8, 16, 32, "float32", "float32be", or "output")
    -- Define how many bits to read for each data type
    --
    -- VALID VALUES:
    -- 8             = Byte (standard) - default for majority of arcade state outputs
    -- 16            = Word
    -- 32            = Dword
    -- "float32"     = 32-bit Float
    -- "float32be"   = 32-bit Big Endian Float
    -- "output"      = NATIVE MIRROR MODE
    --                 If set to "output", the script will NOT read memory addresses
    --                 Instead, it will read the value of a native MAME output string that you define in the player tables below
    DATA_WIDTHS = {
        GLOBAL_ATTRACT_STATUS = 8,
        GLOBAL_CREDITS        = 8,
        GLOBAL_GAME_STATUS    = 8,
        CREDITS               = 8,
        STATUS                = 8,
        STATUS_ALT            = 8,
        AMMO                  = 8,
        AMMO_ALT              = 8,
        LIFE                  = 8,
        LIFE_ALT              = 8,
        RECOIL                = 8,
        RELOAD                = 8,
        DAMAGE                = 8,
        LAMP_START            = "output",
        SHOTS_FIRED           = 16,
        SHOTS_FIRED_ALT       = 16,
        LIFE_LOST             = 16,
        DAMAGE_TAKEN          = 16,
    },
    
    -- MEMORY_ALIGNMENT: Controls the "width" of the high-speed memory tap
    --
    -- TROUBLESHOOTING GUIDE:
    -- 1. Start with MEMORY_ALIGNMENT = 32 (32-bit)
    -- 2. Run the script
    -- 3. If MAME crashes with "end address has low bits unset", change MEMORY_ALIGNMENT to 16 (16-bit)
    -- 4. If that fails, change to 8 (8-bit)
    -- 5. If 8 fails or causes instability, set to false (Standard Polling)
    --
    -- VALID VALUES:
    -- 32          = 32-bit (Model 2/3, Namco System 11/12, PlayStation, Beast Busters, CarnEvil, etc)
    -- 16          = 16-bit (Sega System 16/32, SNES/Genesis, NeoGeo, etc)
    -- 8           = 8-bit  (Operation Wolf, T2, Midway Y-Unit, etc)
    -- false / nil = Standard Polling (Safe Mode, slightly more latency, typically 1 frame / 16ms)
    MEMORY_ALIGNMENT = false,
    
    -- PLAYER_MEMORY_OFFSET: Distance between P1 and next player's memory (in bytes)
    -- Used ONLY when P2, P3, P4 addresses below are set to "auto"
    --
    -- IMPORTANT FOR SIMULTANEOUS PLAY:
    -- If SIMULTANEOUS_PLAY = true, you usually need a real offset (e.g. 0xA8, 0x40, 4), unless you record individual memory addresses for each player
    --
    -- SHARED MEMORY / TURN BASED:
    -- Set to 0 or false. This forces P2 to read the same address as P1 (Offset 0)
    -- Setting to 0 perfectly syncs P2 logic to P1 memory for Turn-Based games
    PLAYER_MEMORY_OFFSET = 4,
    
    -- PLAYER_CREDIT_MEMORY_OFFSET: Specific offset for Credits only
    -- Use this if Credits are stored in a different area than Ammo/Life
    -- 
    -- COMMON VALUES:
    -- nil / false = Uses the standard PLAYER_MEMORY_OFFSET defined above
    -- 1           = Adjacent Byte (Common for NeoGeo / packed arrays)
    -- 4           = Adjacent Integer (If credits are 32-bit)
    PLAYER_CREDIT_MEMORY_OFFSET = false,
    
    --------------------------------------------------
    -- PULSE TIMING (Milliseconds)                  --
    --------------------------------------------------
    RECOIL_DURATION_MS     = 40, -- Signal pulse duration for standard recoil outputs
    RECOIL_ALT_DURATION_MS = 80, -- Signal pulse duration for alternate recoil outputs (lower to 40 if a standard typical weapon is used as an alternative weapon in-game)
    RELOAD_DURATION_MS     = 40, -- Signal pulse duration for reload outputs
    
    -- MACHINE GUN RATE LIMITER
    -- Minimum time (in ms) between recoil pulses
    -- If the game fires faster than this, the script ignores the extra shots to allow the solenoid to physically return and "kick" again
    -- Recommended: 80ms - 100ms for Machine Guns (approx 10-12 rounds/sec)
    -- Set to 0 to disable (fires as fast as possible, may cause "humming")
    MIN_RECOIL_INTERVAL_MS = 100, -- Minimum time gap between each signal pulse for recoil outputs (prevents burning out solenoids)
    
    DAMAGE_DURATION_MS     = 250, -- Signal pulse duration for damage (useful if light gun supports rumble feedback)
    
    --------------------------------------------------
    -- AMMO MATH ADJUSTMENTS                        --
    --------------------------------------------------
    -- AMMO_OFFSET: Added to the memory value before processing
    -- Useful if the game stores "0" for 1 bullet remaining
    -- Set to 0 or false to disable (use raw memory value)
    AMMO_OFFSET     = false,
    AMMO_ALT_OFFSET = false,
    
    -- AMMO_MAX: Any value ABOVE this number is clamped to 0
    -- Useful if the game sets ammo to 255 (0xFF) or 99 during reloading/infinity states
    -- Prevents massive jumps in the "Shots Fired" counter and stops infinite recoil loops
    -- Recommend setting this to exactly the max capacity of the primary weapon
    AMMO_MAX     = false,
    AMMO_ALT_MAX = false,
    
    --------------------------------------------------
    -- LIFE MATH ADJUSTMENTS                        --
    --------------------------------------------------
    -- LIFE_OFFSET: Added to the memory value before processing
    -- Useful if the game stores "0" for 1 life remaining
    -- Example: Memory reads 0. LIFE_OFFSET = 1. Result = 1
    -- Set to 0 or false to disable this logic (use raw memory value)
    LIFE_OFFSET     = false,
    LIFE_ALT_OFFSET = false,
    
    -- LIFE_MAX: Any value ABOVE this number is clamped to 0
    -- Useful if the game wraps memory to 255 (0xFF) when the player dies
    -- Set to false to disable this logic (no clamping)
    LIFE_MAX     = false,
    LIFE_ALT_MAX = false,
    
    --------------------------------------------------
    -- MEMORY ADDRESSES / OUTPUT NAMES              --
    --------------------------------------------------
    -- GLOBAL ATTRACT STATUS:
    -- If provided, forces GameStatus to 0 (inactive) whenever this memory address reads > 0 (or exactly matches ATTRACT_STATUS_ACTIVE_VALUE).
    -- Useful for games that erroneously flag GameStatus as active during attract mode sequences.
    ATTRACT_STATUS = false,
    
    -- GLOBAL CREDITS: 
    -- Set to 'false' if game uses Per-Player only or if you want to bypass the 
    -- "Wait for Credits" safety check.
    CREDITS        = 0x00559270,
    
    -- GLOBAL GAME STATUS: 
    -- Set to 'false' if you want to rely on Priority 1 (Player Status) or Priority 3 (Fallback)
    -- If set to 'false', the script will calculate GameStatus = 1 if ANY player is active
    GAME_STATUS    = false,
    
    -- ACTIVE VALUES:
    -- Defines the exact numerical value that indicates active gameplay for STATUS blocks
    -- Set to 'false' to use the default logic (any value > 0 is considered active)
    -- Set to 0 if the game uses 0 to denote active gameplay
    ATTRACT_STATUS_ACTIVE_VALUE = false,
	GAME_STATUS_ACTIVE_VALUE    = false,
    STATUS_ACTIVE_VALUE         = false,
    STATUS_ALT_ACTIVE_VALUE     = false,
    
    P1 = {
        -- Use specific addresses (e.g. 0x...) if you know them, otherwise set to "auto" (if applicable) or false (if appropriate)
        -- At a minimum, it is recommended that AMMO and LIFE contain memory addresses for P1, which will enable automatic logic for other variables and functions
        
        -- If CREDITS = "auto", then use Global CREDITS address defined above
        CREDITS         = false,
        
        -- PLAYER STATUS (Priority 1):
        -- If player status is set, this value strictly determines if this player is active
        -- If a memory address is provided for player status, it overrides Global Status and Fallback logic for this specific player
        STATUS          = 0x0050EE30,
        STATUS_ALT      = false,
        AMMO            = 0x0050EE38,
        AMMO_ALT        = false,
        LIFE            = 0x0050EE70,
        LIFE_ALT        = false,
        
        -- Recoil, Reload, and Damage are hardware force feedback values, with Recoil being related to a player shooting their weapon, Reload when changing their weapon magazine/clip, and Damage when a player is damaged in-game and/or loses a life (used for "rumble")
        RECOIL          = "auto",
        RELOAD          = "auto",
        DAMAGE          = "auto",
        
        -- LAMP_START: 
        -- If you want to mirror the native MAME output:
        -- 1. Set DATA_WIDTHS.LAMP_START = "output" above
        -- 2. Set LAMP_START = "lamp0" or whatever is appropriate below
        LAMP_START      = "lamp0",
        
        -- "auto" = Calculate based on Ammo/Life changes, 0xADDRESS = Read directly from game memory (no quotes), false = Disable this specific counter
        SHOTS_FIRED     = "auto",
        SHOTS_FIRED_ALT = false,
        DAMAGE_TAKEN    = "auto",
        
        -- Tracks number of lives lost
        -- "auto" = Calculate based on Life change, 0xADDRESS = Read memory, false = Disable
        LIFE_LOST       = "auto",
    },
    P2 = {
        -- Setting AMMO and LIFE to auto inherits P1's addresses for Shared Engine Turn-Based play
        CREDITS         = "auto",
        STATUS          = "auto",
        STATUS_ALT      = "auto",
        AMMO            = "auto",
        AMMO_ALT        = "auto",
        LIFE            = "auto",
        LIFE_ALT        = "auto",
        RECOIL          = "auto",
        RELOAD          = "auto",
        DAMAGE          = "auto",
        LAMP_START      = "lamp1",
        SHOTS_FIRED     = "auto",
        SHOTS_FIRED_ALT = "auto",
        DAMAGE_TAKEN    = "auto",
        LIFE_LOST       = "auto",
    },
    P3 = {
        -- Configuration for Player 3. "auto" will use (P1 Address + PLAYER_MEMORY_OFFSET * 2)
        CREDITS         = "auto",
        STATUS          = "auto",
        STATUS_ALT      = "auto",
        AMMO            = "auto",
        AMMO_ALT        = "auto",
        LIFE            = "auto",
        LIFE_ALT        = "auto",
        RECOIL          = "auto",
        RELOAD          = "auto",
        DAMAGE          = "auto",
        LAMP_START      = "auto",
        SHOTS_FIRED     = "auto",
        SHOTS_FIRED_ALT = "auto",
        DAMAGE_TAKEN    = "auto",
        LIFE_LOST       = "auto",
    },
    P4 = {
        -- Configuration for Player 4. "auto" will use (P1 Address + PLAYER_MEMORY_OFFSET * 3)
        CREDITS         = "auto",
        STATUS          = "auto",
        STATUS_ALT      = "auto",
        AMMO            = "auto",
        AMMO_ALT        = "auto",
        LIFE            = "auto",
        LIFE_ALT        = "auto",
        RECOIL          = "auto",
        RELOAD          = "auto",
        DAMAGE          = "auto",
        LAMP_START      = "auto",
        SHOTS_FIRED     = "auto",
        SHOTS_FIRED_ALT = "auto",
        DAMAGE_TAKEN    = "auto",
        LIFE_LOST       = "auto",
    },
    
    -- AMMO_DIRECTION: How the game counts ammo (Used for "auto" logic)
    -- "decrease" = Counts down (6->5->4). Standard for most games
    -- "increase" = Counts up (0->1->2)
    AMMO_DIRECTION     = "decrease",
    AMMO_ALT_DIRECTION = "decrease",
    
    -- LIFE_DIRECTION: How the game counts life (Used for "auto" logic)
    -- "decrease" = Life bar goes down (Standard)
    -- "increase" = Damage counter goes up (Hits Taken)
    LIFE_DIRECTION     = "decrease",
    LIFE_ALT_DIRECTION = "decrease",
    
    -- SHOTS_FIRED_METHOD: Calculation Logic (Used only if Source is "auto")
    -- "trigger" = Counts +1 for every event (Best for semi-auto)
    -- "bullets" = Counts exact difference (Best for machine guns)
    SHOTS_FIRED_METHOD     = "trigger",
    SHOTS_FIRED_ALT_METHOD = "trigger",
    
    -- RECOIL_METHOD: How direct memory recoil addresses are processed
    -- "pulse" = Triggers only when the memory value increases (best for semi-auto)
    -- "hold"  = Triggers continuously while the value is > 0 (best for machine guns)
    RECOIL_METHOD = "pulse",
    
    -- RECOIL_PRIORITY: Trigger to control the physical solenoid
    -- "ammo"   = ammo drops trigger recoil. The recoil memory address is ignored UNLESS Ammo = 0.
    -- "recoil" = the recoil memory address ALWAYS triggers recoil. Ammo drops are completely ignored for physical feedback.
    RECOIL_PRIORITY = "ammo",
    
    --------------------------------------------------
    -- GLOBAL MASTER SWITCHES                       --
    --------------------------------------------------
    
    -- ENABLE_SHOT_COUNT: Global Master Switch for Shot Counters
    -- true  = Enable counters (Source defined in P1/P2 tables below)
    -- false = Completely disable all shot counting logic
    ENABLE_SHOT_COUNT = true,
    
    -- ENABLE_DAMAGE_COUNT: Global Master Switch for Damage Counters
    -- true  = Enable counters (Source defined in P1/P2 tables above)
    -- false = Completely disable all damage counting logic
    ENABLE_DAMAGE_COUNT = true,
    
    -- ENABLE_LIFE_LOST: Global Master Switch for Life Lost Counters
    -- true  = Enable counters (Source defined in P1/P2 tables above)
    -- false = Completely disable all life lost counting logic
    ENABLE_LIFE_LOST = true,
    
    -- DEMULSHOOTER_COMPATIBILITY: Duplicates Recoil and Damage outputs
    -- true  = Outputs standard suffixes (default is "Recoil" & "Damage"), PLUS "CtmRecoil" & "Damaged" for DemulShooter
    -- false = Outputs standard suffixes only (default is "Recoil" & "Damage")
    DEMULSHOOTER_COMPATIBILITY = true,
    
    -- ENABLE_OSD: Controls on-screen messages
    -- true  = Shows startup messages
    -- false = Silent mode (Maximum performance, no stutter)
    ENABLE_OSD = false,
}

------------------------------------------------------
-- 1. GLOBAL STATE                                  --
------------------------------------------------------
local _Taps = {} 
local _HasCoinedUp = false
local _IsShuttingDown = false

if not CFG.CREDITS then _HasCoinedUp = true end

emu.add_machine_stop_notifier(function() 
    _IsShuttingDown = true 
    for k, tap in pairs(_Taps) do
        pcall(function() tap:remove() end)
    end
    _Taps = {}
end)

------------------------------------------------------
-- 2. SETUP & PRE-CALCULATION                        --
------------------------------------------------------
function Resolve_Addresses()
    -- Normalize all "auto" string inputs to lowercase for exact matching
    local all_players = { CFG.P1, CFG.P2, CFG.P3, CFG.P4 }
    for _, p_cfg in ipairs(all_players) do
        for k, val in pairs(p_cfg) do
            if type(val) == "string" and string.lower(val) == "auto" then
                p_cfg[k] = "auto"
            end
        end
    end

    local p1_hardware = { "RECOIL", "RELOAD", "DAMAGE", "LAMP_START", "STATUS", "STATUS_ALT" }
    for _, key in ipairs(p1_hardware) do
        if CFG.P1[key] == "auto" then
            if key == "STATUS" or key == "STATUS_ALT" then
                -- Do nothing, leave as "auto"
            elseif key == "RECOIL" and (CFG.P1.AMMO or CFG.P1.AMMO_ALT) then
            elseif key == "RELOAD" and (CFG.P1.AMMO or CFG.P1.AMMO_ALT) then
            elseif key == "DAMAGE" and (CFG.P1.LIFE or CFG.P1.LIFE_ALT) then
            elseif key == "LAMP_START" then
            else
                CFG.P1[key] = false
            end
        end
    end

    local standard_offset = CFG.PLAYER_MEMORY_OFFSET or 0
    local credit_offset = CFG.PLAYER_CREDIT_MEMORY_OFFSET or standard_offset
    local player_tables = { CFG.P2, CFG.P3, CFG.P4 }

    for i, p_cfg in ipairs(player_tables) do
        local multiplier = i 
        for key, val in pairs(p_cfg) do
            if val == "auto" then
                local p1_val = CFG.P1[key]
                if type(p1_val) == "number" then
                    local offset_to_use = (key == "CREDITS") and credit_offset or standard_offset
                    p_cfg[key] = p1_val + (offset_to_use * multiplier)

                elseif p1_val == "auto" then
                    p_cfg[key] = "auto" 
                    if CFG.P1[key] == false then p_cfg[key] = false end
                else
                    p_cfg[key] = false
                end
            end
        end
    end

    for _, p_cfg in ipairs(all_players) do
        if not p_cfg.AMMO then
            if p_cfg.RECOIL == "auto" and not p_cfg.AMMO_ALT then p_cfg.RECOIL = false end
            if p_cfg.RELOAD == "auto" and not p_cfg.AMMO_ALT then p_cfg.RELOAD = false end
            if p_cfg.SHOTS_FIRED == "auto" then p_cfg.SHOTS_FIRED = false end
        end
        if not p_cfg.AMMO_ALT then
            if p_cfg.SHOTS_FIRED_ALT == "auto" then p_cfg.SHOTS_FIRED_ALT = false end
        end
        if not p_cfg.LIFE and not p_cfg.LIFE_ALT then
            if p_cfg.DAMAGE_TAKEN == "auto" then p_cfg.DAMAGE_TAKEN = false end
            if p_cfg.LIFE_LOST == "auto" then p_cfg.LIFE_LOST = false end
        end
    end
end
Resolve_Addresses()

local _RecoilDuration = emu.attotime.from_msec(CFG.RECOIL_DURATION_MS)
local _RecoilAltDuration = emu.attotime.from_msec(CFG.RECOIL_ALT_DURATION_MS or 80)
local _MinRecoilInterval = emu.attotime.from_msec(CFG.MIN_RECOIL_INTERVAL_MS or 0)
local _ReloadDuration = emu.attotime.from_msec(CFG.RELOAD_DURATION_MS or 40)
local _DamageDuration = emu.attotime.from_msec(CFG.DAMAGE_DURATION_MS)
local _StartupTime = emu.attotime.from_msec(CFG.STARTUP_DELAY_MS)
local _ZeroTime = emu.attotime.from_seconds(0)

local _GameActiveTick = _ZeroTime

local _Player = {}
for i = 1, 4 do
    _Player[i] = { 
        LastAmmo=0, LastAmmoAlt=0, LastLife=0, LastLifeAlt=0, LastDmgMem=0, 
        RecoilTick=_ZeroTime, ReloadTick=_ZeroTime, DamageTick=_ZeroTime, 
        CurrentRecoilDuration=_RecoilDuration,
        LastRecoilVal=0, LastRumbleVal=0, 
        ShotCount=0, ShotCountAlt=0, DamageCount=0, LifeLostCount=0,
        IsActive=false,
        WasActive=false,
        ActiveTick=_ZeroTime,
        IsRecoilActive=false,
        IsReloadActive=false,
        IsDamageActive=false
    }
end

local _InitTimer = 60 
local _TapsInstalled = false

------------------------------------------------------
-- 3. HELPER FUNCTIONS                              --
------------------------------------------------------
function Show_Message(text)
    if CFG.ENABLE_OSD and manager.machine then 
        manager.machine:popmessage(text) 
    end
end

function Is_Warmup_Complete()
    return manager.machine.time > _StartupTime
end

function Get_Output_Str(player_idx, type_key)
    local target_p = player_idx
    if not CFG.SIMULTANEOUS_PLAY then 
        if type_key == "RECOIL" or type_key == "RELOAD" or type_key == "DAMAGE" or type_key == "LAMP_START" then
            target_p = 1
        end
    end
    
    local suffix = CFG.OUTPUT_SUFFIXES[type_key] or type_key
    return "P" .. target_p .. "_" .. suffix
end

function Read_Data_Safe(mem_handle, source, width)
    if not source then return 0 end
    
    if type(width) == "string" then
        local w_low = string.lower(width)
        if w_low == "output" then
            if type(source) == "string" and manager.machine.output then
                local native_val = manager.machine.output:get_value(source)
                if type(native_val) == "number" then
                    return native_val
                elseif native_val then
                    return 1
                else
                    return 0
                end
            end
            return 0
        end
    end
    
    if not mem_handle then return 0 end
    
    if type(width) == "string" then
        local w_low = string.lower(width)
        if w_low == "float32" then
            local val = mem_handle:read_u32(source)
            return string.unpack("f", string.pack("I4", val))
        elseif w_low == "float32be" then
            local val = mem_handle:read_u32(source)
            val = ((val & 0xFF) << 24) | ((val & 0xFF00) << 8) | ((val & 0xFF0000) >> 8) | ((val & 0xFF000000) >> 24)
            return string.unpack("f", string.pack("I4", val))
        end
    end

    if width == 16 then return mem_handle:read_u16(source) end
    if width == 32 then return mem_handle:read_u32(source) end
    return mem_handle:read_u8(source)
end

function Register_Outputs_Safe(out_handle)
    if not out_handle then return end
    
    out_handle:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_GAME_STATUS, 0)
    if CFG.ATTRACT_STATUS then out_handle:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_ATTRACT_STATUS, 0) end
    out_handle:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_LUA_VERSION, CFG.LUA_VERSION)
    out_handle:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_LUA_DATE, CFG.LUA_DATE)

    if CFG.CREDITS then out_handle:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_CREDITS, 0) end
    
    local list = {}
    for i = 1, CFG.MAX_PLAYERS do
        local p_cfg = CFG["P"..i] 
        
        if p_cfg.STATUS then out_handle:set_value(Get_Output_Str(i, "STATUS"), 0) end
        if p_cfg.STATUS_ALT then out_handle:set_value(Get_Output_Str(i, "STATUS_ALT"), 0) end
        if p_cfg.CREDITS then out_handle:set_value(Get_Output_Str(i, "CREDITS"), 0) end
        
        if p_cfg.AMMO then table.insert(list, Get_Output_Str(i, "AMMO")) end
        if p_cfg.AMMO_ALT then table.insert(list, Get_Output_Str(i, "AMMO_ALT")) end
        if p_cfg.LIFE then table.insert(list, Get_Output_Str(i, "LIFE")) end
        if p_cfg.LIFE_ALT then table.insert(list, Get_Output_Str(i, "LIFE_ALT")) end
        
        if p_cfg.RECOIL then 
            table.insert(list, Get_Output_Str(i, "RECOIL")) 
            if CFG.DEMULSHOOTER_COMPATIBILITY then table.insert(list, "P" .. ((not CFG.SIMULTANEOUS_PLAY) and 1 or i) .. "_CtmRecoil") end
        end
        if p_cfg.RELOAD then table.insert(list, Get_Output_Str(i, "RELOAD")) end
        if p_cfg.DAMAGE then 
            table.insert(list, Get_Output_Str(i, "DAMAGE")) 
            if CFG.DEMULSHOOTER_COMPATIBILITY then table.insert(list, "P" .. ((not CFG.SIMULTANEOUS_PLAY) and 1 or i) .. "_Damaged") end
        end
        
        if p_cfg.LAMP_START then table.insert(list, Get_Output_Str(i, "LAMP_START")) end
        
        if CFG.ENABLE_DAMAGE_COUNT and p_cfg.DAMAGE_TAKEN then table.insert(list, Get_Output_Str(i, "DAMAGE_TAKEN")) end
        if CFG.ENABLE_SHOT_COUNT and p_cfg.SHOTS_FIRED then table.insert(list, Get_Output_Str(i, "SHOTS_FIRED")) end
        if CFG.ENABLE_SHOT_COUNT and p_cfg.SHOTS_FIRED_ALT then table.insert(list, Get_Output_Str(i, "SHOTS_FIRED_ALT")) end
        if CFG.ENABLE_LIFE_LOST and p_cfg.LIFE_LOST then table.insert(list, Get_Output_Str(i, "LIFE_LOST")) end
    end
    
    for _, name in ipairs(list) do out_handle:set_value(name, 0) end
    
    for i = 1, CFG.MAX_PLAYERS do
        local p_cfg = CFG["P"..i]
        if CFG.ENABLE_SHOT_COUNT and p_cfg.SHOTS_FIRED then out_handle:set_value(Get_Output_Str(i, "SHOTS_FIRED"), 0) end
        if CFG.ENABLE_SHOT_COUNT and p_cfg.SHOTS_FIRED_ALT then out_handle:set_value(Get_Output_Str(i, "SHOTS_FIRED_ALT"), 0) end
        if CFG.ENABLE_DAMAGE_COUNT and p_cfg.DAMAGE_TAKEN then out_handle:set_value(Get_Output_Str(i, "DAMAGE_TAKEN"), 0) end
        if CFG.ENABLE_LIFE_LOST and p_cfg.LIFE_LOST then out_handle:set_value(Get_Output_Str(i, "LIFE_LOST"), 0) end
    end
end

function Get_Safe_Tap_Address(addr)
    return addr - (addr % 4)
end

------------------------------------------------------
-- 4. TAP HANDLERS (Called by MAME core)            --
------------------------------------------------------
function OnWrite_Generic(name, val, player_idx, type_key)
    local out = manager.machine.output
    if not out then return end 
    
    local p = _Player[player_idx]

    if not p.IsActive then return end
    
    if type_key == "RECOIL" then
        if val > p.LastRecoilVal then
            local out_name = Get_Output_Str(player_idx, "RECOIL")
            out:set_value(out_name, 1)
            if CFG.DEMULSHOOTER_COMPATIBILITY then
                local target_p = (not CFG.SIMULTANEOUS_PLAY) and 1 or player_idx
                out:set_value("P" .. target_p .. "_CtmRecoil", 1)
            end
            
            p.RecoilTick = manager.machine.time
            p.CurrentRecoilDuration = _RecoilDuration 
            p.IsRecoilActive = true
            
            if (not CFG.SIMULTANEOUS_PLAY) and player_idx > 1 then 
                _Player[1].RecoilTick = manager.machine.time 
                _Player[1].CurrentRecoilDuration = _RecoilDuration
                _Player[1].IsRecoilActive = true
            end
        end
        p.LastRecoilVal = val
    end
end

function Install_Taps_Safe(mem)
    if _TapsInstalled then return end
    local align = CFG.MEMORY_ALIGNMENT
    
    if align then
        local range_padding = 3
        _TapsInstalled = true
        Show_Message("Hybrid Mode: Fast Recoil + Polled Stats")
    else
        Show_Message("Standard Polling Mode Active")
    end
end

------------------------------------------------------
-- 5. MAIN LOGIC LOOP (Wrapped in Safety Bubble)    --
------------------------------------------------------
function Compute_Outputs()
    if _IsShuttingDown then return end

    local status, err = pcall(function()
        
        if not manager.machine then return end
        local cpu = manager.machine.devices[":maincpu"]
        if not cpu then return end
        local mem = cpu.spaces["program"]
        local out = manager.machine.output
        
        if not mem or not out then return end

        if _InitTimer > 0 then
            _InitTimer = _InitTimer - 1
            if _InitTimer == 0 then 
                Register_Outputs_Safe(out)
                Install_Taps_Safe(mem)
            end
        end

        local divisor = CFG.COINS_PER_CREDIT or 1
        if divisor < 1 then divisor = 1 end
        
        local warmup_ok = Is_Warmup_Complete()

        if CFG.CREDITS then 
            local raw = Read_Data_Safe(mem, CFG.CREDITS, CFG.DATA_WIDTHS.GLOBAL_CREDITS)
            local credit_val = math.floor(raw / divisor)
            
            out:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_CREDITS, warmup_ok and credit_val or 0) 
            
            if credit_val > 0 and warmup_ok then 
                _HasCoinedUp = true 
            end
        end
        
        local is_attract_mode = false
        if CFG.ATTRACT_STATUS and type(CFG.ATTRACT_STATUS) == "number" then
            local attract_val = Read_Data_Safe(mem, CFG.ATTRACT_STATUS, CFG.DATA_WIDTHS.GLOBAL_ATTRACT_STATUS or 8)
            if type(CFG.ATTRACT_STATUS_ACTIVE_VALUE) == "number" then
                if attract_val == CFG.ATTRACT_STATUS_ACTIVE_VALUE then
                    is_attract_mode = true
                end
            else
                if attract_val > 0 then
                    is_attract_mode = true
                end
            end
            out:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_ATTRACT_STATUS, warmup_ok and (is_attract_mode and 1 or 0) or 0)
        end

        local global_val = 0
        local global_exists = false
        local is_game_active = false
        
        if CFG.GAME_STATUS then 
            global_exists = true
            if not is_attract_mode then
                global_val = Read_Data_Safe(mem, CFG.GAME_STATUS, CFG.DATA_WIDTHS.GLOBAL_GAME_STATUS)
                if type(CFG.GAME_STATUS_ACTIVE_VALUE) == "number" then
                    if global_val == CFG.GAME_STATUS_ACTIVE_VALUE then is_game_active = true end
                else
                    if global_val > 0 then is_game_active = true end
                end
            end
        end
        
        -- GAME STATUS DEBOUNCE
        if is_game_active then
            if _GameActiveTick == _ZeroTime then _GameActiveTick = manager.machine.time end
            if (manager.machine.time - _GameActiveTick) <= emu.attotime.from_msec(CFG.STATUS_DEBOUNCE_MS or 0) then
                is_game_active = false
            end
        else
            _GameActiveTick = _ZeroTime
            is_game_active = false
        end

        local any_player_active = false
        
        for i = 1, CFG.MAX_PLAYERS do
            local cfg
            if i == 1 then cfg = CFG.P1 
            elseif i == 2 then cfg = CFG.P2 
            elseif i == 3 then cfg = CFG.P3 
            else cfg = CFG.P4 end
            
            local p = _Player[i]

            local curr_ammo = 0
            local curr_ammo_alt = 0
            local curr_life = 0
            local curr_life_alt = 0
            
            if cfg.AMMO then 
                local raw_ammo = Read_Data_Safe(mem, cfg.AMMO, CFG.DATA_WIDTHS.AMMO) 
                curr_ammo = raw_ammo + (CFG.AMMO_OFFSET or 0)
                if CFG.AMMO_MAX and curr_ammo > CFG.AMMO_MAX then curr_ammo = 0 end
            end

            if cfg.AMMO_ALT then 
                local raw_ammo_alt = Read_Data_Safe(mem, cfg.AMMO_ALT, CFG.DATA_WIDTHS.AMMO_ALT) 
                curr_ammo_alt = raw_ammo_alt + (CFG.AMMO_ALT_OFFSET or 0)
                if CFG.AMMO_ALT_MAX and curr_ammo_alt > CFG.AMMO_ALT_MAX then curr_ammo_alt = 0 end
            end
            
            if cfg.LIFE then 
                local raw_life = Read_Data_Safe(mem, cfg.LIFE, CFG.DATA_WIDTHS.LIFE)
                curr_life = raw_life + (CFG.LIFE_OFFSET or 0)
                if CFG.LIFE_MAX and curr_life > CFG.LIFE_MAX then curr_life = 0 end
            end

            if cfg.LIFE_ALT then 
                local raw_life_alt = Read_Data_Safe(mem, cfg.LIFE_ALT, CFG.DATA_WIDTHS.LIFE_ALT)
                curr_life_alt = raw_life_alt + (CFG.LIFE_ALT_OFFSET or 0)
                if CFG.LIFE_ALT_MAX and curr_life_alt > CFG.LIFE_ALT_MAX then curr_life_alt = 0 end
            end

            local p_credits = 0
            local p_credits_known = false
            if cfg.CREDITS then
                if type(cfg.CREDITS) == "number" then 
                    p_credits = Read_Data_Safe(mem, cfg.CREDITS, CFG.DATA_WIDTHS.CREDITS)
                    p_credits_known = true
                elseif cfg.CREDITS == "auto" and CFG.CREDITS then 
                    p_credits = Read_Data_Safe(mem, CFG.CREDITS, CFG.DATA_WIDTHS.GLOBAL_CREDITS) 
                end
                out:set_value(Get_Output_Str(i, "CREDITS"), warmup_ok and math.floor(p_credits / divisor) or 0)
            end
            
            -- LAMP START (Must be processed BEFORE the Active Gate, so it blinks during Attract Mode)
            if cfg.LAMP_START then
                out:set_value(Get_Output_Str(i, "LAMP_START"), warmup_ok and Read_Data_Safe(mem, cfg.LAMP_START, CFG.DATA_WIDTHS.LAMP_START) or 0)
            end

            local is_player_active = false
            local out_status_val = 0
            local out_status_alt_val = 0

            if is_attract_mode then
                -- Player is forced inactive during attract mode
                is_player_active = false
            elseif (cfg.STATUS and cfg.STATUS ~= "auto") or (cfg.STATUS_ALT and cfg.STATUS_ALT ~= "auto") then
                local p_stat_active = false
                local p_stat_alt_active = false

                if cfg.STATUS and cfg.STATUS ~= "auto" then
                    local p_stat_val = Read_Data_Safe(mem, cfg.STATUS, CFG.DATA_WIDTHS.STATUS)
                    if type(CFG.STATUS_ACTIVE_VALUE) == "number" then
                        if p_stat_val == CFG.STATUS_ACTIVE_VALUE then p_stat_active = true end
                    else
                        if p_stat_val > 0 then p_stat_active = true end
                    end
                end
                
                if cfg.STATUS_ALT and cfg.STATUS_ALT ~= "auto" then
                    local p_stat_val_alt = Read_Data_Safe(mem, cfg.STATUS_ALT, CFG.DATA_WIDTHS.STATUS_ALT)
                    if type(CFG.STATUS_ALT_ACTIVE_VALUE) == "number" then
                        if p_stat_val_alt == CFG.STATUS_ALT_ACTIVE_VALUE then p_stat_alt_active = true end
                    else
                        if p_stat_val_alt > 0 then p_stat_alt_active = true end
                    end
                end

                local combined_active = p_stat_active or p_stat_alt_active

                if global_exists then
                    if is_game_active and p_stat_active then out_status_val = 1 end
                    if is_game_active and p_stat_alt_active then out_status_alt_val = 1 end
                else
                    if p_stat_active then out_status_val = 1 end
                    if p_stat_alt_active then out_status_alt_val = 1 end
                end
                
                if out_status_val == 1 or out_status_alt_val == 1 then
                    is_player_active = true
                end

            elseif global_exists then
                if is_game_active and (curr_life > 0 or curr_life_alt > 0) then 
                    is_player_active = true 
                    out_status_val = 1
                    out_status_alt_val = 1
                end

            else
                if _HasCoinedUp and (curr_life > 0 or curr_life_alt > 0) then 
                    if (not p_credits_known) or (p_credits > 0) then
                        is_player_active = true 
                        out_status_val = 1
                        out_status_alt_val = 1
                    end
                end
            end
            
            if not warmup_ok then
                is_player_active = false
                out_status_val = 0
                out_status_alt_val = 0
            end
            
            -- PLAYER STATUS DEBOUNCE
            if is_player_active then
                if p.ActiveTick == _ZeroTime then p.ActiveTick = manager.machine.time end
                if (manager.machine.time - p.ActiveTick) <= emu.attotime.from_msec(CFG.STATUS_DEBOUNCE_MS or 0) then
                    is_player_active = false
                    out_status_val = 0
                    out_status_alt_val = 0
                end
            else
                p.ActiveTick = _ZeroTime
                out_status_val = 0
                out_status_alt_val = 0
            end
            
            p.IsActive = is_player_active
            if is_player_active then any_player_active = true end

            if cfg.STATUS then out:set_value(Get_Output_Str(i, "STATUS"), out_status_val) end
            if cfg.STATUS_ALT then out:set_value(Get_Output_Str(i, "STATUS_ALT"), out_status_alt_val) end

            local just_died = (not is_player_active and p.WasActive)

            if is_player_active or just_died then
            
                local primary_active = (out_status_val == 1)
                local alternate_active = false
                
                if cfg.STATUS_ALT and cfg.STATUS_ALT ~= "auto" then
                    alternate_active = (out_status_alt_val == 1)
                else
                    alternate_active = primary_active
                end
            
                if primary_active then
                    if cfg.AMMO then out:set_value(Get_Output_Str(i, "AMMO"), warmup_ok and curr_ammo or 0) end
                    if cfg.LIFE then out:set_value(Get_Output_Str(i, "LIFE"), warmup_ok and curr_life or 0) end

                    if CFG.ENABLE_SHOT_COUNT and cfg.SHOTS_FIRED and warmup_ok then
                        if type(cfg.SHOTS_FIRED) == "number" then
                            local mem_val = Read_Data_Safe(mem, cfg.SHOTS_FIRED, CFG.DATA_WIDTHS.SHOTS_FIRED)
                            out:set_value(Get_Output_Str(i, "SHOTS_FIRED"), mem_val)
                            p.ShotCount = mem_val
                        elseif cfg.SHOTS_FIRED == "auto" and cfg.AMMO and p.WasActive then
                            local shot = false
                            local diff = 0
                            
                            if string.lower(tostring(CFG.AMMO_DIRECTION)) == "decrease" then
                                if curr_ammo < p.LastAmmo and p.LastAmmo <= 200 then
                                    shot = true; diff = p.LastAmmo - curr_ammo
                                end
                            else
                                if curr_ammo > p.LastAmmo then
                                    shot = true; diff = curr_ammo - p.LastAmmo
                                end
                            end
                            if shot then
                                if string.lower(tostring(CFG.SHOTS_FIRED_METHOD)) == "bullets" then
                                    p.ShotCount = p.ShotCount + diff
                                else
                                    p.ShotCount = p.ShotCount + 1
                                end
                                out:set_value(Get_Output_Str(i, "SHOTS_FIRED"), p.ShotCount)
                            end
                        end
                    end
                else
                    if cfg.AMMO then out:set_value(Get_Output_Str(i, "AMMO"), 0) end
                    if cfg.LIFE then out:set_value(Get_Output_Str(i, "LIFE"), 0) end
                end

                if alternate_active then
                    if cfg.AMMO_ALT then out:set_value(Get_Output_Str(i, "AMMO_ALT"), warmup_ok and curr_ammo_alt or 0) end
                    if cfg.LIFE_ALT then out:set_value(Get_Output_Str(i, "LIFE_ALT"), warmup_ok and curr_life_alt or 0) end

                    if CFG.ENABLE_SHOT_COUNT and cfg.SHOTS_FIRED_ALT and warmup_ok then
                        if type(cfg.SHOTS_FIRED_ALT) == "number" then
                            local mem_val = Read_Data_Safe(mem, cfg.SHOTS_FIRED_ALT, CFG.DATA_WIDTHS.SHOTS_FIRED_ALT)
                            out:set_value(Get_Output_Str(i, "SHOTS_FIRED_ALT"), mem_val)
                            p.ShotCountAlt = mem_val
                        elseif cfg.SHOTS_FIRED_ALT == "auto" and cfg.AMMO_ALT and p.WasActive then
                            local shot = false
                            local diff = 0
                            
                            if string.lower(tostring(CFG.AMMO_ALT_DIRECTION)) == "decrease" then
                                if curr_ammo_alt < p.LastAmmoAlt and p.LastAmmoAlt <= 200 then
                                    shot = true; diff = p.LastAmmoAlt - curr_ammo_alt
                                end
                            else
                                if curr_ammo_alt > p.LastAmmoAlt then
                                    shot = true; diff = curr_ammo_alt - p.LastAmmoAlt
                                end
                            end
                            if shot then
                                if string.lower(tostring(CFG.SHOTS_FIRED_ALT_METHOD)) == "bullets" then
                                    p.ShotCountAlt = p.ShotCountAlt + diff
                                else
                                    p.ShotCountAlt = p.ShotCountAlt + 1
                                end
                                out:set_value(Get_Output_Str(i, "SHOTS_FIRED_ALT"), p.ShotCountAlt)
                            end
                        end
                    end
                else
                    if cfg.AMMO_ALT then out:set_value(Get_Output_Str(i, "AMMO_ALT"), 0) end
                    if cfg.LIFE_ALT then out:set_value(Get_Output_Str(i, "LIFE_ALT"), 0) end
                end

                -- Direct Memory Polling for RECOIL (If a specific address is provided)
                if cfg.RECOIL and type(cfg.RECOIL) == "number" then
                    local recoil_val = Read_Data_Safe(mem, cfg.RECOIL, CFG.DATA_WIDTHS.RECOIL)
                    
                    local allowed_by_priority = false
                    if string.lower(tostring(CFG.RECOIL_PRIORITY)) == "recoil" then
                        allowed_by_priority = true
                    elseif string.lower(tostring(CFG.RECOIL_PRIORITY)) == "ammo" and curr_ammo == 0 then
                        allowed_by_priority = true
                    end
                    
                    if allowed_by_priority then
                        local trigger_recoil = false
                        if string.lower(tostring(CFG.RECOIL_METHOD)) == "hold" then
                            if recoil_val > 0 then trigger_recoil = true end
                        else
                            -- Trigger if the value increases (catches pulses like 0->1 or 1->2)
                            if recoil_val > p.LastRecoilVal then trigger_recoil = true end
                        end
                        
                        if trigger_recoil then
                            local time_since_last = manager.machine.time - p.RecoilTick
                            if time_since_last > _MinRecoilInterval then
                                p.CurrentRecoilDuration = _RecoilDuration
                                out:set_value(Get_Output_Str(i, "RECOIL"), 1)
                                
                                if CFG.DEMULSHOOTER_COMPATIBILITY then
                                    local target_p = (not CFG.SIMULTANEOUS_PLAY) and 1 or i
                                    out:set_value("P" .. target_p .. "_CtmRecoil", 1)
                                end
                                
                                p.RecoilTick = manager.machine.time
                                p.IsRecoilActive = true
                                
                                if (not CFG.SIMULTANEOUS_PLAY) and i > 1 then 
                                    _Player[1].RecoilTick = manager.machine.time 
                                    _Player[1].CurrentRecoilDuration = p.CurrentRecoilDuration
                                    _Player[1].IsRecoilActive = true
                                end
                            end
                        end
                    end
                    p.LastRecoilVal = recoil_val
                end

                local rumble_triggered = false
                
                if type(cfg.DAMAGE_TAKEN) == "number" then
                    local mem_val = Read_Data_Safe(mem, cfg.DAMAGE_TAKEN, CFG.DATA_WIDTHS.DAMAGE_TAKEN)
                    if mem_val > p.LastDmgMem then
                        if warmup_ok then
                            rumble_triggered = true
                            if CFG.ENABLE_DAMAGE_COUNT then
                                p.DamageCount = p.DamageCount + 1
                                out:set_value(Get_Output_Str(i, "DAMAGE_TAKEN"), p.DamageCount)
                            end
                        end
                    end
                    p.LastDmgMem = mem_val
                elseif cfg.DAMAGE_TAKEN == "auto" and (cfg.LIFE or cfg.LIFE_ALT) and p.WasActive then
                    local hit = false
                    
                    if cfg.LIFE then
                        if string.lower(tostring(CFG.LIFE_DIRECTION)) == "decrease" then
                            if curr_life < p.LastLife then hit = true end
                        else
                            if curr_life > p.LastLife then hit = true end
                        end
                    end
                    
                    if cfg.LIFE_ALT then
                        if string.lower(tostring(CFG.LIFE_ALT_DIRECTION)) == "decrease" then
                            if curr_life_alt < p.LastLifeAlt then hit = true end
                        else
                            if curr_life_alt > p.LastLifeAlt then hit = true end
                        end
                    end

                    if hit and warmup_ok then
                        rumble_triggered = true 
                        if CFG.ENABLE_DAMAGE_COUNT then
                            p.DamageCount = p.DamageCount + 1
                            out:set_value(Get_Output_Str(i, "DAMAGE_TAKEN"), p.DamageCount)
                        end
                    end
                end

                if rumble_triggered then
                    out:set_value(Get_Output_Str(i, "DAMAGE"), 1)
                    if CFG.DEMULSHOOTER_COMPATIBILITY then
                        local target_p = (not CFG.SIMULTANEOUS_PLAY) and 1 or i
                        out:set_value("P" .. target_p .. "_Damaged", 1)
                    end
                    
                    p.DamageTick = manager.machine.time
                    p.IsDamageActive = true
                    if (not CFG.SIMULTANEOUS_PLAY) and i > 1 then 
                        _Player[1].DamageTick = manager.machine.time 
                        _Player[1].IsDamageActive = true
                    end
                end
                
                if cfg.DAMAGE then
                    if type(cfg.DAMAGE) == "number" or (type(cfg.DAMAGE) == "string" and cfg.DAMAGE ~= "auto") then
                        local val = Read_Data_Safe(mem, cfg.DAMAGE, CFG.DATA_WIDTHS.DAMAGE)
                        if val > p.LastRumbleVal then
                            out:set_value(Get_Output_Str(i, "DAMAGE"), 1)
                            if CFG.DEMULSHOOTER_COMPATIBILITY then
                                local target_p = (not CFG.SIMULTANEOUS_PLAY) and 1 or i
                                out:set_value("P" .. target_p .. "_Damaged", 1)
                            end
                            
                            p.DamageTick = manager.machine.time
                            p.IsDamageActive = true
                            
                            if (not CFG.SIMULTANEOUS_PLAY) and i > 1 then 
                                _Player[1].DamageTick = manager.machine.time 
                                _Player[1].IsDamageActive = true
                            end

                            if CFG.ENABLE_DAMAGE_COUNT and cfg.DAMAGE_TAKEN == "auto" and not rumble_triggered and warmup_ok then
                                 p.DamageCount = p.DamageCount + 1
                                 out:set_value(Get_Output_Str(i, "DAMAGE_TAKEN"), p.DamageCount)
                            end
                        end
                        p.LastRumbleVal = val
                    end
                end
                
                if CFG.ENABLE_LIFE_LOST then
                    if cfg.LIFE_LOST == "auto" and (cfg.LIFE or cfg.LIFE_ALT) and warmup_ok and p.WasActive then
                         local lost = false
                         if cfg.LIFE then
                             if string.lower(tostring(CFG.LIFE_DIRECTION)) == "decrease" then
                                 if curr_life < p.LastLife then lost = true end
                             else
                                 if curr_life > p.LastLife then lost = true end
                             end
                         end
                         if cfg.LIFE_ALT then
                             if string.lower(tostring(CFG.LIFE_ALT_DIRECTION)) == "decrease" then
                                 if curr_life_alt < p.LastLifeAlt then lost = true end
                             else
                                 if curr_life_alt > p.LastLifeAlt then lost = true end
                             end
                         end
                         
                         if lost then
                             p.LifeLostCount = p.LifeLostCount + 1
                             out:set_value(Get_Output_Str(i, "LIFE_LOST"), p.LifeLostCount)
                         end
                    elseif type(cfg.LIFE_LOST) == "number" then
                         local val = Read_Data_Safe(mem, cfg.LIFE_LOST, CFG.DATA_WIDTHS.LIFE_LOST)
                         out:set_value(Get_Output_Str(i, "LIFE_LOST"), val)
                    end
                end

                if not CFG.MEMORY_ALIGNMENT and primary_active then
                      local trigger_type = 0 
                      
                      if p.WasActive and cfg.AMMO then
                          if string.lower(tostring(CFG.AMMO_DIRECTION)) == "decrease" then
                              if curr_ammo < p.LastAmmo and p.LastAmmo <= 200 then trigger_type = 1 end
                          else
                              if curr_ammo > p.LastAmmo then trigger_type = 1 end
                          end
                      end
                      
                      if alternate_active and p.WasActive and cfg.AMMO_ALT then
                          if string.lower(tostring(CFG.AMMO_ALT_DIRECTION)) == "decrease" then
                              if curr_ammo_alt < p.LastAmmoAlt and p.LastAmmoAlt <= 200 then trigger_type = 2 end
                          else
                              if curr_ammo_alt > p.LastAmmoAlt then trigger_type = 2 end
                          end
                      end

                      local allowed_by_priority = false
                      if cfg.RECOIL == "auto" then
                          allowed_by_priority = true
                      elseif type(cfg.RECOIL) == "number" and string.lower(tostring(CFG.RECOIL_PRIORITY)) == "ammo" then
                          allowed_by_priority = true
                      end
                      
                      if trigger_type > 0 and allowed_by_priority then
                          local time_since_last = manager.machine.time - p.RecoilTick
                          if time_since_last > _MinRecoilInterval then
                              if trigger_type == 1 then
                                  p.CurrentRecoilDuration = _RecoilDuration
                              else
                                  p.CurrentRecoilDuration = _RecoilAltDuration
                              end

                              out:set_value(Get_Output_Str(i, "RECOIL"), 1)
                              if CFG.DEMULSHOOTER_COMPATIBILITY then
                                  local target_p = (not CFG.SIMULTANEOUS_PLAY) and 1 or i
                                  out:set_value("P" .. target_p .. "_CtmRecoil", 1)
                              end
                              
                              p.RecoilTick = manager.machine.time
                              p.IsRecoilActive = true
                              
                              if (not CFG.SIMULTANEOUS_PLAY) and i > 1 then 
                                  _Player[1].RecoilTick = manager.machine.time 
                                  _Player[1].CurrentRecoilDuration = p.CurrentRecoilDuration
                                  _Player[1].IsRecoilActive = true
                              end
                          end
                      end
                      
                      local reload_trigger = false
                      if p.WasActive and cfg.AMMO then
                          if string.lower(tostring(CFG.AMMO_DIRECTION)) == "decrease" then
                              if curr_ammo > p.LastAmmo then reload_trigger = true end
                          else
                              if curr_ammo < p.LastAmmo then reload_trigger = true end
                          end
                      end
                      
                      if alternate_active and p.WasActive and cfg.AMMO_ALT then
                          if string.lower(tostring(CFG.AMMO_ALT_DIRECTION)) == "decrease" then
                              if curr_ammo_alt > p.LastAmmoAlt then reload_trigger = true end
                          else
                              if curr_ammo_alt < p.LastAmmoAlt then reload_trigger = true end
                          end
                      end
                      
                      if reload_trigger and warmup_ok then
                          if cfg.RELOAD then
                              out:set_value(Get_Output_Str(i, "RELOAD"), 1)
                              p.ReloadTick = manager.machine.time
                              p.IsReloadActive = true
                              
                              if (not CFG.SIMULTANEOUS_PLAY) and i > 1 then
                                  _Player[1].ReloadTick = manager.machine.time
                                  _Player[1].IsReloadActive = true
                              end
                          end
                      end
                end
            else
                -- Explicitly clear static values when a player dies or is inactive
                if cfg.AMMO then out:set_value(Get_Output_Str(i, "AMMO"), 0) end
                if cfg.LIFE then out:set_value(Get_Output_Str(i, "LIFE"), 0) end
                if cfg.AMMO_ALT then out:set_value(Get_Output_Str(i, "AMMO_ALT"), 0) end
                if cfg.LIFE_ALT then out:set_value(Get_Output_Str(i, "LIFE_ALT"), 0) end
            end

            p.LastAmmo = curr_ammo
            p.LastAmmoAlt = curr_ammo_alt
            p.LastLife = curr_life
            p.LastLifeAlt = curr_life_alt
            p.WasActive = p.IsActive

            local can_clear_output = true
            if (not CFG.SIMULTANEOUS_PLAY) and i > 1 then 
                can_clear_output = false 
            end

            if can_clear_output then
                if p.IsRecoilActive then
                    local recoil_elapsed = manager.machine.time - p.RecoilTick
                    if recoil_elapsed > p.CurrentRecoilDuration then
                        out:set_value(Get_Output_Str(i, "RECOIL"), 0)
                        if CFG.DEMULSHOOTER_COMPATIBILITY then
                            local target_p = (not CFG.SIMULTANEOUS_PLAY) and 1 or i
                            out:set_value("P" .. target_p .. "_CtmRecoil", 0)
                        end
                        p.IsRecoilActive = false
                    end
                end
                
                if p.IsReloadActive then
                    local reload_elapsed = manager.machine.time - p.ReloadTick
                    if reload_elapsed > _ReloadDuration then
                        out:set_value(Get_Output_Str(i, "RELOAD"), 0)
                        p.IsReloadActive = false
                    end
                end
                
                if p.IsDamageActive then
                    local damage_elapsed = manager.machine.time - p.DamageTick
                    if damage_elapsed > _DamageDuration then
                        out:set_value(Get_Output_Str(i, "DAMAGE"), 0)
                        if CFG.DEMULSHOOTER_COMPATIBILITY then
                            local target_p = (not CFG.SIMULTANEOUS_PLAY) and 1 or i
                            out:set_value("P" .. target_p .. "_Damaged", 0)
                        end
                        p.IsDamageActive = false
                    end
                end
            end
        end

        if global_exists then
            out:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_GAME_STATUS, (warmup_ok and is_game_active) and 1 or 0)
        else
            out:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_GAME_STATUS, warmup_ok and (any_player_active and 1 or 0) or 0)
        end
        
        out:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_LUA_VERSION, CFG.LUA_VERSION)
        out:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_LUA_DATE, CFG.LUA_DATE)

    end)
    
    if not status then 
    end
end

emu.register_frame_done(Compute_Outputs, "frame")