#
# MAME STATE OUTPUT PROJECT (MSOP)
# MSOP MAMEhooker INI GENERATOR (Database game config -> MAMEhooker <rom>.ini skeletons)
# Compiler Version: 1.1.2
# Compiler Date: 2026.07.14
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
# defaultLG generator via msop_output_model. By DEFAULT the skeleton is MSOP-ONLY: it lists only the
# plugin's own MSOP state outputs (+ each game's curated ADDITIONAL_OUTPUT_FORWARDS). Pass --include-driver
# to ALSO include the scraped MAME native outputs from database_driver.lua (matching a plugin that ships it).
#
# Output: output/<channel>/ini/<rom>.ini  (CRLF, WITH a trailing newline - matches the shipped
# skeletons). --channel stable|beta selects both the input database and this output tree.
#

import os
import sys
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from msop_output_model import (  # noqa: E402
    BASE_DIR, REPO_ROOT, build_outputs, load_driver_natives, supported_roms, load_default, load_game,
    write_lines, diff_summary, set_channel,
)

# Shipped skeleton references, for --report.
REF_DIR = os.path.join(REPO_ROOT, "Compilers", "Hooker Compiler", "output", "ini", "MAME_MSOP_Plugin")
EOL = "\r\n"  # MAMEhooker reads CRLF; the shipped skeletons have a trailing newline.

# Fixed sections. System_AspectRatio is a plugin directive, not a MAME output, so it is excluded
# from [Output] (matches the shipped MAME_MSOP_Plugin skeletons).
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
    ap.add_argument("--include-driver", action="store_true",
                    help="ALSO include the scraped MAME native outputs from database_driver.lua in [Output]. "
                         "By default the skeleton is MSOP-only: just the plugin's own MSOP state outputs "
                         "(+ each game's curated ADDITIONAL_OUTPUT_FORWARDS)")
    ap.add_argument("--report", action="store_true", help="diff every generated file against the shipped references")
    ap.add_argument("--rom", help="restrict to a single rom name")
    args = ap.parse_args()

    set_channel(args.channel)
    out_dir = os.path.join(BASE_DIR, "output", args.channel, "ini")

    default = load_default()
    natives = load_driver_natives() if args.include_driver else {}
    if args.include_driver and not natives:
        print("NOTE: --include-driver was set but database_driver.lua was not found - native driver outputs will be omitted.", file=sys.stderr)
    os.makedirs(out_dir, exist_ok=True)

    print("=" * 78)
    print("  MSOP MAMEhooker INI GENERATOR")
    print(f"  channel -> {args.channel}")
    print(f"  driver  -> {'included' if args.include_driver else 'EXCLUDED (MSOP-only, default)'}")
    print(f"  ini     -> {out_dir}")
    print("=" * 78)

    written = exact = 0
    for rom in supported_roms():
        if args.rom and rom != args.rom:
            continue
        lines, n_out = ini_lines(load_game(rom), default, natives.get(rom, []))
        text = write_lines(os.path.join(out_dir, rom + ".ini"), lines, EOL, trailing=True)
        written += 1
        if args.report:
            d = diff_summary(text, os.path.join(REF_DIR, rom + ".ini"))
            exact += (d is None)
            print(f"  {rom:12s} {'exact' if d is None else d}")
        else:
            print(f"  --- {rom} ({n_out} outputs) -> ini ---")

    print("-" * 78)
    if args.report:
        print(f"  {exact}/{written} exact vs references")
    print(f"  Generated {written} ini file(s).")


if __name__ == "__main__":
    main()
