------------------------------------------------------
-- UNIVERSAL MAME LUA SCRIPT FOR STATE OUTPUTS (DESIGNED FOR LIGHT GUNS)
-- GitHub: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
-- Universal Script Version: 5.0.2
-- Last Modified Date: 2026.03.13
-- Created by DJ GLiTCH, with testing help from Muggins
-- License: GNU GENERAL PUBLIC LICENSE 3.0
-- MAME ROM: lethalen
------------------------------------------------------

local CFG = {
    --------------------------------------------------
    -- SYSTEM SETTINGS                              --
    --------------------------------------------------
    -- STARTUP_DELAY_MS: Time to wait before tracking stats (in ms).
    -- Prevents false "shots fired" events and blocks "Dirty RAM" on boot.
    -- Default: 5000 (5 seconds).
    STARTUP_DELAY_MS = 7000,

    -- COINS_PER_CREDIT: How many coins make 1 Credit?
    -- Used to calculate the correct "Credits" value for state outputs.
    -- Logic: math.floor(Coins / COINS_PER_CREDIT).
    -- Example: Set to 2. If you insert 3 coins, output is 1 Credit (1.5 rounded down).
    -- Default: 1 (1 Coin = 1 Credit).
    COINS_PER_CREDIT = 2,

    -- MAX_PLAYERS: Set the number of players to track (1 to 4).
    -- Default: 2
    MAX_PLAYERS = 2,

    -- SIMULTANEOUS_PLAY: Controls how outputs are routed.
    -- true  = Standard Arcade Mode (Simultaneous). 
    --          Each player has their own outputs (P1 triggers P1_Recoil, P2 triggers P2_Recoil).
    --          Use this for Time Crisis, Point Blank, etc.
    -- false = Shared Hardware Mode (Turn Based). 
    --          All players route to P1 outputs (P2 memory events trigger P1_Recoil).
    --          Use this if passing a single physical gun between players (e.g. Lethal Enforcers 2).
    SIMULTANEOUS_PLAY = true,

    --------------------------------------------------
    -- STATE OUTPUT NAMES (SUFFIXES)                --
    --------------------------------------------------
    -- Customize the string names sent to external software.
    -- The script will automatically prepend the player number (e.g., "P1_").
    -- Change these if your hardware software expects different names.
    OUTPUT_SUFFIXES = {
        GLOBAL_GAME_STATUS = "GameStatus",
        GLOBAL_CREDITS     = "Credits",
        AMMO               = "Ammo",
        AMMO_ALT           = "AmmoAlt",
        LIFE               = "Life",
        CREDITS            = "Credits",
        RECOIL             = "Recoil",
        DAMAGE             = "Damage",
        LAMP_START         = "LampStart",
        STATUS             = "Status",
        DAMAGE_TAKEN       = "DamageTaken",
        SHOTS_FIRED        = "ShotsFired",
        SHOTS_FIRED_ALT    = "ShotsFiredAlt",
        LIFE_LOST          = "LifeLost",
    },

    --------------------------------------------------
    -- HARDWARE CONFIGURATION                       --
    --------------------------------------------------
    
    -- MEMORY READ WIDTHS (8, 16, 32, "float32", "float32be", or "output")
    -- Define how many bits to read for each data type.
    --
    -- VALID VALUES:
    -- 8             = Byte (Standard). Most arcade lamps/outputs.
    -- 16            = Word. Common for Timers, Beast Busters Life/Recoil.
    -- 32            = Dword. Common for modern hardware (Lindbergh, Type X).
    -- "float32"     = 32-bit Float. Standard 3D games.
    -- "float32be"   = 32-bit Big Endian Float.
    -- "output"      = NATIVE MIRROR MODE. 
    --                 If set to "output", the script will NOT read memory addresses.
    --                 Instead, it will read the value of a native MAME output string
    --                 (e.g. "lamp0") that you define in the Player Tables below.
    DATA_WIDTHS = {
        GAME_STATUS = 8,
        AMMO        = 8,
        AMMO_ALT    = 8,
        LIFE        = 8,
        CREDITS     = 8,
        RECOIL      = 8,
        DAMAGE      = 8,
        LAMP_START  = 8,
        STATUS      = 8,
        LIFE_LOST    = 16,
        SHOTS_FIRED  = 16,
        SHOTS_FIRED_ALT = 16,
        DAMAGE_TAKEN = 16,
    },

    -- MEMORY_ALIGNMENT: Controls the "width" of the high-speed memory tap.
    --
    -- TROUBLESHOOTING GUIDE:
    -- 1. Start with MEMORY_ALIGNMENT = 32 (32-bit).
    -- 2. Run the script. If MAME crashes with "end address has low bits unset":
    -- 3. Change MEMORY_ALIGNMENT to 16 (16-bit).
    -- 4. If that fails, change to 8 (8-bit).
    -- 5. If 8 fails or causes instability, set to false (Standard Polling).
    --
    -- VALID VALUES:
    -- 32          = 32-bit (Model 2/3, Namco System 11/12, PlayStation, Beast Busters, CarnEvil)
    -- 16          = 16-bit (Sega System 16/32, SNES/Genesis, NeoGeo)
    -- 8           = 8-bit  (Operation Wolf, T2, Midway Y-Unit)
    -- false / nil = Standard Polling (Safe Mode, slightly more latency, typically 1 frame / 16ms)
    MEMORY_ALIGNMENT = false,

    -- PLAYER_MEMORY_OFFSET: Distance between P1 and next player's memory (in bytes).
    -- Used ONLY when P2, P3, P4 addresses below are set to "auto".
    --
    -- IMPORTANT FOR SIMULTANEOUS PLAY:
    -- If SIMULTANEOUS_PLAY = true, you usually need a real offset (e.g. 0xA8, 0x40, 4).
    --
    -- SHARED MEMORY / TURN BASED:
    -- Set to 0 or false. This forces P2 to read the same address as P1 (Offset 0).
    -- Setting to 0 perfectly syncs P2 logic to P1 memory for Turn-Based games.
    PLAYER_MEMORY_OFFSET = 0x40,

    -- PLAYER_CREDIT_MEMORY_OFFSET: Specific offset for Credits only.
    -- Use this if Credits are stored in a different area than Ammo/Life.
    -- 
    -- COMMON VALUES:
    -- nil / false = Uses the standard PLAYER_MEMORY_OFFSET defined above.
    -- 1           = Adjacent Byte (Common for NeoGeo / packed arrays).
    -- 4           = Adjacent Integer (If credits are 32-bit).
    PLAYER_CREDIT_MEMORY_OFFSET = false,

    --------------------------------------------------
    -- PULSE TIMING (Milliseconds)                  --
    --------------------------------------------------
    RECOIL_DURATION_MS = 40,       -- Standard Recoil Solenoid ON time
    RECOIL_ALT_DURATION_MS = 80,   -- Heavier/Longer kick for Alternate Weapon
    
    -- MACHINE GUN RATE LIMITER
    -- Minimum time (in ms) between recoil pulses.
    -- If the game fires faster than this, the script ignores the extra shots
    -- to allow the solenoid to physically return and "kick" again.
    -- Recommended: 80ms - 100ms for Machine Guns (approx 10-12 rounds/sec).
    -- Set to 0 to disable (fires as fast as possible, may cause "humming").
    MIN_RECOIL_INTERVAL_MS = 100,

    DAMAGE_DURATION_MS = 250,  -- Damage Rumble ON time
    
    --------------------------------------------------
    -- AMMO MATH ADJUSTMENTS                        --
    --------------------------------------------------
    -- AMMO_OFFSET: Added to the memory value before processing.
    -- Useful if the game stores "0" for 1 bullet remaining.
    -- Set to 0 or false to disable (use raw memory value).
    AMMO_OFFSET = false,
    AMMO_ALT_OFFSET = false,

    -- AMMO_MAX: Any value ABOVE this number is clamped to 0.
    -- Useful if the game sets ammo to 255 (0xFF) or 99 during reloading/infinity states.
    -- Prevents massive jumps in the "Shots Fired" counter and stops infinite recoil loops.
    -- Recommend setting this to exactly the max capacity of the primary weapon.
    AMMO_MAX = false,
    AMMO_ALT_MAX = false,

    --------------------------------------------------
    -- LIFE MATH ADJUSTMENTS                        --
    --------------------------------------------------
    -- LIFE_OFFSET: Added to the memory value before processing.
    -- Useful if the game stores "0" for 1 life remaining.
    -- Example: Memory reads 0. LIFE_OFFSET = 1. Result = 1.
    -- Set to 0 or false to disable this logic (use raw memory value).
    LIFE_OFFSET = false,

    -- LIFE_MAX: Any value ABOVE this number is clamped to 0.
    -- Useful if the game wraps memory to 255 (0xFF) when the player dies.
    -- Set to false to disable this logic (no clamping).
    LIFE_MAX = false,

    --------------------------------------------------
    -- MEMORY ADDRESSES / OUTPUT NAMES              --
    --------------------------------------------------
    -- GLOBAL CREDITS: 
    -- Set to 'false' if game uses Per-Player only or if you want to bypass the 
    -- "Wait for Credits" safety check.
    CREDITS     = 0x00002030,

    -- GAME_STATUS: 
    -- Set to 'false' if you want to rely on Priority 1 (Player Status) or Priority 3 (Fallback).
    -- If set to 'false', the script will calculate GameStatus = 1 if ANY player is active.
    GAME_STATUS = 0x00002000,
    
    -- GAME_STATUS_ACTIVE_VALUE:
    -- Defines the exact numerical value that indicates active gameplay for STATUS and GAME_STATUS.
    -- Set to 'false' to use the default logic (any value > 0 is considered active).
    GAME_STATUS_ACTIVE_VALUE = false,

    P1 = {
        -- Use specific addresses (e.g. 0x...) if you know them, otherwise set to "auto" (if applicable) or false
        
        -- If CREDITS = "auto", then use Global CREDITS address defined above
        CREDITS      = false,
        
        -- PLAYER STATUS (Priority 1):
        -- If set, this value strictly determines if this player is active.
        -- It overrides Global Status and Fallback logic for this specific player.
        STATUS       = 0x0000219C,
        
        -- At a minimum, it is recommended that AMMO and LIFE contain memory addresses for P1, which will enable automatic logic for other variables and functions
        AMMO         = 0x00002193,
        AMMO_ALT     = false,
        LIFE         = 0x00002191,
        
        -- Set to "auto" to calculate based on Ammo change, or set a memory address if recoil specific targets are available
        RECOIL       = "auto",
        
        -- Damage is hardware rumble feedback, typically associated with when a player is damaged in-game and/or loses a life
        -- Set to "auto" to calculate based on Life change, or set a memory address if damage specific targets are available
        DAMAGE       = "auto",
        
        -- LAMP_START: 
        -- If you want to mirror the native MAME output 'lamp0':
        -- 1. Set DATA_WIDTHS.LAMP_START = "output" above.
        -- 2. Set LAMP_START = "lamp0" here.
        LAMP_START   = false,
        
        -- "auto" = Calculate based on Ammo/Life changes, 0xADDRESS = Read directly from game memory (no quotes), false = Disable this specific counter.
        SHOTS_FIRED  = "auto",
        SHOTS_FIRED_ALT = false,
        DAMAGE_TAKEN = "auto",
        
        -- Tracks number of lives lost
        -- "auto" = Calculate based on Life change, 0xADDRESS = Read memory, false = Disable.
        LIFE_LOST    = "auto",
    },
    P2 = {
        -- Setting AMMO and LIFE to auto inherits P1's addresses for Shared Engine Turn-Based play.
        CREDITS      = "auto", -- If set to "auto" for CREDITS, then it will be determined using PLAYER_CREDIT_MEMORY_OFFSET, but if PLAYER_CREDIT_MEMORY_OFFSET is set to false, then PLAYER_MEMORY_OFFSET is used
        STATUS       = 0x000021DC,
        AMMO         = "auto",
        AMMO_ALT     = "auto",
        LIFE         = "auto",
        RECOIL       = "auto",
        DAMAGE       = "auto",
        LAMP_START   = "auto",
        SHOTS_FIRED  = "auto",
        SHOTS_FIRED_ALT = "auto",
        DAMAGE_TAKEN = "auto",
        LIFE_LOST    = "auto",
    },
    P3 = {
        -- Configuration for Player 3. "auto" will use (P1 Address + PLAYER_MEMORY_OFFSET * 2).
        CREDITS      = "auto",
        STATUS       = "auto",
        AMMO         = "auto",
        AMMO_ALT     = "auto",
        LIFE         = "auto",
        RECOIL       = "auto",
        DAMAGE       = "auto",
        LAMP_START   = "auto",
        SHOTS_FIRED  = "auto",
        SHOTS_FIRED_ALT = "auto",
        DAMAGE_TAKEN = "auto",
        LIFE_LOST    = "auto",
    },
    P4 = {
        -- Configuration for Player 4. "auto" will use (P1 Address + PLAYER_MEMORY_OFFSET * 3).
        CREDITS      = "auto",
        STATUS       = "auto",
        AMMO         = "auto",
        AMMO_ALT     = "auto",
        LIFE         = "auto",
        RECOIL       = "auto",
        DAMAGE       = "auto",
        LAMP_START   = "auto",
        SHOTS_FIRED  = "auto",
        SHOTS_FIRED_ALT = "auto",
        DAMAGE_TAKEN = "auto",
        LIFE_LOST    = "auto",
    },

    -- AMMO_DIRECTION: How the game counts ammo (Used for "auto" logic).
    -- "decrease" = Counts down (6->5->4). Standard for most games.
    -- "increase" = Counts up (0->1->2). Used in Point Blank/Mechanical games.
    AMMO_DIRECTION = "decrease",
    AMMO_ALT_DIRECTION = "decrease",
    
    -- LIFE_DIRECTION: How the game counts life (Used for "auto" logic).
    -- "decrease" = Life bar goes down (Standard).
    -- "increase" = Damage counter goes up (Hits Taken).
    LIFE_DIRECTION = "decrease",
    
    -- SHOTS_FIRED_METHOD: Calculation Logic (Used only if Source is "auto").
    -- "trigger" = Counts +1 for every event (Best for semi-auto).
    -- "bullets" = Counts exact difference (Best for machine guns).
    SHOTS_FIRED_METHOD = "trigger",
    SHOTS_FIRED_ALT_METHOD = "trigger",
    
    -- ENABLE_SHOT_COUNT: Global Master Switch for Shot Counters.
    -- true  = Enable counters (Source defined in P1/P2 tables below).
    -- false = Completely disable all shot counting logic.
    ENABLE_SHOT_COUNT = true,
    
    -- ENABLE_LIFE_LOST: Global Master Switch for Life Lost Counters.
    -- true  = Enable counters (Source defined in P1/P2 tables above).
    -- false = Completely disable all life lost counting logic.
    ENABLE_LIFE_LOST = true,
    
    -- ENABLE_DAMAGE_COUNT: Global Master Switch for Damage Counters.
    -- true  = Enable counters (Source defined in P1/P2 tables above).
    -- false = Completely disable all damage counting logic.
    ENABLE_DAMAGE_COUNT = true,
    
    -- ENABLE_OSD: Controls on-screen messages.
    -- true  = Shows startup messages.
    -- false = Silent mode (Maximum performance, no stutter).
    ENABLE_OSD = false,
}

------------------------------------------------------
-- 1. GLOBAL STATE                                  --
------------------------------------------------------
-- NOTE: No global _Mem or _Out handles are stored here anymore.
-- This prevents the "Stale Pointer" crash on exit.
local _Taps = {} 

-- Credits Latch
-- Tracks if the user has inserted a coin at least once this session.
local _HasCoinedUp = false
-- Crash Prevention Flag
-- Signals the main loop to stop reading memory immediately during MAME shutdown.
local _IsShuttingDown = false

-- If credits are disabled in config (set to false), bypass the latch check immediately
if not CFG.CREDITS then _HasCoinedUp = true end

-- Simple cleanup on exit
emu.add_machine_stop_notifier(function() 
    _IsShuttingDown = true -- Set flag to stop the main loop
    
    for k, tap in pairs(_Taps) do
        -- Safely try to remove taps (ignore errors if machine is already dead)
        pcall(function() tap:remove() end)
    end
    _Taps = {}
end)

------------------------------------------------------
-- 2. SETUP & PRE-CALCULATION                        --
------------------------------------------------------
function Resolve_Addresses()
    -- 1. Sanitize P1 Hardware Outputs
    -- If P1 hardware outputs are "auto", disable them (false)
    -- because P1 cannot inherit addresses from itself.
    local p1_hardware = { "RECOIL", "DAMAGE", "LAMP_START", "STATUS" }
    for _, key in ipairs(p1_hardware) do
        if CFG.P1[key] == "auto" then
            -- If Status is "auto" and Global Game Status has an address (is a number), 
            -- inherit the Global Status address for Player Status.
            if key == "STATUS" and type(CFG.GAME_STATUS) == "number" then
                CFG.P1[key] = CFG.GAME_STATUS
            -- Do NOT disable Recoil/Damage if they are "auto" and have valid sources (Ammo/Life)
            elseif key == "RECOIL" and CFG.P1.AMMO then
                -- Valid: Keep as "auto"
            elseif key == "DAMAGE" and CFG.P1.LIFE then
                -- Valid: Keep as "auto"
            elseif key == "LAMP_START" then
                -- Valid: Keep as "auto"
            else
                CFG.P1[key] = false
            end
        end
    end

    -- 2. Resolve P2, P3, P4 Offsets
    -- If PLAYER_MEMORY_OFFSET is false or nil, default to 0. 
    -- This ensures "auto" still calculates an address (Shared Memory) rather than disabling the output.
    local standard_offset = CFG.PLAYER_MEMORY_OFFSET or 0
    local credit_offset = CFG.PLAYER_CREDIT_MEMORY_OFFSET or standard_offset
    local player_tables = { CFG.P2, CFG.P3, CFG.P4 }

    for i, p_cfg in ipairs(player_tables) do
        local multiplier = i -- P2=1x, P3=2x, P4=3x
        
        for key, val in pairs(p_cfg) do
            if val == "auto" then
                local p1_val = CFG.P1[key]
                -- Only apply offset math if P1 is a NUMBER (Address).
                -- If P1 is a STRING (Native Output Name), we cannot auto-calculate, so disable it.
                if type(p1_val) == "number" then
                    -- If P1 Status is actually just the Global Game Status, 
                    -- then P2/3/4 Status should also be the Global Game Status (No Offset)
                    if key == "STATUS" and p1_val == CFG.GAME_STATUS then
                        p_cfg[key] = p1_val -- Copy exact address (Mirror Global)
                    else
                        -- Standard Offset Calculation
                        local offset_to_use = (key == "CREDITS") and credit_offset or standard_offset
                        p_cfg[key] = p1_val + (offset_to_use * multiplier)
                    end

                elseif p1_val == "auto" then
                    -- If P1 was "auto" (and now resolved to false above), this becomes false too
                    p_cfg[key] = "auto" 
                    if CFG.P1[key] == false then p_cfg[key] = false end
                else
                    -- P1 is a String or False, so P2 cannot be Auto.
                    p_cfg[key] = false
                end
            end
        end
    end

    -- 3. Dependency Pruning
    -- If a source variable is false, force its dependent "auto" variables to false.
    -- This ensures the system does not try to output variables that cannot be determined.
    local all_players = { CFG.P1, CFG.P2, CFG.P3, CFG.P4 }
    for _, p_cfg in ipairs(all_players) do
        -- Ammo Dependencies
        if not p_cfg.AMMO then
            if p_cfg.RECOIL == "auto" then p_cfg.RECOIL = false end
            if p_cfg.SHOTS_FIRED == "auto" then p_cfg.SHOTS_FIRED = false end
        end
        if not p_cfg.AMMO_ALT then
            if p_cfg.SHOTS_FIRED_ALT == "auto" then p_cfg.SHOTS_FIRED_ALT = false end
        end
        -- Life Dependencies
        if not p_cfg.LIFE then
            -- Do NOT disable DAMAGE if it is auto; we need it for calculated rumble!
            if p_cfg.DAMAGE_TAKEN == "auto" then p_cfg.DAMAGE_TAKEN = false end
            -- Also disable LIFE_LOST if no Life source
            if p_cfg.LIFE_LOST == "auto" then p_cfg.LIFE_LOST = false end
        end
    end
end
Resolve_Addresses()

local _RecoilDuration = emu.attotime.from_msec(CFG.RECOIL_DURATION_MS)
local _RecoilAltDuration = emu.attotime.from_msec(CFG.RECOIL_ALT_DURATION_MS or 80)
local _MinRecoilInterval = emu.attotime.from_msec(CFG.MIN_RECOIL_INTERVAL_MS or 0)
local _DamageDuration = emu.attotime.from_msec(CFG.DAMAGE_DURATION_MS)
local _StartupTime = emu.attotime.from_msec(CFG.STARTUP_DELAY_MS)
local _ZeroTime = emu.attotime.from_seconds(0) -- Cached Zero Time object

-- Initialize Player State Table Dynamically
local _Player = {}
for i = 1, 4 do
    _Player[i] = { 
        LastAmmo=0, LastAmmoAlt=0, LastLife=0, LastDmgMem=0, 
        -- Initialize Ticks as Attotime objects to prevent crash
        RecoilTick=_ZeroTime, DamageTick=_ZeroTime, 
        CurrentRecoilDuration=_RecoilDuration, -- Dynamically set before clearing
        LastRecoilVal=0, LastRumbleVal=0, 
        ShotCount=0, ShotCountAlt=0, DamageCount=0, LifeLostCount=0,
        IsActive=false, -- Tracks active state for Tap Handler logic
        IsRecoilActive=false, -- Internal boolean to prevent out:get_value read failures
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
    -- This function uses CFG.STARTUP_DELAY_MS
    return manager.machine.time > _StartupTime
end

-- Helper to get the correct output string based on Simultaneous Play setting and User Config
function Get_Output_Str(player_idx, type_key)
    local target_p = player_idx
    -- SPLIT ROUTING FOR SHARED HARDWARE:
    -- If NOT Simultaneous Play (Shared Hardware), we route PHYSICAL hardware outputs to Player 1.
    -- However, we allow software UI outputs (Ammo, Life, Stats, Status) to stay separated to the actual player.
    if not CFG.SIMULTANEOUS_PLAY then 
        if type_key == "RECOIL" or type_key == "DAMAGE" or type_key == "LAMP_START" then
            target_p = 1
        end
    end
    
    -- Dynamically pull the user-defined suffix, defaulting to the key if not found
    local suffix = CFG.OUTPUT_SUFFIXES[type_key] or type_key
    return "P" .. target_p .. "_" .. suffix
end

-- Read_Data_Safe handles both Memory and Native Outputs
function Read_Data_Safe(mem_handle, source, width)
    if not source then return 0 end

    -- Mode A: Native Output Mirroring (Lowercase check)
    if width == "output" then
        if type(source) == "string" and manager.machine.output then
            return manager.machine.output:get_value(source)
        end
        return 0
    end

    -- Mode B: Memory Read (Standard)
    if not mem_handle then return 0 end
    
    if width == "float32" then
        local val = mem_handle:read_u32(source)
        return string.unpack("f", string.pack("I4", val))
    elseif width == "float32be" then
        local val = mem_handle:read_u32(source)
        val = ((val & 0xFF) << 24) | ((val & 0xFF00) << 8) | ((val & 0xFF0000) >> 8) | ((val & 0xFF000000) >> 24)
        return string.unpack("f", string.pack("I4", val))
    end

    if width == 16 then return mem_handle:read_u16(source) end
    if width == 32 then return mem_handle:read_u32(source) end
    return mem_handle:read_u8(source)
end

-- Helper to register outputs (Safe check included)
function Register_Outputs_Safe(out_handle)
    if not out_handle then return end
    
    -- Global Output Initialization (No 1->0 pulse for these)
    -- This ensures they are registered immediately as 0 if that is their true state.
    out_handle:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_GAME_STATUS, 0)
    if CFG.CREDITS then out_handle:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_CREDITS, 0) end
    
    -- Player Output Initialization List
    local list = {}
    for i = 1, CFG.MAX_PLAYERS do
        local p_cfg = CFG["P"..i] -- Access config for conditional checks
        
        -- Set Player Status & Credits to 0 immediately (No pulse)
        -- Only if configured (not false)
        if p_cfg.STATUS then out_handle:set_value(Get_Output_Str(i, "STATUS"), 0) end
        if p_cfg.CREDITS then out_handle:set_value(Get_Output_Str(i, "CREDITS"), 0) end
        
        -- Conditional check: Only register outputs if the source is valid
        if p_cfg.AMMO then table.insert(list, Get_Output_Str(i, "AMMO")) end
        if p_cfg.AMMO_ALT then table.insert(list, Get_Output_Str(i, "AMMO_ALT")) end
        if p_cfg.LIFE then table.insert(list, Get_Output_Str(i, "LIFE")) end
        
        -- Ensure Recoil/Damage are registered if "Auto" mode is possible
        -- (If AMMO exists, Auto-Recoil exists. If LIFE exists, Auto-Damage exists)
        if p_cfg.RECOIL or p_cfg.AMMO or p_cfg.AMMO_ALT then table.insert(list, Get_Output_Str(i, "RECOIL")) end
        if p_cfg.DAMAGE or p_cfg.LIFE then table.insert(list, Get_Output_Str(i, "DAMAGE")) end
        
        if p_cfg.LAMP_START then table.insert(list, Get_Output_Str(i, "LAMP_START")) end
        
        if CFG.ENABLE_DAMAGE_COUNT and (p_cfg.DAMAGE_TAKEN or p_cfg.LIFE) then table.insert(list, Get_Output_Str(i, "DAMAGE_TAKEN")) end
        if CFG.ENABLE_SHOT_COUNT and (p_cfg.SHOTS_FIRED or p_cfg.AMMO) then table.insert(list, Get_Output_Str(i, "SHOTS_FIRED")) end
        if CFG.ENABLE_SHOT_COUNT and (p_cfg.SHOTS_FIRED_ALT or p_cfg.AMMO_ALT) then table.insert(list, Get_Output_Str(i, "SHOTS_FIRED_ALT")) end
        -- Register output only if enabled globally and per-player
        if CFG.ENABLE_LIFE_LOST and p_cfg.LIFE_LOST then table.insert(list, Get_Output_Str(i, "LIFE_LOST")) end
    end
    
    -- Silently initialize Player outputs to 0 (no pulse)
    for _, name in ipairs(list) do out_handle:set_value(name, 0) end
    
    -- Force clear specific counters
    for i = 1, CFG.MAX_PLAYERS do
        local p_cfg = CFG["P"..i]
        if CFG.ENABLE_SHOT_COUNT and (p_cfg.SHOTS_FIRED or p_cfg.AMMO) then out_handle:set_value(Get_Output_Str(i, "SHOTS_FIRED"), 0) end
        if CFG.ENABLE_SHOT_COUNT and (p_cfg.SHOTS_FIRED_ALT or p_cfg.AMMO_ALT) then out_handle:set_value(Get_Output_Str(i, "SHOTS_FIRED_ALT"), 0) end
        if CFG.ENABLE_DAMAGE_COUNT and (p_cfg.DAMAGE_TAKEN or p_cfg.LIFE) then out_handle:set_value(Get_Output_Str(i, "DAMAGE_TAKEN"), 0) end
        if CFG.ENABLE_LIFE_LOST and p_cfg.LIFE_LOST then out_handle:set_value(Get_Output_Str(i, "LIFE_LOST"), 0) end
    end
end

function Get_Safe_Tap_Address(addr)
    return addr - (addr % 4)
end

------------------------------------------------------
-- 4. TAP HANDLERS (Called by MAME core)            --
------------------------------------------------------
-- NOTE: We must fetch 'out' fresh even here!
function OnWrite_Generic(name, val, player_idx, type_key)
    local out = manager.machine.output
    if not out then return end -- Safety check
    
    local p = _Player[player_idx]

    -- Gate the Tap Handler with Active Status
    -- If the player is not active (Status=0), ignore this memory write immediately.
    -- This prevents the tap from firing when P2 is inactive but memory is initializing.
    if not p.IsActive then return end
    
    if type_key == "RECOIL" then
        -- V5.0.2: Checks if value increased, supporting both binary toggles and incrementing counters
        if val > p.LastRecoilVal then
            -- Use Simultaneous Play logic for output name
            local out_name = Get_Output_Str(player_idx, "RECOIL")
            out:set_value(out_name, 1)
            p.RecoilTick = manager.machine.time
            p.CurrentRecoilDuration = _RecoilDuration -- Default hardware taps to standard duration
            p.IsRecoilActive = true
            
            -- If Turn Based (Shared Hardware), sync P1 timer so P1 logic handles cleanup
            if (not CFG.SIMULTANEOUS_PLAY) and player_idx > 1 then 
                _Player[1].RecoilTick = manager.machine.time 
                _Player[1].CurrentRecoilDuration = _RecoilDuration
                _Player[1].IsRecoilActive = true
            end
        end
        p.LastRecoilVal = val
    end
end

-- Tap creation helper
function Install_Taps_Safe(mem)
    if _TapsInstalled then return end
    local align = CFG.MEMORY_ALIGNMENT
    
    -- Logic now checks if 'align' is truthy (8, 16, 32)
    -- This handles numbers correctly and treats false/nil as Polling Mode.
    if align then
        local range_padding = 3
        -- If taps are needed later, they should be installed using 'mem:install_write_tap' here.
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
    -- EXIT GUARD: Stop immediately if MAME is shutting down.
    if _IsShuttingDown then return end

    -- SAFETY BUBBLE: Wrap everything in pcall to catch ANY crash during shutdown
    local status, err = pcall(function()
        
        -- 1. FRESH FETCH: Get handles NOW. If MAME is shutting down, these return nil.
        if not manager.machine then return end
        local cpu = manager.machine.devices[":maincpu"]
        if not cpu then return end
        local mem = cpu.spaces["program"]
        local out = manager.machine.output
        
        -- If handles are dead, stop immediately
        if not mem or not out then return end

        -- 2. Initialization (Lazy Load)
        if _InitTimer > 0 then
            _InitTimer = _InitTimer - 1
            if _InitTimer == 0 then 
                Register_Outputs_Safe(out)
                Install_Taps_Safe(mem)
            end
        end

        -- 3. Logic Execution
        local divisor = CFG.COINS_PER_CREDIT or 1
        if divisor < 1 then divisor = 1 end
        
        -- Cache the Warmup Status at the start of the frame for efficiency and consistency
        local warmup_ok = Is_Warmup_Complete()

        -- Global Credits & Latch Check
        if CFG.CREDITS then 
            local raw = Read_Data_Safe(mem, CFG.CREDITS, CFG.DATA_WIDTHS.CREDITS)
            local credit_val = math.floor(raw / divisor)
            
            -- Set to exact credit_val if warmup is complete, else force 0
            out:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_CREDITS, warmup_ok and credit_val or 0) 
            
            -- The "Double Lock":
            -- Only latch the "Has Coined Up" flag AFTER the STARTUP_DELAY_MS has passed.
            -- This prevents the latch from being tripped by dirty memory during boot.
            if credit_val > 0 and warmup_ok then 
                _HasCoinedUp = true 
            end
        end
        
        -- Step 1: Check Global Status (if available)
        local global_val = 0
        local global_exists = false
        local is_game_active = false
        if CFG.GAME_STATUS then 
            global_val = Read_Data_Safe(mem, CFG.GAME_STATUS, CFG.DATA_WIDTHS.GAME_STATUS)
            global_exists = true
            
            -- Pre-calculate Global Game Active boolean
            if type(CFG.GAME_STATUS_ACTIVE_VALUE) == "number" then
                if global_val == CFG.GAME_STATUS_ACTIVE_VALUE then is_game_active = true end
            else
                if global_val > 0 then is_game_active = true end
            end
        end

        -- Step 2: Main Player Loop
        local any_player_active = false
        
        for i = 1, CFG.MAX_PLAYERS do
            local cfg
            if i == 1 then cfg = CFG.P1 
            elseif i == 2 then cfg = CFG.P2 
            elseif i == 3 then cfg = CFG.P3 
            else cfg = CFG.P4 end
            
            local p = _Player[i]

            -- Read Stats
            local curr_ammo = 0
            local curr_ammo_alt = 0
            local curr_life = 0
            
            if cfg.AMMO then 
                local raw_ammo = Read_Data_Safe(mem, cfg.AMMO, CFG.DATA_WIDTHS.AMMO) 
                -- 1. Apply Ammo Offset (e.g. 0 -> 1)
                curr_ammo = raw_ammo + (CFG.AMMO_OFFSET or 0)
                -- 2. Apply Ammo Max Clamp
                if CFG.AMMO_MAX and curr_ammo > CFG.AMMO_MAX then
                    curr_ammo = 0
                end
            end

            if cfg.AMMO_ALT then 
                local raw_ammo_alt = Read_Data_Safe(mem, cfg.AMMO_ALT, CFG.DATA_WIDTHS.AMMO_ALT) 
                -- 1. Apply Alt Ammo Offset
                curr_ammo_alt = raw_ammo_alt + (CFG.AMMO_ALT_OFFSET or 0)
                -- 2. Apply Alt Ammo Max Clamp
                if CFG.AMMO_ALT_MAX and curr_ammo_alt > CFG.AMMO_ALT_MAX then
                    curr_ammo_alt = 0
                end
            end
            
            if cfg.LIFE then 
                local raw_life = Read_Data_Safe(mem, cfg.LIFE, CFG.DATA_WIDTHS.LIFE)
                -- 1. Apply Life Offset (e.g. 0 -> 1)
                curr_life = raw_life + (CFG.LIFE_OFFSET or 0)
                -- 2. Apply Life Max Clamp (e.g. 256 -> 0)
                if CFG.LIFE_MAX and curr_life > CFG.LIFE_MAX then
                    curr_life = 0
                end
            end

            -- Read Player Credits (Used for stricter fallback logic)
            local p_credits = 0
            local p_credits_known = false
            if cfg.CREDITS then
                if type(cfg.CREDITS) == "number" then 
                    p_credits = Read_Data_Safe(mem, cfg.CREDITS, CFG.DATA_WIDTHS.CREDITS)
                    p_credits_known = true
                elseif cfg.CREDITS == "auto" and CFG.CREDITS then 
                    p_credits = Read_Data_Safe(mem, CFG.CREDITS, CFG.DATA_WIDTHS.CREDITS) 
                end
                -- Gate Output
                out:set_value(Get_Output_Str(i, "CREDITS"), warmup_ok and math.floor(p_credits / divisor) or 0)
            end

            -- --------------------------------------------------------
            -- DETERMINATION: IS THIS PLAYER ACTIVE?
            -- --------------------------------------------------------
            local is_player_active = false

            -- Priority 1: Specific Player Status
            if cfg.STATUS and cfg.STATUS ~= "auto" then
                local p_stat_val = Read_Data_Safe(mem, cfg.STATUS, CFG.DATA_WIDTHS.STATUS)
                
                local p_stat_active = false
                if type(CFG.GAME_STATUS_ACTIVE_VALUE) == "number" then
                    if p_stat_val == CFG.GAME_STATUS_ACTIVE_VALUE then p_stat_active = true end
                else
                    if p_stat_val > 0 then p_stat_active = true end
                end

                -- INTERSECTION LOGIC: If global status is known, BOTH must be active.
                if global_exists then
                    if is_game_active and p_stat_active then
                        is_player_active = true
                    end
                else
                    -- If no global status is mapped, rely purely on player status
                    if p_stat_active then 
                        is_player_active = true 
                    end
                end

            -- Priority 2: Global Game Status + Life (No Individual Status mapped)
            elseif global_exists then
                -- Both must be true: Game is active AND player has life remaining
                if is_game_active and curr_life > 0 then 
                    is_player_active = true 
                end

            -- Priority 3: Fallback (Coin + Life)
            else
                if _HasCoinedUp and curr_life > 0 then 
                    -- If we know P2's credit count, do NOT wake them up on P1's coin unless P2 has credits too.
                    -- If credits are unknown (not mapped), we must assume active.
                    if (not p_credits_known) or (p_credits > 0) then
                        is_player_active = true 
                    end
                end
            end
            
            -- HARD WARMUP GATE
            -- Force active state to false during warmup so hardware events do not trigger
            if not warmup_ok then
                is_player_active = false
            end
            
            -- Save State for Tap Handler
            -- We save this so the Tap Handler knows whether to allow high-speed recoil.
            p.IsActive = is_player_active
            
            -- Used for Status Synthesis below
            if is_player_active then any_player_active = true end

            -- Normalized Output: Send clean 1 or 0 instead of raw memory value
            if cfg.STATUS then 
                out:set_value(Get_Output_Str(i, "STATUS"), is_player_active and 1 or 0) 
            end

            -- [GATED ACTION LOGIC] - Runs only if Player is Active
            if is_player_active then
            
                -- Base UI Outputs (Software UI is frozen for inactive players in Turn-Based play)
                if cfg.LAMP_START then out:set_value(Get_Output_Str(i, "LAMP_START"), warmup_ok and Read_Data_Safe(mem, cfg.LAMP_START, CFG.DATA_WIDTHS.LAMP_START) or 0) end
                if cfg.AMMO then out:set_value(Get_Output_Str(i, "AMMO"), warmup_ok and curr_ammo or 0) end
                if cfg.AMMO_ALT then out:set_value(Get_Output_Str(i, "AMMO_ALT"), warmup_ok and curr_ammo_alt or 0) end
                if cfg.LIFE then out:set_value(Get_Output_Str(i, "LIFE"), warmup_ok and curr_life or 0) end

                -- Primary Shot Counter
                if CFG.ENABLE_SHOT_COUNT and cfg.SHOTS_FIRED and warmup_ok then
                    if type(cfg.SHOTS_FIRED) == "number" then
                        -- Use Read_Data_Safe for variable width support
                        local mem_val = Read_Data_Safe(mem, cfg.SHOTS_FIRED, CFG.DATA_WIDTHS.SHOTS_FIRED)
                        out:set_value(Get_Output_Str(i, "SHOTS_FIRED"), mem_val)
                        p.ShotCount = mem_val
                    elseif cfg.SHOTS_FIRED == "auto" and cfg.AMMO then
                        local shot = false
                        local diff = 0
                        
                        if CFG.AMMO_DIRECTION == "decrease" then
                            -- Only trigger if decreased AND reasonable value
                            if curr_ammo < p.LastAmmo and p.LastAmmo <= 200 then
                                shot = true; diff = p.LastAmmo - curr_ammo
                            end
                        else
                            if curr_ammo > p.LastAmmo then
                                shot = true; diff = curr_ammo - p.LastAmmo
                            end
                        end
                        if shot then
                            if CFG.SHOTS_FIRED_METHOD == "bullets" then
                                p.ShotCount = p.ShotCount + diff
                            else
                                p.ShotCount = p.ShotCount + 1
                            end
                            out:set_value(Get_Output_Str(i, "SHOTS_FIRED"), p.ShotCount)
                        end
                    end
                end

                -- Alternate Shot Counter
                if CFG.ENABLE_SHOT_COUNT and cfg.SHOTS_FIRED_ALT and warmup_ok then
                    if type(cfg.SHOTS_FIRED_ALT) == "number" then
                        local mem_val = Read_Data_Safe(mem, cfg.SHOTS_FIRED_ALT, CFG.DATA_WIDTHS.SHOTS_FIRED_ALT)
                        out:set_value(Get_Output_Str(i, "SHOTS_FIRED_ALT"), mem_val)
                        p.ShotCountAlt = mem_val
                    elseif cfg.SHOTS_FIRED_ALT == "auto" and cfg.AMMO_ALT then
                        local shot = false
                        local diff = 0
                        
                        if CFG.AMMO_ALT_DIRECTION == "decrease" then
                            if curr_ammo_alt < p.LastAmmoAlt and p.LastAmmoAlt <= 200 then
                                shot = true; diff = p.LastAmmoAlt - curr_ammo_alt
                            end
                        else
                            if curr_ammo_alt > p.LastAmmoAlt then
                                shot = true; diff = curr_ammo_alt - p.LastAmmoAlt
                            end
                        end
                        if shot then
                            if CFG.SHOTS_FIRED_ALT_METHOD == "bullets" then
                                p.ShotCountAlt = p.ShotCountAlt + diff
                            else
                                p.ShotCountAlt = p.ShotCountAlt + 1
                            end
                            out:set_value(Get_Output_Str(i, "SHOTS_FIRED_ALT"), p.ShotCountAlt)
                        end
                    end
                end

                -- DECOUPLED DAMAGE LOGIC
                -- Physical hardware rumble triggers independently from the on-screen statistics counter.
                local rumble_triggered = false
                
                if type(cfg.DAMAGE_TAKEN) == "number" then
                    -- Use Read_Data_Safe for variable width support
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
                elseif cfg.DAMAGE_TAKEN == "auto" and cfg.LIFE then
                    local hit = false
                    if CFG.LIFE_DIRECTION == "decrease" then
                        -- Simple check works because Offset/Max logic (above) smoothed the data
                        if curr_life < p.LastLife then hit = true end
                    else
                        if curr_life > p.LastLife then hit = true end
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
                    p.DamageTick = manager.machine.time
                    p.IsDamageActive = true
                    -- If NOT Simultaneous (Shared Hardware), Sync P1 timer
                    if (not CFG.SIMULTANEOUS_PLAY) and i > 1 then 
                        _Player[1].DamageTick = manager.machine.time 
                        _Player[1].IsDamageActive = true
                    end
                end
                
                -- Hardware Rumble Check (Inside Active Gate)
                -- Uses 'DAMAGE' config key (formerly RUMBLE)
                if cfg.DAMAGE then
                    -- Only try to read if it is NOT "auto" string
                    if type(cfg.DAMAGE) == "number" or (type(cfg.DAMAGE) == "string" and cfg.DAMAGE ~= "auto") then
                        local val = Read_Data_Safe(mem, cfg.DAMAGE, CFG.DATA_WIDTHS.DAMAGE)
                        
                        -- V5.0.2: Checks if value increased, supporting both binary toggles and incrementing counters
                        if val > p.LastRumbleVal then
                            out:set_value(Get_Output_Str(i, "DAMAGE"), 1)
                            p.DamageTick = manager.machine.time
                            p.IsDamageActive = true
                            
                            -- If NOT Simultaneous (Shared Hardware), Sync P1 timer
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
                
                -- Life Lost Logic
                if CFG.ENABLE_LIFE_LOST then
                    if cfg.LIFE_LOST == "auto" and cfg.LIFE and warmup_ok then
                         local lost = false
                         if CFG.LIFE_DIRECTION == "decrease" then
                             if curr_life < p.LastLife then lost = true end
                         else
                             if curr_life > p.LastLife then lost = true end
                         end
                         if lost then
                             p.LifeLostCount = p.LifeLostCount + 1
                             out:set_value(Get_Output_Str(i, "LIFE_LOST"), p.LifeLostCount)
                         end
                    elseif type(cfg.LIFE_LOST) == "number" then
                         -- Support direct reading if user supplies an address (uses variable width)
                         local val = Read_Data_Safe(mem, cfg.LIFE_LOST, CFG.DATA_WIDTHS.LIFE_LOST)
                         out:set_value(Get_Output_Str(i, "LIFE_LOST"), val)
                    end
                end

                -- Recoil Check (Inside Active Gate)
                -- Polling is enabled when MEMORY_ALIGNMENT evaluates as false
                if not CFG.MEMORY_ALIGNMENT then
                      local trigger_type = 0 -- 0=none, 1=primary, 2=alt
                      
                      -- Check Primary Ammo Drop
                      if cfg.AMMO then
                          if CFG.AMMO_DIRECTION == "decrease" then
                              if curr_ammo < p.LastAmmo and p.LastAmmo <= 200 then trigger_type = 1 end
                          else
                              if curr_ammo > p.LastAmmo then trigger_type = 1 end
                          end
                      end
                      
                      -- Check Alternate Ammo Drop (Overwrites trigger_type if both happen, alt takes priority)
                      if cfg.AMMO_ALT then
                          if CFG.AMMO_ALT_DIRECTION == "decrease" then
                              if curr_ammo_alt < p.LastAmmoAlt and p.LastAmmoAlt <= 200 then trigger_type = 2 end
                          else
                              if curr_ammo_alt > p.LastAmmoAlt then trigger_type = 2 end
                          end
                      end
                      
                      if trigger_type > 0 then
                          -- MACHINE GUN RATE LIMITER
                          local time_since_last = manager.machine.time - p.RecoilTick
                          if time_since_last > _MinRecoilInterval then
                              -- Dynamically assign duration based on weapon type
                              if trigger_type == 1 then
                                  p.CurrentRecoilDuration = _RecoilDuration
                              else
                                  p.CurrentRecoilDuration = _RecoilAltDuration
                              end

                              out:set_value(Get_Output_Str(i, "RECOIL"), 1)
                              p.RecoilTick = manager.machine.time
                              p.IsRecoilActive = true
                              
                              -- If NOT Simultaneous (Shared Hardware), Sync P1 timer and duration
                              if (not CFG.SIMULTANEOUS_PLAY) and i > 1 then 
                                  _Player[1].RecoilTick = manager.machine.time 
                                  _Player[1].CurrentRecoilDuration = p.CurrentRecoilDuration
                                  _Player[1].IsRecoilActive = true
                              end
                          end
                      end
                end
            else
                -- [SAFETY CLAMP FIX]
                -- Only allow inactive players to wipe physical hardware if it is standard simultaneous play.
                -- Otherwise, inactive players will accidentally wipe the Active Player's hardware lines.
                if CFG.SIMULTANEOUS_PLAY then
                    if cfg.RECOIL or cfg.AMMO or cfg.AMMO_ALT then 
                        out:set_value(Get_Output_Str(i, "RECOIL"), 0) 
                        p.IsRecoilActive = false
                    end
                    if cfg.DAMAGE or cfg.LIFE then 
                        out:set_value(Get_Output_Str(i, "DAMAGE"), 0) 
                        p.IsDamageActive = false
                    end
                end
            end
            -- [GATED LOGIC END]

            p.LastAmmo = curr_ammo
            p.LastAmmoAlt = curr_ammo_alt
            p.LastLife = curr_life

            -- Handle Output Timing
            -- If SIMULTANEOUS = true, everyone handles their own outputs.
            -- If SIMULTANEOUS = false, ONLY P1 loop clears the shared output.
            local can_clear_output = true
            if (not CFG.SIMULTANEOUS_PLAY) and i > 1 then 
                can_clear_output = false 
            end

            -- DECOUPLED TIMER CLEARING (No longer relies on out:get_value)
            if can_clear_output then
                if p.IsRecoilActive then
                    local recoil_elapsed = manager.machine.time - p.RecoilTick
                    if recoil_elapsed > p.CurrentRecoilDuration then
                        out:set_value(Get_Output_Str(i, "RECOIL"), 0)
                        p.IsRecoilActive = false
                    end
                end
                
                if p.IsDamageActive then
                    local damage_elapsed = manager.machine.time - p.DamageTick
                    if damage_elapsed > _DamageDuration then
                        out:set_value(Get_Output_Str(i, "DAMAGE"), 0)
                        p.IsDamageActive = false
                    end
                end
            end
        end -- End Player Loop

        -- GLOBAL SHARED HARDWARE CLAMP
        -- If no one is actively playing, safely pull down the physical hardware lines.
        if not CFG.SIMULTANEOUS_PLAY and not any_player_active then
            out:set_value(Get_Output_Str(1, "RECOIL"), 0)
            out:set_value(Get_Output_Str(1, "DAMAGE"), 0)
            _Player[1].IsRecoilActive = false
            _Player[1].IsDamageActive = false
        end

        -- Final Step: Report Global GameStatus
        -- If global address exists, use it (normalized to 1 or 0). If not, synthesize from individual player status.
        if global_exists then
            out:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_GAME_STATUS, (warmup_ok and is_game_active) and 1 or 0)
        else
            out:set_value(CFG.OUTPUT_SUFFIXES.GLOBAL_GAME_STATUS, warmup_ok and (any_player_active and 1 or 0) or 0)
        end

    end)
    
    -- If pcall caught an error (e.g. MAME shutdown), do nothing.
    if not status then 
        -- Optional: print("Lua Safety Catch: " .. tostring(err)) 
    end
end

emu.register_frame_done(Compute_Outputs, "frame")