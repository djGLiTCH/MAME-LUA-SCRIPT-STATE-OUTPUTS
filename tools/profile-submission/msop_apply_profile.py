#
# MAME STATE OUTPUT PROJECT (MSOP)
# MSOP APPLY PROFILE (submitted game profile -> beta game database)
# Script Version: 1.0.0
# Script Date: 2026.10.19
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#
# Checks a game profile attached to a Game Profile Submission issue and places it in the beta game
# database. It is a maintainer tool: it is not part of the MSOP Database Compiler download.
#
#     python msop_apply_profile.py <rom>.json [--rom <name>] [--apply]
#
#   <rom>.json   the downloaded attachment; the ROM name is the file name without .json
#   --rom        the ROM name, when the downloaded file was renamed
#   --apply      write the profile to input/beta/database/games/<GAME_TYPE>/<rom>.json
#
# The checks:
#   * the file is one JSON object with no duplicate keys;
#   * the ROM name is a MAME short name (lower-case letters, digits and underscores, 16 at most);
#   * ENABLE_ROM is true and LUA_GAME is set;
#   * GAME_TYPE, if given, is lightgun, racing or both;
#   * a lightgun or both profile gives a STATUS or LIFE address for at least one player, and a
#     racing profile has an FFB block with ENABLED true;
#   * the ROM is not already in the stable database, nor in beta under another GAME_TYPE folder.
# A setting that _default.json does not know is a warning, not a failure.
#
# Without --apply nothing is written. The result is reported as new, changed (with the settings
# that differ) or same against the beta profile.
#
# Exit codes: 0 the profile passes (and was written with --apply), 1 a check failed, 2 bad usage.
#

import argparse
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
COMPILER_DIR = os.path.join(os.path.dirname(HERE), "database-compiler")
GAMES_DIR = os.path.join(COMPILER_DIR, "input", "{channel}", "database", "games")
GAME_TYPES = ("lightgun", "racing", "both")
PLAYERS = ("P1", "P2", "P3", "P4")
ROM_NAME = re.compile(r"^[a-z0-9_]{1,16}$")


def load_reject_duplicate_keys():
    """Reuses the compiler's duplicate-key hook, so a submission is parsed exactly as a build
    parses it."""
    path = os.path.join(COMPILER_DIR, "scripts", "msop_database_compiler.py")
    spec = importlib.util.spec_from_file_location("msop_database_compiler", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.reject_duplicate_keys


def is_set(value):
    """A setting counts as given unless it is absent, false, null or an empty string."""
    return value not in (None, False, "")


def find_profiles(channel, rom):
    """Every <rom>.json in a channel's games folder, as paths relative to it."""
    root = GAMES_DIR.format(channel=channel)
    found = []
    for dirpath, _, filenames in os.walk(root):
        if rom + ".json" in filenames:
            found.append(os.path.relpath(os.path.join(dirpath, rom + ".json"), root).replace(os.sep, "/"))
    return sorted(found)


def unknown_settings(profile, default):
    """Settings in the profile that _default.json does not have, as "KEY" or "P1.KEY"."""
    known_player = set()
    for player in PLAYERS:
        known_player.update(default.get(player, {}) or {})
    unknown = []
    for key, value in profile.items():
        if key.endswith("_comment"):
            continue
        if key not in default:
            unknown.append(key)
        elif key in PLAYERS and isinstance(value, dict):
            unknown.extend(f"{key}.{k}" for k in value if not k.endswith("_comment") and k not in known_player)
    return unknown


def differences(old, new):
    """Top-level and per-player settings whose values differ between two profiles."""
    changed = []
    for key in sorted(set(old) | set(new)):
        a, b = old.get(key), new.get(key)
        if key in PLAYERS and isinstance(a, dict) and isinstance(b, dict):
            changed.extend(f"{key}.{k}" for k in sorted(set(a) | set(b)) if a.get(k) != b.get(k))
        elif a != b:
            changed.append(key)
    return changed


def main():
    ap = argparse.ArgumentParser(description="Check a submitted game profile and place it in the beta database.")
    ap.add_argument("file")
    ap.add_argument("--rom")
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()

    if not os.path.isfile(a.file):
        print(f"[ERROR] File not found: {a.file}")
        return 2
    rom = a.rom or os.path.splitext(os.path.basename(a.file))[0]
    errors, warnings = [], []

    reject_duplicate_keys = load_reject_duplicate_keys()
    try:
        with open(a.file, "r", encoding="utf-8-sig") as f:
            profile = json.load(f, object_pairs_hook=reject_duplicate_keys)
    except (ValueError, UnicodeDecodeError) as e:
        print(f"[ERROR] {os.path.basename(a.file)} is not valid JSON: {e}")
        return 1
    if not isinstance(profile, dict):
        print("[ERROR] The file must hold one JSON object.")
        return 1

    with open(os.path.join(GAMES_DIR.format(channel="beta"), "_default.json"), "r", encoding="utf-8") as f:
        default = json.load(f)

    if not ROM_NAME.match(rom):
        errors.append(f"'{rom}' is not a MAME short name (lower-case letters, digits and underscores, 16 at most).")
    if profile.get("ENABLE_ROM") is not True:
        errors.append("ENABLE_ROM must be true.")
    if not isinstance(profile.get("LUA_GAME"), str) or not profile["LUA_GAME"].strip():
        errors.append("LUA_GAME must name the game.")

    game_type = profile.get("GAME_TYPE", default.get("GAME_TYPE", "lightgun"))
    if game_type not in GAME_TYPES:
        errors.append(f"GAME_TYPE '{game_type}' is not one of {', '.join(GAME_TYPES)}.")
    elif game_type == "racing":
        ffb = profile.get("FFB")
        if not isinstance(ffb, dict) or ffb.get("ENABLED") is not True:
            errors.append("A racing profile needs an FFB block with ENABLED true.")
    else:
        players = [p for p in PLAYERS if isinstance(profile.get(p), dict)
                   and (is_set(profile[p].get("STATUS")) or is_set(profile[p].get("LIFE")))]
        if not players:
            errors.append("At least one player needs a STATUS or LIFE address.")

    unknown = unknown_settings(profile, default)
    if unknown:
        warnings.append("Settings _default.json does not know: " + ", ".join(unknown))

    target = f"{game_type}/{rom}.json"
    in_stable = find_profiles("stable", rom)
    in_beta = find_profiles("beta", rom)
    if in_stable:
        errors.append(f"{rom} is already in the stable database ({', '.join(in_stable)}). "
                      "A change to it belongs in an Existing Game / ROM Profile Correction issue.")
    others = [p for p in in_beta if p != target]
    if others:
        errors.append(f"{rom} is already in the beta database as {', '.join(others)}; "
                      f"a second copy at {target} would list the ROM twice.")

    status = "new"
    target_path = os.path.join(GAMES_DIR.format(channel="beta"), *target.split("/"))
    if target in in_beta:
        with open(target_path, "r", encoding="utf-8") as f:
            changed = differences(json.load(f), profile)
        status = "changed: " + ", ".join(changed) if changed else "same"

    print(f"\nProfile : {rom} ({profile.get('LUA_GAME', '?')})")
    print(f"Target  : input/beta/database/games/{target}")
    print(f"Status  : {status}")
    for w in warnings:
        print(f"[WARNING] {w}")
    for e in errors:
        print(f"[ERROR] {e}")
    if errors:
        print("\nThe profile was not written.")
        return 1

    if a.apply and status != "same":
        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        with open(target_path, "w", encoding="utf-8", newline="\r\n") as f:
            f.write(json.dumps(profile, indent=4) + "\n")
        print(f"\nWritten to input/beta/database/games/{target}.")
    elif not a.apply:
        print("\nThe profile passes. Run again with --apply to write it.")

    print("\nStill to do by hand:")
    print("  1. Add the ROM's row to updates/msop-games.json.")
    print("  2. Add a line for the ROM to the database record in updates/msop-changelog.json,")
    print("     with the credit from the issue.")
    print("  3. Rebuild the beta channel (run_beta.bat or run_beta.sh in tools/database-compiler/scripts).")
    print("  4. Move the profile to stable once it has been played on Beta.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
