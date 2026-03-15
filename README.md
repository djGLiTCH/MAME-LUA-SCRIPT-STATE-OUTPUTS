# MAME-LUA-SCRIPT-STATE-OUTPUTS
UNIVERSAL MAME LUA SCRIPT FOR STATE OUTPUTS (DESIGNED FOR LIGHT GUNS)

As the light gun community is already aware, some MAME ROMs/games do not support native state output, which prevents tools like Mamehooker or Hook of The Reaper from understanding game events for force feedback (such as recoil or rumble). In these instances, LUA scripts are needed to enable state outputs (or enhanced state outputs with statistics/counters).

I am sharing my project that aims to solve this problem by creating a universal script that maximises compatibility across games, and has support for further collaboration via a GitHub project where the community can build upon this work and add support for new games by uploading new game scripts using the universal template.

I have made these scripts with a priority for light guns, however, it can be adapted to suit any kind of force feedback as desired, and is highly customisable to ensure all games can be used within the same LUA script template.

For example, most games will have a memory address for an ammo magazine that decreases with each shot fired, but if there is no ammo magazine in the game then the game logic may increase ammo values with every shot fired infinitely, so simply changing AMMO_DIRECTION = "increase" will ensure the RECOIL logic correctly triggers in the correct ammo direction. Settings like this help to maximise compatibility across games with little effort being required by the end user in making things work, and will typically only require four key memory addresses:

- Credits
- Game Status* (fallback logic exists if this is missing)
- Ammo
- Life

To help the light gun community, I have prepared a selection of MAME games for use with this LUA script. To install these, copy the relevant files into the following folders as appropriate (and overwrite if necessary):

- MAME/ini
- MAME/scripts
- HOTR/defaultLG/MAME_LUA

Note: If a file exists within HOTR/defaultLG with the same filename, then this will take priority over the file in HOTR/defaultLG/MAME_LUA, and so the original filename in HOTR/defaultLG must be deleted. I will attempt to improve compatibility of defaultLG files for use with multiple emulators in a future release.

The following lightguns have been tested and proven to work with these MAME LUA scripts and Hook Of The Reaper (https://github.com/6Bolt/Hook-Of-The-Reaper):

- Gun4IR Namco Guncom
- Retroshooter RS3 Reaper Pro
- Sinden

Please refer to the "Progress Notes" included in each release to understand what is being worked on and what to look out for prior to the final release. As things stand right now, it should only be a few games requiring official Game Status memory address identification, but in the meantime fallback logic has been used which prevents recoil and rumble during attract mode on initial game bootup, but after playing a game, dying, and returning to the main menu, then recoil and rumble may operate during attract mode (only initial attract mode upon bootup is ignored with the fallback logic).

Special thanks to Muggins for all of his help in beta testing with me and verifying compatibility with Sinden light guns. And a special thanks to Argon for the original idea, who I believe created the original MAME LUA script that was floating around online, which inspired me to create this version from the ground up for easier maintenance, compatibility, and collaboration across the light gun community through a unified template design.

https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
