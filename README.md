# MAME-LUA-SCRIPT-STATE-OUTPUTS
UNIVERSAL MAME LUA SCRIPT FOR STATE OUTPUTS (DESIGNED FOR LIGHT GUNS)

## About

As the light gun community is already aware, some MAME ROMs/games do not support native state output, which prevents tools like MAME Hooker or Hook of The Reaper from understanding game events for force feedback (such as recoil, reload, or rumble). In these instances, Lua scripts are needed to enable state outputs (or enhanced state outputs with statistics/counters).

I am sharing my project that aims to solve this problem by creating a universal script that maximises compatibility across all light gun games in MAME, and has support for further collaboration via a GitHub project where the community can build upon this work and add support for new games by uploading new game scripts using the universal template.

I have made these scripts with a priority for light guns, however, it can be adapted to suit any kind of force feedback as desired, and is highly customisable to ensure all games can be used within the same Lua script template.

### Simplified Purpose

When you play a game / ROM in MAME, performing certain actions in-game will create game logic events that result in a change of value in a memory address (or many many memory addresses). However, these memory addresses are not consistent between games / ROMs, nor do they always share the same values for the same action events.

The purpose of these Lua scripts are to map all relevant memory addresses and logic used in each MAME game back to a standardised set of references. With this, we can establish a way to consistently tell an external tool "I just fired the gun, please send the recoil command". This takes pressure away from the external tool in deciphering game logic, and so it can easily take game events from the LUA script and convert that into physical commands for the light gun.

#### Sequence Example

As an example, the sequence of events could look something like this:

MAME In-Game Event (i.e. ammo in magazine drops) >
Lua Script Detection (i.e. ammo values change detected) >
Lua Script Logic (i.e. ammo has dropped, so update the state output for recoil) >
External Tool (e.g. Hook Of The Reaper) Receives State Output (i.e. state output for recoil = 1) >
External Tool (e.g. Hook Of The Reaper) Processed Command for Light Gun (i.e. the state output for recoil is mapped to solenoid recoil of the light gun, so the solenoid recoil command is physically sent to the light gun)

### Logic Example

As an example for how a light gun Lua script may work, most games will have a memory address for an ammo magazine that decreases with each shot fired, which makes it easy to keep track of how many recoil and reload events have occurred. However, in some games the ammo memory address may instead count up for each mission infinitely (i.e. ptblank), so by having additional logic in the LUA script we can simply set AMMO_DIRECTION = "increase", which will ensure the recoil logic correctly triggers. Settings like this help to maximise compatibility across games with little effort being required by the end user in making things work.

### Key Memory Addresses

Typically, only require four key memory addresses (and some minor logic tweaks like the one mentioned above) are required:

- Credits
- Game Status* (fallback logic exists if this is missing)
- Ammo
- Life

## Support

To help the light gun community, I have prepared a selection of MAME games for use with this Lua script.

### Installation

To install or update, copy the relevant files into the following folders as appropriate (and overwrite if necessary):

1. For the first install, please make a backup of your "HookOfTheReaper\defaultLG" folder, and then delete the "MAME_LUA" folder located at "HookOfTheReaper\defaultLG\MAME_LUA". The files in the "MAME_LUA" folder are different Lua scripts that will cause conflicts when used in parallel with my Lua scripts. The Lua scripts you are about to copy over have more features and supported games, so the existing "MAME_LUA" folder included with HOTR must be deleted to prevent these conflicts, hence why I recommend backing it up before deletion.

2. Please copy and paste the "defaultLG" folder into your "HookOfTheReaper\defaultLG" folder, and overwrite any files when prompted. The copied over files should work with both MAME and Model 2 emulators if playing the same ROM/game (e.g. vcop2).

3. Copy the relevant "ini" files into your "MAME\ini" folder. The ini version you copy over will depend on whether you are using the MAME offscreen reload plugin or not (if you do not know what this means, just copy over the files from the "ini" folder).

4. Copy the "scripts" files into your "MAME\scripts" folder. If the "scripts" folder does not exist in your MAME root directory, please create the "scripts" folder first. You do not need to change anything in MAME for this folder to be recognised with my Lua scripts.

5. Ensure your mame.ini file inside your MAME root directory has "output" set to "network" if using Hook Of The Reaper (HOTR).

Note: If a file exists within "HookOfTheReaper\defaultLG" with the same filename, then this should take priority over a file with the same filename in "HookOfTheReaper\defaultLG\MAME_LUA", but to prevent conflict issues it is advised you delete the "HookOfTheReaper\defaultLG\MAME_LUA" folder as outlined in Step 1.

### Supported Light Guns

All light guns will be supported by the Lua scripts, as they only control the state outputs.

It is up to other tools, such as MAME Hooker or Hook Of The Reaper, to support the unique commands and communication methods required by your lightgun.

The following lightguns have been tested and proven to work with these MAME Lua scripts and Hook Of The Reaper (https://github.com/6Bolt/Hook-Of-The-Reaper):

- Gun4IR Namco Guncom
- Retroshooter RS3 Reaper Pro
- Sinden

### Supported Games / ROMs (MAME)

Please refer to the "Progress Notes" included in each release to understand what is being worked on and what issues might exist in each release.

The list of currently supported MAME ROMs / games in the source code are:

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

## Credits

Special thanks to Muggins for all of his help in beta testing with me and verifying compatibility with Sinden light guns.

And a special thanks to Argon for the original MAME LUA script idea, who I believe created the original MAME Lua script that was floating around online and inspired me to create this version from the ground up for easier maintenance, compatibility, and collaboration across the light gun community through a unified template design.



https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
