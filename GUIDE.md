# MAME State Output Project (MSOP)
# MSOP Compiler & Plugin Guide

This guide breaks down the MSOP Plugin database variables by functional category and provides JSON examples for common game archetypes, which are used by the MSOP Compiler to create the required `database.lua` file. Because the master `database.lua` file is compiled from individual game `.json` files or a single `database.json` file, all configurations below are written in pure JSON since this is the source format.

### Two Ways to Build a Game Profile
Every game profile is a single `.json` file, and there are two ways to create one and compile it into `database.lua`:

* **MESH (Modern Emulator State Hub)** - once it is publicly released, the **MSOP Game Editor** on MESH's Games tab (in Advanced mode) lets you create a new game profile, or adjust an existing one, through a form with validated fields and per-player auto-fill, then compile `database.lua` with a single click - no Python required. Your profiles are saved in MESH's settings folder as the same JSON files described in this guide, kept separate from the official ones so updates never overwrite them, which means a game you add in MESH can also be shared in a pull request.
* **The MSOP Database Compiler** - the Python tool described below, which builds the whole database, along with the matching Hook Of The Reaper and MAMEhooker files, from a folder of `.json` files. This suits working with the profile files directly, or in bulk.

---

## 1. Using the MSOP Database Compiler

Because MAME Lua plugins require a `.lua` array for high-performance reading, the MSOP framework uses a Python script (`msop_database_compiler.py`) to automatically build `database.lua` from either individual game `.json` files or a single `database.json` file.

### Prerequisites
* You must have **Python 3.x** installed on your system.

### Folder Structure
Ensure your files are organised correctly. The compiler resolves all of its paths relative to the project root (so it can be run from anywhere) and reads your individual `.json` game profiles from the `input/stable/database/games` folder. Profiles can sit directly in `games/` or in any subfolder - the shipped profiles are sorted by `GAME_TYPE` into subfolders such as `games/lightgun/` and `games/racing/` - and every tool searches the whole folder tree, so the folder a file sits in is purely organisational. The ROM name always comes from the file name, and the same ROM appearing twice is a build error. The `_default.json` game profile must exist at the root of `games/` in order for this to work properly, as this is used to fill in all the non-mentioned settings and logic for each game profile.

> The tool builds per **release channel**. **`stable`** is the normal channel (and the only one that ships in the downloadable Database Compiler). A parallel **`beta`** channel - `input/beta/...` > `output/beta/...` - is kept by the maintainer for new/untested games, so a beta plugin is always paired with beta Hook Of The Reaper / MAMEhooker files generated from that *same* beta database.

```text
Database Compiler/
  ├── scripts/
  │    ├── msop_database_compiler.py          (games *.json  ->  database.lua + database.json)
  │    ├── msop_native_outputs_compiler.py    (MAME source   ->  native_outputs_by_rom.lua + native_outputs_by_driver.lua)   [optional]
  │    ├── msop_hotr_defaultlg_generator.py   (games *.json  ->  Hook Of The Reaper defaultLG/*)
  │    ├── msop_mamehooker_ini_generator.py   (games *.json  ->  MAMEhooker *.ini skeletons)
  │    ├── msop_output_model.py               (shared helper - not run directly)
  │    ├── run_stable.bat / run_stable.sh     (build the STABLE channel - full pipeline)
  │    ├── run_beta.bat   / run_beta.sh       (build the BETA channel)
  │    ├── run.bat        / run.sh            (build BOTH channels)
  │    └── ...                                (msop-only + single-tool launchers)
  ├── input/
  │    └── stable/                            (beta/ mirrors this for the maintainer's beta channel)
  │         ├── stateoutput/   (init.lua, plugin.json, readme.txt)
  │         └── database/
  │              ├── database.json
  │              └── games/
  │                   ├── _default.json       (must stay at the games/ root)
  │                   └── lightgun/           (one subfolder per GAME_TYPE, e.g. racing/ in beta)
  │                        ├── alien3.json
  │                        ├── area51.json
  │                        └── ...
  └── output/                                 (auto-generated - rebuilt on every run, apart from the optional native output tables)
       └── stable/
            ├── stateoutput/   (the complete plugin folder: database.lua, the native output tables, and copies of init.lua, plugin.json and readme.txt)
            ├── ini/           (MAMEhooker per-game .ini skeletons)
            ├── defaultLG/     (Hook Of The Reaper per-game templates)
            └── results/       (native output scrape report)
```

### Compiling Your Database
Whenever you create a new game JSON or edit an existing one, you must recompile the MSOP Database for use with the MSOP Plugin:

#### Windows

**Requirements:**
Ensure you have Python 3 installed on your Windows system and that it is added to your system's `PATH` variables. If this hasn't been completed, the python command will not be recognised.

**Instructions**
1. Navigate to the `scripts` folder of the extracted MSOP Compiler
2. Double-click **`run_stable.bat`**. This runs the whole stable pipeline in one go: it compiles your game JSONs into `database.lua`/`database.json`, then regenerates the Hook Of The Reaper `defaultLG` templates and the MAMEhooker `.ini` skeletons. (The optional step that scrapes MAME's own native outputs into `native_outputs_by_rom.lua` and `native_outputs_by_driver.lua` is skipped unless you set `MAME_SRC` at the top of the launcher to a MAME source checkout.)
3. A Command Prompt window shows each step's progress and a summary when it finishes.

**Alternative:** Open Command Prompt (`cmd`), `cd` to the MSOP Compiler's `scripts` folder, and run `run_stable.bat`.

> **Reverse compile (rebuild per-game JSONs from a single `database.json`):** run `python msop_database_compiler.py` on its own - with no channel argument it shows the interactive menu with **`[ 1 ]`** (per-game JSONs > `database.lua`) and **`[ 2 ]`** (`database.json` > per-game JSONs, each sorted into its `GAME_TYPE` subfolder). The `run_*` launchers always use option 1.

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
1. **Database compile** - reads every individual `.json` in the channel's `games` folder tree (or the single combined `database.json`), validates each for correct JSON syntax (if there's an error you're told the specific line), keeps the two source formats in sync, and generates a fresh `database.lua` (plus `database.json`). It also aligns the plugin's version and date across `init.lua`, `plugin.json` and `readme.txt`, and copies them alongside `database.lua` so the output folder is a complete plugin.
2. **Native output scrape** *(optional)* - if a MAME source path is set, scrapes MAME's own native output names into two lookup tables the plugin uses to re-broadcast them: `native_outputs_by_rom.lua` (per supported ROM) and `native_outputs_by_driver.lua` (per MAME driver, which also covers clones and games MSOP has no profile for). When this step is skipped, any tables already in the output folder are left in place; without them the plugin simply delivers its MSOP outputs only.
3. **Hook Of The Reaper templates** - generates a `defaultLG` mapping file per supported game into `output/<channel>/defaultLG/`.
4. **MAMEhooker skeletons** - generates a blank per-game `.ini` into `output/<channel>/ini/`, prepopulated with the MSOP outputs that game emits, plus the MAME native outputs from `native_outputs_by_rom.lua` whenever that table is present (the MSOP-only launchers leave them out).
5. **games.json sync** *(maintainer step)* - records, in the MSOP supported games list, which channel databases include each game. It is skipped in the downloadable Database Compiler, which does not ship that list.

Your new plugin folder (`output/stable/stateoutput/`) is now complete - `database.lua`, the native output tables and the plugin files together - and ready to copy into MAME's `plugins/stateoutput/` folder for use with the MSOP Plugin. For the complete launcher reference - the MSOP-only variants, the single-tool launchers, and how the maintainer builds the beta channel - see the Database Compiler's own `README.md`.

If you have added support for additional games, sharing this with the community via a pull request on the MSOP GitHub would be greatly appreciated. :) If you would rather not write the profile yourself, you can also request a game with the **New Game / ROM Profile Request** [issue form](https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS/issues/new/choose).

https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS

---

## 2. Variable Breakdown

### Core Architecture & Game Metadata
These variables define how the plugin identifies the game and where it looks for data.

* **`LUA_VERSION`**: The release number of the MSOP Plugin Database the profile belongs to. This should be left alone and taken care of by `_default`.
* **`LUA_DATE`**: This is the date that the MSOP Plugin Database was compiled. This should be left alone and taken care of by `_default`.
* **`LUA_GAME`**: The official name for the game.
* **`ENABLE_ROM`**: Used to enable or disable a supported game ROM for use by MSOP Plugin. This is useful if you have a custom script or build that clashes with MSOP Plugin, and you want to disable MSOP for that specific game without uninstalling MSOP Plugin entirely.
* **`GAME_TYPE`** *(plugin v9.2.0+)*: The genre gate - `"lightgun"` (the default; existing profiles are unaffected), `"racing"`, or `"both"`. Racing profiles skip the per-player gun pipeline each frame and compile only the `FFB_*` output vocabulary, so each ROM's output stream carries only names it can actually drive; gun games never emit FFB names. Use `"both"` for hybrids (e.g. a racing game that also tracks life/damage). Unknown values degrade to `"lightgun"`.
* **`LUA_ROM_ID`**: An optional number to report as the `MSOP_LuaROMid` output for this game. No profile needs to set it: when it is absent, the plugin derives the ID from the ROM's short name, so every ROM has a stable ID of its own.
* **`CPU_TAG`**: Tells MAME which emulated CPU contains the game's core logic (Defaults: `":maincpu"`).
* **`MEMORY_SPACE`**: The address space within `CPU_TAG` that the plugin reads the game's values from (e.g. `"program"`, `"data"`) (Defaults: `"program"`).
* **`PLAYER_MEMORY_OFFSET`**: The mathematical distance (in hex) between Player 1's memory addresses and Player 2's. Setting this allows you to set Player 2, 3, and 4 variables to `"auto"`, allowing the script to calculate their memory addresses automatically using Player 1 as the starting memory address location.
* **`GAME_STATUS` & `GAME_STATUS_ALT`**: The memory address that tells the plugin a game is in progress, which drives the `MSOP_GameStatus` output. `GAME_STATUS_ALT` *(plugin v9.4.0+)* is an optional second address for a game that tracks this in a different place per mode: the game is active when either address reads active. For example, Time Crisis uses `0x00E01772` in story mode and `0x00E00798` in time mode. The alternate address shares the CPU, memory space and data width of `GAME_STATUS`, and is read only when `GAME_STATUS` is an address itself. `GAME_STATUS_ACTIVE_VALUE` sets the value (or list of values) that means active, and `GAME_STATUS_ALT_ACTIVE_VALUE` does the same for the alternate address, falling back to `GAME_STATUS_ACTIVE_VALUE` when left `false` (Defaults: `false`, where any value above zero counts as active).

### The Player Configuration Table (`P1`, `P2`, etc.)
This maps the exact RAM addresses for in-game events. Any variable here can be assigned a specific hex string (e.g., `"0x00A199B5"`) or `"auto"` to inherit and offset P1's data.

* **`STATUS` & `STATUS_ALT`**: The memory address that dictates if a player is actively in the game. Where a `GAME_STATUS` address is set as well, the player is active only while both read active. If a player's status is 0, the plugin securely disables their force feedback to prevent phantom firing during attract mode or other instances where the game logic dictates that the player should not be active. The default logic is any value above 0 = alive/playing and 0 = game over/attract mode, but this can be changed using `STATUS_ACTIVE_VALUE`, and `STATUS_ALT_ACTIVE_VALUE`.
* **`AMMO`, `AMMO_ALT`, `AMMO_GRENADE`**: Tracks the bullet count. A change in this value automatically triggers the physical recoil solenoid and logs a shot fired. The default logic is ammo will decrease to trigger recoil, but this can be changed using `AMMO_DIRECTION`, `AMMO_ALT_DIRECTION`, and `AMMO_GRENADE_DIRECTION`.
* **`LIFE` & `LIFE_ALT`**: Tracks the player's health bar. A change in this value can be used to automatically detect `DAMAGE` and log `DAMAGE_TAKEN` and `LIFE_LOST`. The default logic is life will decrease to trigger `DAMAGE`, but this can be changed using `LIFE_DIRECTION`, and `LIFE_ALT_DIRECTION`.
* **`DAMAGE`**: The memory address that flags when a player takes a hit from an enemy. Triggers the physical damage solenoid/rumble. The default logic is to set this as `auto` which will infer damage using `LIFE` and `LIFE_DIRECTION`.
* **`RECOIL` & `RELOAD`**: Manual hardware triggers. Used to watch for a physical trigger pull or reload sequence directly in RAM, bypassing the ammo counter. The default logic is to set this as `auto` which will infer recoil and reload using `AMMO` and `AMMO_DIRECTION`.
* **`LAMP_START`**: Maps to the physical Start button LEDs on the arcade cabinet.

### Behavioural Logic
These variables dictate *how* the plugin interprets the RAM addresses above.

* **`AMMO_DIRECTION` / `LIFE_DIRECTION`**: `"decrease"` (default) or `"increase"`; `AMMO_DIRECTION` also accepts `"change"`. Most games decrease ammo/life. However, games like *Point Blank* count *up* and start each new round with `AMMO = 0`. Set to `"increase"` so the script knows ammo going UP is a shot/hit.
* **`RECOIL_METHOD`**: `"pulse"` (default), `"hold"`, `"change"`, or `"latch"`. Use `"hold"` for automatic machine gun games. This tells the plugin to continuously fire the solenoid as long as the memory address stays active (i.e. `RECOIL > 0`), rather than pulsing.
* **`RECOIL_MEM_ADD_VALUE` & `RECOIL_MEM_MIN_VALUE`**: Optional, for a `RECOIL` memory address. `RECOIL_MEM_ADD_VALUE` is the exact value that means the gun has fired. `RECOIL_MEM_MIN_VALUE` *(plugin v9.4.0+)* is the lowest value that counts as an active recoil read, and is ignored when `RECOIL_MEM_ADD_VALUE` is set. With both left as `false`, any value above 0 counts as active. `RECOIL_METHOD` then decides when an active value starts a pulse.
* **`RELOAD_MEM_ADD_VALUE` & `RELOAD_MEM_MIN_VALUE`**: Optional, for a `RELOAD` memory address. `RELOAD_MEM_ADD_VALUE` is the exact value, or a list of values, that means a reload has happened. `RELOAD_MEM_MIN_VALUE` triggers a reload when the value rises and is at least that value, and is ignored when `RELOAD_MEM_ADD_VALUE` is set. With both left as `false`, any rise triggers a reload.
* **`RECOIL_PRIORITY`**: `"ammo"` (default) or `"recoil"`. Defines the source of truth for `RECOIL`. Default expects that bullets will drop. Set to `"recoil"` if the `AMMO` memory address is unreliable and you want the script to rely strictly on the player's physical `RECOIL` trigger pulls rather than rely on `AMMO` value changes.
* **`SHOTS_FIRED_METHOD`**: `"trigger"` (default) or `"bullets"`. If a shotgun blasts 5 bullets at once, `"trigger"` counts it as 1 shot. `"bullets"` calculates the math difference and counts it as 5 shots.
* **`FORCE_FEEDBACK_ENABLER`**: `"both"` (default), `"status"`, `"life"`, or `"gamestatus"`. Determines the safety lock for solenoids. An active player always gets force feedback. `"status"`, `"life"` and `"gamestatus"` each allow it as well while that one value reads active: if a game's `STATUS` address is buggy, change this to `"life"` so that a player with a health bar > 0 still gets force feedback.

### Output Timing
These variables set how long each output pulse lasts and how closely pulses can follow one another. A profile carries each game's own timing; protecting a solenoid is the job of the program driving the light gun, unless `ENABLE_RECOIL_SAFETY_DELAY` is turned on.

* **`RECOIL_DURATION_MS`** (Default: `40`): How long (in milliseconds) the physical recoil solenoid extends before snapping back. This is typically overwritten by the "Hooker" program you are using, but this will still assist in enforcing a duration that a recoil state event is held at 1 (which indicates recoil is taking place).
* **`MIN_RECOIL_INTERVAL_MS`** (Default: `100`): The shortest gap between the start of one recoil pulse and the next. A profile sets it to match the game's own rate of fire. You can increase it to slow the recoil rate without affecting in-game firing speed. A value at or below `RECOIL_DURATION_MS` is raised to that duration plus 20 ms. With `RECOIL_METHOD` set to `"hold"`, `RECOIL_HOLD_MS` sets the gap when it is set.
* **`ENABLE_RECOIL_SAFETY_DELAY`** (Default: `false`, set in `_default`): The recoil safety delay. While `false`, recoil outputs follow each game's own timing and the program driving the light gun is responsible for protecting its solenoid. Set it to `true` and no game sends recoil pulses closer together than `RECOIL_SAFETY_DELAY_MS`: both `MIN_RECOIL_INTERVAL_MS` and `RECOIL_HOLD_MS` are raised to at least that value. Pulse lengths are not changed.
* **`RECOIL_SAFETY_DELAY_MS`** (Default: `100`, set in `_default`): The shortest gap between recoil pulses while `ENABLE_RECOIL_SAFETY_DELAY` is `true`. At 100 a gun kicks at most ten times a second.
* **Fast-firing games (a shot every 50ms or less):** A recoil pulse can only end on a frame boundary (about every 16.7ms at 60Hz), so the default 40ms pulse really ends at 50ms. If the next shot lands on that same frame, the output never drops and the kick is lost. Set both values in the game's profile: a `RECOIL_DURATION_MS` that ends at least one frame before the next shot, and a `MIN_RECOIL_INTERVAL_MS` (or `RECOIL_HOLD_MS` for the hold method) just under the shot gap and above the pulse length. Games firing every 66ms or slower work with the default 40ms pulse and only need the interval set.
  * **Example - Crisis Zone:** The machine gun fires a shot every 50ms (about 20 a second). With the defaults (40ms pulse, 100ms interval) only every second shot produced a kick: the 100ms interval skipped the shot in between, and lowering the interval alone would not have helped, because the 40ms pulse ends at 50ms, the same frame the next shot lands on. Its profile therefore sets `RECOIL_DURATION_MS` to `30`, so the pulse ends at 33ms and the output drops before the next shot, and `MIN_RECOIL_INTERVAL_MS` to `40`, which is under the 50ms shot gap and above the pulse length. Every shot now produces its own kick.

### Feature Toggles & Fixes
* **`SCREEN_FLASH`**: For use with older arcade games that used a 'screen flash' to detect crosshair position on-screen in a game (common with CRT displays). Set to `true` and provide the `SCREEN_FLASH_MEMORY_ADDRESS` and `SCREEN_FLASH_DISABLE_VALUE` to actively overwrite MAME's memory and disable blinding white screen flashes.
* **`DEMULSHOOTER_COMPATIBILITY`**: Seamlessly duplicates outputs to `CtmRecoil`, `Damaged` and `CtmLmpStart` to sync with DemulShooter architecture. When set to `true`, this will duplicate `RECOIL`, `DAMAGE` and `LAMP_START` outputs so that both the plugin naming convention (`Recoil`, `Damage` and `LampStart`) and demulshooter naming convention (`CtmRecoil`, `Damaged` and `CtmLmpStart`) are utilised. This is set to `true` by default.
* **`ADDITIONAL_OUTPUT_FORWARDS`**: A list of extra MAME-native output names (lamps, LEDs, etc.) for the plugin to re-broadcast alongside its own state outputs for this game - on top of the list the plugin finds for the game: the running machine's own outputs where MAME can list them, otherwise the per-ROM list compiled in `native_outputs_by_rom.lua`. Useful when a driver exposes native outputs you want delivered through the same MSOP stream.

---

### Force Feedback (`FFB` block) *(plugin v9.2.0+, racing/both game types)*

Racing-genre profiles configure an `FFB` block that tells the plugin where the game's raw
force-feedback command lives and how to decode it into the standardised effect channels
(`MSOP_P<n>_FFB_Constant` / `_Spring` / `_Friction` / `_Damper` / `_Sine` / `_Rumble` / `_Raw`):

* **`ENABLED`**: Master switch for the FFB engine on this ROM.
* **`SOURCES`**: A list probed in order each frame until one resolves, for up to 600 frames. Plain strings are **native
  output names** the MAME driver itself creates (e.g. `"wheel"`, resolved through exact
  `device.outputs` enumeration with a root-device probe fallback, and through MAME's output manager
  on MAME 0.288 and earlier); `"0x..."` hex strings are
  emulated **memory addresses**, read via `CPU_TAGS.FFB` / `MEMORY_SPACES.FFB` /
  `DATA_WIDTHS.FFB` - the same acquisition model as the gun games' Ammo/Life.
* **`DECODE`**: The per-game encoding translator - `passthrough`, `signed8` (two's-complement
  full-value, e.g. the Midway Cruis'n/Rush family and Gaelco's Speed Up), `konami_dir4` (bits
  0-3 = force level, bit 4 = direction; Thrill Drive/GTI Club family), `model2_bands` (Sega
  Model 2 banded drive-board protocol; multi-channel), `namco_lut_rr` (Rave Racer's scrambled
  MCU byte via a 256-entry lookup table), `sega_rally_bands` (Sega Rally's two 32-step bands),
  `hng64_bands` (Hyper Neo Geo 64 racers), `sidebs_5bit` (Taito Side by Side), `virtua_racing`
  (Model 1 banded protocol), `pdrift_8step` (Power Drift's bank-motor byte), `flag_shake`
  (on/off shaker-only cabinets), or `harddrivin_serial` (Hard/Race Drivin's stateful 4-byte
  serial frame). Decoders update only the channels a command addresses; other channels persist
  until changed, and an explicit 0 releases. The decoders after `namco_lut_rr` in this list need
  plugin v9.3.3+.
* **`INVERT`** *(optional, plugin v9.3.3+)*: `true` flips the signed `FFB_Constant` channel for cabinets whose
  wheel encoding runs opposite to their family norm (e.g. the Cruis'n / SF Rush ROMs vs the
  otherwise identical California Speed / Cart Fury group). Magnitude channels are unaffected.
* **`SCALE`**: Full-scale output value (255 = Signed255/Unsigned255, the standard).
* **`PLAYER`**: Which player index emits the FFB outputs (1-4).
* **`EVENTS`** *(optional)*: Address-sourced semantic events - keys `COLLISION`, `GEARCHANGE`,
  `SURFACERUMBLE`, `TYRESLIP`, `ENGINERUMBLE`, each `{ "SOURCE": "0x...", "MODE":
  "nonzero|change|increase|value", "STRENGTH": ..., "DURATION_MS": ..., "MAX": ..., "WIDTH": ... }`.
  `nonzero` is level-style (STRENGTH while the flag byte is non-zero), `change`/`increase` pulse
  for `DURATION_MS`, and `value` scales the raw read against `MAX`.

Most racing games have no researched game-state memory address yet. When none is known, the
top-level `"GAME_STATUS": "always"` *(plugin v9.3.4+)* declares the game active whenever it is
running: the `MSOP_GameStatus` output raises once warmup completes (still respecting an
address-backed `ATTRACT_STATUS` if one is configured) instead of staying at 0 for the whole
session, which racing profiles otherwise do because they skip the per-player activity pipeline.
Replace it with the real address once one is found.

No racing profile is hardware-validated yet - readiness is being verified game by game,
and several games need an in-game service menu setting before any output appears.

### Full Settings Reference

Every setting a profile can carry, with the value `_default` gives it. A profile only needs the settings it changes. The sections above explain the main ones in more depth; this list covers the rest and gives each one's default.

A value of `false` means "not used" for an address or an optional value. Addresses are hex strings such as `"0x00A199B5"`.

#### Reading memory

| Setting | Default | Description |
| --- | --- | --- |
| `CPU_TAG` | `":maincpu"` | The emulated CPU every address is read from, unless `CPU_TAGS` names another for a setting. |
| `MEMORY_SPACE` | `"program"` | The address space every address is read from, unless `MEMORY_SPACES` names another for a setting. |
| `CPU_TAGS` | all `false` | One entry per readable setting (`AMMO`, `LIFE`, `STATUS`, `RECOIL`, `GLOBAL_CREDITS`, `GLOBAL_GAME_STATUS`, `SCREEN_FLASH`, `FFB` and so on). An entry gives that setting its own CPU; `false` uses `CPU_TAG`. |
| `MEMORY_SPACES` | all `false` | As `CPU_TAGS`, for the address space; `false` uses `MEMORY_SPACE`. The value `"region"` reads and writes the MAME memory region named by the setting's CPU tag, and is used to write to ROM for a screen flash patch. |
| `DATA_WIDTHS` | `8`, and `16` for the counters | How each setting's address is read: `8`, `16`, `32` or `64` for an unsigned integer of that many bits, `"float32"` for a 32-bit little-endian float, or `"float32be"` for a 32-bit big-endian float. `"output"` reads one of MAME's own outputs, and the setting then holds the output's name and not an address; it works for `LAMP_START`, `STATUS`, `STATUS_ALT` and the ammo and life settings. |
| `PLAYER_MEMORY_OFFSET` | `false` | The distance between one player's addresses and the next. A P2, P3 or P4 value of `"auto"` is the P1 address plus this offset for each player after P1. |
| `PLAYER_CREDIT_MEMORY_OFFSET` | `false` | The same, for the players' `CREDITS` addresses only. `false` uses `PLAYER_MEMORY_OFFSET`. |
| `STARTUP_DELAY_MS` | `5000` | How long after the game starts or resets every output is held at 0, so that the game's memory test and boot values are not reported as events. |

#### Players

| Setting | Default | Description |
| --- | --- | --- |
| `MAX_PLAYERS` | `2` | The number of players the game supports, from `1` to `4`. A value outside that range is brought inside it. |
| `SIMULTANEOUS_PLAY` | `true` | `false` is for a game whose players take turns on one gun: every player's recoil, reload, damage, rumble and start lamp are sent under player 1's output names, and player 1's `LAMP_START` alone drives the start lamp. |
| `P1`, `P2`, `P3`, `P4` | see below | One table per player. Only the tables up to `MAX_PLAYERS` are used. In `_default`, every P2 to P4 value is `"auto"`. |

Each player table can hold the following. An address setting is an address, `"auto"` or `false`. In `P1`, `"auto"` on an ammo or life setting is treated as `false`, because P1 has nothing to derive it from.

| Setting | P1 default | Description |
| --- | --- | --- |
| `CREDITS` | `false` | The player's own credit count, for a game that keeps credits per player. In P2 to P4, `"auto"` is P1's address plus the credit offset. When P1 is `"auto"` as well, every player shares the global `CREDITS` value. |
| `STATUS`, `STATUS_ALT` | `false` | Whether the player is in the game. `"auto"` derives it from the game status and the player's life, or from credits and life when the game has no game status address. |
| `STATUS_ACTIVE_VALUE`, `STATUS_ALT_ACTIVE_VALUE` | `false` | The value, or list of values, at the status address that means the player is active. `false` uses the top-level setting of the same name, and if that is also `false`, any value above 0. In P2 to P4, `"auto"` is worked out like an address (P1's number plus the player offset), so give each player its own value when P1 sets one. A P1 list is not passed on: the player then uses the top-level value. |
| `AMMO`, `AMMO_ALT`, `AMMO_GRENADE` | `false` | The ammo counts of the primary weapon, a second weapon and grenades. |
| `LIFE`, `LIFE_ALT` | `false` | The player's life, and a second life value where a game has one. |
| `RECOIL` | `"auto"` | `"auto"` takes recoil from the ammo counts. An address is a value the game sets when the gun fires. |
| `RELOAD` | `"auto"` | `"auto"` takes a reload from the ammo counts. An address is a value the game sets on a reload. |
| `DAMAGE` | `"auto"` | `"auto"` sends a damage pulse on each hit that `DAMAGE_TAKEN` detects, so it needs `DAMAGE_TAKEN` to be `"auto"` or an address, and a `LIFE` or `LIFE_ALT` address for player 1. An address is a value that rises when the player is hit. |
| `RUMBLE` | `false` | An address whose value rises when the game wants a rumble. Each rise starts a pulse on the `Rumble` output. |
| `LAMP_START` | `false` | The player's start lamp. |
| `SHOTS_FIRED_PRIMARY`, `SHOTS_FIRED_ALT`, `SHOTS_FIRED_GRENADE` | `"auto"` | `"auto"` counts the shots from each ammo count. An address reads the game's own counter. |
| `SHOTS_FIRED` | `"auto"` | The `ShotsFired` output is always the total of the three counts above. |
| `DAMAGE_TAKEN` | `"auto"` | `"auto"` counts the hits detected from the life values. An address is a value that rises on each hit. |
| `LIFE_LOST` | `"auto"` | `"auto"` adds up the life the player loses. An address reads the game's own counter. |
| `SCREEN_FLASH_MEMORY_ADDRESS`, `SCREEN_FLASH_DISABLE_VALUE`, `SCREEN_FLASH_RESTORE_VALUE` | not set | Optional, for a game with a screen flash address per player. They work as the top-level settings of the same names. |

#### Game state and credits

| Setting | Default | Description |
| --- | --- | --- |
| `GAME_STATUS`, `GAME_STATUS_ALT` | `false` | The address that shows a game is in progress, and an optional second one, which is read only when `GAME_STATUS` is an address. `GAME_STATUS` can also be `"always"`. With `false` or `"auto"`, `MSOP_GameStatus` is 1 while any player is active. |
| `GAME_STATUS_ACTIVE_VALUE`, `GAME_STATUS_ALT_ACTIVE_VALUE` | `false` | The value, or list of values, that means active. `false` means any value above 0; for the second address, `false` first falls back to `GAME_STATUS_ACTIVE_VALUE`. |
| `STATUS_ACTIVE_VALUE`, `STATUS_ALT_ACTIVE_VALUE` | `false` | The active value for every player's `STATUS` and `STATUS_ALT`, unless a player table sets its own. |
| `ATTRACT_STATUS` | `false` | The address that shows the game is in attract mode. While it reads active, no player is treated as active. With no address, `MSOP_AttractStatus` is 1 whenever no game and no player is active. |
| `ATTRACT_STATUS_ACTIVE_VALUE` | `false` | The value, or list of values, at `ATTRACT_STATUS` that means attract mode. `false` means any value above 0. |
| `STATUS_DEBOUNCE_MS` | `34` | How long a player or the game must read as active before its status output goes to 1. It keeps a value that flickers for a frame from being reported. |
| `CREDITS` | `false` | The address of the game's credit count, sent as `MSOP_Credits`. |
| `COINS_PER_CREDIT` | `1` | For a game that stores coins and not credits: the stored value is divided by this number. |
| `CREDITS_CLEAR_TIMEOUT_SEC` | `60` | After this many seconds with no game in progress, credit drops that were not matched to a player are forgotten. |

#### Ammo and life values

| Setting | Default | Description |
| --- | --- | --- |
| `AMMO_DIRECTION`, `AMMO_ALT_DIRECTION`, `AMMO_GRENADE_DIRECTION` | `"decrease"` | `"decrease"`, `"increase"` or `"change"`: which movement of the ammo count is a shot. |
| `LIFE_DIRECTION`, `LIFE_ALT_DIRECTION` | `"decrease"` | `"decrease"` or `"increase"`: which movement of the life value is a hit. |
| `AMMO_OFFSET`, `AMMO_ALT_OFFSET`, `AMMO_GRENADE_OFFSET` | `false` | A number added to the value read, for a game that stores ammo shifted by a fixed amount. |
| `AMMO_MAX`, `AMMO_ALT_MAX`, `AMMO_GRENADE_MAX` | `false` | A value read above this number is treated as 0. |
| `AMMO_THRESHOLD`, `AMMO_ALT_THRESHOLD`, `AMMO_GRENADE_THRESHOLD` | `254` | With a direction of `"decrease"`, a fall only counts as a shot when the value before it was at or below this number. It stops a placeholder such as 255 dropping to the real count from being read as a burst of shots. |
| `LIFE_OFFSET`, `LIFE_ALT_OFFSET` | `false` | A number added to the life value read. |
| `LIFE_MAX`, `LIFE_ALT_MAX` | `false` | A life value read above this number is treated as 0. |

The `Clip` output of each player is 1 while that player's `AMMO` is above 0. It is produced only when `AMMO_DIRECTION` is `"decrease"`.

#### Recoil, reload and counters

| Setting | Default | Description |
| --- | --- | --- |
| `RECOIL_METHOD` | `"pulse"` | `"pulse"` fires when the value rises, `"hold"` fires repeatedly while it is active, `"change"` fires on any change while it is active, and `"latch"` fires only when it goes from 0 to active. |
| `RECOIL_PRIORITY` | `"ammo"` | `"ammo"` or `"recoil"`: which source decides a shot when a player has both ammo and a `RECOIL` address. |
| `RECOIL_MEM_ADD_VALUE`, `RECOIL_MEM_MIN_VALUE` | `false` | The exact value, or the lowest value, of a `RECOIL` address that means the gun has fired. |
| `RELOAD_MEM_ADD_VALUE`, `RELOAD_MEM_MIN_VALUE` | `false` | The exact value or values, or the lowest value, of a `RELOAD` address that means a reload. |
| `SHOTS_FIRED_METHOD`, `SHOTS_FIRED_ALT_METHOD`, `SHOTS_FIRED_GRENADE_METHOD` | `"trigger"` | `"trigger"` counts one shot per change of the ammo count. `"bullets"` counts the size of the change. |
| `FORCE_FEEDBACK_ENABLER` | `"both"` | `"both"`, `"status"`, `"life"` or `"gamestatus"`: when recoil, reload, damage and rumble are sent. An active player always gets them; `"status"`, `"life"` and `"gamestatus"` also allow them while the player's status, the player's life or the game status reads active. |

#### Output timing

| Setting | Default | Description |
| --- | --- | --- |
| `RECOIL_DURATION_MS` | `40` | The length of a recoil pulse for the primary weapon. |
| `RECOIL_ALT_DURATION_MS` | `40` | The length of a recoil pulse for a shot counted from `AMMO_ALT`. |
| `RECOIL_GRENADE_DURATION_MS` | `80` | The length of a recoil pulse for a shot counted from `AMMO_GRENADE`. |
| `MIN_RECOIL_INTERVAL_MS` | `100` | The shortest gap between the start of one recoil pulse and the next. |
| `RECOIL_HOLD_MS` | `100` | With a `RECOIL_METHOD` of `"hold"`, the gap between pulses while the address stays active. A value at or below `RECOIL_DURATION_MS` is raised to that duration plus 20 ms. |
| `ENABLE_RECOIL_SAFETY_DELAY` | `false` | *(plugin v9.3.5+)* `true` raises `MIN_RECOIL_INTERVAL_MS` and `RECOIL_HOLD_MS` to at least `RECOIL_SAFETY_DELAY_MS` for every game. |
| `RECOIL_SAFETY_DELAY_MS` | `100` | *(plugin v9.3.5+)* The shortest gap between recoil pulses while the safety delay is on. |
| `RELOAD_DURATION_MS` | `40` | The length of a reload pulse. |
| `DAMAGE_DURATION_MS` | `250` | The length of a damage pulse. |
| `RUMBLE_DURATION_MS` | `250` | The length of a rumble pulse. |

#### Feature switches

| Setting | Default | Description |
| --- | --- | --- |
| `ENABLE_ROM` | `false` in `_default` | `true` in a game's profile turns MSOP on for that ROM. |
| `GAME_TYPE` | `"lightgun"` | *(plugin v9.2.0+)* `"lightgun"`, `"racing"` or `"both"`. |
| `ENABLE_RECOIL_AMMO`, `ENABLE_RECOIL_AMMO_ALT`, `ENABLE_RECOIL_AMMO_GRENADE` | `true` | `false` stops that ammo count from starting a recoil pulse. |
| `ENABLE_RELOAD_AMMO`, `ENABLE_RELOAD_AMMO_ALT`, `ENABLE_RELOAD_AMMO_GRENADE` | `true` | `false` stops that ammo count from starting a reload pulse. |
| `ENABLE_SHOT_COUNT` | `true` | `false` turns off the `ShotsFired` outputs. |
| `ENABLE_DAMAGE_COUNT` | `true` | `false` turns off the `DamageTaken` output. |
| `ENABLE_LIFE_LOST` | `true` | `false` turns off the `LifeLost` output. |
| `ENABLE_CREDIT_COUNT` | `true` | `false` turns off the `CreditsInserted`, `CreditsConsumed` and `MSOP_GlobalCreditsInserted` outputs. |
| `DEMULSHOOTER_COMPATIBILITY` | `true` | Also sends recoil, damage and the start lamp under the names DemulShooter uses (`P<n>_CtmRecoil`, `P<n>_Damaged`, `P<n>_CtmLmpStart`). |
| `SCREEN_FLASH` | `false` | `true` holds `SCREEN_FLASH_MEMORY_ADDRESS` at `SCREEN_FLASH_DISABLE_VALUE` while the game runs. |
| `SCREEN_FLASH_MEMORY_ADDRESS`, `SCREEN_FLASH_DISABLE_VALUE` | `false` | The address to hold, and the value that turns the flash off. |
| `SCREEN_FLASH_RESTORE_VALUE` | `false` | The value written back to the address when the game stops. |
| `ADDITIONAL_OUTPUT_FORWARDS` | `[]` | Extra MAME output names to send alongside MSOP's own. |
| `ENABLE_OSD` | `false` | `true` also shows the plugin's diagnostic messages on screen. They always print to the console. The switch of the same name at the top of `init.lua` turns them on for every game. |
| `ENABLE_OSD_CONNECTION_STATUS` | `true` | *(plugin v9.3.2+)* Shows an on-screen message when the connection to MESH is lost, fails or returns, and for the two output mode notices. It is read from `_default` only; `false` there silences the on-screen messages, and the console messages still print. |

#### Force feedback

The `FFB` block is described in its own section above. Its defaults are:

| Setting | Default | Description |
| --- | --- | --- |
| `ENABLED` | `false` | `true` turns the force feedback outputs on for the ROM. |
| `SOURCES` | `[]` | The output names or addresses to read the force command from, tried in order. |
| `DECODE` | `"passthrough"` | The decoder for the game's force command. |
| `SCALE` | `255` | The full-scale value of the outputs. |
| `PLAYER` | `1` | The player whose outputs carry the force feedback, from `1` to `MAX_PLAYERS`. A value outside that range is treated as `1`. |
| `INVERT` | not set | `true` reverses the sign of the `FFB_Constant` output. |
| `EVENTS` | `{}` | Optional events read from memory. In each one, `MODE` defaults to `"nonzero"`, `DURATION_MS` to `150`, and `STRENGTH` and `MAX` to `SCALE`. |

#### Output names

| Setting | Default | Description |
| --- | --- | --- |
| `OUTPUT_SUFFIXES` | one entry per output | The last part of each output's name. A player output is `MSOP_P<n>_<suffix>` and a global output is `MSOP_<suffix>`. Changing a suffix renames the output for that game, so the programs that read it must be changed to match. A `CLIP` entry is optional and defaults to `"Clip"`. |
| `LUA_VERSION`, `LUA_DATE`, `LUA_GAME` | set by `_default` and the profile | The database release and the game's name. |
| `LUA_ROM_ID` | not set | An optional number for the `MSOP_LuaROMid` output. |

#### Settings the plugin does not read

`OFFSCREEN_RELOAD`, `LIGHTGUN_PATCH` and `MEMORY_ALIGNMENT` appear in `_default` and in some profiles as notes about the game. The plugin does not read them, and they change no output.

---

## 3. Tutorial Examples (JSON Format)

When adding a new game, you will create a new `.json` file inside the `input/stable/database/games` directory, normally in the subfolder for its `GAME_TYPE` (e.g. `games/lightgun/area51.json`). If you use MESH's MSOP Game Editor instead, it creates the file for you.

Please note that the following examples are stripped down versions of the .json file used by each game, which helps to highlight the specific differences between each example scenario. Extra features exist in the final .json files for each of the games used in each example. Each example leaves out `"ENABLE_ROM": true`, which a profile needs before the plugin runs it.

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
**The Execution:** Set `AMMO` to `false` and map the raw hardware trigger press directly to the `RECOIL` parameter. Set `MIN_RECOIL_INTERVAL_MS` to pace the recoil pulses with the on-screen bullets.

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
