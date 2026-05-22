------------------------------------------------------
-- MAME STATE OUTPUT LUA SCRIPT
-- Script Template Version: 7.5.1
-- Last Modified Date (YYYY.MM.DD): 2026.05.22
-- Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
-- License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
-- Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
-- Created by DJ GLiTCH, with additional testing by Muggins
------------------------------------------------------

local CFG = {
    --------------------------------------------------
    -- LUA SCRIPT METADATA                          --
    --------------------------------------------------
    -- MAME state outputs only support integers (no decimals or text strings)
    -- Lua Version represents the version of the universal MAME Lua script used as the baseline code
    LUA_VERSION = 751,
    LUA_DATE    = 20260522,
    LUA_ROM     = "sgunner2",
    LUA_GAME    = "Steel Gunner 2",
    LUA_ROM_ID  = 78,
    
    -- External Script Hooks (for future projects)
    OFFSCREEN_RELOAD = false,
    LIGHTGUN_PATCH   = false,
    
    -- SCREEN FLASH REMOVAL
    -- Disables the bright white flashes used for optical CRT light guns to prevent eye strain/seizures.
    SCREEN_FLASH                = false,
    SCREEN_FLASH_MEMORY_ADDRESS = false,
    SCREEN_FLASH_DISABLE_VALUE  = false,
    SCREEN_FLASH_RESTORE_VALUE  = false,
    
    --------------------------------------------------
    -- SYSTEM SETTINGS                              --
    --------------------------------------------------
    -- CPU_TAG: Defines the global CPU to read memory from. Default should be ":maincpu"
    CPU_TAG = ":maincpu",
    
    -- MEMORY_SPACE: Defines the global memory space to read from. Default should be "program"
    MEMORY_SPACE = "program",
    
    -- CPU_TAGS (Multi-CPU Overrides)
    -- Allows you to specify different CPUs for specific variables
    -- If a variable is set to false, blank (""), or "auto", it seamlessly falls back to the Global CPU_TAG
    CPU_TAGS = {
        SCREEN_FLASH            = false,
        GLOBAL_ATTRACT_STATUS   = false,
        GLOBAL_CREDITS          = false,
        GLOBAL_GAME_STATUS      = false,
        CREDITS                 = false,
        STATUS                  = false,
        STATUS_ALT              = false,
        AMMO                    = false,
        AMMO_ALT                = false,
        AMMO_GRENADE            = false,
        LIFE                    = false,
        LIFE_ALT                = false,
        RECOIL                  = false,
        RELOAD                  = false,
        DAMAGE                  = false,
        RUMBLE                  = false,
        LAMP_START              = false,
        SHOTS_FIRED_PRIMARY     = false,
        SHOTS_FIRED_ALT         = false,
        SHOTS_FIRED_GRENADE     = false,
        LIFE_LOST               = false,
        DAMAGE_TAKEN            = false,
    },
    
    -- MEMORY_SPACES (Multi-Bus Overrides)
    -- Allows you to specify different memory spaces (e.g., "data" vs "program")
    -- If a variable is set to false, blank (""), or "auto", it falls back to the Global MEMORY_SPACE
    MEMORY_SPACES = {
        SCREEN_FLASH            = false,
        GLOBAL_ATTRACT_STATUS   = false,
        GLOBAL_CREDITS          = false,
        GLOBAL_GAME_STATUS      = false,
        CREDITS                 = false,
        STATUS                  = false,
        STATUS_ALT              = false,
        AMMO                    = false,
        AMMO_ALT                = false,
        AMMO_GRENADE            = false,
        LIFE                    = false,
        LIFE_ALT                = false,
        RECOIL                  = false,
        RELOAD                  = false,
        DAMAGE                  = false,
        RUMBLE                  = false,
        LAMP_START              = false,
        SHOTS_FIRED_PRIMARY     = false,
        SHOTS_FIRED_ALT         = false,
        SHOTS_FIRED_GRENADE     = false,
        LIFE_LOST               = false,
        DAMAGE_TAKEN            = false,
    },
    
    -- STARTUP_DELAY_MS: Time to wait before tracking stats (in ms).
    -- Prevents false "shots fired" events and blocks "Dirty RAM" while the arcade board boots up.
    STARTUP_DELAY_MS = 4000,
    
    -- STATUS_DEBOUNCE_MS: Time (in ms) to wait before validating an "Active" state.
    -- Prevents 1-frame flashes if a game momentarily drops player status during cutscenes.
    STATUS_DEBOUNCE_MS = 34,
    
    -- CREDITS_CLEAR_TIMEOUT_SEC: Safety valve for "walk-aways".
    -- If the game remains completely inactive (GameStatus = 0) for this many seconds, 
    -- all pending unconsumed credits are wiped. Set to false to disable.
    CREDITS_CLEAR_TIMEOUT_SEC  = 60,
    
    -- COINS_PER_CREDIT: How many coins make 1 Credit?
    -- Example: Set to 2. If you insert 3 coins, output is 1 Credit (1.5 rounds down to 1).
    COINS_PER_CREDIT = 1,
    
    -- MAX_PLAYERS: Set the number of players to track (1 to 4)
    MAX_PLAYERS = 2,
    
    -- SIMULTANEOUS_PLAY: Controls how outputs are routed.
    -- true  = Standard Arcade Mode (Simultaneous). Each player triggers their own hardware outputs.
    -- false = Shared Hardware Mode (Turn Based). All players route their FFB triggers to Player 1's hardware.
    SIMULTANEOUS_PLAY = true,
    
    --------------------------------------------------
    -- STATE OUTPUT NAMES (SUFFIXES)                --
    --------------------------------------------------
    -- Customize the string names sent to external software.
    -- The script will automatically prepend the player number (e.g. "P1_")
    OUTPUT_SUFFIXES = {
        GLOBAL_LUA_VERSION      = "LuaVersion",
        GLOBAL_LUA_DATE         = "LuaDate",
        GLOBAL_LUA_ROM_ID       = "LuaROMid",
        GLOBAL_CREDITS          = "Credits",
        GLOBAL_CREDITS_INSERTED = "GlobalCreditsInserted",
        GLOBAL_GAME_STATUS      = "GameStatus",
        GLOBAL_ATTRACT_STATUS   = "AttractStatus",
        
        CREDITS                 = "Credits",
        CREDITS_INSERTED        = "CreditsInserted",
        CREDITS_CONSUMED        = "CreditsConsumed",
        
        STATUS                  = "Status",
        STATUS_ALT              = "StatusAlt",
        
        -- Player Stats
        AMMO                    = "Ammo",
        AMMO_ALT                = "AmmoAlt",
        AMMO_GRENADE            = "AmmoGrenade",
        LIFE                    = "Life",
        LIFE_ALT                = "LifeAlt",
        
        -- Hardware Force Feedback
        RECOIL                  = "Recoil",
        RELOAD                  = "Reload",
        DAMAGE                  = "Damage",
        RUMBLE                  = "Rumble",
        
        LAMP_START              = "LampStart",
        
        -- Calculated Stats
        SHOTS_FIRED             = "ShotsFired", -- The Total Sum of all weapons
        SHOTS_FIRED_PRIMARY     = "ShotsFiredPrimary",
        SHOTS_FIRED_ALT         = "ShotsFiredAlt",
        SHOTS_FIRED_GRENADE     = "ShotsFiredGrenade",
        DAMAGE_TAKEN            = "DamageTaken",
        LIFE_LOST               = "LifeLost",
    },
    
    --------------------------------------------------
    -- HARDWARE CONFIGURATION                       --
    --------------------------------------------------
    -- MEMORY READ WIDTHS (8, 16, 32, "float32", "float32be", or "output")
    -- Define how many bits to read for each data type
    --
    -- VALID VALUES:
    -- 8             = Byte (standard) - default for majority of arcade 2D games
    -- 16            = Word
    -- 32            = Dword
    -- "float32"     = 32-bit Float (Common in modern 3D games)
    -- "float32be"   = 32-bit Big Endian Float
    -- "output"      = NATIVE MIRROR MODE
    --                 If set to "output", the script will NOT read memory addresses.
    --                 Instead, it reads the value of a native MAME output string defined in the player tables.
    DATA_WIDTHS = {
        SCREEN_FLASH            = 8,
        GLOBAL_ATTRACT_STATUS   = 8,
        GLOBAL_CREDITS          = 8,
        GLOBAL_CREDITS_INSERTED = 16,
        GLOBAL_GAME_STATUS      = 8,
        CREDITS                 = 8,
        CREDITS_INSERTED        = 16,
        CREDITS_CONSUMED        = 16,
        STATUS                  = 8,
        STATUS_ALT              = 8,
        AMMO                    = 8,
        AMMO_ALT                = 8,
        AMMO_GRENADE            = 8,
        LIFE                    = 8,
        LIFE_ALT                = 8,
        RECOIL                  = 8,
        RELOAD                  = 8,
        DAMAGE                  = 8,
        RUMBLE                  = 8,
        LAMP_START              = 8,
        SHOTS_FIRED             = 16,
        SHOTS_FIRED_PRIMARY     = 16,
        SHOTS_FIRED_ALT         = 16,
        SHOTS_FIRED_GRENADE     = 16,
        LIFE_LOST               = 16,
        DAMAGE_TAKEN            = 16
    },
    
    -- MEMORY_ALIGNMENT: Controls the "width" of the high-speed memory tap
    --
    -- TROUBLESHOOTING GUIDE:
    -- 1. Start with MEMORY_ALIGNMENT = 32 (32-bit)
    -- 2. Run the script. If MAME crashes with "end address has low bits unset", change to 16.
    -- 3. If that fails, change to 8 (8-bit)
    -- 4. If 8 fails or causes instability, set to false (Standard Polling Safe Mode)
    --
    -- VALID VALUES:
    -- 32          = 32-bit (Model 2/3, Namco System 11/12, PlayStation, Beast Busters, CarnEvil)
    -- 16          = 16-bit (Sega System 16/32, SNES/Genesis, NeoGeo)
    -- 8           = 8-bit  (Operation Wolf, T2, Midway Y-Unit)
    -- false       = Standard Polling (Safe Mode, ~16ms latency)
    MEMORY_ALIGNMENT = false,
    
    -- PLAYER_MEMORY_OFFSET: Distance between P1 and next player's memory (in bytes)
    -- Used ONLY when P2, P3, P4 addresses below are set to "auto"
    --
    -- IMPORTANT FOR SIMULTANEOUS PLAY:
    -- You usually need a real offset (e.g. 0xA8, 0x40, 4) unless you manually record individual memory addresses for P2.
    --
    -- SHARED MEMORY / TURN BASED:
    -- Set to 0 or false. This forces P2 to read the same address as P1 (Offset 0).
    PLAYER_MEMORY_OFFSET = 0x2,
    
    -- PLAYER_CREDIT_MEMORY_OFFSET: Specific offset for Credits only.
    -- Use this if Credits are stored in a different memory array than Ammo/Life.
    -- false = Uses the standard PLAYER_MEMORY_OFFSET.
    PLAYER_CREDIT_MEMORY_OFFSET = false,
    
    --------------------------------------------------
    -- PULSE TIMING (Milliseconds)                  --
    --------------------------------------------------
    -- Signal pulse durations sent to the physical hardware.
    RECOIL_DURATION_MS         = 40, 
    RECOIL_ALT_DURATION_MS     = 40, 
    RECOIL_GRENADE_DURATION_MS = 80, 
    RELOAD_DURATION_MS         = 40, 
    
    -- MACHINE GUN RATE LIMITER (MIN_RECOIL_INTERVAL_MS)
    -- Minimum time (in ms) between recoil pulses. 
    -- If the game fires faster than this, the script ignores the extra shots to allow the physical solenoid to return and "kick" again.
    -- Recommended: 80ms - 100ms for Machine Guns (approx 10-12 rounds/sec).
    MIN_RECOIL_INTERVAL_MS     = 100, 
    
    -- RECOIL_HOLD_MS: 
    -- Interval between pulses when RECOIL_METHOD = "hold" and the recoil trigger is held down.
    -- Used to create a slower "empty-click" fire rate when primary ammo hits 0.
    RECOIL_HOLD_MS             = 100, 
    
    DAMAGE_DURATION_MS         = 250, 
    RUMBLE_DURATION_MS         = 250, 
    
    --------------------------------------------------
    -- AMMO MATH ADJUSTMENTS                        --
    --------------------------------------------------
    -- AMMO_OFFSET: Added to the memory value before processing.
    -- Useful if the game stores "0" in RAM when there is actually 1 bullet remaining.
    AMMO_OFFSET         = false,
    AMMO_ALT_OFFSET     = false,
    AMMO_GRENADE_OFFSET = false,
    
    -- AMMO_MAX: Hard Clamps. Any value ABOVE this number is forcefully rewritten to 0.
    -- Extremely important if the game sets ammo to 255 (0xFF) or 99 during reloading/infinity states.
    -- Prevents massive jumps in the "Shots Fired" counter and stops infinite recoil loops.
    AMMO_MAX            = false,
    AMMO_ALT_MAX        = false,
    AMMO_GRENADE_MAX    = false,

    -- AMMO_THRESHOLD: Event Filters.
    -- Ignores mathematically dropping ammo (Shots Fired & Recoil) if the drop originates from a number above this threshold.
    -- Useful for bypassing 16-bit integer underflows (65535) or temporary "Infinite Ammo" bitmasks (99) without erasing the true memory value.
    -- If false, safely defaults to 254.
    AMMO_THRESHOLD         = 254,
    AMMO_ALT_THRESHOLD     = 254,
    AMMO_GRENADE_THRESHOLD = 254,
    
    --------------------------------------------------
    -- LIFE MATH ADJUSTMENTS                        --
    --------------------------------------------------
    -- LIFE_OFFSET: Added to the memory value before processing.
    LIFE_OFFSET     = false,
    LIFE_ALT_OFFSET = false,
    
    -- LIFE_MAX: Any value ABOVE this number is clamped to 0.
    -- Crucial for games that use 16-bit unsigned integers. If life drops below 0, it wraps to 65535 (Integer Underflow).
    -- Setting a MAX clamps that underflow back down to 0 so LifeLost calculations remain accurate.
    LIFE_MAX        = false,
    LIFE_ALT_MAX    = false,
    
    --------------------------------------------------
    -- MEMORY ADDRESSES                             --
    --------------------------------------------------
    -- GLOBAL ATTRACT STATUS:
    -- Forces GameStatus to 0 (inactive) whenever this reads > 0 (or exactly matches ATTRACT_STATUS_ACTIVE_VALUE).
    -- Useful for games that erroneously flag GameStatus as active during attract mode cutscenes.
    ATTRACT_STATUS = false,
    
    -- GLOBAL CREDITS: 
    -- Set to 'false' if game uses Per-Player only or if you want to bypass "Wait for Credits" safety checks.
    CREDITS        = false,
    
    -- GLOBAL GAME STATUS: 
    -- Set to 'false' to rely on individual Player Status (Priority 1) or Life/Credits (Fallback).
    -- If 'false', the script calculates GameStatus = 1 if ANY player is currently active.
    GAME_STATUS    = 0x00100944,
    
    -- ACTIVE VALUES:
    -- Defines the exact numerical value that indicates active gameplay.
    -- false = Use default logic (any value > 0 is considered active).
    -- 0     = Use this if the game specifically uses 0 to denote active gameplay.
    ATTRACT_STATUS_ACTIVE_VALUE = false,
    GAME_STATUS_ACTIVE_VALUE    = false,
    STATUS_ACTIVE_VALUE         = false,
    STATUS_ALT_ACTIVE_VALUE     = false,
    
    P1 = {
        CREDITS                 = 0x00108C11,
        
        -- PLAYER STATUS (Priority 1):
        -- If player status is set, this value strictly determines if this player is active.
        -- Overrides Global Status and Fallback logic for this specific player.
        STATUS                  = 0x00108AED,
        STATUS_ACTIVE_VALUE     = false,
        STATUS_ALT              = false,
        STATUS_ALT_ACTIVE_VALUE = false,
        
        AMMO                    = 0x00108D43,
        AMMO_ALT                = 0x00108D3F,
        AMMO_GRENADE            = false,
        LIFE                    = 0x00108C25,
        LIFE_ALT                = false,
        
        -- HARDWARE FEEDBACK:
        -- Recoil = Weapon Shooting | Reload = Changing Magazine | Damage = Player Hit | Rumble = Environmental FFB
        RECOIL                  = "auto",
        RELOAD                  = "auto",
        DAMAGE                  = "auto",
        RUMBLE                  = false,
        LAMP_START              = false,
        
        -- CALCULATED STATS:
        -- "auto" = Calculate internally based on Ammo/Life changes. 
        -- 0xADDRESS = Read directly from native game memory.
        SHOTS_FIRED             = "auto", -- Note: P1_ShotsFired is always dynamically calculated as the Sum Total.
        SHOTS_FIRED_PRIMARY     = "auto",
        SHOTS_FIRED_ALT         = "auto",
        SHOTS_FIRED_GRENADE     = "auto",
        DAMAGE_TAKEN            = "auto",
        LIFE_LOST               = "auto"
    },
    
    P2 = {
        CREDITS                 = "auto",
        STATUS                  = 0x00108B79,
        STATUS_ACTIVE_VALUE     = "auto",
        STATUS_ALT              = "auto",
        STATUS_ALT_ACTIVE_VALUE = "auto",
        AMMO                    = "auto",
        AMMO_ALT                = "auto",
        AMMO_GRENADE            = "auto",
        LIFE                    = "auto",
        LIFE_ALT                = "auto",
        RECOIL                  = "auto",
        RELOAD                  = "auto",
        DAMAGE                  = "auto",
        RUMBLE                  = "auto",
        LAMP_START              = "auto",
        SHOTS_FIRED             = "auto",
        SHOTS_FIRED_PRIMARY     = "auto",
        SHOTS_FIRED_ALT         = "auto",
        SHOTS_FIRED_GRENADE     = "auto",
        DAMAGE_TAKEN            = "auto",
        LIFE_LOST               = "auto"
    },
    
    P3 = {
        CREDITS                 = "auto",
        STATUS                  = "auto",
        STATUS_ACTIVE_VALUE     = "auto",
        STATUS_ALT              = "auto",
        STATUS_ALT_ACTIVE_VALUE = "auto",
        AMMO                    = "auto",
        AMMO_ALT                = "auto",
        AMMO_GRENADE            = "auto",
        LIFE                    = "auto",
        LIFE_ALT                = "auto",
        RECOIL                  = "auto",
        RELOAD                  = "auto",
        DAMAGE                  = "auto",
        RUMBLE                  = "auto",
        LAMP_START              = "auto",
        SHOTS_FIRED             = "auto",
        SHOTS_FIRED_PRIMARY     = "auto",
        SHOTS_FIRED_ALT         = "auto",
        SHOTS_FIRED_GRENADE     = "auto",
        DAMAGE_TAKEN            = "auto",
        LIFE_LOST               = "auto"
    },
    
    P4 = {
        CREDITS                 = "auto",
        STATUS                  = "auto",
        STATUS_ACTIVE_VALUE     = "auto",
        STATUS_ALT              = "auto",
        STATUS_ALT_ACTIVE_VALUE = "auto",
        AMMO                    = "auto",
        AMMO_ALT                = "auto",
        AMMO_GRENADE            = "auto",
        LIFE                    = "auto",
        LIFE_ALT                = "auto",
        RECOIL                  = "auto",
        RELOAD                  = "auto",
        DAMAGE                  = "auto",
        RUMBLE                  = "auto",
        LAMP_START              = "auto",
        SHOTS_FIRED             = "auto",
        SHOTS_FIRED_PRIMARY     = "auto",
        SHOTS_FIRED_ALT         = "auto",
        SHOTS_FIRED_GRENADE     = "auto",
        DAMAGE_TAKEN            = "auto",
        LIFE_LOST               = "auto"
    },
    
    --------------------------------------------------
    -- LOGIC & COUNTING BEHAVIOR                    --
    --------------------------------------------------
    -- AMMO/LIFE DIRECTION: How the game naturally counts.
    -- "decrease" = Counts down (6->5->4). Standard for most games.
    -- "increase" = Counts up (0->1->2).
    -- "change"   = Triggers on ANY change, including wraps. (Best for infinite ammo machine guns).
    AMMO_DIRECTION             = "increase",
    AMMO_ALT_DIRECTION         = "decrease",
    AMMO_GRENADE_DIRECTION     = "decrease",
    LIFE_DIRECTION             = "decrease",
    LIFE_ALT_DIRECTION         = "decrease",
    
    -- SHOTS_FIRED_METHOD: Calculation Logic (Used only if Source is "auto")
    -- "trigger" = Counts +1 for every event (Best for semi-auto weapons).
    -- "bullets" = Counts the exact mathematical difference (Best for machine guns that drop 3 bullets per frame).
    SHOTS_FIRED_METHOD         = "trigger",
    SHOTS_FIRED_ALT_METHOD     = "trigger",
    SHOTS_FIRED_GRENADE_METHOD = "trigger",
    
    -- FORCE_FEEDBACK_ENABLER: Hardware Safety Gate
    -- Controls what exact conditions must be met for physical force feedback to physically trigger.
    -- "gamestatus" = Triggers as long as global game status is active (useful if individual player status is unknown).
    -- "both"       = Default behavior. Requires player to be fully active via Status/Life/Credits AND game to be active.
    -- "status"     = Triggers as long as the player's individual memory status flag is active.
    -- "life"       = Triggers as long as the player's life is > 0.
    FORCE_FEEDBACK_ENABLER = "both",
    
    -- RECOIL_METHOD: How direct memory recoil addresses are processed
    -- "pulse"  = Triggers only when the memory value strictly increases (Best for semi-auto).
    -- "hold"   = Triggers continuously while the value is > 0 (Best for machine guns).
    -- "change" = Triggers whenever the value changes, as long as the new value is > 0.
    -- "latch"  = Triggers once when the value becomes > 0, and won't trigger again until it returns to 0.
    RECOIL_METHOD          = "pulse",
    
    -- RECOIL_PRIORITY: The Master Hardware Trigger
    -- "ammo"   = Ammo drops trigger recoil. The recoil memory address is ignored UNLESS Ammo = 0.
    -- "recoil" = The recoil memory address ALWAYS triggers recoil. Ammo drops are ignored.
    RECOIL_PRIORITY        = "ammo",
    RECOIL_MEM_ADD_VALUE   = false,
    
    --------------------------------------------------
    -- GLOBAL MASTER SWITCHES                       --
    --------------------------------------------------
    -- Independently enable/disable recoil and reload for Primary, Alternate, and Grenade ammo.
    -- Set ENABLE_RELOAD_AMMO to false to disable primary weapon reload interruptions for machine gun games.
    ENABLE_RECOIL_AMMO         = true,
    ENABLE_RECOIL_AMMO_ALT     = true,
    ENABLE_RECOIL_AMMO_GRENADE = true,
    ENABLE_RELOAD_AMMO         = false,
    ENABLE_RELOAD_AMMO_ALT     = true,
    ENABLE_RELOAD_AMMO_GRENADE = true,
    
    -- Global Master Switches for Calculated Output Stats
    ENABLE_CREDIT_COUNT        = true,
    ENABLE_SHOT_COUNT          = true,
    ENABLE_DAMAGE_COUNT        = true,
    ENABLE_LIFE_LOST           = true,
    
    -- DEMULSHOOTER_COMPATIBILITY:
    -- true  = Outputs standard suffixes (Recoil & Damage), PLUS "CtmRecoil" & "Damaged" for DemulShooter.
    DEMULSHOOTER_COMPATIBILITY = true,
    
    -- ENABLE_OSD: Controls MAME on-screen messages
    -- false = Silent mode (Maximum performance, no stutter).
    ENABLE_OSD                 = false,
}

------------------------------------------------------
-- 1. GLOBAL STATE & PRE-CALCULATED ARRAYS          --
------------------------------------------------------
local _Taps = {} 
local _HasCoinedUp = false
local _IsShuttingDown = false

-- Global Timers
local _GameActiveTick = emu.attotime.from_seconds(0)
local _GameInactiveTick = emu.attotime.from_seconds(0)

-- Global Credit Tracking Engine
local _LastGlobalCredits = 0
local _GlobalCreditsInserted = 0
local _PendingGlobalCreditDrops = 0

-- Multi-CPU Maps
local _MemConfig = {}
local _UniqueMemTargets = {}

-- OPTIMIZATION 1: Player Config Array
-- By mapping CFG.P1, CFG.P2, etc., into an array, we completely eliminate the 
-- slow "if i == 1 then" branching logic inside the high-speed 60fps main loop.
local _PlayerCFG = { CFG.P1, CFG.P2, CFG.P3, CFG.P4 }

-- OPTIMIZATION 2: String Pre-Caching
-- In Lua, creating a new string causes memory to be allocated. Doing this 100+ times 
-- per frame triggers the Garbage Collector and causes micro-stuttering.
-- We pre-build every possible output string here so the loop never has to concatenate.
local _OutputNames = {}
local _GlobalOutputs = {}

-- Ensure only one instance of this script runs at a time (prevents zombie scripts on reload)
local _ScriptInstance = {}
_G.MameOutputActiveInstance = _ScriptInstance

-- If CREDITS is completely disabled, treat the game as always coined up
if not CFG.CREDITS then _HasCoinedUp = true end

-- Shutdown Hook: Safely cleans up taps and restores RAM when the game closes
local function on_machine_stop()
    _IsShuttingDown = true 
    
    if CFG and CFG.SCREEN_FLASH and type(CFG.SCREEN_FLASH_MEMORY_ADDRESS) == "number" and type(CFG.SCREEN_FLASH_RESTORE_VALUE) == "number" then
        if manager and manager.machine then
            local conf = _MemConfig["SCREEN_FLASH"]
            if conf then
                local cpu = manager.machine.devices[conf.tag]
                if cpu then
                    local mem = cpu.spaces[conf.space]
                    if mem then
                        local flash_width = CFG.DATA_WIDTHS.SCREEN_FLASH or 8
                        if flash_width == 16 then mem:write_u16(CFG.SCREEN_FLASH_MEMORY_ADDRESS, CFG.SCREEN_FLASH_RESTORE_VALUE)
                        elseif flash_width == 32 then mem:write_u32(CFG.SCREEN_FLASH_MEMORY_ADDRESS, CFG.SCREEN_FLASH_RESTORE_VALUE)
                        else mem:write_u8(CFG.SCREEN_FLASH_MEMORY_ADDRESS, CFG.SCREEN_FLASH_RESTORE_VALUE) end
                    end
                end
            end
        end
    end

    for k, tap in pairs(_Taps) do pcall(function() tap:remove() end) end
    _Taps = {}
end

if emu.add_machine_stop_notifier then emu.add_machine_stop_notifier(on_machine_stop)
elseif emu.register_stop then emu.register_stop(on_machine_stop) end

------------------------------------------------------
-- 2. SETUP & PRE-CALCULATION                       --
------------------------------------------------------
function Resolve_Addresses_And_Strings()
    -- OPTIMIZATION 3: String Normalization
    -- We force all config logic strings to lowercase exactly once at boot.
    -- This prevents us from having to run `string.lower()` thousands of times during gameplay.
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

    -- OPTIMIZATION 4: Multi-CPU Memory Bus Mapping
    -- Calculates exact CPU paths for all variables once at boot to prevent string garbage in the 60fps loop.
    local data_types = {
        "SCREEN_FLASH", "GLOBAL_ATTRACT_STATUS", "GLOBAL_CREDITS", "GLOBAL_GAME_STATUS",
        "CREDITS", "STATUS", "STATUS_ALT",
        "AMMO", "AMMO_ALT", "AMMO_GRENADE", "LIFE", "LIFE_ALT",
        "RECOIL", "RELOAD", "DAMAGE", "RUMBLE", "LAMP_START",
        "SHOTS_FIRED_PRIMARY", "SHOTS_FIRED_ALT", "SHOTS_FIRED_GRENADE",
        "LIFE_LOST", "DAMAGE_TAKEN"
    }

    local function Resolve_Mem_Path(val, global_val)
        if val == nil or val == false or val == "" or string.lower(tostring(val)) == "auto" then
            return global_val
        end
        return tostring(val)
    end

    for _, key in ipairs(data_types) do
        local t = Resolve_Mem_Path(CFG.CPU_TAGS and CFG.CPU_TAGS[key], CFG.CPU_TAG or ":maincpu")
        local s = Resolve_Mem_Path(CFG.MEMORY_SPACES and CFG.MEMORY_SPACES[key], CFG.MEMORY_SPACE or "program")
        
        _MemConfig[key] = { tag = t, space = s }
        
        local exists = false
        for _, v in ipairs(_UniqueMemTargets) do
            if v.tag == t and v.space == s then exists = true; break end
        end
        if not exists then table.insert(_UniqueMemTargets, {tag = t, space = s}) end
    end

    -- Construct the cached output string arrays
    for i = 1, CFG.MAX_PLAYERS do
        _OutputNames[i] = {}
        for key, suffix in pairs(CFG.OUTPUT_SUFFIXES) do
            if not string.match(key, "^GLOBAL_") then
                local target_p = i
                -- Turn-Based FFB Routing: Force hardware outputs to Player 1 if game is Shared
                if not CFG.SIMULTANEOUS_PLAY and (key == "RECOIL" or key == "RELOAD" or key == "DAMAGE" or key == "RUMBLE" or key == "LAMP_START") then target_p = 1 end
                _OutputNames[i][key] = "P" .. target_p .. "_" .. tostring(suffix)
            end
        end
        -- Hardcoded DemulShooter overrides
        local target_p_ctm = (not CFG.SIMULTANEOUS_PLAY) and 1 or i
        _OutputNames[i]["CtmRecoil"] = "P" .. target_p_ctm .. "_CtmRecoil" 
        _OutputNames[i]["Damaged"]   = "P" .. target_p_ctm .. "_Damaged"
    end
    
    -- Cache Global outputs
    for key, suffix in pairs(CFG.OUTPUT_SUFFIXES) do
        if string.match(key, "^GLOBAL_") then _GlobalOutputs[key] = tostring(suffix) end
    end

    -- Process "auto" variables for Player 1
    local all_players = { CFG.P1, CFG.P2, CFG.P3, CFG.P4 }
    for _, p_cfg in ipairs(all_players) do
        for k, val in pairs(p_cfg) do
            if type(val) == "string" and string.lower(val) == "auto" then p_cfg[k] = "auto" end
        end
    end

    -- Ensure hardware "auto" states gracefully disable if they have no underlying Ammo/Life data to track
    local p1_hardware = { "RECOIL", "RELOAD", "DAMAGE", "RUMBLE", "LAMP_START", "STATUS", "STATUS_ALT" }
    for _, key in ipairs(p1_hardware) do
        if CFG.P1[key] == "auto" then
            if key == "STATUS" or key == "STATUS_ALT" then -- leave as auto
            elseif key == "RECOIL" and (CFG.P1.AMMO or CFG.P1.AMMO_ALT or CFG.P1.AMMO_GRENADE) then
            elseif key == "RELOAD" and (CFG.P1.AMMO or CFG.P1.AMMO_ALT or CFG.P1.AMMO_GRENADE) then
            elseif key == "DAMAGE" and (CFG.P1.LIFE or CFG.P1.LIFE_ALT) then
            elseif key == "LAMP_START" then
            else CFG.P1[key] = false end
        end
    end

    -- Calculate memory offsets for Players 2, 3, and 4 automatically
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
                elseif p1_val == "auto" then p_cfg[key] = "auto"; if CFG.P1[key] == false then p_cfg[key] = false end
                else p_cfg[key] = false end
            end
        end
    end
end
Resolve_Addresses_And_Strings()

-- Convert configuration milliseconds into native MAME Attotimes for high-speed calculation
local _RecoilDuration = emu.attotime.from_msec(CFG.RECOIL_DURATION_MS)
local _RecoilAltDuration = emu.attotime.from_msec(CFG.RECOIL_ALT_DURATION_MS or 80)
local _RecoilGrenadeDuration = emu.attotime.from_msec(CFG.RECOIL_GRENADE_DURATION_MS or 150)
local _MinRecoilInterval = emu.attotime.from_msec(CFG.MIN_RECOIL_INTERVAL_MS or 0)
local _RecoilHoldInterval = CFG.RECOIL_HOLD_MS and emu.attotime.from_msec(CFG.RECOIL_HOLD_MS) or _MinRecoilInterval
local _ReloadDuration = emu.attotime.from_msec(CFG.RELOAD_DURATION_MS or 40)
local _DamageDuration = emu.attotime.from_msec(CFG.DAMAGE_DURATION_MS)
local _RumbleDuration = emu.attotime.from_msec(CFG.RUMBLE_DURATION_MS or CFG.DAMAGE_DURATION_MS or 250)
local _StartupTime = emu.attotime.from_msec(CFG.STARTUP_DELAY_MS)
local _ZeroTime = emu.attotime.from_seconds(0)

-- Player State Master Dictionary
-- This holds the live memory tracking values for every player as the game runs
local _Player = {}
for i = 1, 4 do
    _Player[i] = { 
        LastOutputs={}, -- Tracking array to prevent MAME API spam
        LastAmmo=0, LastAmmoAlt=0, LastAmmoGrenade=0, LastLife=0, LastLifeAlt=0, LastDmgMem=0, LastCredits=0,
        RecoilTick=_ZeroTime, ReloadTick=_ZeroTime, DamageTick=_ZeroTime, RumbleTick=_ZeroTime,
        CurrentRecoilDuration=_RecoilDuration,
        LastRecoilVal=0, LastDamageVal=0, LastRumbleEventVal=0,
        ShotCountPrimary=0, ShotCountAlt=0, ShotCountGrenade=0, DamageCount=0, LifeLostCount=0, CreditsInserted=0, CreditsConsumed=0, PendingCreditDrops=0,
        IsActive=false, WasActive=false, ActiveTick=_ZeroTime,
        IsRecoilActive=false, IsReloadActive=false, IsDamageActive=false, IsRumbleActive=false,
        IsFFBAllowed=false, WasFFBAllowed=false
    }
end

local _GlobalLastOutputs = {}
local _InitTimer = 60 
local _TapsInstalled = false

------------------------------------------------------
-- 3. HELPER FUNCTIONS                              --
------------------------------------------------------
-- Displays debug messages on the arcade screen
function Show_Message(text)
    if CFG.ENABLE_OSD and manager.machine then manager.machine:popmessage(text) end
end

-- Checks if the boot delay timer has expired
function Is_Warmup_Complete() return manager.machine.time > _StartupTime end

-- Core Memory Reader
function Read_Data_Safe(mem_handle, source, width)
    if not source then return 0 end
    if type(width) == "string" then
        local w_low = string.lower(width)
        -- Special handler for Native Output mode (reading existing MAME strings instead of RAM)
        if w_low == "output" then
            if type(source) == "string" and manager.machine.output then
                local native_val = manager.machine.output:get_value(source)
                return type(native_val) == "number" and native_val or (native_val and 1 or 0)
            end
            return 0
        end
        -- Float decoding for modern 3D games
        if w_low == "float32" then
            local val = mem_handle:read_u32(source)
            return string.unpack("f", string.pack("I4", val))
        elseif w_low == "float32be" then
            local val = mem_handle:read_u32(source)
            val = ((val & 0xFF) << 24) | ((val & 0xFF00) << 8) | ((val & 0xFF0000) >> 8) | ((val & 0xFF000000) >> 24)
            return string.unpack("f", string.pack("I4", val))
        end
    end
    
    if not mem_handle then return 0 end
    
    -- Standard unsigned integer reading
    if width == 16 then return mem_handle:read_u16(source) end
    if width == 32 then return mem_handle:read_u32(source) end
    return mem_handle:read_u8(source)
end

-- Forces all configured outputs to broadcast a '0' so external software can hook into them
function Register_Outputs_Safe(out_handle)
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
        local keys = {"AMMO", "AMMO_ALT", "AMMO_GRENADE", "LIFE", "LIFE_ALT", "RECOIL", "RELOAD", "DAMAGE", "RUMBLE", "LAMP_START"}
        for _, k in ipairs(keys) do
            if p_cfg[k] then 
                out_handle:set_value(_OutputNames[i][k], 0) 
                if k == "RECOIL" and CFG.DEMULSHOOTER_COMPATIBILITY then out_handle:set_value(_OutputNames[i]["CtmRecoil"], 0) end
                if k == "DAMAGE" and CFG.DEMULSHOOTER_COMPATIBILITY then out_handle:set_value(_OutputNames[i]["Damaged"], 0) end
            end
        end
        if CFG.ENABLE_DAMAGE_COUNT and p_cfg.DAMAGE_TAKEN then out_handle:set_value(_OutputNames[i]["DAMAGE_TAKEN"], 0) end
        if CFG.ENABLE_SHOT_COUNT and p_cfg.SHOTS_FIRED then out_handle:set_value(_OutputNames[i]["SHOTS_FIRED"], 0) end
        if CFG.ENABLE_SHOT_COUNT and p_cfg.SHOTS_FIRED_PRIMARY then out_handle:set_value(_OutputNames[i]["SHOTS_FIRED_PRIMARY"], 0) end
        if CFG.ENABLE_SHOT_COUNT and p_cfg.SHOTS_FIRED_ALT then out_handle:set_value(_OutputNames[i]["SHOTS_FIRED_ALT"], 0) end
        if CFG.ENABLE_SHOT_COUNT and p_cfg.SHOTS_FIRED_GRENADE then out_handle:set_value(_OutputNames[i]["SHOTS_FIRED_GRENADE"], 0) end
        if CFG.ENABLE_LIFE_LOST and p_cfg.LIFE_LOST then out_handle:set_value(_OutputNames[i]["LIFE_LOST"], 0) end
    end
end

function Install_Taps_Safe()
    if _TapsInstalled then return end
    if CFG.MEMORY_ALIGNMENT then
        _TapsInstalled = true
        Show_Message("Hybrid Mode: Fast FFB + Polled Stats")
    else Show_Message("Standard Polling Mode Active") end
end

------------------------------------------------------
-- 5. MAIN LOGIC LOOP (Wrapped in pcall)            --
------------------------------------------------------
function Compute_Outputs()
    if _IsShuttingDown then return end
    local status, err = pcall(function()
        
        -- OPTIMIZATION 5: Local Caching & Multi-CPU Waking
        -- We grab the MAME API handles once at the start of the frame. 
        -- This avoids traversing the API bridge thousands of times during the player iterations.
        local machine = manager.machine
        if not machine or machine.system.name ~= CFG.LUA_ROM or _G.MameOutputActiveInstance ~= _ScriptInstance then _IsShuttingDown = true; return end
        
        local out = machine.output
        local current_time = machine.time
        if not out then return end
        
        -- Wake up all required CPU memory buses mapped during boot
        local mem_pool = {}
        local has_any_mem = false
        for _, target in ipairs(_UniqueMemTargets) do
            local dev = machine.devices[target.tag]
            if dev then
                if not mem_pool[target.tag] then mem_pool[target.tag] = {} end
                mem_pool[target.tag][target.space] = dev.spaces[target.space]
                has_any_mem = true
            end
        end
        
        if not has_any_mem then return end -- Abort if the machine is completely dead
        
        -- Blazing fast local lookup for the correct memory handle
        local function Get_Mem(key)
            local conf = _MemConfig[key]
            if not conf then return nil end
            return mem_pool[conf.tag] and mem_pool[conf.tag][conf.space]
        end
        
        -- OPTIMIZATION 6: Output Spam Wrapper
        -- The script evaluates 60 times a second. If Ammo is 0, we don't want to command MAME
        -- to set "Ammo = 0" 60 times a second. This wrapper checks the LastOutputs cache and ONLY
        -- talks to MAME if the value has fundamentally changed.
        local function Set_Output(p_idx, key, value)
            local p = _Player[p_idx]
            if p.LastOutputs[key] ~= value then
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
            if _InitTimer == 0 then Register_Outputs_Safe(out); Install_Taps_Safe() end
        end
        
        local divisor = CFG.COINS_PER_CREDIT or 1
        if divisor < 1 then divisor = 1 end
        local warmup_ok = Is_Warmup_Complete()
        
        -- Screen Flash override execution
        if warmup_ok and CFG.SCREEN_FLASH and type(CFG.SCREEN_FLASH_MEMORY_ADDRESS) == "number" then
            local sf_mem = Get_Mem("SCREEN_FLASH")
            if sf_mem then
                local flash_width = CFG.DATA_WIDTHS.SCREEN_FLASH or 8
                if flash_width == 16 then sf_mem:write_u16(CFG.SCREEN_FLASH_MEMORY_ADDRESS, CFG.SCREEN_FLASH_DISABLE_VALUE)
                elseif flash_width == 32 then sf_mem:write_u32(CFG.SCREEN_FLASH_MEMORY_ADDRESS, CFG.SCREEN_FLASH_DISABLE_VALUE)
                else sf_mem:write_u8(CFG.SCREEN_FLASH_MEMORY_ADDRESS, CFG.SCREEN_FLASH_DISABLE_VALUE) end
            end
        end

        -- ==============================================
        -- ATTRACT MODE DETECTION & SAFETY VALVE
        -- ==============================================
        local is_attract_mode = false
        if CFG.ATTRACT_STATUS and type(CFG.ATTRACT_STATUS) == "number" then
            local val = Read_Data_Safe(Get_Mem("GLOBAL_ATTRACT_STATUS"), CFG.ATTRACT_STATUS, CFG.DATA_WIDTHS.GLOBAL_ATTRACT_STATUS or 8)
            local active = CFG.ATTRACT_STATUS_ACTIVE_VALUE
            is_attract_mode = (type(active) == "number") and (val == active) or (val > 0)
            Set_Global_Output("GLOBAL_ATTRACT_STATUS", warmup_ok and (is_attract_mode and 1 or 0) or 0)
            
            -- THE SAFETY VALVE: Wipe pending credits if the game resets to attract mode
            if is_attract_mode then
                _PendingGlobalCreditDrops = 0
            end
        end

        -- ==============================================
        -- GLOBAL CREDITS (INSERTED & CONSUMED TRACKING)
        -- ==============================================
        if CFG.CREDITS and type(CFG.CREDITS) == "number" then 
            local raw = Read_Data_Safe(Get_Mem("GLOBAL_CREDITS"), CFG.CREDITS, CFG.DATA_WIDTHS.GLOBAL_CREDITS)
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

        -- GLOBAL GAME STATUS DETECTION
        local is_game_active = false
        local global_exists = false
        if CFG.GAME_STATUS and type(CFG.GAME_STATUS) == "number" then 
            global_exists = true
            if not is_attract_mode then
                local val = Read_Data_Safe(Get_Mem("GLOBAL_GAME_STATUS"), CFG.GAME_STATUS, CFG.DATA_WIDTHS.GLOBAL_GAME_STATUS)
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

        -- ==============================================
        -- PLAYER LOOP
        -- ==============================================
        local any_player_active = false
        for i = 1, CFG.MAX_PLAYERS do
            local cfg = _PlayerCFG[i]
            local p = _Player[i]
            
            -- THE SAFETY VALVE: Wipe pending credits if the game resets to attract mode
            if is_attract_mode then p.PendingCreditDrops = 0 end
            
            local curr_ammo = 0
            local curr_ammo_alt = 0
            local curr_ammo_grenade = 0
            local curr_life = 0
            local curr_life_alt = 0
            
            -- Read Player Hardware RAM
            if cfg.AMMO then 
                curr_ammo = Read_Data_Safe(Get_Mem("AMMO"), cfg.AMMO, CFG.DATA_WIDTHS.AMMO) + (CFG.AMMO_OFFSET or 0)
                if CFG.AMMO_MAX and curr_ammo > CFG.AMMO_MAX then curr_ammo = 0 end
            end
            if cfg.AMMO_ALT then 
                curr_ammo_alt = Read_Data_Safe(Get_Mem("AMMO_ALT"), cfg.AMMO_ALT, CFG.DATA_WIDTHS.AMMO_ALT) + (CFG.AMMO_ALT_OFFSET or 0)
                if CFG.AMMO_ALT_MAX and curr_ammo_alt > CFG.AMMO_ALT_MAX then curr_ammo_alt = 0 end
            end
            if cfg.AMMO_GRENADE then 
                curr_ammo_grenade = Read_Data_Safe(Get_Mem("AMMO_GRENADE"), cfg.AMMO_GRENADE, CFG.DATA_WIDTHS.AMMO_GRENADE) + (CFG.AMMO_GRENADE_OFFSET or 0)
                if CFG.AMMO_GRENADE_MAX and curr_ammo_grenade > CFG.AMMO_GRENADE_MAX then curr_ammo_grenade = 0 end
            end
            if cfg.LIFE then 
                curr_life = Read_Data_Safe(Get_Mem("LIFE"), cfg.LIFE, CFG.DATA_WIDTHS.LIFE) + (CFG.LIFE_OFFSET or 0)
                if CFG.LIFE_MAX and curr_life > CFG.LIFE_MAX then curr_life = 0 end
            end
            if cfg.LIFE_ALT then 
                curr_life_alt = Read_Data_Safe(Get_Mem("LIFE_ALT"), cfg.LIFE_ALT, CFG.DATA_WIDTHS.LIFE_ALT) + (CFG.LIFE_ALT_OFFSET or 0)
                if CFG.LIFE_ALT_MAX and curr_life_alt > CFG.LIFE_ALT_MAX then curr_life_alt = 0 end
            end

            -- Process Player Credits & Independent Spawn/Consume Logic
            local p_credits = 0
            local p_credits_known = false
            if cfg.CREDITS then
                if type(cfg.CREDITS) == "number" then 
                    local raw = Read_Data_Safe(Get_Mem("CREDITS"), cfg.CREDITS, CFG.DATA_WIDTHS.CREDITS)
                    p_credits = math.floor(raw / divisor)
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
                elseif cfg.CREDITS == "auto" and CFG.CREDITS then 
                    p_credits = Read_Data_Safe(Get_Mem("GLOBAL_CREDITS"), CFG.CREDITS, CFG.DATA_WIDTHS.GLOBAL_CREDITS) 
                end
            end
            
            -- Detect Spawn Events for Credit Consumption
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
            
            if cfg.LAMP_START then Set_Output(i, "LAMP_START", warmup_ok and Read_Data_Safe(Get_Mem("LAMP_START"), cfg.LAMP_START, CFG.DATA_WIDTHS.LAMP_START) or 0) end

            local is_player_active = false
            local out_status_val = 0
            local out_status_alt_val = 0

            -- INDIVIDUAL PLAYER STATUS LOGIC
            -- Evaluates in this order: Priority 1 (Memory Address) -> Priority 2 (Global Status + Life) -> Priority 3 (Credits + Life)
            if not is_attract_mode then
                if (cfg.STATUS and cfg.STATUS ~= "auto") or (cfg.STATUS_ALT and cfg.STATUS_ALT ~= "auto") then
                    local p_stat_active = false
                    local p_stat_alt_active = false
                    if cfg.STATUS and cfg.STATUS ~= "auto" then
                        local val = Read_Data_Safe(Get_Mem("STATUS"), cfg.STATUS, CFG.DATA_WIDTHS.STATUS)
                        local act = cfg.STATUS_ACTIVE_VALUE or CFG.STATUS_ACTIVE_VALUE
                        p_stat_active = (type(act) == "table") and (function() for _,v in ipairs(act) do if val == v then return true end end return false end)() or ((type(act) == "number" and val == act) or (not act and val > 0))
                    end
                    if cfg.STATUS_ALT and cfg.STATUS_ALT ~= "auto" then
                        local val = Read_Data_Safe(Get_Mem("STATUS_ALT"), cfg.STATUS_ALT, CFG.DATA_WIDTHS.STATUS_ALT)
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
            
            -- Debounce check: Player must remain inactive for the debounce limit before officially dying
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

            -- ==============================================
            -- 1. AUTO RECOIL & RELOAD
            -- ==============================================
            -- Calculates FFB triggers based purely on the change of Ammo capacity.
            -- This block is evaluated FIRST, so that if a grenade or alternate weapon is fired,
            -- it actively pre-empts and suppresses the manual 'empty click' in Section 2.
            local auto_recoil_triggered_this_frame = false
            
            -- Evaluate thresholds (Fallback to 254 if not defined in JSON)
            local t_ammo = CFG.AMMO_THRESHOLD or 254
            local t_alt = CFG.AMMO_ALT_THRESHOLD or 254
            local t_grenade = CFG.AMMO_GRENADE_THRESHOLD or 254
            
            if not CFG.MEMORY_ALIGNMENT and p.IsFFBAllowed then
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
                  
                  -- Determine which Recoil timer config to use depending on the weapon fired
                  if trigger > 0 and (cfg.RECOIL == "auto" or (type(cfg.RECOIL) == "number" and CFG.RECOIL_PRIORITY == "ammo")) then
                      if current_time - p.RecoilTick > _MinRecoilInterval then
                          if trigger == 1 then p.CurrentRecoilDuration = _RecoilDuration
                          elseif trigger == 2 then p.CurrentRecoilDuration = _RecoilAltDuration
                          elseif trigger == 3 then p.CurrentRecoilDuration = _RecoilGrenadeDuration end
                          
                          Set_Output(i, "RECOIL", 1); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(i, "CtmRecoil", 1) end
                          
                          -- SHARED TIMER: Auto-recoil sets the shared tick, ensuring manual recoil is suppressed
                          p.RecoilTick = current_time
                          p.IsRecoilActive = true
                          auto_recoil_triggered_this_frame = true
                          
                          if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].RecoilTick = current_time; _Player[1].IsRecoilActive = true end
                      end
                  end
                  
                  -- Reload FFB Checks
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
            end

            -- ==============================================
            -- 2. DIRECT MEMORY RECOIL (Manual Trigger Override)
            -- ==============================================
            -- Because this is evaluated after Auto-Recoil, we can gracefully abort the 
            -- empty-click if an alternate weapon (or grenade) just fired a split second ago.
            if p.IsFFBAllowed and not auto_recoil_triggered_this_frame then
                if cfg.RECOIL and type(cfg.RECOIL) == "number" then
                    local val = Read_Data_Safe(Get_Mem("RECOIL"), cfg.RECOIL, CFG.DATA_WIDTHS.RECOIL)
                    
                    if (CFG.RECOIL_PRIORITY ~= "ammo" or curr_ammo == 0) then
                        local trigger = false
                        if type(CFG.RECOIL_MEM_ADD_VALUE) == "number" then
                            if CFG.RECOIL_METHOD == "hold" then trigger = (val == CFG.RECOIL_MEM_ADD_VALUE) else trigger = (val == CFG.RECOIL_MEM_ADD_VALUE and p.LastRecoilVal ~= CFG.RECOIL_MEM_ADD_VALUE) end
                        else
                            trigger = (CFG.RECOIL_METHOD == "hold") and (val > 0) or (CFG.RECOIL_METHOD == "change") and (val ~= p.LastRecoilVal and val > 0) or (CFG.RECOIL_METHOD == "latch") and (val > 0 and p.LastRecoilVal == 0) or (val > p.LastRecoilVal)
                        end
                        
                        -- The critical fix for empty click rates:
                        -- If the user configures "hold", this ensures the empty-clicks obey the slower RECOIL_HOLD_MS setting
                        local active_interval = (CFG.RECOIL_METHOD == "hold") and _RecoilHoldInterval or _MinRecoilInterval
                        
                        if trigger and (current_time - p.RecoilTick > active_interval) then
                            p.CurrentRecoilDuration = _RecoilDuration; Set_Output(i, "RECOIL", 1); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(i, "CtmRecoil", 1) end
                            
                            -- Because manual recoil signifies a physical hardware actuation, we record it as a Primary Shot Fired
                            if CFG.ENABLE_SHOT_COUNT and warmup_ok then
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

            -- ==============================================
            -- 3. STATS OUTPUT (Ammo, Life, Shots Fired)
            -- ==============================================
            local primary_active = (out_status_val == 1)
            local alternate_active = (cfg.STATUS_ALT and cfg.STATUS_ALT ~= "auto") and (out_status_alt_val == 1) or primary_active
            
            -- Broadcast stats to outputs. If player is inactive, broadcast 0 to keep the data clean.
            if is_player_active or just_died then
                if primary_active then
                    if cfg.AMMO then Set_Output(i, "AMMO", warmup_ok and curr_ammo or 0) end
                    if cfg.LIFE then Set_Output(i, "LIFE", warmup_ok and curr_life or 0) end
                    
                    -- Calculate Primary Shots Fired
                    if CFG.ENABLE_SHOT_COUNT and cfg.SHOTS_FIRED_PRIMARY and warmup_ok then
                        if type(cfg.SHOTS_FIRED_PRIMARY) == "number" then 
                             local val = Read_Data_Safe(Get_Mem("SHOTS_FIRED_PRIMARY"), cfg.SHOTS_FIRED_PRIMARY, CFG.DATA_WIDTHS.SHOTS_FIRED_PRIMARY)
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
                    
                    -- Calculate Alt Shots Fired
                    if CFG.ENABLE_SHOT_COUNT and cfg.SHOTS_FIRED_ALT and warmup_ok then
                        if type(cfg.SHOTS_FIRED_ALT) == "number" then
                            local val = Read_Data_Safe(Get_Mem("SHOTS_FIRED_ALT"), cfg.SHOTS_FIRED_ALT, CFG.DATA_WIDTHS.SHOTS_FIRED_ALT)
                            Set_Output(i, "SHOTS_FIRED_ALT", val); p.ShotCountAlt = val
                        elseif cfg.SHOTS_FIRED_ALT == "auto" and cfg.AMMO_ALT and p.WasActive then
                            local diff = (CFG.AMMO_ALT_DIRECTION == "decrease") and (curr_ammo_alt < p.LastAmmoAlt and p.LastAmmoAlt <= t_alt and p.LastAmmoAlt - curr_ammo_alt or 0) or ((curr_ammo_alt > p.LastAmmoAlt) and (curr_ammo_alt - p.LastAmmoAlt) or 0)
                            if diff > 0 or (CFG.AMMO_ALT_DIRECTION == "change" and curr_ammo_alt ~= p.LastAmmoAlt) then
                                p.ShotCountAlt = p.ShotCountAlt + (CFG.SHOTS_FIRED_ALT_METHOD == "bullets" and diff or 1)
                                Set_Output(i, "SHOTS_FIRED_ALT", p.ShotCountAlt)
                            end
                        end
                    end
                    
                    -- Calculate Grenades
                    if cfg.AMMO_GRENADE then Set_Output(i, "AMMO_GRENADE", warmup_ok and curr_ammo_grenade or 0) end
                    if CFG.ENABLE_SHOT_COUNT and cfg.SHOTS_FIRED_GRENADE and warmup_ok then
                        if type(cfg.SHOTS_FIRED_GRENADE) == "number" then
                            local val = Read_Data_Safe(Get_Mem("SHOTS_FIRED_GRENADE"), cfg.SHOTS_FIRED_GRENADE, CFG.DATA_WIDTHS.SHOTS_FIRED_GRENADE)
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
            
            -- SHOTS_FIRED MASTER TOTAL
            if CFG.ENABLE_SHOT_COUNT and warmup_ok then
                local total_shots = p.ShotCountPrimary + p.ShotCountAlt + p.ShotCountGrenade
                Set_Output(i, "SHOTS_FIRED", total_shots)
            end

            -- ==============================================
            -- 4. DAMAGE (Player Hit) / RUMBLE / LIFE LOST
            -- ==============================================
            if is_player_active or just_died then
                local hit_triggered = false
                
                -- Calculate Damage Taken
                if type(cfg.DAMAGE_TAKEN) == "number" then
                    local val = Read_Data_Safe(Get_Mem("DAMAGE_TAKEN"), cfg.DAMAGE_TAKEN, CFG.DATA_WIDTHS.DAMAGE_TAKEN)
                    if val > p.LastDmgMem and warmup_ok then
                        if CFG.ENABLE_DAMAGE_COUNT then p.DamageCount = p.DamageCount + 1; Set_Output(i, "DAMAGE_TAKEN", p.DamageCount) end
                    end
                    p.LastDmgMem = val
                elseif cfg.DAMAGE_TAKEN == "auto" and (cfg.LIFE or cfg.LIFE_ALT) and p.WasActive then
                    local hit = (cfg.LIFE and ((CFG.LIFE_DIRECTION == "decrease" and curr_life < p.LastLife) or (curr_life > p.LastLife))) or (cfg.LIFE_ALT and ((CFG.LIFE_ALT_DIRECTION == "decrease" and curr_life_alt < p.LastLifeAlt) or (curr_life_alt > p.LastLifeAlt)))
                    if hit and warmup_ok and CFG.ENABLE_DAMAGE_COUNT then p.DamageCount = p.DamageCount + 1; Set_Output(i, "DAMAGE_TAKEN", p.DamageCount) end
                end

                local ffb_now = p.IsFFBAllowed or (just_died and p.WasFFBAllowed)
                
                -- Trigger Damage (Hit) FFB
                if cfg.DAMAGE and ffb_now then
                    if type(cfg.DAMAGE) == "number" then
                        local val = Read_Data_Safe(Get_Mem("DAMAGE"), cfg.DAMAGE, CFG.DATA_WIDTHS.DAMAGE)
                        if val > p.LastDamageVal then
                            Set_Output(i, "DAMAGE", 1); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(i, "Damaged", 1) end
                            p.DamageTick = current_time; p.IsDamageActive = true
                            if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].DamageTick = current_time; _Player[1].IsDamageActive = true end
                        end
                        p.LastDamageVal = val
                    end
                end
                
                -- Trigger Environmental Rumble FFB
                if cfg.RUMBLE and ffb_now then
                    if type(cfg.RUMBLE) == "number" then
                        local val = Read_Data_Safe(Get_Mem("RUMBLE"), cfg.RUMBLE, CFG.DATA_WIDTHS.RUMBLE)
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
                                 if curr_life < p.LastLife then 
                                     lost = true; diff = p.LastLife - curr_life
                                 end
                             else
                                 if curr_life > p.LastLife then 
                                     lost = true; diff = curr_life - p.LastLife
                                 end
                             end
                         end
                         
                         if cfg.LIFE_ALT then
                             if CFG.LIFE_ALT_DIRECTION == "decrease" then
                                 if curr_life_alt < p.LastLifeAlt then 
                                     lost = true; diff = p.LastLifeAlt - curr_life_alt
                                 end
                             else
                                 if curr_life_alt > p.LastLifeAlt then 
                                     lost = true; diff = curr_life_alt - p.LastLifeAlt
                                 end
                             end
                         end
                         
                         if lost then
                             p.LifeLostCount = p.LifeLostCount + diff
                             Set_Output(i, "LIFE_LOST", p.LifeLostCount)
                         end
                    elseif type(cfg.LIFE_LOST) == "number" then
                         local val = Read_Data_Safe(Get_Mem("LIFE_LOST"), cfg.LIFE_LOST, CFG.DATA_WIDTHS.LIFE_LOST)
                         Set_Output(i, "LIFE_LOST", val)
                    end
                end
            end

            -- ==============================================
            -- 5. UPDATE PREVIOUS VALUES STATE
            -- ==============================================
            -- Commits the memory values to the tracking variables for comparison on the next 60fps frame
            p.LastAmmo = curr_ammo; p.LastAmmoAlt = curr_ammo_alt; p.LastAmmoGrenade = curr_ammo_grenade
            p.LastLife = curr_life; p.LastLifeAlt = curr_life_alt; p.WasActive = p.IsActive; p.WasFFBAllowed = p.IsFFBAllowed

            -- ==============================================
            -- 6. TIMER CLEANUP & HARDWARE DEACTIVATION
            -- ==============================================
            -- Cleans up any FFB sequences that have exceeded their designated durations
            if CFG.SIMULTANEOUS_PLAY or i == 1 then
                if p.IsRecoilActive and (current_time - p.RecoilTick > p.CurrentRecoilDuration) then Set_Output(i, "RECOIL", 0); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(i, "CtmRecoil", 0) end; p.IsRecoilActive = false end
                if p.IsReloadActive and (current_time - p.ReloadTick > _ReloadDuration) then Set_Output(i, "RELOAD", 0); p.IsReloadActive = false end
                if p.IsDamageActive and (current_time - p.DamageTick > _DamageDuration) then Set_Output(i, "DAMAGE", 0); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(i, "Damaged", 0) end; p.IsDamageActive = false end
                if p.IsRumbleActive and (current_time - p.RumbleTick > _RumbleDuration) then Set_Output(i, "RUMBLE", 0); p.IsRumbleActive = false end
            end
        end
        
        -- ==============================================
        -- 7. GAME STATUS & INACTIVE SAFETY VALVE
        -- ==============================================
        local final_game_active = ((global_exists and is_game_active) or (not global_exists and any_player_active))
        Set_Global_Output("GLOBAL_GAME_STATUS", warmup_ok and final_game_active and 1 or 0)
        
        -- Walk-away protection: Wipe pending credits if the game is completely idle for the timeout duration.
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
        
    end)
end

emu.register_frame_done(Compute_Outputs, "frame")