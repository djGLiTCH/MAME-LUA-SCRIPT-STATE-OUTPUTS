#
# MAME STATE OUTPUT PROJECT (MSOP)
# MSOP GAMES JSON SYNC (channel game database -> games.json "Channels")
# Script Version: 1.0.1
# Script Date: 2026.09.28
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#
# Keeps the MSOP supported games list (updates/msop-games.json) aligned with each release channel's
# game database. Every game row carries a "Channels" object recording, per channel, the database date
# (plugin.json "datedatabase") of the first build of that channel that included the ROM:
#
#     "Channels": { "stable": "2026.08.24", "beta": "2026.08.30" }
#
# A channel key is present only while that channel's database includes the ROM with ENABLE_ROM true,
# so an app can tell which games each channel ships without relying on the plugin version - both
# channels can ship the same plugin version while their game databases differ. An installed plugin
# whose datedatabase is on or after a game's channel date has a database that includes the game.
#
# For the channel being run:
#   * a ROM in the database whose row has no date for the channel gets this build's datedatabase;
#   * an existing date is kept, because it records the first build that included the ROM - unless it
#     is later than this build's datedatabase, which cannot be right, so it is pulled back;
#   * a row whose ROM has left the channel's database loses that channel's key;
#   * a ROM in the database with no games.json row is an error for stable (the shipped channel must
#     be fully listed) and a warning for beta. The row metadata (names, hardware, etc.) stays
#     hand-curated - this script only ever writes "Channels".
# Any error leaves games.json untouched and exits 1.
#
# Release checks - apps compare each channel's published plugin version and database date with the
# installed plugin's, so two things must hold before publishing:
#   * at the same plugin version, stable's database is never dated after beta's. Some app versions
#     move beta users to stable when stable's date is later; run.* builds both channels on one day;
#   * the channel's first msop-changelog.json entry (PluginStable / PluginBeta, beside games.json) names
#     this plugin's version and database date - the date read from DatabaseReleases[0]
#     .IncludedDatabaseDate, else ReleaseDatePlugin, as the apps read it. An older date makes every
#     install read as ahead of its channel; a newer one leaves the update prompt showing.
# They are warnings in a normal run (the changelog is written at release time) and errors under
# --check, the pre-publish check.
#
# games.json is a maintainer file that lives outside the Database Compiler folder, so the standalone
# Database Compiler download does not include it; when it cannot be found this step is skipped.
#
# The file is written in its existing format (4-space indent, CRLF, no trailing newline) and only
# when something changed, so a build that changes nothing leaves it byte-identical.
#
# Options:
#   --channel stable|beta   the channel database to sync from (default stable)
#   --games-json <path>     games.json to update (default: <repo>/updates/msop-games.json)
#   --check                 report only: write nothing, exit 1 if games.json would change, has errors,
#                           or a release check fails
#   --backfill              one-off seeding: a missing date takes the row's SupportedDate instead of
#                           this build's date (never later than this build's datedatabase)
#

import argparse
import json
import os
import re
import sys
import textwrap

SCRIPT_VERSION = "1.0.1"
SCRIPT_DATE = "2026.09.28"

# scripts/ -> the Database Compiler folder -> tools/ -> the repository root.
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_ROOT = os.path.dirname(os.path.dirname(BASE_DIR))
DEFAULT_GAMES_JSON = os.path.join(REPO_ROOT, "updates", "msop-games.json")

CHANNELS = ("stable", "beta")
DATE_RE = re.compile(r"^\d{4}\.\d{2}\.\d{2}$")
EOL = "\r\n"


class SyncError(Exception):
    pass


def load_json(path):
    try:
        with open(path, encoding="utf-8-sig") as f:
            return json.load(f)
    except (OSError, ValueError) as e:
        raise SyncError(f"cannot read {path}: {e}")


def channel_database(channel):
    """The ROMs the channel's database ships, i.e. every games/**/*.json whose effective ENABLE_ROM
    (the game's own value, else _default's) is true - the same rule init.lua applies at runtime."""
    games_dir = os.path.join(BASE_DIR, "input", channel, "database", "games")
    if not os.path.isdir(games_dir):
        raise SyncError(f"channel database not found: {games_dir}")
    default = load_json(os.path.join(games_dir, "_default.json"))
    default_enabled = default.get("ENABLE_ROM", True)

    roms, seen = set(), {}
    for dirpath, dirnames, filenames in os.walk(games_dir):
        dirnames.sort()
        for name in sorted(filenames):
            if not name.lower().endswith(".json"):
                continue
            rom = name[:-5]
            if rom == "_default":
                continue
            path = os.path.join(dirpath, name)
            if rom in seen:
                raise SyncError(f"ROM '{rom}' exists twice in the {channel} database: "
                                f"{os.path.relpath(seen[rom], games_dir)} and {os.path.relpath(path, games_dir)}")
            seen[rom] = path
            if load_json(path).get("ENABLE_ROM", default_enabled) is not False:
                roms.add(rom)
    return roms


def channel_plugin(channel):
    """(version, datedatabase) from the channel's plugin.json, or None when the channel is absent."""
    plugin_json = os.path.join(BASE_DIR, "input", channel, "stateoutput", "plugin.json")
    if not os.path.isfile(plugin_json):
        return None
    plugin = load_json(plugin_json).get("plugin", {})
    version, date = str(plugin.get("version", "")), str(plugin.get("datedatabase", ""))
    if not DATE_RE.match(date):
        raise SyncError(f"{plugin_json} has no valid datedatabase (found '{date}')")
    return version, date


def release_checks(channel, plugin, changelog_json):
    """The problems that would mislead apps if this build were published (see the header)."""
    problems = []
    stable, beta = (plugin if channel == "stable" else channel_plugin("stable")), \
                   (plugin if channel == "beta" else channel_plugin("beta"))
    if stable and beta and stable[0] == beta[0] and stable[1] > beta[1]:
        problems.append(f"stable's database ({stable[1]}) is dated after beta's ({beta[1]}) at plugin "
                        f"{stable[0]} - rebuild beta before publishing (run.* builds both channels)")

    if os.path.isfile(changelog_json):
        key = "PluginStable" if channel == "stable" else "PluginBeta"
        entries = load_json(changelog_json).get(key) or []
        if not entries:
            problems.append(f"msop-changelog.json has no {key} entries")
        else:
            first = entries[0]
            releases = first.get("DatabaseReleases") or [{}]
            date = releases[0].get("IncludedDatabaseDate") or first.get("ReleaseDatePlugin", "")
            if (first.get("Version"), date) != plugin:
                problems.append(f"msop-changelog.json's first {key} entry reads {first.get('Version')} / {date}, "
                                f"but the {channel} plugin is {plugin[0]} / {plugin[1]}")
    return problems


def ordered_channels(channels):
    """Known channels first in a fixed order, anything else after, so output is deterministic."""
    out = {ch: channels[ch] for ch in CHANNELS if ch in channels}
    out.update({k: v for k, v in channels.items() if k not in out})
    return out


def with_channels(row, channels):
    """The row with "Channels" as its last key (existing key order otherwise kept)."""
    out = {k: v for k, v in row.items() if k != "Channels"}
    out["Channels"] = ordered_channels(channels)
    return out


def sync(games, channel, rom_set, build_date, backfill):
    """Returns (new_games, changes, warnings, errors); never mutates the input."""
    rows = games.get("SupportedGames")
    if not isinstance(rows, list):
        return None, [], [], ["games.json has no SupportedGames list"]

    changes, warnings, errors = [], [], []
    listed = {}
    for row in rows:
        rom = row.get("ROM")
        if rom in listed:
            errors.append(f"ROM '{rom}' is listed twice in games.json")
        listed[rom] = row

    new_rows = []
    for row in rows:
        rom = row.get("ROM")
        channels = dict(row.get("Channels") or {})
        current = channels.get(channel)
        if rom in rom_set:
            if current is None:
                seed = build_date
                if backfill and DATE_RE.match(str(row.get("SupportedDate", ""))):
                    seed = min(row["SupportedDate"], build_date)
                channels[channel] = seed
                changes.append(f" [ADDED]   {rom:<12} {channel} -> {seed}")
            elif not DATE_RE.match(str(current)):
                errors.append(f"ROM '{rom}' has an invalid {channel} date '{current}'")
            elif current > build_date:
                channels[channel] = build_date
                changes.append(f" [CLAMPED] {rom:<12} {channel} {current} -> {build_date} (later than this build)")
        elif current is not None:
            del channels[channel]
            changes.append(f" [REMOVED] {rom:<12} {channel} (no longer in the {channel} database)")
        new_row = with_channels(row, channels) if (channels or "Channels" in row or rom in rom_set) else row
        if not channels:
            warnings.append(f"ROM '{rom}' has no channel recorded yet (apps will hide it)")
        new_rows.append(new_row)

    missing = sorted(rom_set - set(listed))
    if channel == "stable":
        errors.extend(f"ROM '{rom}' is in the stable database but has no games.json row" for rom in missing)
    elif missing:
        warnings.append(f"{len(missing)} ROM(s) in the {channel} database have no games.json row: " + ", ".join(missing))

    new_games = {k: (new_rows if k == "SupportedGames" else v) for k, v in games.items()}
    return new_games, changes, warnings, errors


def render(games):
    return json.dumps(games, indent=4, ensure_ascii=False).replace("\n", EOL)


def main():
    ap = argparse.ArgumentParser(description="Sync games.json Channels from a channel's game database.")
    ap.add_argument("--channel", choices=CHANNELS, default="stable")
    ap.add_argument("--games-json", default=DEFAULT_GAMES_JSON)
    ap.add_argument("--check", action="store_true",
                    help="report only; exit 1 if games.json would change, has errors, or a release check fails")
    ap.add_argument("--backfill", action="store_true", help="seed missing dates from SupportedDate (one-off)")
    args = ap.parse_args()

    print("=" * 70)
    print(f" MSOP GAMES JSON SYNC v{SCRIPT_VERSION} ({SCRIPT_DATE}) - channel: {args.channel}")
    print("=" * 70)

    games_json = os.path.abspath(args.games_json)
    if not os.path.isfile(games_json):
        print(f" games.json not found at {games_json}")
        print(" Skipped - this is a maintainer step; the standalone Database Compiler does not ship games.json.")
        return 0

    try:
        rom_set = channel_database(args.channel)
        plugin = channel_plugin(args.channel)
        if plugin is None:
            raise SyncError(f"the {args.channel} channel has no stateoutput/plugin.json")
        build_date = plugin[1]
        with open(games_json, "rb") as f:
            raw = f.read()
        games = json.loads(raw.decode("utf-8-sig"))
        release = release_checks(args.channel, plugin, os.path.join(os.path.dirname(games_json), "msop-changelog.json"))
    except (SyncError, ValueError, OSError) as e:
        print(f" [ERROR] {e}")
        return 1

    new_games, changes, warnings, errors = sync(games, args.channel, rom_set, build_date, args.backfill)
    (errors if args.check else warnings).extend(f"release check: {p}" for p in release)
    print(f" games.json      : {games_json}")
    print(f" {args.channel:<6} database : {len(rom_set)} enabled ROM(s), plugin {plugin[0]}, datedatabase {build_date}")
    if args.backfill:
        print(" mode            : backfill (missing dates seeded from SupportedDate)")
    print("-" * 70)
    for line in changes:
        print(line)
    for tag, lines in ((" [WARNING] ", warnings), (" [ERROR]   ", errors)):
        for line in lines:
            print(textwrap.fill(line, width=100, initial_indent=tag, subsequent_indent=" " * len(tag)))

    if errors:
        print("-" * 70)
        print(f" {len(errors)} error(s) - games.json left untouched.")
        return 1

    new_text = render(new_games)
    old_text = raw.decode("utf-8-sig")
    changed = new_text != old_text
    print("-" * 70)
    if not changed:
        print(f" games.json already aligned with the {args.channel} database - nothing to write.")
        return 0
    if args.check:
        print(f" --check: games.json would change ({len(changes)} change(s)) - nothing written.")
        return 1
    with open(games_json, "wb") as f:
        f.write(new_text.encode("utf-8"))
    print(f" games.json updated ({len(changes)} change(s)).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
