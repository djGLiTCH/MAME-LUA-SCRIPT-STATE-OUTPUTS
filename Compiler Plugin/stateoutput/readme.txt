================================================================================
MAME State Output Project (MSOP)
MSOP Plugin Readme
================================================================================

Plugin Version: 8.3.0
Plugin Date:    2026.06.30
Database Date:  2026.06.30
Created By:     Jacob Simpson (DJ GLiTCH)
License:        GNU General Public License GPL-v3.0
Repository:     https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
Contributors:   Muggins (tester), Hexxed (ideas), Bandicoot (tester), 
                PolybiusExtreme (feedback), Argon (inspiration)

--------------------------------------------------------------------------------
OVERVIEW
--------------------------------------------------------------------------------

The MAME State Output Project or MSOP for short (previously known as the
Universal MAME Lua Script for State Outputs) is a robust solution designed to
enhance the MAME arcade emulation experience. It provides real-time state
outputs (derived from in-game state events or created in real-time based on
logic that adapts various in-game state events), enabling advanced features
like force feedback, light gun hardware support, dynamic lighting, and more.
It is highly recommended that you use the MSOP Configurator to manage the
MSOP Plugin, as this allows automatic configuration and simplifies updates.

--------------------------------------------------------------------------------
HOW IT WORKS
--------------------------------------------------------------------------------

The plugin operates by monitoring specific memory address values within MAME 
to track game states and applies various logic to derive accurate state outputs.

* Logic Priority: The plugin utilises a sophisticated priority hierarchy to 
  ensure accurate hardware behaviour. It evaluates Player Specific Status 
  first, followed by Global Game Status, and finally applies fallback logic 
  to ensure the hardware never enters an undefined state.

* Data Handling: The plugin converts internal MAME memory values into
  actionable signals. Specifically, it tracks key events—such as ammo changes
  (recoil and/or reload), life changes (damage), lamp states (such as player
  start), and many more, to trigger external hardware response (e.g. force
  feedback, lighting, display counters, etc.).

* Variable Management: To maintain stability, the plugin employs dedicated 
  variables for distinct game states, ensuring that inputs from one player do 
  not interfere with the feedback of another.

--------------------------------------------------------------------------------
REQUIREMENTS & COMPATIBILITY
--------------------------------------------------------------------------------

* IMPORTANT: This plugin exclusively supports standalone MAME. RetroArch (and 
  its MAME cores) are NOT supported due to differences in how cores are handled.

This plugin is designed to interface with third-party "hooker" software to 
translate state outputs into physical hardware actions (force feedback, LEDs, 
etc.). Compatible software known to work with these outputs includes:

* Hook of the Reaper (by 6Bolt): https://github.com/6Bolt/Hook-Of-The-Reaper
* MAMEhooker (by Howard Casto): https://dragonking.arcadecontrols.com/static.php?page=aboutmamehooker
* OutputHooker (by PolybiusExtreme): https://github.com/PolybiusExtreme/OutputHooker
* QMamehook (by SeongGino): https://github.com/SeongGino/QMamehook

At this time, Hook of the Reaper (HOTR) is recommended, unless you understand 
how to create your own ini state output to command files that the other "hooker" 
software expects.

In the future, once the Configurator app has been updated to support the automatic 
creation of ini state output to command files, I will swap my recommendation to 
OutputHooker as it has more options for hardware and software experiences.

--------------------------------------------------------------------------------
OUTPUT MAPPINGS (MAMEhooker, OutputHooker, and QMamehook)
--------------------------------------------------------------------------------

For now, you can use the following Outputs in your per game ini file which will 
work across all supported games.

[Output]
Credits=
GameStatus=
P1_LampStart=
P1_Status=
P1_Life=
P1_Damaged=
P1_CtmRecoil=
P1_Reload=
P2_LampStart=
P2_Status=
P2_Life=
P2_Damaged=
P2_CtmRecoil=
P2_Reload=

Please note that not all outputs will be available for each supported game, 
but the main outputs will always be available (PX_CtmRecoil, PX_Reload, 
PX_Damaged).

--------------------------------------------------------------------------------
MSOP CONFIGURATOR APP: TUTORIAL & USAGE
--------------------------------------------------------------------------------

The MSOP Configurator app is designed to streamline the installation and 
maintenance of your plugin files and configuration database.

1. Initial Setup: Launch the Configurator app. You will be prompted to select 
   your standalone MAME directory.
2. Output Selection: Choose your preferred "hooker" program from the available 
   options so the app can correctly map the output integrations.
3. Channel Selection: Choose between the "Stable" or "Beta" release channels 
   (see details below, 'Stable' is highly recommended).
4. Install/Update: Run the update process to automatically download the latest 
   database mappings and copy the necessary plugin files directly into your MAME 
   folder and update your "hooker" program with command mappings if supported.

Beta vs. Stable Plugin Channels:
* Stable: The recommended track for most users. These releases have been 
  thoroughly tested for reliable force feedback and hardware compatibility.
* Beta: The bleeding-edge track. This includes newly supported games, 
  experimental features, and recent bug fixes. Use this if you want to test 
  the newest additions or help the community identify bugs.

--------------------------------------------------------------------------------
MSOP CONFIGURATOR APP: COMMAND LINE USAGE
--------------------------------------------------------------------------------

For advanced users and arcade cabinet front-ends, the MSOP Configurator can be 
executed silently via the command line. This is particularly useful for scripting 
automated plugin updates before launching a game.

Available commands include:

-update
The recommended command. This checks for a Configurator app update first.
If found, it silently updates the Configurator, restarts itself, and
seamlessly chains into updating your MAME State Output Plugin and Hooker
configurations both silently and automatically.

-updateplugin
Bypasses Configurator app update checks and exclusively updates your MAME
State Output Plugin files and Hooker configurations to match your currently
selected release channel.

-updateapp (or: -updateconfigurator)
Exclusively checks for and installs updates to the Configurator app itself.

--------------------------------------------------------------------------------
UPDATES & MAINTENANCE
--------------------------------------------------------------------------------

To ensure your arcade setup remains compatible with the latest game ROMs and 
MAME updates, please run the MSOP Configurator app regularly.

Updating the Plugin:
Using the Configurator ensures you have the latest memory address mappings, bug 
fixes, and feature enhancements. It is recommended to check for updates every 
time you add new hardware or perform significant maintenance on your arcade 
cabinet, or perhaps want to check if support has been added for a new game ROM.
You can install, update, or uninstall the MSOP Plugin using the buttons on the
Home page of the MSOP Configurator app.

Updating the Configurator App:
When a new version of the Configurator app itself is released (such as UI updates 
or new features), you will be prompted to download the update automatically
when you next open the Configurator app and are connected to the internet.
It is worth checking the project GitHub to make sure no automatic update
changes were made that broke previous methods used to automatically update.

--------------------------------------------------------------------------------
COMMUNITY CONTRIBUTIONS
--------------------------------------------------------------------------------

If you would like to contribute to the project, such as improving the plugin 
(optimisations and/or feature enhancements), adding support for new games, or
revising existing games to fix bugs and/or add new features, please visit the
official GitHub repository linked above.

--------------------------------------------------------------------------------
TECHNICAL SUPPORT
--------------------------------------------------------------------------------

No technical support is guaranteed to be provided, however, if you believe you 
have identified a bug or encountered an issue that is directly related to this 
plugin, then please raise an issue in the official GitHub repository linked 
above.

--------------------------------------------------------------------------------
DISCLAIMER
--------------------------------------------------------------------------------

This software is provided "as is", without warranty of any kind. This application
and its associated plugin are not officially affiliated with or endorsed by the
MAME development team or any specific arcade hardware manufacturer.

--------------------------------------------------------------------------------

Copyright (c) 2026 by Jacob Simpson (DJ GLiTCH)