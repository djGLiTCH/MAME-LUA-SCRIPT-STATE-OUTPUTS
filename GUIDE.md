# MAME State Output Project (MSOP)
# MSOP Compiler & Plugin Guide

This guide breaks down the MSOP Plugin database variables by functional category and provides JSON examples for common game archetypes, which are used by the MSOP Compiler to create the required `database.lua` file. Because the master `database.lua` file is compiled from individual game `.json` files or a single `database.json` file, all configurations below are written in pure JSON since this is the source format.

---

## 1. Using the MSOP Database Compiler

Because MAME Lua plugins require a `.lua` array for high-performance reading, the MSOP framework uses a Python script (`msop_database_compiler.py`) to automatically build `database.lua` from either individual game `.json` files or a single `database.json` file.

### Prerequisites
* You must have **Python 3.x** installed on your system.

### Folder Structure
Ensure your files are organized correctly. The compiler resolves all of its paths relative to the project root (so it can be run from anywhere) and expects your individual `.json` game profiles in the `input/stable/database/games` folder. The `_default` game profile must exist in order for this to work properly, as this is used to fill in all the non-mentioned settings and logic for each game profile.

> The tool builds per **release channel**. **`stable`** is the normal channel (and the only one that ships in the downloadable Database Compiler). A parallel **`beta`** channel - `input/beta/...` > `output/beta/...` - is kept by the maintainer for new/untested games, so a beta plugin is always paired with beta Hook Of The Reaper / MAMEhooker files generated from that *same* beta database.

```text
Database Compiler/
  ├── scripts/
  │    ├── msop_database_compiler.py          (games *.json  ->  database.lua + database.json)
  │    ├── msop_native_outputs_compiler.py   (MAME source   ->  native_outputs_by_rom.lua)   [optional]
  │    ├── msop_hotr_defaultlg_generator.py   (database      ->  Hook Of The Reaper defaultLG/*)
  │    ├── msop_mamehooker_ini_generator.py   (database      ->  MAMEhooker *.ini skeletons)
  │    ├── msop_output_model.py               (shared helper - not run directly)
  │    ├── run_stable.bat / run_stable.sh     (build the STABLE channel - full pipeline)
  │    ├── run_beta.bat   / run_beta.sh       (build the BETA channel)
  │    ├── run.bat        / run.sh            (build BOTH channels)
  │    └── ...                                (msop-only + single-generator launchers)
  ├── input/
  │    └── stable/                            (beta/ mirrors this for the maintainer's beta channel)
  │         ├── stateoutput/   (init.lua, plugin.json, readme.txt)
  │         └── database/
  │              ├── database.json
  │              └── games/
  │                   ├── _default.json
  │                   ├── alien3.json
  │                   ├── area51.json
  │                   └── ...
  └── output/                                 (auto-generated - safe to delete, rebuilt on every run)
       └── stable/
            ├── stateoutput/   (database.lua + native_outputs_by_rom.lua)
            ├── ini/           (MAMEhooker per-game .ini skeletons)
            └── defaultLG/     (Hook Of The Reaper per-game templates)
```

### Compiling Your Database
Whenever you create a new game JSON or edit an existing one, you must recompile the MSOP Database for use with the MSOP Plugin:

#### Windows

**Requirements:**
Ensure you have Python 3 installed on your Windows system and that it is added to your system's `PATH` variables. If this hasn't been completed, the python command will not be recognised.

**Instructions**
1. Navigate to the `scripts` folder of the extracted MSOP Compiler
2. Double-click **`run_stable.bat`**. This runs the whole stable pipeline in one go: it compiles your game JSONs into `database.lua`/`database.json`, then regenerates the Hook Of The Reaper `defaultLG` templates and the MAMEhooker `.ini` skeletons. (The optional driver step that scrapes MAME's own native outputs into `native_outputs_by_rom.lua` is skipped unless you set a MAME source path at the top of the launcher.)
3. A Command Prompt window shows each step's progress and a summary when it finishes.

**Alternative:** Open Command Prompt (`cmd`), `cd` to the MSOP Compiler's `scripts` folder, and run `run_stable.bat`.

> **Reverse compile (rebuild per-game JSONs from a single `database.json`):** run `python msop_database_compiler.py` on its own - with no channel argument it shows the interactive menu with **`[ 1 ]`** (per-game JSONs > `database.lua`) and **`[ 2 ]`** (`database.json` > per-game JSONs). The `run_*` launchers always use option 1.

#### Linux or macOS

**Requirements:**
Modern Linux and macOS distributions usually require python3 (which the MSOP Compiler explicitly calls). Please ensure Python 3 is installed on your Linux or macOS system.

**Instructions**

1. Open your Terminal app
2. Use the `cd` command to navigate to the folder containing the extracted MSOP Compiler. For example:

    **`cd ~/Downloads/MSOP_Compiler`**
3. Make the launcher executable (only needed the first time you use the MSOP Compiler):

    **`chmod +x scripts/run_stable.sh`**
4. Execute it:

    **`./scripts/run_stable.sh`**
5. The terminal shows each step's progress (database compile > HOTR templates > MAMEhooker INIs) and prints a summary when it finishes.

As on Windows, run `python3 msop_database_compiler.py` on its own for the interactive menu (option **`[ 2 ]`** rebuilds the per-game JSONs from a single `database.json`).


#### How The Pipeline Works

Running `run_stable` (or `run_beta` / `run`) executes these steps for that channel, all reading from its `input/...` and writing to its `output/...`:
1. **Database compile** - reads every individual `.json` in the channel's `games` folder (or the single combined `database.json`), validates each for correct JSON syntax (if there's an error you're told the specific line), keeps the two source formats in sync, and generates a fresh `database.lua` (plus `database.json`).
2. **Driver compile** *(optional)* - if a MAME source path is set, scrapes MAME's own native output names into `native_outputs_by_rom.lua` so the plugin can re-broadcast them. Skipped otherwise, in which case the plugin simply delivers its MSOP outputs only.
3. **Hook Of The Reaper templates** - generates a `defaultLG` mapping file per supported game into `output/<channel>/defaultLG/`.
4. **MAMEhooker skeletons** - generates a blank per-game `.ini` into `output/<channel>/ini/`, prepopulated with the MSOP outputs that game emits (and, if the driver ran, the MAME native outputs too).

Your new `database.lua` (in `output/stable/stateoutput/`) is now ready to be used in MAME with the MSOP Plugin. For the complete launcher reference - the MSOP-only variants, the single-generator launchers, and how the maintainer builds the beta channel - see the Database Compiler's own `README.md`.

If you have added support for additional games, sharing this with the community via a pull request on the MSOP GitHub would be greatly appreciated. :)

https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS

---

## 2. Variable Breakdown

### Core Architecture & Game Metadata
These variables define how the plugin identifies the game and where it looks for data.

* **`LUA_VERSION`**: This is the MSOP Plugin version that was used during creation of the game `.json` file. This should be left alone and taken care of by `_default`.
* **`LUA_DATE`**: This is the date that the MSOP Plugin Database was compiled. This should be left alone and taken care of by `_default`.
* **`LUA_GAME`**: The official name for the game.
* **`ENABLE_ROM`**: Used to enable or disable a supported game ROM for use by MSOP Plugin. This is useful if you have a custom script or build that clashes with MSOP Plugin, and you want to disable MSOP for that specific game without uninstalling MSOP Plugin entirely.
* **`GAME_TYPE`** *(plugin v9.2.0+)*: The genre gate - `"lightgun"` (the default; existing profiles are unaffected), `"racing"`, or `"both"`. Racing profiles skip the per-player gun pipeline each frame and compile only the `FFB_*` output vocabulary, so each ROM's output stream carries only names it can actually drive; gun games never emit FFB names. Use `"both"` for hybrids (e.g. a racing game that also tracks life/damage). Unknown values degrade to `"lightgun"`.
* **`LUA_ROM_ID`**: The unique tracker ID for the game (parent and clone may share the same ID).
* **`CPU_TAG`**: Tells MAME which emulated CPU contains the game's core logic (Defaults: `":maincpu"`).
* **`MEMORY_SPACE`**: The address space within `CPU_TAG` that the plugin reads the game's values from (e.g. `"program"`, `"data"`) (Defaults: `"program"`).
* **`PLAYER_MEMORY_OFFSET`**: The mathematical distance (in hex) between Player 1's memory addresses and Player 2's. Setting this allows you to set Player 2, 3, and 4 variables to `"auto"`, allowing the script to calculate their memory addresses automatically using Player 1 as the starting memory address location.

### The Player Configuration Table (`P1`, `P2`, etc.)
This maps the exact RAM addresses for in-game events. Any variable here can be assigned a specific hex string (e.g., `"0x00A199B5"`) or `"auto"` to inherit and offset P1's data.

* **`STATUS` & `STATUS_ALT`**: The memory address that dictates if a player is actively in the game. This overrides global `GAME_STATUS`. If a player's status is 0, the plugin securely disables their force feedback to prevent phantom firing during attract mode or other instances where the game logic dictates that the player should not be active. The default logic is 1 = alive/playing and 0 = game over/attract mode, but this can be changed using `STATUS_ACTIVE_VALUE`, and `STATUS_ALT_ACTIVE_VALUE`.
* **`AMMO`, `AMMO_ALT`, `AMMO_GRENADE`**: Tracks the bullet count. A change in this value automatically triggers the physical recoil solenoid and logs a shot fired. The default logic is ammo will decrease to trigger recoil, but this can be changed using `AMMO_DIRECTION`, `AMMO_ALT_DIRECTION`, and `AMMO_GRENADE_DIRECTION`.
* **`LIFE` & `LIFE_ALT`**: Tracks the player's health bar. A change in this value can be used to automatically detect `DAMAGE` and log `DAMAGE_TAKEN` and `LIFE_LOST`. The default logic is life will decrease to trigger `DAMAGE`, but this can be changed using `LIFE_DIRECTION`, and `LIFE_ALT_DIRECTION`.
* **`DAMAGE`**: The memory address that flags when a player takes a hit from an enemy. Triggers the physical damage solenoid/rumble. The default logic is to set this as `auto` which will infer damage using `LIFE` and `LIFE_DIRECTION`.
* **`RECOIL` & `RELOAD`**: Manual hardware triggers. Used to watch for a physical trigger pull or reload sequence directly in RAM, bypassing the ammo counter. The default logic is to set this as `auto` which will infer recoil and reload using `AMMO` and `AMMO_DIRECTION`.
* **`LAMPSTART`**: Maps to the physical Start button LEDs on the arcade cabinet.

### Behavioral Logic
These variables dictate *how* the plugin interprets the RAM addresses above.

* **`AMMO_DIRECTION` / `LIFE_DIRECTION`**: `"decrease"` (default), `"increase"`, or `"change"`. Most games decrease ammo/life. However, games like *Point Blank* count *up* and start each new round with `AMMO = 0`. Set to `"increase"` so the script knows ammo going UP is a shot/hit.
* **`RECOIL_METHOD`**: `"pulse"` (default), `"hold"`, `"change"`, or `"latch"`. Use `"hold"` for automatic machine gun games. This tells the plugin to continuously fire the solenoid as long as the memory address stays active (i.e. `RECOIL > 0`), rather than pulsing.
* **`RECOIL_PRIORITY`**: `"ammo"` (default) or `"recoil"`. Defines the source of truth for `RECOIL`. Default expects that bullets will drop. Set to `"recoil"` if the `AMMO` memory address is unreliable and you want the script to rely strictly on the player's physical `RECOIL` trigger pulls rather than rely on `AMMO` value changes.
* **`SHOTS_FIRED_METHOD`**: `"trigger"` (default) or `"bullets"`. If a shotgun blasts 5 bullets at once, `"trigger"` counts it as 1 shot. `"bullets"` calculates the math difference and counts it as 5 shots.
* **`FORCE_FEEDBACK_ENABLER`**: `"both"` (default), `"status"`, `"life"`, or `"gamestatus"`. Determines the safety lock for solenoids. If a game's `STATUS` address is buggy, change this to `"life"` to ensure solenoids only fire if the player has a health bar > 0.

### Hardware Timing & Safety Clamps
These variables protect physical arcade hardware from burning out.

* **`RECOIL_DURATION_MS`** (Default: `40`): How long (in milliseconds) the physical recoil solenoid extends before snapping back. This is typically overwritten by the "Hooker" program you are using, but this will still assist in enforcing a duration that a recoil state event is held at 1 (which indicates recoil is taking place).
* **`MIN_RECOIL_INTERVAL_MS`** (Default: `100`): The "Machine Gun Safety Clamp." It forces a mandatory gap between shots to prevent physical lockups. You can increase this to manually slow down the physical solenoid rate without affecting in-game firing speed.

### Feature Toggles & Fixes
* **`SCREEN_FLASH`**: For use with older arcade games that used a 'screen flash' to detect crosshair position on-screen in a game (common with CRT displays). Set to `true` and provide the `SCREEN_FLASH_MEMORY_ADDRESS` and `SCREEN_FLASH_DISABLE_VALUE` to actively overwrite MAME's memory and disable blinding white screen flashes.
* **`DEMULSHOOTER_COMPATIBILITY`**: Seamlessly duplicates outputs to `CtmRecoil` and `Damaged` to sync with DemulShooter architecture. When set to `true`, this will duplicate `RECOIL` and `DAMAGE` outputs so that both the plugin naming convention (`Recoil` and `Damage`) and demulshooter naming convention (`CtmRecoil` and `Damaged`) are utilised. This is set to `true` by default.
* **`ADDITIONAL_OUTPUT_FORWARDS`**: A list of extra MAME-native output names (lamps, LEDs, etc.) for the plugin to re-broadcast alongside its own state outputs for this game - on top of the per-driver list that ships compiled in `native_outputs_by_rom.lua`. Useful when a driver exposes native outputs you want delivered through the same MSOP stream.

---

### Force Feedback (`FFB` block) *(plugin v9.2.0+, racing/both game types)*

Racing-genre profiles configure an `FFB` block that tells the plugin where the game's raw
force-feedback command lives and how to decode it into the standardized effect channels
(`MSOP_P<n>_FFB_Constant` / `_Spring` / `_Friction` / `_Damper` / `_Sine` / `_Rumble` / `_Raw`):

* **`ENABLED`**: Master switch for the FFB engine on this ROM.
* **`SOURCES`**: A list probed in order each frame until one resolves. Plain strings are **native
  output names** the MAME driver itself creates (e.g. `"wheel"`, resolved through exact
  `device.outputs` enumeration with a root-device probe fallback); `"0x..."` hex strings are
  emulated **memory addresses**, read via `CPU_TAGS.FFB` / `MEMORY_SPACES.FFB` /
  `DATA_WIDTHS.FFB` - the same acquisition model as the gun games' Ammo/Life.
* **`DECODE`**: The per-game encoding translator - `passthrough`, `signed8` (two's-complement
  full-value, e.g. the Midway Cruis'n/Rush family), `konami_dir4` (bits 0-3 = force level,
  bit 4 = direction; Thrill Drive/GTI Club family), `model2_bands` (Sega Model 2 banded
  drive-board protocol; multi-channel), or `namco_lut_rr` (Rave Racer's scrambled MCU byte via a
  256-entry lookup table). Decoders update only the channels a command addresses; other channels
  persist until changed, and an explicit 0 releases.
* **`SCALE`**: Full-scale output value (255 = Signed255/Unsigned255, the standard).
* **`PLAYER`**: Which player index emits the FFB outputs (1-4).
* **`EVENTS`** *(optional)*: Address-sourced semantic events - keys `COLLISION`, `GEARCHANGE`,
  `SURFACERUMBLE`, `TYRESLIP`, `ENGINERUMBLE`, each `{ "SOURCE": "0x...", "MODE":
  "nonzero|change|increase|value", "STRENGTH": ..., "DURATION_MS": ..., "MAX": ..., "WIDTH": ... }`.
  `nonzero` is level-style (STRENGTH while the flag byte is non-zero), `change`/`increase` pulse
  for `DURATION_MS`, and `value` scales the raw read against `MAX`.

See `Compilers/Database Compiler/FFB-TESTING.md` for the full vocabulary contract, testing
procedure, and how to profile a new racing game.

## 3. Tutorial Examples (JSON Format)

When adding a new game, you will create a new `.json` file inside the `input/stable/database/games` directory (e.g. `area51.json`).

Please note that the following examples are stripped down versions of the .json file used by each game, which helps to highlight the specific differences between each example scenario. Extra features exist in the final .json files for each of the games used in each example.

### Example 1: The Standard Setup (*Area 51*)
**The Goal:** A standard 2-player light gun game. 
**The Execution:** You only need to find Player 1's memory addresses. By defining the `PLAYER_MEMORY_OFFSET`, P2 can be set to `"auto"` to inherit and calculate the math perfectly.

```json
{
    "LUA_GAME": "Area 51",
    "PLAYER_MEMORY_OFFSET": "0xA8",
    "P1": {
        "STATUS": "0x10008733",
        "AMMO": "0x1000876F",
        "LIFE": "0x1000879B"
    },
    "P2": {
        "STATUS": "auto",
        "AMMO": "auto",
        "LIFE": "auto"
    }
}
```

### Example 2: The Machine Gun Exception (*Alien 3*)
**The Goal:** A game with multiple weapons where the primary gun acts like a continuous machine gun.
**The Execution:** We map three different ammo types. More importantly, we change the `RECOIL_METHOD` to `"hold"`. When the player runs out of primary ammo, the script uses the `"hold"` method to fall back to the raw `RECOIL` trigger, allowing the physical gun to continue to recoil (at a slower rate) even when ammo is empty.

```json
{
    "LUA_GAME": "Alien3: The Gun",
    "RECOIL_METHOD": "hold",
    "RECOIL_PRIORITY": "ammo",
    "P1": {
        "STATUS": "0x002005F1",
        "AMMO": "0x00200698",
        "AMMO_ALT": "0x0020069C",
        "AMMO_GRENADE": "0x00200697",
        "RECOIL": "0x00200690"
    }
}
```

### Example 3: The "No Ammo Address" Fallback (*Dragon Gun*)
**The Goal:** Support a game where the ammo memory address cannot be found, but hardware recoil tracking is still desired.
**The Execution:** Set `AMMO` to `false` and map the raw hardware trigger press directly to the `RECOIL` parameter. Set `MIN_RECOIL_INTERVAL_MS` to a safe limit to artificially pace the gun with on-screen bullets while ensuring the solenoid won't overheat from being used too quickly.

```json
{
    "LUA_GAME": "Dragon Gun",
    "MIN_RECOIL_INTERVAL_MS": 100,
    "RECOIL_HOLD_MS": 100,
    "RECOIL_METHOD": "hold",
    "RECOIL_PRIORITY": "ammo",
    "P1": {
        "STATUS": "0x0011F1DC",
        "AMMO": false,
        "LIFE": "0x00100008",
        "RECOIL": "0x0011F1B6"
    }
}
```

### Example 4: The Upward Ammo Counter (*Point Blank*)
**The Goal:** Support a game that counts bullets *fired* (e.g. from 0 up to 6) instead of bullets *remaining*.
**The Execution:** Map the ammo address as normal, but override the mathematical logic by setting `AMMO_DIRECTION` to `"increase"` instead of the default `"decrease"`.

```json
{
    "LUA_GAME": "Point Blank",
    "PLAYER_MEMORY_OFFSET": "0x02",
    "AMMO_DIRECTION": "increase",
    "P1": {
        "STATUS": "0x00210427",
        "AMMO": "0x00210011",
        "LIFE": "0x001C00B7"
    }
}
```

### Example 5: The Screen Flash Patch (*Crypt Killer*)
**The Goal:** Automatically disable blinding white screen flashes that occur when firing or taking damage.
**The Execution:** Enable the `SCREEN_FLASH` toggle. Provide the exact memory address, the hex value required to disable it, and the hex value required to restore normal graphics.

```json
{
    "LUA_GAME": "Crypt Killer",
    "SCREEN_FLASH": true,
    "SCREEN_FLASH_MEMORY_ADDRESS": "0x8001512A",
    "SCREEN_FLASH_DISABLE_VALUE": "0x1400",
    "SCREEN_FLASH_DISABLE_VALUE_comment": "Special thanks to Pugsy for finding this value",
    "SCREEN_FLASH_RESTORE_VALUE": "0x0C03",
    "STARTUP_DELAY_MS": 70000,
    "MAX_PLAYERS": 3,
    "DATA_WIDTHS": {
        "SCREEN_FLASH": 16
    },
    "PLAYER_MEMORY_OFFSET": "0x58",
    "ATTRACT_STATUS": "0x001EFDD3",
    "CREDITS": "0x002189C1",
    "P1": {
        "STATUS": "0x002377C8",
        "AMMO": "0x002377D3",
        "LIFE": "0x002377CC"
    }
}
```

### Example 6: The 2-in-1 Combo Game (*Area 51 / Maximum Force Duo*)
**The Goal:** Support a single ROM that contains two completely different games with different memory structures.
**The Execution:** Use the standard keys (`STATUS`, `AMMO`, `LIFE`) to map Game A, and the alternate keys (`STATUS_ALT`, `AMMO_ALT`, `LIFE_ALT`) to map Game B. The plugin dynamically switches tracking logic based on which status address becomes active.

```json
{
    "LUA_GAME": "Area 51 / Maximum Force Duo",
    "P1": {
        "STATUS": "0x00A19979",
        "STATUS_ALT": "0x00A09001",
        "AMMO": "0x00A199B5",
        "AMMO_ALT": "0x00A19479",
        "LIFE": "0x00A199E1",
        "LIFE_ALT": "0x00A19425"
    }
}
```

### Example 7: The Turn-Based Game (*Duck Hunt*)
**The Goal:** Support a multiplayer game where players take turns using the exact same controller, meaning only one player is ever truly "active" on the screen.
**The Execution:** Set the `SIMULTANEOUS_PLAY` flag to `false`. Set `PLAYER_MEMORY_OFFSET` to `0` so the plugin doesn't try to calculate secondary blocks. Map unique `STATUS` addresses for both players, but share the `AMMO` and `LIFE` data - the plugin will route the shared data to whichever player's status is currently active.

```json
{
    "LUA_GAME": "Duck Hunt",
    "SIMULTANEOUS_PLAY": false,
    "PLAYER_MEMORY_OFFSET": 0,
    "P1": {
        "STATUS": "0x0000067C",
        "AMMO": "0x000000BA",
        "LIFE": "0x000000C5"
    },
    "P2": {
        "STATUS": "0x00000602"
    }
}
```

---

Copyright © 2026 by Jacob Simpson (DJ GLiTCH)
