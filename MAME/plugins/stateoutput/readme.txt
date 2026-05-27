================================================================================
MAME State Output Project
================================================================================

PROJECT DETAILS
--------------------------------------------------------------------------------
Version:      8.1.6
Date:         2026.05.27
Author:       Jacob Simpson (DJ GLiTCH)
Contributors: Muggins (testing), Hexxed (brainstorming), Bandicoot (testing), 
              Argon (inspiring)
License:      GNU General Public License GPL-v3.0
Repository:   https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS

OVERVIEW
--------------------------------------------------------------------------------
The MAME State Output project (previously known as the Universal MAME Lua 
Script for State Outputs) is a robust plugin designed to enhance the MAME 
arcade emulation experience. It provides real-time state outputs (derived from 
in-game state events or created in real-time based on logic that adapts various 
in-game state events), enabling advanced features like force feedback, light 
gun hardware support, and dynamic arcade cabinet lighting.

By tapping into MAME’s internal memory addresses, this script bridges the gap 
between digital game states and physical arcade hardware, allowing for a 
truly immersive and tactile experience.

HOW IT WORKS
--------------------------------------------------------------------------------
The script operates by monitoring specific memory address values within MAME 
to track game states and applies various logic to derive accurate state outputs.

* Logic Priority: The script utilises a sophisticated priority hierarchy to 
  ensure accurate hardware behaviour. It evaluates Player Specific Status 
  first, followed by Global Game Status, and finally applies fallback logic 
  to ensure the hardware never enters an undefined state.

* Data Handling: It converts internal MAME memory values into actionable 
  signals. Specifically, it tracks key events—such as ammo changes (recoil 
  and/or reload), life changes (damage / vibration), lamp states (such as 
  player start), and many more, to trigger external hardware response 
  (e.g. force feedback, lighting, display counters, etc.).

* Variable Management: To maintain stability, the script employs dedicated 
  variables for distinct game states, ensuring that inputs from one player do 
  not interfere with the feedback of another.

REQUIREMENTS & COMPATIBILITY
--------------------------------------------------------------------------------
This plugin is designed to interface with third-party "hooker" software to 
translate state outputs into physical hardware actions (force feedback, LEDs, 
etc.). Compatible software known to work with these outputs includes:

* Hook of the Reaper: https://github.com/6Bolt/Hook-Of-The-Reaper
* MAME Hooker: https://dragonking.arcadecontrols.com/static.php?page=aboutmamehooker
* OutputHooker: https://github.com/PolybiusExtreme/OutputHooker
* QMamehook: https://github.com/SeongGino/QMamehook

At this time, Hook of the Reaper (HOTR) is recommended, unless you understand 
how to create your own ini state output to command files that the other "hooker" 
software expects.

In the future, once the Updater Tool has been updated to support the automatic 
creation of ini state output to command files, I will swap my recommendation to 
OutputHooker as it has more options for hardware and software experiences.

UPDATES & MAINTENANCE
--------------------------------------------------------------------------------
To ensure your arcade setup remains compatible with the latest game ROMs and 
MAME core updates, please run the included Updater Tool regularly.

Using the updater ensures you have the latest memory address mappings, bug 
fixes, and feature enhancements. It is recommended to check for updates every 
time you add new hardware or perform significant maintenance on your arcade 
cabinet, or perhaps want to check if support has been added for a new game ROM.

TECHNICAL SUPPORT
--------------------------------------------------------------------------------
No technical support is guaranteed to be provided, however, if you believe you 
have identified a bug or encountered an issue that is directly related to this 
plugin, then please raise an issue in the official GitHub repository linked 
above.

COMMUNITY CONTRIBUTIONS
--------------------------------------------------------------------------------
If you would like to contribute to the project, such as improving the plugin 
lua (optimisations and/or feature enhancements), adding support for new games, 
or revising existing games to fix bugs and/or add new features, please visit 
the official GitHub repository linked above.