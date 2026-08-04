================================================================================
MAME State Output Project (MSOP)
MSOP Plugin Readme
================================================================================

Plugin Version: 9.2.1
Plugin Date:    2026.08.04
Database Date:  2026.08.04
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
It is highly recommended that you use MESH (Modern Emulator State Hub) - formerly the MSOP Configurator - to manage the
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
  actionable signals. Specifically, it tracks key events - such as ammo changes
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

Hook of the Reaper (HOTR) remains the recommended external hooker for a
plug-and-play light gun setup. If you prefer the MAMEhooker-family tools
(MAMEhooker, OutputHooker, QMamehook), the MESH app (Modern Emulator State
Hub - formerly the MSOP Configurator) generates and maintains their per-game
ini command files automatically from your configured hardware profiles - no
hand-written inis required. MESH can also drive light guns and LED lighting
itself (its built-in Player Hardware Commands and Native LED Control
engines), so an external hooker program is entirely optional.

--------------------------------------------------------------------------------
HOW MSOP DELIVERS ITS OUTPUTS (AND WHY MESH MATTERS)
--------------------------------------------------------------------------------

MAME 0.289 removed the ability for a Lua plugin to CREATE outputs. MSOP can still
read MAME's existing (driver-created) outputs, but it can no longer hand its own
outputs to MAME for broadcasting. Everything MSOP produces - recoil, ammo, life,
lamps, the derived Clip flag - therefore has to leave MAME over MSOP's own TCP
relay connection instead.

That relay needs something listening on the other end. This is what MESH provides.

WITH MESH (recommended)
  * Works on EVERY MAME version, 0.200 through 0.289+, because MESH hosts the
    relay MSOP dials into.
  * MESH speaks MAME's own network-output protocol, so any hooker program
    connects to MESH exactly as it would to MAME - nothing about the hooker
    changes.
  * MESH can also drive your hardware directly (its Native LED Control and
    Native Peripheral Control engines), so a hooker program is optional.
  * MESH compiles and distributes each hooker's per-game ini files for you.
  * Two delivery modes (Settings -> MESH):
      - Hooker Compatible (default): MESH's relay owns port 8000. Hookers get
        MSOP's outputs plus the native outputs MSOP forwards for unsupported
        games. Set MAME to '-output none' or '-output console'.
      - Maximum Coverage: MAME runs '-output network' and owns 8000, so EVERY
        native output of EVERY game flows with no lookup tables; MESH moves its
        relay to 8001 for MSOP's outputs and reads both. External hookers are
        not supported in this mode (see the trade-off below).

WHICH PORT MSOP USES (AUTOMATIC)
  MSOP chooses its relay port from MAME's own '-output' setting, with nothing to
  configure - this applies to a hand-installed plugin as much as a MESH-managed one.
  As a rule of thumb by version: MAME 0.288 and earlier can broadcast MSOP's outputs
  itself, so '-output network' works alone; MAME 0.289 and later cannot, so the relay
  carries them and '-output none' or 'console' keeps everything on one port:
      -output none / console  -> port 8000. MAME is not using it, and 8000 is where
                                 every hooker program looks, so whatever is on 8000
                                 is always the richest stream available.
      -output network         -> port 8001. MAME's own server owns 8000; staying
                                 there would make MSOP a stray client of MAME, whose
                                 protocol discards everything sent to it.
      -output windows         -> port 8000. Windows output uses Win32 messages and
                                 binds no socket, so 8000 remains free for MSOP.

  IMPORTANT: a hooker program can only connect to ONE port. Whichever program owns
  8000 decides what that hooker sees - so with '-output network' it will receive
  MAME's own native outputs and NONE of MSOP's (those are on 8001). If you are
  using a hooker program, prefer '-output none' or '-output console' so everything
  arrives on 8000 together.

HOW MSOP FINDS A GAME'S NATIVE OUTPUTS TO FORWARD
  Under the relay MAME runs '-output none' or '-output console', so MAME's own output
  modules never broadcast the game's native outputs (lamp0, Player1_Gun_Recoil,
  P1_Start_lamp, ...). MSOP forwards them itself over the relay so nothing is lost -
  including for games MSOP has no profile for. It gets the list of names two ways, and
  always prefers the first:

  1. LIVE ENUMERATION (preferred; MAME builds that expose the 'device.outputs'
     property). MSOP asks the running machine which outputs it has actually created and
     forwards exactly those - no lookup tables, always current, and correct even for a
     game nobody ever pre-scanned. This uses MAME's read-only 'device.outputs' property,
     proposed upstream as mamedev/mame PR #15745. It only READS the output list and
     creates nothing. On any build without it, MSOP silently falls back to (2), so
     nothing changes on today's stock MAME.

  2. SHIPPED LOOKUP FILES (fallback; every current stock MAME, since #15745 is not yet
     merged). Two optional files sit in the stateoutput folder beside database.lua:
       * native_outputs_by_rom.lua    - native output names keyed by ROM, scanned for
                                        the games MSOP supports. The more specific of the
                                        two (it can include layout-derived names).
       * native_outputs_by_driver.lua - native output names keyed by MAME driver source
                                        file, scanned across the whole driver tree, so one
                                        entry covers every ROM (and clone) that driver
                                        builds. This is what lets an UNSUPPORTED game
                                        still forward its natives.
     A supported ROM uses its by_rom entry; an unsupported ROM falls back to its driver's
     by_driver entry. Both are regenerated by the compiler (msop_native_outputs_compiler.py)
     - never hand-edit them. If they are absent, nothing breaks: MSOP still delivers its
     own outputs, and unsupported games simply produce nothing extra.

  Either way the result is the same stream: one connection to 127.0.0.1:8000 carries BOTH
  the custom MSOP_ outputs and the game's native ones - so MSOP can be the single source
  of every state output. To forward a name no discovery route can see (e.g. another
  script's own output), list it per game in the database's ADDITIONAL_OUTPUT_FORWARDS; it
  is always honoured on top, whichever route above supplied the rest.

  Native forwarding is deliberately NOT done when MSOP is on its own port (MAME set to
  '-output network', MSOP on 8001): MAME is already broadcasting those same natives on
  8000, so forwarding them again would deliver each one twice to anything reading both
  sockets.

  Cost: negligible. Forwarding is a cached read per known name per frame with no
  allocation, and a value is only ever put on the wire when it CHANGES. Measured on
  Point Blank 2 (28 candidate names) it was within about 1% of running with forwarding
  off entirely - 430% vs 435% of realtime with throttling off.

WHEN IS THE RELAY USED AT ALL?
  MSOP asks the running build whether it can create a custom output - the legacy
  output.set_value route, tested for real rather than
  guessed from a version number. If that route does not work, MAME can hold none of
  MSOP's outputs and therefore cannot broadcast them in ANY output mode, so the
  relay is the only delivery path and is switched on regardless of the setting.
  This is deliberately capability-based rather than version-based: custom and
  pre-release builds can report a version that does not match their behaviour, and
  guessing from the number alone left '-output windows' silently undelivered.

  EXPECTED CONSOLE MESSAGE. That probe runs in MAME's console. When the plugin loads it
  first prints an explicit "COMPATIBILITY TEST" line saying it is about to check whether
  this build can create state outputs, then makes the test call. On MAME 0.289 and newer,
  MAME answers with its OWN error/warning about an unknown output on the very next line -
  that message is EXPECTED, is not a fault in MSOP or the game, and is immediately followed
  by MSOP's own line confirming the result and that it has switched to relay delivery. On
  MAME 0.288 and earlier the test passes quietly and no such error appears.

IF NOTHING IS LISTENING ON THE RELAY PORT
  MSOP dials the relay; it never waits for one. If nothing answers, it retries on a
  back-off rather than every frame, because a REFUSED connection is not always cheap:
  on a machine that answers properly it is refused in well under a millisecond, but
  where local firewall or security software silently drops loopback connection
  attempts instead of refusing them outright, the operating system waits out its
  retransmit first - about 2 seconds, measured. MAME's socket open is a plain
  blocking call with no timeout setting, so that pause freezes emulation until it
  returns, and MAME is not something this plugin can change.

  The schedule, timed on a real clock rather than on frames:
      one free attempt at every ROM start, where the pause is hidden inside loading
      after losing a relay that WAS there   -> 2s, 4s, 8s, then every 15s
      when nothing has ever answered        -> 5s, 10s, then the adaptive cap below

  A SUCCESSFUL connect costs nothing, which is why the lost-relay case retries
  eagerly: a relay that was up moments ago (the MESH app restarting, typically) is
  very likely to answer, and it always keeps the responsive 15s cap.

  ADAPTIVE BEHAVIOUR WHEN NOBODY EVER ANSWERS (v9.1.1). Every dial is timed. On a
  machine that refuses a dead port instantly (the healthy case) retries stay at the
  15s cap - they cost nothing worth avoiding. On a machine where each dial stalls
  (loopback connects silently dropped), never-answered retries slow to every 60s
  instead. And once the initial schedule is exhausted with nothing ever answering:
      * a game MSOP has NO profile for (pass-through only) STOPS dialling for the
        rest of that session - its relay traffic would only be mirrored native
        outputs, which is not worth freezing the game for on a repeating timer.
        A ROM with no native outputs to mirror at all stops after the single
        ROM-start attempt.
      * a SUPPORTED game keeps trying at the adaptive cap - its real MSOP outputs
        (recoil, ammo, life) are worth one dial per interval.
  Dialling re-arms wherever a listener plausibly just appeared, each costing at
  most one deliberate dial: every ROM start or soft reset (the pause hides inside
  loading), and UNPAUSING the machine - so "pause the game, start MESH, unpause"
  connects instantly.

  THE ON-SCREEN WARNING. The first time a session concludes nobody is listening,
  MSOP prints a warning to the console AND puts a one-shot message on MAME's OSD:
  nothing is connected to the MSOP Relay, and MESH (or another hooker tool reading
  the relay) must be running BEFORE launching a ROM for state outputs to be
  delivered. When the give-up applies (a game MSOP has no profile for), the same
  message also states that no further connection attempts will be made this
  session, and how to reconnect: after starting MESH, pause and unpause the game
  (or reset / load a new ROM). For supported games it instead notes that MSOP
  will keep retrying occasionally.

  If you are not using the relay at all, set '-output network' on MAME 0.288 or
  earlier and MSOP will not dial anything.

WITHOUT MESH (MSOP + a hooker program only)
  * MAME 0.200 - 0.288 ONLY, and MAME must be set to '-output network' (or
    '-output windows'). In that configuration MAME creates and broadcasts MSOP's
    outputs itself, and your hooker connects to MAME directly. This works well
    and needs nothing else installed.
  * On MAME 0.289+ this arrangement CANNOT work. MAME will not create MSOP's
    outputs, so it has nothing to broadcast, and MSOP's relay has nobody to dial.
    You would see the game's own native outputs (lamps, recoil lines the driver
    creates) but NONE of MSOP's - no ammo, no life, no derived recoil or reload.
  * You also give up the per-game ini generation, the supported-games list, the
    plugin/database updater, and the diagnostics MESH provides.

THE TRADE-OFF, IN ONE LINE
  Port 8000 can host MAME's own output server OR a relay carrying MSOP's
  outputs - not both. MAME's port is hard-coded and its protocol only ever
  broadcasts outward, so nothing can merge the two streams back together for a
  single hooker connection. Whichever program owns 8000 decides what a hooker
  can see; MESH exists so that program can be one that carries BOTH.

--------------------------------------------------------------------------------
OUTPUT MAPPINGS (MAMEhooker, OutputHooker, and QMamehook)
--------------------------------------------------------------------------------

For now, you can use the following Outputs in your per game ini file which will 
work across all supported games. Every output MSOP creates is prefixed with 
"MSOP_" to keep it distinct from outputs the game's own driver or MAME's core 
may already register under the same short name (e.g. a raw "Credits" or 
"Status" output belonging to something else entirely) - make sure your hooker 
software's mapping file uses the full prefixed name below, not the short name.

Two tables are provided below depending on what you're building:

- CONDENSED: outputs that trigger a physical reaction (recoil, reload, lamps,
  rumble, the hit-detection pulse). Use this if you're wiring up force
  feedback or lighting hardware and don't need the informational values.
- COMPLETE: every output MSOP can produce, including the condensed set plus
  informational values (ammo, life, credits, status flags, shot/damage
  counters, plugin metadata) for building displays, logging, or scoring.

Not every output in either table will be available for every supported game -
each ROM's database entry determines which of these it actually drives. The 
condensed set is the one most consistently supported across the ROM list.

--------------------------------------------------------------------------------
CONDENSED (force feedback / physical reaction triggers)
--------------------------------------------------------------------------------

[Output]
MSOP_P1_LampStart=
MSOP_P1_CtmRecoil=
MSOP_P1_Recoil=
MSOP_P1_Reload=
MSOP_P1_Rumble=
MSOP_P1_Damaged=
MSOP_P2_LampStart=
MSOP_P2_CtmRecoil=
MSOP_P2_Recoil=
MSOP_P2_Reload=
MSOP_P2_Rumble=
MSOP_P2_Damaged=

Note 1: PX = Player Number (e.g. P1 = Player 1)
Note 2: MSOP currently supports up to 4 players, so the above outputs extend to P4.
Note 3: Recoil can be PX_Recoil or PX_CtmRecoil (with demulshooter compatibility)
Note 4: Damage can be PX_Damage or PX_Damaged (with demulshooter compatibility)

--------------------------------------------------------------------------------
COMPLETE (all outputs: triggers plus informational values)
--------------------------------------------------------------------------------

[Output]
MSOP_Credits=
MSOP_GameStatus=
MSOP_AttractStatus=
MSOP_GlobalCreditsInserted=
MSOP_LuaVersion=
MSOP_LuaDate=
MSOP_LuaROMid=
MSOP_P1_LampStart=
MSOP_P1_CtmRecoil=
MSOP_P1_Recoil=
MSOP_P1_Reload=
MSOP_P1_Rumble=
MSOP_P1_Damaged=
MSOP_P1_Damage=
MSOP_P1_DamageTaken=
MSOP_P1_Status=
MSOP_P1_StatusAlt=
MSOP_P1_Life=
MSOP_P1_LifeAlt=
MSOP_P1_LifeLost=
MSOP_P1_Ammo=
MSOP_P1_AmmoAlt=
MSOP_P1_AmmoGrenade=
MSOP_P1_ShotsFired=
MSOP_P1_ShotsFiredPrimary=
MSOP_P1_ShotsFiredAlt=
MSOP_P1_ShotsFiredGrenade=
MSOP_P1_CreditsInserted=
MSOP_P1_CreditsConsumed=
MSOP_P2_LampStart=
MSOP_P2_CtmRecoil=
MSOP_P2_Recoil=
MSOP_P2_Reload=
MSOP_P2_Rumble=
MSOP_P2_Damaged=
MSOP_P2_Damage=
MSOP_P2_DamageTaken=
MSOP_P2_Status=
MSOP_P2_StatusAlt=
MSOP_P2_Life=
MSOP_P2_LifeAlt=
MSOP_P2_LifeLost=
MSOP_P2_Ammo=
MSOP_P2_AmmoAlt=
MSOP_P2_AmmoGrenade=
MSOP_P2_ShotsFired=
MSOP_P2_ShotsFiredPrimary=
MSOP_P2_ShotsFiredAlt=
MSOP_P2_ShotsFiredGrenade=
MSOP_P2_CreditsInserted=
MSOP_P2_CreditsConsumed=

Every output above only appears once a supported ROM actually drives it away 
from its default value - this keeps your hooker software free of names that 
ROM never uses, and is consistent across every output MSOP produces, global 
or per-player.

Note 1: PX = Player Number (e.g. P1 = Player 1)
Note 2: MSOP currently supports up to 4 players, so the above outputs extend to P4.
Note 3: Recoil can be PX_Recoil or PX_CtmRecoil (with demulshooter compatibility)
Note 4: Damage can be PX_Damage or PX_Damaged (with demulshooter compatibility)

--------------------------------------------------------------------------------
MESH APP (FORMERLY MSOP CONFIGURATOR): TUTORIAL & USAGE
--------------------------------------------------------------------------------

The MESH app is designed to streamline the installation and
maintenance of your plugin files and configuration database.

1. Initial Setup: Launch the MESH app. You will be prompted to select 
   your standalone MAME directory.
2. Output Selection: Optionally choose an external "hooker" program so the
   app can map the output integrations - or configure none and let MESH's
   built-in engines drive your hardware directly.
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
MESH APP: COMMAND LINE USAGE
--------------------------------------------------------------------------------

For advanced users and arcade cabinet front-ends, the MESH app can be
executed silently via the command line. This is particularly useful for scripting 
automated plugin updates before launching a game.

Available commands include:

-update
The recommended command. This checks for a MESH app update first.
If found, it silently updates the app, restarts itself, and
seamlessly chains into updating your MAME State Output Plugin and Hooker
configurations both silently and automatically.

-updateplugin
Bypasses MESH app update checks and exclusively updates your MAME
State Output Plugin files and Hooker configurations to match your currently
selected release channel.

-updateapp (or: -updateconfigurator)
Exclusively checks for and installs updates to the MESH app itself (the
-updateconfigurator alias is kept for older scripts).

The full headless suite goes further: -compileinis, -compiledatabase,
-fetchcontent, -verifyinstall, -checkhealth, plus live-control commands for a
running app (-led, -peripherals, -event, -shutdown). Run the executable with
-help for the complete reference.

--------------------------------------------------------------------------------
UPDATES & MAINTENANCE
--------------------------------------------------------------------------------

To ensure your arcade setup remains compatible with the latest game ROMs and 
MAME updates, please run the MESH app regularly.

Updating the Plugin:
Using the MESH app ensures you have the latest memory address mappings, bug 
fixes, and feature enhancements. It is recommended to check for updates every 
time you add new hardware or perform significant maintenance on your arcade 
cabinet, or perhaps want to check if support has been added for a new game ROM.
You can install, update, or uninstall the MSOP Plugin using the buttons on the
Home page of the MESH app.

Updating the MESH App:
When a new version of the MESH app itself is released (such as UI updates 
or new features), you will be prompted to download the update automatically
when you next open the app and are
connected to the internet.
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