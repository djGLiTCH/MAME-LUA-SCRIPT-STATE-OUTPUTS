# MAME State Output Project (MSOP)
## MSOP Plugin

- **Plugin Version:** 9.3.0
- **Plugin Date:** 2026.08.10
- **Database Date:** 2026.08.10
- **Created By:** Jacob Simpson (DJ GLiTCH)
- **License:** GNU General Public License GPL-v3.0
- **Repository:** https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
- **Contributors:** Muggins (tester), Hexxed (ideas), Bandicoot (tester), EndProdukt (tester), PolybiusExtreme (feedback), Argon (inspiration)

---

## Overview

The MAME State Output Project - or **MSOP** for short (previously known as the Universal MAME Lua
Script for State Outputs) - is a robust solution designed to enhance the MAME arcade emulation
experience. It provides real-time state outputs (derived from in-game state events, or created in
real-time based on logic that adapts various in-game state events), enabling advanced features like
force feedback, light gun hardware support, dynamic lighting, and more.

It is highly recommended that you use **MESH (Modern Emulator State Hub)** - the desktop app formerly
known as the *MSOP Configurator* - to manage the MSOP Plugin, as this allows automatic configuration
and simplifies updates.

## How It Works

The plugin operates by monitoring specific memory address values within MAME to track game states
and applies various logic to derive accurate state outputs.

- **Logic Priority:** The plugin utilises a sophisticated priority hierarchy to ensure accurate
  hardware behaviour. It evaluates Player Specific Status first, followed by Global Game Status, and
  finally applies fallback logic to ensure the hardware never enters an undefined state.
- **Data Handling:** The plugin converts internal MAME memory values into actionable signals.
  Specifically, it tracks key events - such as ammo changes (recoil and/or reload), life changes
  (damage), lamp states (such as player start), and many more - to trigger external hardware
  responses (e.g. force feedback, lighting, display counters, etc.).
- **Variable Management:** To maintain stability, the plugin employs dedicated variables for distinct
  game states, ensuring that inputs from one player do not interfere with the feedback of another.

## Requirements & Compatibility

> **IMPORTANT:** This plugin exclusively supports **standalone MAME**. RetroArch (and its MAME cores)
> are **NOT** supported, due to differences in how cores are handled.

This plugin is designed to interface with third-party "hooker" software to translate state outputs
into physical hardware actions (force feedback, LEDs, etc.). Compatible software known to work with
these outputs includes:

- [Hook of the Reaper](https://github.com/6Bolt/Hook-Of-The-Reaper) - by 6Bolt
- [MAMEhooker](https://dragonking.arcadecontrols.com/static.php?page=aboutmamehooker) - by Howard Casto
- [OutputHooker](https://github.com/PolybiusExtreme/OutputHooker) - by PolybiusExtreme
- [QMamehook](https://github.com/SeongGino/QMamehook) - by SeongGino

**Hook of the Reaper (HOTR)** remains the recommended external hooker for a plug-and-play light gun
setup. If you prefer the MAMEhooker-family tools (MAMEhooker, OutputHooker, QMamehook), the MESH app
generates and maintains their per-game INI command files automatically from your configured hardware
profiles - no hand-written INIs required. MESH can also drive light guns and LED lighting itself
(its built-in Player Hardware Commands and Native LED Control engines), so an external hooker
program is entirely optional.

## How Outputs Are Delivered

MAME 0.289 removed the ability for a Lua plugin to create state outputs, so on those builds MAME can
no longer hold - and therefore no longer broadcast - anything MSOP produces. How MSOP's outputs leave
MAME depends on the build:

- **MAME 0.289 and later (and any relay setup):** MSOP streams its outputs over its own TCP relay
  connection to **MESH's dedicated MSOP ingest port (127.0.0.1:8004)**. MESH must be running to
  receive them. Port **8000** remains what it has always been - MAME's own `-output network` server,
  or the hooker-facing side that MESH manages - and MSOP never binds or dials it in any mode. Hooker
  programs keep connecting to 8000 exactly as they always have.
- **MAME 0.200 - 0.288 with `-output network` or `-output windows`:** MAME creates and broadcasts
  every output itself, MSOP's included, and MSOP opens no socket at all.
- **MAME 0.200 - 0.288 with `-output none` or `-output console`:** the outputs exist but MAME never
  broadcasts them, so MSOP delivers them over the relay as above.

The plugin works all of this out at runtime by asking the running MAME build what it can do - there
is nothing to configure. For the full delivery-model reference (port arrangement, native-output
forwarding, reconnect behaviour, and what happens when nothing is listening), see the included
`readme.txt`.

## Output Mappings (MAMEhooker, OutputHooker, and QMamehook)

For now, you can use the following outputs in your per-game INI file, which will work across all
supported games. Every output MSOP creates is prefixed with `MSOP_` to keep it distinct from outputs
the game's own driver or MAME's core may already register under the same short name (e.g. a raw
`Credits` or `Status` output belonging to something else entirely) - make sure your hooker software's
mapping file uses the full prefixed name below, not the short name.

Two tables are provided below depending on what you're building:

- **Condensed** - outputs that trigger a physical reaction (recoil, reload, lamps, rumble, the
  hit-detection pulse). Use this if you're wiring up force feedback or lighting hardware and don't
  need the informational values.
- **Complete** - every output MSOP can produce, including the condensed set plus informational values
  (ammo, life, credits, status flags, shot/damage counters, plugin metadata) for building displays,
  logging, or scoring.

Not every output in either table will be available for every supported game - each ROM's database
entry determines which of these it actually drives. The condensed set is the one most consistently
supported across the ROM list.

### Condensed (force feedback / physical reaction triggers)

```ini
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
```

- **Note 1:** `PX` = Player Number (e.g. `P1` = Player 1).
- **Note 2:** MSOP currently supports up to 4 players, so the above outputs extend to P4.
- **Note 3:** Recoil can be `PX_Recoil` or `PX_CtmRecoil` (with DemulShooter compatibility).
- **Note 4:** Damage can be `PX_Damage` or `PX_Damaged` (with DemulShooter compatibility).

### Complete (all outputs: triggers plus informational values)

```ini
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
```

Every output above only appears once a supported ROM actually drives it away from its default value - 
this keeps your hooker software free of names that ROM never uses, and is consistent across every
output MSOP produces, global or per-player.

- **Note 1:** `PX` = Player Number (e.g. `P1` = Player 1).
- **Note 2:** MSOP currently supports up to 4 players, so the above outputs extend to P4.
- **Note 3:** Recoil can be `PX_Recoil` or `PX_CtmRecoil` (with DemulShooter compatibility).
- **Note 4:** Damage can be `PX_Damage` or `PX_Damaged` (with DemulShooter compatibility).

### Racing / Force Feedback outputs (new in v9.2.0)

Racing-genre games emit a dedicated **force feedback vocabulary** instead of the gun set. The
plugin reads the game's raw force-feedback command (a native driver output, or an emulated
memory address - the same acquisition model as the gun games), decodes the game-specific
encoding inside the plugin, and re-emits it as standardized effect channels that any consumer
(MESH, or a hooker program) can map onto real hardware with zero game knowledge:

```ini
[Output]
MSOP_P1_FFB_Constant=
MSOP_P1_FFB_Spring=
MSOP_P1_FFB_Friction=
MSOP_P1_FFB_Damper=
MSOP_P1_FFB_Sine=
MSOP_P1_FFB_Rumble=
MSOP_P1_FFB_Raw=
MSOP_P1_FFB_Collision=
MSOP_P1_FFB_GearChange=
MSOP_P1_FFB_SurfaceRumble=
MSOP_P1_FFB_TyreSlip=
MSOP_P1_FFB_EngineRumble=
```

- **Stream channels** persist until changed and an explicit `0` releases them:
  `FFB_Constant` is signed -255..+255 (**positive = force from the right**, i.e. wheel pushed
  left); `FFB_Spring`, `FFB_Friction`, `FFB_Damper`, `FFB_Sine`, and `FFB_Rumble` are 0..255.
  `FFB_Raw` is the undecoded source value (diagnostics / new-game analysis).
- **Semantic events** (`FFB_Collision`, `FFB_GearChange`, `FFB_SurfaceRumble`, `FFB_TyreSlip`,
  `FFB_EngineRumble`; 0..255, pulse/level style) are optional per game, read from separate
  per-game memory addresses. They appear only for games whose database entry configures them.
- `FFB_Rumble` is a **continuous** force-correlated motor level and deliberately coexists with
  the pulse-style `PX_Rumble` - a consumer with a single rumble path should mix the two by
  **MAX**, never sum.
- Every game's database entry now carries a **`GAME_TYPE`** (`lightgun` default / `racing` /
  `both`): racing games emit only the FFB vocabulary (plus the global outputs) and skip the gun
  pipeline entirely, and gun games never emit FFB names - so your hooker mappings only ever see
  the names each ROM can actually drive. Supported racing ROMs in this release: `thrilld`
  (Thrill Drive), `gticlub` (GTI Club), `raverace` (Rave Racer - enable feedback in its service
  menu), `overrev` (Over Rev - change output mode in its service menu).

## MESH App (formerly MSOP Configurator) - Tutorial & Usage

The MESH app is designed to streamline the installation and maintenance of your plugin files and
configuration database.

1. **Initial Setup:** Launch the MESH app. You will be prompted to select your standalone MAME
   directory.
2. **Output Selection:** Optionally choose an external "hooker" program so the app can map the output
   integrations - or configure none and let MESH's built-in engines drive your hardware directly.
3. **Channel Selection:** Choose between the "Stable" or "Beta" release channels (see details below;
   'Stable' is highly recommended).
4. **Install/Update:** Run the update process to automatically download the latest database mappings
   and copy the necessary plugin files directly into your MAME folder, and update your "hooker" program
   with command mappings if supported.

**Beta vs. Stable Plugin Channels:**

- **Stable:** The recommended track for most users. These releases have been thoroughly tested for
  reliable force feedback and hardware compatibility.
- **Beta:** The bleeding-edge track. This includes newly supported games, experimental features, and
  recent bug fixes. Use this if you want to test the newest additions or help the community identify
  bugs.

## MESH App - Command-Line Usage

For advanced users and arcade cabinet front-ends, the MESH app can be executed silently via
the command line. This is particularly useful for scripting automated plugin updates before launching
a game. Available commands include:

- **`-update`** - The recommended command. This checks for a MESH app update first. If found,
  it silently updates the app, restarts itself, and seamlessly chains into updating your MAME
  State Output Plugin and Hooker configurations both silently and automatically.
- **`-updateplugin`** - Bypasses MESH app update checks and exclusively updates your MAME State
  Output Plugin files and Hooker configurations to match your currently selected release channel.
- **`-updateapp`** (or `-updateconfigurator`) - Exclusively checks for and installs updates to the
  MESH app itself (the `-updateconfigurator` alias is kept for older scripts).

The full headless suite goes further - `-compileinis`, `-compiledatabase`, `-fetchcontent`,
`-verifyinstall`, `-checkhealth`, plus live-control commands for a running app (`-led`,
`-peripherals`, `-event`, `-shutdown`). Run the executable with `-help` for the complete reference.

## Updates & Maintenance

To ensure your arcade setup remains compatible with the latest game ROMs and MAME updates, please run
the MESH app regularly.

**Updating the Plugin:** Using the MESH app ensures you have the latest memory address mappings,
bug fixes, and feature enhancements. It is recommended to check for updates every time you add new
hardware or perform significant maintenance on your arcade cabinet, or perhaps want to check if support
has been added for a new game ROM. You can install, update, or uninstall the MSOP Plugin using the
buttons on the Home page of the MESH app.

**Updating the MESH App:** When a new version of the MESH app itself is released (such as UI updates
or new features), you will be prompted to download the update automatically when you next open the app
and are connected to the internet. It is worth checking the project GitHub to
make sure no automatic update changes were made that broke previous methods used to automatically
update.

## Community Contributions

If you would like to contribute to the project - such as improving the plugin (optimisations and/or
feature enhancements), adding support for new games, or revising existing games to fix bugs and/or add
new features - please visit the [official GitHub repository](https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS).

## Technical Support

No technical support is guaranteed to be provided; however, if you believe you have identified a bug or
encountered an issue that is directly related to this plugin, then please raise an issue in the
[official GitHub repository](https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS).

## Disclaimer

This software is provided "as is", without warranty of any kind. This application and its associated
plugin are not officially affiliated with or endorsed by the MAME development team or any specific
arcade hardware manufacturer.

---

Copyright (c) 2026 by Jacob Simpson (DJ GLiTCH)
