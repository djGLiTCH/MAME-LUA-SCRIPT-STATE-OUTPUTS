# MAME State Output Project (MSOP)
# Configuration & Compiler Guide

This guide breaks down the MSOP plugin database variables by functional category and provides JSON examples for common game archetypes. Because the master `database.lua` file is compiled from individual game `.json` files or a single `database.json` file, all configurations below are written in pure JSON since this is the source format.

---

## 1. Variable Breakdown

### Core Architecture & Game Metadata
These variables define how the plugin identifies the game and where it looks for data.

* **`LUA_VERSION`**: This is the MSOP Plugin version that was used during creation of the game `.json` file. This should be left alone and taken care of by `_default`.
* **`LUA_DATE`**: This is the date that the MSOP Plugin Database was compiled. This should be left alone and taken care of by `_default`.
* **`LUA_GAME` & `LUA_ROM_ID`**: The readable name and your unique ID for the game. The unique ID is found in a Google Sheets document that is used by the MSOP team to keep track of all games with planned support.
* **`CPU_TAG` & `MEMORY_SPACE`**: Tells MAME which emulated CPU contains the game's core logic (Defaults: `":maincpu"` and `"program"`). Change this if you are patching a multi-CPU system where audio/I/O is handled separately (e.g., *Alien 3* uses `":mainpcb:maincpu"`).
* **`PLAYER_MEMORY_OFFSET`**: The mathematical distance (in hex) between Player 1's memory addresses and Player 2's. Setting this allows you to set Player 2, 3, and 4 variables to `"auto"`, allowing the script to calculate their addresses automatically.

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

---

## 2. Tutorial Examples (JSON Format)

When adding a new game, you will create a new `.json` file inside the `game_json` directory (e.g. `area51.json`). 

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
    "MIN_RECOIL_INTERVAL_MS": 80,
    "RECOIL_HOLD_MS": 80,
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
    "SCREEN_FLASH_RESTORE_VALUE": "0x0C03",
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
**The Execution:** Set the `SIMULTANEOUS_PLAY` flag to `false`. Set `PLAYER_MEMORY_OFFSET` to `0` so the plugin doesn't try to calculate secondary blocks. Map unique `STATUS` addresses for both players, but share the `AMMO` and `LIFE` data—the plugin will route the shared data to whichever player's status is currently active.

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

## 3. Using the MSOP Database Compiler

Because MAME Lua plugins require a `.lua` array for high-performance reading, the MSOP framework uses a Python script (`msop_database_compiler.py`) to automatically build `database.lua` from either individual game `.json` files or a single `database.json` file.

### Prerequisites
* You must have **Python 3.x** installed on your system.

### Folder Structure
Ensure your files are organized correctly. The compiler uses smart path detection and expects to find a `game_json` folder containing your individual `.json` game profiles. The `_default` game profile must exist in order for this to work properly, as this is used to fill in all the non-mentioned settings and logic for each game profile.

```text
/stateoutput
  ├── msop_database_compiler.py
  ├── database.lua (Generated)
  ├── database.json
  └── /game_json
       ├── _default.json
       ├── alien3.json
       ├── area51.json
       └── ...
```

### Compiling Your Database
Whenever you create a new game JSON or edit an existing one, you must recompile the database:

1. Open your terminal or command prompt.
2. Navigate to the directory containing the compiler script.
3. Run the by opening it with a batch script or by manually running the script:
   ```bash
   python msop_database_compiler.py
   ```
4. A menu will appear with two options:
   * **`[ 1 ] Compile from folder with individual game JSONs`**
   * **`[ 2 ] Compile from single Database JSON`**
5. Type **`1`** or **`2`** as appropriate, and hit Enter. 

The script will read all individual `.json` files in your `game_json` folder, validate them, and generate a fresh `database.lua` (and modify the opposing individual `.json` game profiles or single `database.json` file to keep everything in sync). Your new game configuration is now ready to be used in MAME!
