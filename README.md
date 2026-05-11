# MAME Universal State Outputs (LUA)

[![License: GPL-v3.0](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![MAME](https://img.shields.io/badge/MAME-Compatible-red.svg)](https://mamedev.org/)

**A universal Lua framework for MAME designed to enable force feedback (recoil, reload, rumble, lights, display, etc.) for light gun games that lack native state outputs or require additional state outputs.**

---

## 📖 What Does This Do?

Many classic MAME arcade games do not natively output "state" data. Without this data, external tools like [**Hook of The Reaper (HOTR)**](https://hotr.6bolt.com/), [**MAME Hooker**](https://dragonking.arcadecontrols.com/static.php?page=aboutmamehooker), [**OutputHooker**](https://github.com/PolybiusExtreme/OutputHooker), and/or [**QMameHook**](https://github.com/SeongGino/QMamehook) have no way of knowing when you fire your weapon or take damage, meaning your light gun's physical recoil, rumble, lights, display, etc. won't work.

This Lua script fixes that. It quietly monitors the game in the background and sends a standardised signal to your hardware whenever an action happens, ensuring your light gun physically aligns to what is happening in-game and on-screen.

---

## 🛠 Installation & Setup

> [!IMPORTANT]  
> **Backup your files.** This installation replaces existing scripts to prevent conflicts. It is recommended that you backup your configured Output Program folder prior installation.

### Option 1: Automatic Installation (Recommended)
I have provided a custom Updater Tool to streamline the installation and ensure all files are placed in the correct directories automatically. This will automatically update both MAME and your relevant Output Program(s).

1. Download the latest version of the **Updater Tool**, extract the **Updater Tool** executable, and run the **Updater Tool** executable.
2. Follow the on-screen prompts. The tool will automatically clean out old conflicting scripts and copy the latest framework files directly into your MAME and relevant Output Program(s) directories.

### Option 2: Manual Installation
If you prefer to manage the file structure yourself, follow these manual steps:

#### MAME
1. **MAME INI:** Copy the `.ini` files from the latest release to your `MAME\ini` folder. *(Use the version that matches your "off-screen reload plugin" preference).*
2. **MAME Scripts:** Copy the `scripts` folder from the latest release to your `MAME` root directory. *(If the folder doesn't exist, create it).*
3. **Enable Output:** Open your `mame.ini` file in the MAME root directory and ensure the output is set to network:
```output network```

#### Output Programs ("Hooking" Programs)
There are many state output "hooking" programs that exist, however, support has been provided for the following tools. These are sorted alphabetically, and are not sorted by preference or recommendation.

#### Hook of the Reaper (HOTR)
[**GitHub**](https://github.com/6Bolt/Hook-Of-The-Reaper) | [**Website**](https://hotr.6bolt.com/)

1. **Clean Old Scripts:** Navigate to `HookOfTheReaper\defaultLG\` and **delete** the folder named `MAME_LUA`.

2. **Copy New Files:** Copy the files from the `defaultLG` folder from the latest release into your `HookOfTheReaper\defaultLG\` directory. Overwrite any files when prompted.

#### MAME Hooker
[**Website**](https://dragonking.arcadecontrols.com/static.php?page=aboutmamehooker)

*TBC*

#### OutputHooker
[**GitHub**](https://github.com/PolybiusExtreme/OutputHooker)

*TBC*

#### QMameHook
[**GitHub**](https://github.com/SeongGino/QMamehook)

*TBC*

## 🔫 Light Gun Compatibility

These scripts handle the logic, while your external Output Program handles the communication to your light gun or physical hardware. Verified supported hardware includes (sorted alphabetically):

- Alien
- Blamcon
- Gun4IR
- Retroshooter MX24
- Retroshooter RS3 (Reaper Pro)
- Sinden Lightgun
- xGunner

## 🎮 Supported MAME ROMs / Games

The latest source code and release includes support for the following MAME ROMs / Games:

| ROM | Game |
| :--- | :--- |
| `area51` | Area 51 |
| `area51mx` | Area 51 / Maximum Force Duo |
| `bbust2` | Beast Busters: Second Nightmare |
| `bel` | Behind Enemy Lines |
| `carnevil` | CarnEvil |
| `cryptklr` | Crypt Killer |
| `dragngun` | Dragon Gun |
| `duckhunt` | Vs. Duck Hunt |
| `hotd` | The House of the Dead |
| `invasnab` | Invasion: The Abductors |
| `jdredd` | Judge Dredd |
| `jpark` | Jurassic Park |
| `le2` | Lethal Enforcers II: Gun Fighters |
| `lethalen` | Lethal Enforcers |
| `lethalj` | Lethal Justice |
| `maxforce` | Maximum Force |
| `policetr` | Police Trainer |
| `ptblank` | Point Blank |
| `sgunner` | Steel Gunner |
| `sgunner2` | Steel Gunner 2 |
| `timecris` | Time Crisis |
| `timecrs2` | Time Crisis II |
| `vcop` | Virtua Cop |
| `vcop2` | Virtua Cop 2 |

Please check the detailed "Progress Notes" included in the latest release for additional details and/or comments for each MAME ROM / game, including any known issues. If you encounter a new issue that isn't documented, please create a new issue on GitHub [here](https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS/issues).

## ⚙️ Under the Hood (Technical Details)

*This section will be further expanded upon in the next couple of weeks while I finish development of the Updater Tool and testing of the latest batch of newly supported games, but a preview of this section is available below*

This section is for developers or community members looking to adapt the script for new games or troubleshoot logic.

### The Translation Layer

In-game actions trigger changes in memory addresses, but these vary wildly between games. For example, one game might count ammo down (10 to 0), while another counts total shots fired infinitely upward.

The Lua script monitors four key memory addresses (Credits, Game Status, Ammo, Life) and combines this with a complex set of logic to determine several game-specific values while utitlising a standardised output.

### Standardised Variables & Priority Logic

To ensure reliable performance across all titles and prevent "phantom" hardware triggers, the script relies on a unified variable naming convention and strict evaluation logic:

1. **Player State Priority:** The script evaluates activity using a strict hierarchy: player-specific STATUS > player-specific LIFE > global GAME_STATUS > fallback logic

2. **Active Player Tracking:** It utilizes a dedicated gamestatus variable to accurately track active players, which prevents unwanted force feedback during attract mode when nobody is playing a game

By funneling all game events through this standardised logic flow, external tools only have to listen for simple, consistent commands (e.g., PX_RECOIL = 1), taking the pressure off the Output Program(s) to decipher complex game states.

## 🤝 Contributing & Credits

This is a community-driven project. If you find a game that isn't supported, please use the provided template in `Compiler\lua_database.json` to map the memory addresses and submit a Pull Request!

Special Thanks:
- Muggins, for grueling beta testing of the Lua scripts and Sinden light gun verification
- Bandicoot, for assisting with additional beta testing of the Lua scripts and Alien light gun verification
- Argon, who created the original concept that inspired this ground-up rewrite for better compatibility and unified template design
