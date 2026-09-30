# Updater (legacy)

This folder is kept only for MSOP Configurator v1.0.6 and earlier. Those versions look for their own
updates in `Updater/JSON/changelog.json`, an address built into them that cannot be changed.

That file is outdated and frozen. It lists only the MSOP Configurator, and its one job is to offer
those versions the upgrade to v1.1.0, which restores downloads of the MSOP Plugin, Hook Of The Reaper
and MAMEhooker files, and the list of supported games.

Everything current lives in [`updates/`](../updates/):

- `updates/msop-content.json` lists where every download lives;
- `updates/msop-changelog.json` is the current changelog.

Please do not edit, move or remove this folder.
