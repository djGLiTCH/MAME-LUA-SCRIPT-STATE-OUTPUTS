# MAME State Output Project (Plugin and Configurator)

[![License: GPL-v3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![MAME](https://img.shields.io/badge/MAME-Compatible-green.svg)](https://mamedev.org/)

<p align="center">
  <img src="Images/MAME_State_Output_Project_Transparent_Square_1_1024.png" alt="MAME State Output Project (MSOP) Logo" width="256">
</p>

**A universal state output plugin framework for MAME designed to enable force feedback (recoil, reload, rumble, lights, display, etc.) for games that lack native state outputs or require additional state output triggers. Currently aimed at light gun games, but other genres can be easily supported as well by the community.**

---

## 📖 Historical Context: From Lua Script to MAME Plugin

Previously, this project was known as the "Universal MAME Lua Script for State Outputs". It relied on standalone Lua scripts for each game / ROM to monitor memory addresses and output states. While effective, as the list of supported games grew, we needed a more robust and integrated solution.

We have since migrated to a **native MAME Plugin architecture** to establish a centralized state output framework. This transition allows us to:
* Optimize background performance and reduce overhead.
* Seamlessly integrate with MAME's built-in plugin ecosystem.
* Automate the generation of configuration files.
* Easily add support for new games / ROMs by updating a single file (database.lua).
* Provide a more stable foundation for future community contributions.

---

## ⚙️ What Does This Do?

Many classic MAME arcade games do not natively output "state" data. Without this data, external tools like [**Hook of The Reaper (HOTR)**](https://hotr.6bolt.com/), [**MAMEhooker**](https://dragonking.arcadecontrols.com/static.php?page=aboutmamehooker), [**OutputHooker**](https://github.com/PolybiusExtreme/OutputHooker), and/or [**QMameHook**](https://github.com/SeongGino/QMamehook) have no way of knowing when you fire your weapon or take damage. This means your light gun's physical recoil, rumble, lights, display, etc. won't work.

This plugin fixes that. It quietly monitors the game in the background and sends a standardised signal to your hardware whenever an action state event happens, ensuring your hardware physically aligns to what is happening in-game and on-screen.

---

## 🔫 Light Gun Compatibility

This plugin handles the logic, while your external Output Program handles the communication to your light gun or physical hardware. Verified supported hardware includes:

* Alien
* Blamcon
* Gun4IR
* Retroshooter MX24
* Retroshooter RS3 (Reaper Pro)
* Sinden
* X-Gunner

---

## 🕹️ Supported MAME ROMs / Games

While there are no guarantees that support will be added for every MAME ROM / game (as this takes a lot of my personal time without community contributions and technical hurdles may prevent some games from being supported), the Google Sheets spreadsheet below is used by MSOP for tracking the current status of known MAME ROMs / games.

[MSOP - Supported Games](https://docs.google.com/spreadsheets/d/17VVvfFBOEA-wKUkgWtro3O3fWqo9LeqYRcmX1Q6i5V4/edit?usp=sharing)

If you would like edit access in the spreadsheet to fill in missing information, incorrect details, and/or add to the list of MAME ROMs / games, please raise a GitHub issue or DM me on Discord so I can share edit permissions with your Google account.

As a reminder, the focus at this stage has been on light gun games, but this can be extended to other game genres if the community is interested and willing to step in and help out. :)

The latest source code and release includes support for the following MAME ROMs / games:

| ROM | Game | Comments |
| :--- | :--- | :--- |
| `alien3` | Alien3: The Gun | Working |
| `area51` | Area 51 | Working |
| `area51mx` | Area 51 / Maximum Force Duo | Working<br>Counters (e.g. ShotsFired, LifeLost, etc.) are disabled due to 2-in-1 game. |
| `bbust2` | Beast Busters: Second Nightmare | Working |
| `bel` | Behind Enemy Lines | Working<br>Slowed fire rate when Ammo = 0 may require further timing adjustments. |
| `carnevil` | CarnEvil | Working |
| `crszone` | Crisis Zone | Working |
| `cryptklr` | Crypt Killer | Working |
| `dragngun` | Dragon Gun | Working |
| `dragngunj` | Dragon Gun (Japan) | Working |
| `duckhunt` | Vs. Duck Hunt | Working |
| `hotd` | The House of the Dead | Working |
| `invasnab` | Invasion: The Abductors | Working |
| `jdredd` | Judge Dredd | Working |
| `jpark` | Jurassic Park | Working<br>Life and Ammo are disabled due to memory addresses shifting with new player life.<br>Recoil, Status, and Lamp Start are enabled. |
| `le2` | Lethal Enforcers II: Gun Fighters | Working |
| `lethalen` | Lethal Enforcers | Working |
| `lethalj` | Lethal Justice | Working |
| `maxforce` | Maximum Force | Working |
| `opwolf` | Operation Wolf | Working |
| `opwolf3` | Operation Wolf 3 | Working |
| `othunder` | Operation Thunderbolt | Working |
| `policetr` | Police Trainer | Working |
| `ptblank` | Point Blank | Working |
| `sgunner` | Steel Gunner | Working |
| `sgunnerj` | Steel Gunner (Japan) | Working |
| `sgunner2` | Steel Gunner 2 | Working |
| `sgunner2j` | Steel Gunner 2 (Japan) | Working |
| `timecris` | Time Crisis | Working |
| `timecrs2` | Time Crisis II | Working |
| `vcop` | Virtua Cop | Working |
| `vcop2` | Virtua Cop 2 | Working |

If you encounter a new issue that isn't documented, please create a new issue on GitHub [here](https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS/issues).

---

## 🛠️ Installation & Setup

> [!IMPORTANT]  
> **Backup your files.** This installation replaces existing scripts/plugins to prevent conflicts. It is recommended that you backup your configured 'Hooker' Program folder prior to installation.

> [!WARNING]  
> **Standalone MAME Only:** This plugin exclusively supports standalone MAME. RetroArch (and its MAME cores) are NOT supported due to differences in how cores are handled.

### Option 1: Automatic Installation (Recommended)
We provide a custom Configurator app to streamline the installation and ensure all files are placed in the correct directories automatically. This will automatically update both MAME and your relevant Output Program(s). We highly recommend this app be used to install and configure your build.

1. Download the latest version of the **Configurator App**, extract the executable, and run it.
2. Follow the on-screen prompts. The tool will automatically clean out old conflicting scripts and copy the latest plugin framework files directly into your MAME and relevant Output Program(s) directories.

#### MSOP Configurator App Workflow:
* **Initial Setup:** Launch the Configurator app. You will be prompted to select your standalone MAME directory.
* **Output Selection:** Choose your preferred "hooker" program from the available options so the app can correctly map the output integrations.
* **Channel Selection:** Choose between the "Stable" or "Beta" release channels ('Stable' is highly recommended).
* **Install/Update:** Run the update process to automatically download the latest database mappings, copy the necessary plugin files directly into your MAME folder, and update your "hooker" program with command mappings if supported.

### Option 2: Manual Installation & Migration
If you prefer to manage the file structure yourself, please follow these manual steps:

#### Step 1: Clean Up Old Architecture (Crucial for Upgrading)
To prevent conflicts between the old standalone scripts and the new plugin, you must remove the old files first:
1. **Remove Old Lua Scripts:** Navigate to your `MAME\scripts` directory and delete any `.lua` files or folders associated with the previous State Output project (v7 and below).
2. **Remove Old INI Files:** Navigate to your `MAME\ini` folder and delete any `.ini` configuration files or folders associated with the previous State Output project (v7 and below).

#### Step 2: Install the New Plugin
1. **MAME INI:** Copy the new `.ini` files from the latest release to your `MAME\ini` folder. *This step is completely optional, and only needed if you want the "classic" version of the offscreen reload feature in MAME.*
2. **MAME Plugins:** Copy the extracted plugin folders from the latest release into your `MAME\plugins` directory. 
3. **Enable Output:** Open your `mame.ini` file in the MAME root directory and ensure the output is set to network:
`output network`
4. **Enable Plugins:** Ensure the plugins is enabled in your `plugin.ini` file:
`plugins 1`

#### Step 3: Output Programs ('Hooker' Programs)
There are many state output 'hooker' programs that exist, however, support has been provided for the following tools:

**Hook of the Reaper (HOTR) (Recommended)**
[**GitHub**](https://github.com/6Bolt/Hook-Of-The-Reaper) | [**Website**](https://hotr.6bolt.com/)
1. **Clean Old Scripts:** Navigate to `HookOfTheReaper\defaultLG\` and **delete** the folder named `MAME_LUA`.
2. **Copy New Files:** Copy the files from the `defaultLG` folder from the latest release into your `HookOfTheReaper\defaultLG\` directory. Overwrite any files when prompted.

*(Note: Refer to documentation for MAME Hooker, OutputHooker, and QMameHook setup, which will be expanded later once the Configurator App can handle automatic ini generation).*

---

## 📡 Release Channels (Stable vs Beta)

The Configurator now supports dual release channels, allowing you to choose between maximum stability or cutting-edge features. You can toggle between these channels at any time using the radio buttons on the home screen.

* **Stable Channel (Recommended):** The default track. These releases are thoroughly tested and guaranteed to provide a reliable experience for your arcade cabinet.
* **Beta Channel:** Contains experimental features, bug fixes, and early support for newly added games or ROMs that are currently in active testing. 
* **Smart Syncing:** The Configurator intelligently monitors both channels. If a Beta cycle ends and the Stable channel surpasses your installed Beta version, the app will automatically prompt you to jump back to the Stable track so you never miss an update.
* **Offline Caching:** The app silently caches the latest release files for both channels in the background upon launch, ensuring you can still install or reinstall plugins even if your cabinet goes offline.

---

## 🔧 Under the Hood (Technical Details)

This section is for developers or community members looking to adapt the plugin for new games or troubleshoot logic. More technical details can be found in [GUIDE](GUIDE.md).

### The Translation Layer
In-game actions trigger changes in memory addresses, but these vary wildly between games. For example, one game might count ammo down (10 to 0), while another counts total shots fired infinitely upward.

The plugin monitors four key memory addresses (Credits, Game Status, Ammo, Life) and combines this with a complex set of logic to determine several game-specific values or triggers while utitlising a standardised output.

### Standardised Variables & Priority Logic
To ensure reliable performance across all titles and prevent "phantom" hardware triggers, the plugin relies on a unified variable naming convention and strict evaluation logic:

1. **Player State Priority:** The plugin evaluates activity using a strict hierarchy: player-specific STATUS > player-specific LIFE > global GAME_STATUS > fallback logic.
2. **Active Player Tracking:** It utilizes a dedicated gamestatus variable to accurately track active players, which prevents unwanted force feedback during attract mode when nobody is playing a game.

By funneling all game events through this standardised logic flow, external tools only have to listen for simple, consistent commands (e.g., PX_Life = 1), taking the pressure off the Output Program(s) to decipher complex game states.

---

## 🤖 Command Line Automation (Headless Mode)

For arcade owners and frontend users (RetroBat, LaunchBox, etc.) who want a true "set and forget" experience, the Configurator app fully supports headless command-line execution. 

You can map these arguments to batch scripts that run on system boot or game launch. The application will execute completely invisibly in the background, download the required files, update your configurations, and close itself without ever drawing a UI or interrupting your arcade immersion.

**Available Commands:**
* `-update`
  * **The Recommended Command** | This checks for a Configurator app update first. If found, it silently updates the Configurator, restarts itself, and seamlessly chains into updating your MAME State Output Plugin and Hooker configurations both silently and automatically. 
* `-updateplugin`
  * Bypasses Configurator app update checks and exclusively updates your MAME State Output Plugin files and Hooker configurations to match your currently selected release channel.
* `-updateapp` (or `-updateconfigurator`)
  * Exclusively checks for and installs updates to the Configurator app itself. 

**Headless Safety Features:**
* **Mutex Locking:** If a background script triggers while you are manually using the Configurator UI, the script will safely abort to prevent overwriting files you are actively modifying.
* **Silent Error Logging:** If an update fails in the background (e.g., your internet connection drops), the app will not throw an error popup on your arcade screen. Instead, it fails silently and writes the crash details to `%AppData%\MameStateOutputConfigurator\silent_update_error.txt` for your review.

---

## 🤝 Contributing & Credits

This is a community-driven project. If you find a game that isn't supported, please build this out in the latest `database.lua` file to map the memory addresses and submit a Pull Request!

**Special Thanks:**
* **Muggins**, for all of his help and support. Without his tireless efforts in testing each release and suggesting quality of live improvements, it would not be what it is today.
* **Bandicoot**, for all of his helpin testing newly supported games for this project.
* **Hexxed**, for all of his help in testing new design ideas, suggestions for improvements, and general architecture discussions for this project.
* **Argon**, for the initial Lua script concept that sparked the idea for this project.
* **PolybiusExtreme**, for [**OutputHooker**](https://github.com/PolybiusExtreme/OutputHooker), and general testing and feedback for this project.
* **Howard Casto**, for [**MAMEhooker**](https://dragonking.arcadecontrols.com/static.php?page=aboutmamehooker).
* **SeongGino**, for [**QMameHook**](https://github.com/SeongGino/QMamehook).
* **6Bolt**, for [**Hook Of The Reaper**](https://github.com/6Bolt/Hook-Of-The-Reaper).
* The [**MAME Development Team**](https://www.mamedev.org), for building and maintaining such an amazing emulation project.

---

Copyright © 2026 by Jacob Simpson (DJ GLiTCH)
