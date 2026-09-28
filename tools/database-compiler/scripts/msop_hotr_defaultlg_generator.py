#
# MAME STATE OUTPUT PROJECT (MSOP)
# MSOP HOTR defaultLG GENERATOR (Database game config -> Hook Of The Reaper defaultLG/<rom>.txt)
# Compiler Version: 1.1.2
# Compiler Date: 2026.09.04
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#
# Generates a Hook Of The Reaper defaultLG/<rom>.txt mapping file for every MSOP-Plugin-supported
# game, from the game database. Each file tells HOTR how to translate the MSOP plugin's state
# outputs into HOTR gun functions.
#
# Mapping policy:
#   * Player count = resolved MAX_PLAYERS.
#   * Recoil & Reload : ALWAYS, per player -> the dedicated MSOP recoil/reload commands. Never
#                       inferred from ammo (a game can expose several ammo counters).
#   * Ammo   : DISPLAY ONLY (>Display_Ammo), emitted whenever an active ammo output exists.
#   * Life & Damage : always, per player.
#   * LampStart : when a LAMP_START output exists.   * Credits : always.
#
# Output: output/<channel>/defaultLG/<rom>.txt  (CRLF, NO trailing newline). --channel stable|beta
# selects both the input database and this output tree.
# The per-game output derivation is shared with the .ini generator via msop_output_model.
#
# --report proves regeneration parity against the COMMITTED output tree: each game's diff is taken
# against the existing output/<channel>/defaultLG/<rom>.txt BEFORE that file is overwritten, so
# "exact" means the committed corpus already matches the database, and a database edit shows up as
# a named diff (a game with no committed file yet reads "NEW (no reference)").
#

import os
import sys
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from msop_output_model import (  # noqa: E402
    BASE_DIR, resolve_players, supported_roms, load_default, load_game,
    write_lines, diff_summary, set_channel, GameDataError,
)

EOL = "\r\n"  # HOTR reads CRLF; the defaultLG files carry NO trailing newline.

# The [States] block is identical in every file.
HOTR_STATES = [
    "[States]",
    ":mame_start", "*All", ">Open_COM", ">AspectRatio_4:3",
    ":mame_stop", "*All", ">Close_COM",
]


def hotr_lines(game, default):
    active, n = resolve_players(game, default)
    has_ammo = any("AMMO" in active[i] for i in active)          # ammo shown whenever it exists
    has_lamp = any("LAMPSTART" in active[i] for i in active)

    out = ["Players", str(n)]
    out += [f"P{p}" for p in range(1, n + 1)]
    out += [
        "Recoil & Reload",
        f"Ammo_Value {1 if has_ammo else 0} Ammo_Value",
        "Recoil 1 Reload_Value",
        "Recoil_R2S 0",
        "Recoil_Value 1 Reload_Value",
    ]
    out += HOTR_STATES
    out.append("[Signals]")
    out.append(":MSOP_Credits")
    if has_lamp:
        out += [f":MSOP_P{p}_LampStart" for p in range(1, n + 1)]
    for p in range(1, n + 1):
        if has_ammo:  # DISPLAY ONLY - never drives recoil/reload
            out += [f":MSOP_P{p}_Ammo", f"*P{p}", "#Ammo_Value", "#Reload_Value", ">Display_Ammo"]
        out += [f":MSOP_P{p}_Recoil", f"*P{p}", "#Recoil", "#Recoil_Value"]
        out += [f":MSOP_P{p}_Reload", f"*P{p}", "#Reload", "#Reload_Value"]
        out += [f":MSOP_P{p}_Life",   f"*P{p}", ">Display_Life", ">Death_Value"]
        out += [f":MSOP_P{p}_Damage", f"*P{p}", ">Damage"]
    return out


def main():
    ap = argparse.ArgumentParser(description="Generate HOTR defaultLG templates from the MSOP database.")
    ap.add_argument("--channel", choices=("stable", "beta"), default="stable",
                    help="which channel's database to read and where to write (default: stable)")
    ap.add_argument("--report", action="store_true",
                    help="diff every generated file against its committed copy in the output tree "
                         "(the diff is taken before the file is overwritten)")
    ap.add_argument("--rom", help="restrict to a single rom name")
    args = ap.parse_args()

    set_channel(args.channel)
    out_dir = os.path.join(BASE_DIR, "output", args.channel, "defaultLG")

    try:
        default = load_default()
    except GameDataError as e:
        print("[ERROR] {}".format(e), file=sys.stderr)
        sys.exit(1)
    os.makedirs(out_dir, exist_ok=True)

    print("=" * 78)
    print("  MSOP HOTR defaultLG GENERATOR")
    print(f"  channel   -> {args.channel}")
    print(f"  defaultLG -> {out_dir}")
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
        lines = hotr_lines(game, default)
        out_path = os.path.join(out_dir, rom + ".txt")
        if args.report:
            # The reference is the committed copy of this same file, so the diff MUST be taken
            # before write_lines overwrites it - otherwise every game compares to itself.
            d = diff_summary(EOL.join(lines), out_path)
        write_lines(out_path, lines, EOL, trailing=False)
        written += 1
        if args.report:
            exact += (d is None)
            print(f"  {rom:12s} {'exact' if d is None else d}")
        else:
            print(f"  --- {rom} -> defaultLG ---")

    print("-" * 78)
    if args.report:
        print(f"  {exact}/{written} exact vs the committed output tree")
    print(f"  Generated {written} defaultLG file(s).")


if __name__ == "__main__":
    main()
