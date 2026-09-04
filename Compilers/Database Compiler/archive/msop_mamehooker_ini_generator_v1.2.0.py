#
# MAME STATE OUTPUT PROJECT (MSOP)
# MSOP MAMEhooker INI GENERATOR (Database game config -> MAMEhooker <rom>.ini skeletons)
# Compiler Version: 1.2.0
# Compiler Date: 2026.09.04
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#
# Generates an empty MAMEhooker-style <rom>.ini for every MSOP-Plugin-supported game, from the game
# database. Each file is a blank [General]/[KeyStates]/[Output] skeleton whose [Output] section is
# prepopulated with every MSOP output the game emits (values left blank, ready for the user to fill
# in hardware commands).
#
# The [Output] set is the authoritative per-game output set (mirrors init.lua), minus
# System_AspectRatio (a plugin directive, not a MAME output). The derivation is shared with the HOTR
# defaultLG generator via msop_output_model. By DEFAULT the skeleton ALSO includes the scraped MAME
# native outputs from native_outputs_by_rom.lua (matching the shipped full build, which forwards
# them at runtime); if that file is absent, the run header notes it and the natives are simply
# omitted. Pass --exclude-driver for a deliberately MSOP-only skeleton: just the plugin's own MSOP
# state outputs (+ each game's curated ADDITIONAL_OUTPUT_FORWARDS).
#
# Output: output/<channel>/ini/<rom>.ini  (CRLF, WITH a trailing newline). --channel stable|beta
# selects both the input database and this output tree.
#
# --report proves regeneration parity against the COMMITTED output tree: each game's diff is taken
# against the existing output/<channel>/ini/<rom>.ini BEFORE that file is overwritten, so "exact"
# means the committed corpus already matches the database, and a database edit shows up as a named
# diff (a game with no committed file yet reads "NEW (no reference)").
#

import os
import sys
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from msop_output_model import (  # noqa: E402
    BASE_DIR, build_outputs, load_driver_natives, supported_roms, load_default, load_game,
    write_lines, diff_summary, set_channel, GameDataError,
)

EOL = "\r\n"  # MAMEhooker reads CRLF; the skeletons carry a trailing newline.

# Fixed sections. System_AspectRatio is a plugin directive, not a MAME output, so it is excluded
# from [Output].
INI_FIXED = [
    "[General]", "MameStart=", "MameStop=", "StateChange=", "OnRotate=", "OnPause=",
    "", "[KeyStates]", "RefreshTime=33",
    "", "[Output]",
]
INI_OUTPUT_EXCLUDE = {"System_AspectRatio"}


def ini_lines(game, default, natives):
    keys = [k for k in build_outputs(game, default, natives) if k not in INI_OUTPUT_EXCLUDE]
    return list(INI_FIXED) + [f"{k}=" for k in keys], len(keys)


def main():
    ap = argparse.ArgumentParser(description="Generate MAMEhooker .ini skeletons from the MSOP database.")
    ap.add_argument("--channel", choices=("stable", "beta"), default="stable",
                    help="which channel's database to read and where to write (default: stable)")
    ap.add_argument("--exclude-driver", action="store_true",
                    help="EXCLUDE the scraped MAME native outputs from [Output] (MSOP-only skeleton: just the "
                         "plugin's own MSOP state outputs + each game's curated ADDITIONAL_OUTPUT_FORWARDS). "
                         "By default the natives from native_outputs_by_rom.lua are included whenever that file exists")
    ap.add_argument("--report", action="store_true",
                    help="diff every generated file against its committed copy in the output tree "
                         "(the diff is taken before the file is overwritten)")
    ap.add_argument("--rom", help="restrict to a single rom name")
    args = ap.parse_args()

    set_channel(args.channel)
    out_dir = os.path.join(BASE_DIR, "output", args.channel, "ini")

    try:
        default = load_default()
    except GameDataError as e:
        print("[ERROR] {}".format(e), file=sys.stderr)
        sys.exit(1)
    natives = {} if args.exclude_driver else load_driver_natives()
    if args.exclude_driver:
        driver_note = "EXCLUDED (--exclude-driver, MSOP-only)"
    elif natives:
        driver_note = "included (default)"
    else:
        driver_note = "NOT FOUND - native_outputs_by_rom.lua is missing, so native outputs are omitted"
    os.makedirs(out_dir, exist_ok=True)

    print("=" * 78)
    print("  MSOP MAMEhooker INI GENERATOR")
    print(f"  channel -> {args.channel}")
    print(f"  driver  -> {driver_note}")
    print(f"  ini     -> {out_dir}")
    print("=" * 78)

    written = exact = 0
    for rom in supported_roms():
        if args.rom and rom != args.rom:
            continue
        try:
            game = load_game(rom)
        except GameDataError as e:
            print("[ERROR] {}".format(e), file=sys.stderr)
            sys.exit(1)
        lines, n_out = ini_lines(game, default, natives.get(rom, []))
        out_path = os.path.join(out_dir, rom + ".ini")
        if args.report:
            # The reference is the committed copy of this same file, so the diff MUST be taken
            # before write_lines overwrites it - otherwise every game compares to itself.
            d = diff_summary(EOL.join(lines) + EOL, out_path)
        write_lines(out_path, lines, EOL, trailing=True)
        written += 1
        if args.report:
            exact += (d is None)
            print(f"  {rom:12s} {'exact' if d is None else d}")
        else:
            print(f"  --- {rom} ({n_out} outputs) -> ini ---")

    print("-" * 78)
    if args.report:
        print(f"  {exact}/{written} exact vs the committed output tree")
    print(f"  Generated {written} ini file(s).")


if __name__ == "__main__":
    main()
