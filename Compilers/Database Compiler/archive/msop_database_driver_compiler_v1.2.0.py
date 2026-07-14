#
# MAME STATE OUTPUT PROJECT (MSOP)
# MSOP DATABASE DRIVER COMPILER
# Compiler Version: 1.2.0
# Compiler Date: 2026.07.05
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#
# Scrapes a MAME source checkout for NATIVE output names (outputs a game
# driver's own C++ creates - e.g. "recoil0", "lamp0", "Player1_Gun_Recoil" -
# as opposed to anything MSOP's Lua plugin creates itself) and compiles them
# into database_driver.lua, a companion file to database.lua that init.lua
# loads and merges with database.lua's own (hand-curated, never touched by
# this tool) ADDITIONAL_OUTPUT_FORWARDS field.
#
# Deliberately a SEPARATE tool from msop_database_compiler.py: that compiler
# only needs game_json/ and has no MAME-source dependency at all, so anyone
# without a local MAME checkout can still compile database.lua/database.json
# normally. This tool is the only one that needs a MAME source checkout, and
# running it is entirely optional - database_driver.lua degrades to "no
# native output forwarding" gracefully if it's missing or stale, it's never
# load-bearing for anything else the plugin does.
#
# Unlike game_json/ (which always lives at a fixed location relative to this
# script), a MAME checkout could be anywhere on the user's disk, so there's
# no equivalent auto-detection possible for it. Instead, see
# resolve_mame_src(): --mame-src on the command line always wins if given;
# otherwise the MAME_SRC_PATH constant just below is used. There is no
# external config file - MAME_SRC_PATH is meant to be edited directly in
# this script, once, by whoever's running it.
#
# The native output names this tool identifies come from scripted analysis
# of MAME's own source code (https://github.com/mamedev/mame), a separate
# project not affiliated with MSOP. MAME is free software distributed under
# the GNU General Public License v2.0 or later; the large majority of
# individual files, including the driver files this tool reads, are
# separately licensed under the 3-Clause BSD License. Full license terms:
# https://github.com/mamedev/mame/blob/master/COPYING - "MAME" is a
# registered trademark of Gregory Ember, referenced throughout this script
# solely to describe what it reads and where its data comes from, not to
# imply any endorsement or affiliation.
#
# Method: one pass over every driver .cpp collects, per ROM name, which
# GAME()/GAMEL() macro line named it - giving the driver file, the C++ state
# class used, and (if the macro's last argument is layout_X) its layout file.
# Then, per ROM: the driver file (+ matching .h, since MAME sometimes
# declares an output_finder<> field in one and initializes it in the other)
# is scanned for output_finder<N> field declarations and their constructor-
# initializer-list name patterns ("foo%u", start index N), cross-referenced
# by field name and expanded into concrete candidate names; separately, any
# resolved .lay layout file is scanned for view-placed elements with a name=
# attribute (verified against MAME's own layout parser - src/emu/rendlay.cpp:
# `m_output_name = env.get_attribute_string(itemnode, "name")`, later used to
# construct a real output_proxy; elements with only ref=, no name=, are pure
# decoration and correctly excluded).
#
# This is a regex heuristic over real C++, not a compiler - it will miss
# unusual formatting and can occasionally cross-attribute a field from a
# different class in the same file. There's no risk to over-including a
# candidate that turns out not to apply to a given ROM though: the Lua
# runtime side (Forward_Native_Outputs in init.lua) only ever forwards a
# name if MAME's own output table confirms it actually exists for the
# machine that's currently running - an absent name is a one-time no-op at
# first lookup, cached, never sent, never an error.
#
# Default mode is report-only. Pass --apply to write database_driver.lua
# directly: every ROM found (via game_json/ or --rom) gets its entry
# unconditionally overwritten with exactly what this run found - not merged
# with whatever was there before. Re-running this after MAME's source or
# MSOP's game list changes reproduces the same result from scratch every
# time, without anyone needing to hand-curate which candidates look right.
#

import argparse
import importlib.util
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime

# SMART PATH AUTO-DETECTION (matches msop_database_compiler.py's convention).
# Only used to discover which ROMs to scrape for - this tool never writes
# into game_json/.
if os.path.exists("game_json") and os.path.isdir("game_json"):
    DEFAULT_GAME_JSON_DIR = "game_json"
    DEFAULT_OUTPUT_DIR = "."
elif os.path.isdir(os.path.join("stateoutput", "game_json")):
    DEFAULT_GAME_JSON_DIR = os.path.join("stateoutput", "game_json")
    DEFAULT_OUTPUT_DIR = "stateoutput"
else:
    DEFAULT_GAME_JSON_DIR = None
    DEFAULT_OUTPUT_DIR = "stateoutput"

OUTPUT_LUA = "database_driver.lua"

# KEEP IN SYNC with the header comment above - stamped into
# database_driver.lua's own generated header so a compiled file can be
# traced back to the exact compiler version that produced it.
COMPILER_VERSION = "1.2.0"

# Set this to your local MAME source checkout's path (the folder that
# contains src/mame/), e.g. r"C:\Users\me\mame" or "/home/me/mame", so you
# don't have to pass --mame-src every time. Leave empty to require
# --mame-src on every run instead.
MAME_SRC_PATH = r"C:\msys64\home\djgli\mame"

# MAME's GAME()/GAMEL() driver-table entries have NO trailing semicolon -
# they're consecutive macro invocations expanding into a designated-initializer
# table, one entry per physical line in every real example checked. Matched
# per line (MULTILINE, anchored to line-end) with a GREEDY capture so a
# closing paren embedded in a quoted description (e.g. "Action (F2)") doesn't
# truncate the match early - the real end of the call is the LAST `)` on the
# line, not the first. Entries routinely carry trailing comments after that
# closing paren in more than one style - a bare "// <build date>" (timecris,
# namcos22.cpp), or a "/* 004 */ // <note>" combination (bbust2, hng64.cpp) -
# so rather than special-casing comment syntax, anything at all is allowed to
# follow the closing paren up to end of line.
GAME_MACRO_RE = re.compile(r"^\s*GAMEL?\s*\((.*)\)[^\n]*$", re.MULTILINE)

# output_finder<N> field_name;  (N empty => single output, not an array)
OUTPUT_FINDER_DECL_RE = re.compile(r"\boutput_finder<(\d*)>\s+(\w+)\s*;")

# field_name(*this, "pattern"[, start_index[U]])  - constructor-initializer-list
# form used to actually bind the field to a name/index at runtime.
OUTPUT_FINDER_INIT_RE = re.compile(
    r'\b(\w+)\(\*this,\s*"([^"]+)"\s*(?:,\s*(\d+)U?)?\)'
)


def _load_format_lua_value():
    """Reuses msop_database_compiler.py's Lua-table formatter (same
    directory) instead of reimplementing it, so database_driver.lua and
    database.lua always share identical formatting conventions."""
    compiler_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "msop_database_compiler.py"
    )
    spec = importlib.util.spec_from_file_location("msop_database_compiler", compiler_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.format_lua_value


def get_supported_roms(game_json_dir):
    """Every *.json in game_json/ except _default.json and any _-prefixed template."""
    roms = []
    for name in sorted(os.listdir(game_json_dir)):
        if not name.endswith(".json"):
            continue
        stem = name[:-5]
        if stem.startswith("_"):
            continue
        roms.append(stem)
    return roms


def _read_text(path):
    """Best-effort text read - returns "" instead of raising on any I/O
    error, so one unreadable file during the driver-tree walk doesn't abort
    the whole scrape."""
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read()
    except OSError:
        return ""


def resolve_mame_src(cli_value):
    """Figures out which MAME source checkout to scan, in priority order:
      1. --mame-src on the command line, if given - a one-off override for
         this run only, doesn't touch MAME_SRC_PATH above.
      2. MAME_SRC_PATH, the constant near the top of this script - the
         intended way to configure this permanently: open this file in a
         text editor, fill it in once, save. There is deliberately no
         external config file and no interactive prompt for this - the
         script's own source is the single place this is expected to live.
    Returns a validated path (confirmed to contain a src/mame/ subfolder);
    exits with a clear error message on stderr if neither source is usable."""

    def looks_valid(path):
        return bool(path) and os.path.isdir(os.path.join(path, "src", "mame"))

    if cli_value:
        if not looks_valid(cli_value):
            print(
                f"ERROR: '{cli_value}' doesn't look like a MAME source "
                f"checkout (expected a src/mame/ subfolder).",
                file=sys.stderr,
            )
            sys.exit(1)
        return cli_value

    if looks_valid(MAME_SRC_PATH):
        return MAME_SRC_PATH

    print(
        "ERROR: no MAME source checkout path is configured.\n"
        "Either pass --mame-src \"<path>\" on the command line, or open "
        "this script (msop_database_driver_compiler.py) and set "
        "MAME_SRC_PATH near the top of the file to your local MAME source "
        "checkout's path, then save and re-run.",
        file=sys.stderr,
    )
    sys.exit(1)


def build_rom_driver_index(mame_src):
    """One pass over every driver .cpp for GAME()/GAMEL() macro invocations.
    Returns {rom_name: {"file": path, "class": state_class_name, "layout": path_or_None}}.
    Built once up front rather than re-scanning per ROM - MAME's driver tree
    is large enough that doing this per-lookup would be needlessly slow
    across even a few dozen ROMs.

    Note: a MAME "parent" ROM name (used only as the 3rd argument of some
    OTHER entry's GAME() line, e.g. "ptblank2") may never appear as an
    entry's own 2nd argument at all, if every real dump is a "clone" of it -
    such a parent will not show up in this index, since it was never itself
    launchable. Its clones (e.g. ptblank2a, ptblank2ua) will."""
    index = {}
    mame_dir = os.path.join(mame_src, "src", "mame")
    for dirpath, _, filenames in os.walk(mame_dir):
        for fn in filenames:
            if not fn.endswith(".cpp"):
                continue
            path = os.path.join(dirpath, fn)
            text = _read_text(path)
            if not text:
                continue

            for m in GAME_MACRO_RE.finditer(text):
                tokens = [t.strip() for t in m.group(1).split(",")]
                if len(tokens) < 6:
                    continue
                rom_name = tokens[1]
                if rom_name in index:
                    continue

                layout = None
                layout_m = re.match(r"layout_(\w+)$", tokens[-1])
                if layout_m:
                    candidate = os.path.join(
                        mame_src, "src", "mame", "layout", layout_m.group(1) + ".lay"
                    )
                    if os.path.isfile(candidate):
                        layout = candidate

                index[rom_name] = {
                    "file": path,
                    "class": tokens[5],
                    "layout": layout,
                }
    return index


def find_output_finder_names(driver_file):
    """Finds every output_finder<> field declared+initialized reachable from
    driver_file, plus a same-named header in the same directory if one
    exists (MAME sometimes declares the field in the .h and initializes it
    in the .cpp's constructor, or vice versa - both need checking). Returns
    a list of (field_name, [candidate output names])."""
    text = _read_text(driver_file)
    header = os.path.splitext(driver_file)[0] + ".h"
    if os.path.isfile(header):
        text += "\n" + _read_text(header)

    declared = {}  # field name -> count (None = single output, not an array)
    for m in OUTPUT_FINDER_DECL_RE.finditer(text):
        count_str, field = m.groups()
        declared[field] = int(count_str) if count_str else None

    results = []
    seen_fields = set()
    for m in OUTPUT_FINDER_INIT_RE.finditer(text):
        field, pattern, start = m.groups()
        if field not in declared or field in seen_fields:
            continue
        seen_fields.add(field)

        count = declared[field]
        start_idx = int(start) if start else 0
        py_pattern = pattern.replace("%u", "%d")
        if count and "%" in py_pattern:
            names = [py_pattern % (start_idx + i) for i in range(count)]
        else:
            names = [pattern]
        results.append((field, names))
    return results


def extract_layout_output_names(lay_path):
    """Walk every <view> subtree and collect the `name` attribute of any
    element that has one - see module docstring for why this is the correct
    (source-verified) rule for "is this a live output, not decoration"."""
    try:
        tree = ET.parse(lay_path)
    except ET.ParseError as e:
        return None, f"XML parse error: {e}"

    names = []
    seen = set()
    for view in tree.getroot().iter("view"):
        for node in view.iter():
            name = node.get("name")
            if name and name not in seen:
                seen.add(name)
                names.append(name)
    return names, None


def flatten_candidates(candidates):
    """Merges output_finder + layout candidates for one ROM into a single
    deduped, order-preserving list - the exact value database_driver.lua's
    entry for this ROM gets set to under --apply."""
    names = []
    seen = set()
    for group in candidates.get("output_finder", []):
        for n in group["names"]:
            if n not in seen:
                seen.add(n)
                names.append(n)
    for n in candidates.get("layout", []):
        if n not in seen:
            seen.add(n)
            names.append(n)
    return names


def write_database_driver_lua(output_dir, driver_data):
    """Writes database_driver.lua: {rom_name -> [output names]}, in the same
    sorted-key / format_lua_value style as database.lua's own build_lua_string,
    via _load_format_lua_value() so both files always format identically."""
    format_lua_value = _load_format_lua_value()

    lines = ["local database_driver = {"]
    for rom_name in sorted(driver_data.keys()):
        lines.append(f'    ["{rom_name}"] = {format_lua_value(driver_data[rom_name], 1)},')
    lines.append("}\n\nreturn database_driver\n")

    COMPILER_DATE = datetime.now().strftime("%Y.%m.%d")
    header = (
        "--\n-- MAME STATE OUTPUT PROJECT (MSOP)\n"
        "-- MSOP DATABASE DRIVER LUA\n"
        f"-- Compiler Version: {COMPILER_VERSION}\n"
        f"-- Compiled Date: {COMPILER_DATE}\n"
        "-- Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS\n"
        "-- License: GNU GENERAL PUBLIC LICENSE GPL-v3.0\n"
        "-- Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.\n--\n"
        "-- Auto-generated by msop_database_driver_compiler.py from a MAME source\n"
        "-- checkout - DO NOT HAND-EDIT. Re-run that script to regenerate. Manual\n"
        "-- additions belong in database.lua's own ADDITIONAL_OUTPUT_FORWARDS field\n"
        "-- instead (see init.lua's Forward_Native_Outputs, which merges both).\n--\n"
        "-- The output names below were identified by scripted analysis of MAME's\n"
        "-- own source code (https://github.com/mamedev/mame), a separate project\n"
        "-- not affiliated with MSOP. MAME is free software distributed under the\n"
        "-- GNU General Public License v2.0 or later; the large majority of\n"
        "-- individual files, including the driver files this data was read from,\n"
        "-- are separately licensed under the 3-Clause BSD License. Full license\n"
        "-- terms: https://github.com/mamedev/mame/blob/master/COPYING - \"MAME\" is\n"
        "-- a registered trademark of Gregory Ember, referenced here solely to\n"
        "-- describe this data's source, not to imply endorsement or affiliation.\n--\n\n"
    )

    os.makedirs(output_dir, exist_ok=True)
    out_path = os.path.join(output_dir, OUTPUT_LUA)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(header + "\n".join(lines))
    return out_path


def print_summary(mame_src, report, applied, report_path, out_path):
    """Prints the end-of-run console report in the same bordered, aligned
    style as msop_database_compiler.py's own print_summary, so success/
    failure is equally easy to read at a glance for both tools. Recomputes
    every count directly from `report` (rather than trusting counters
    accumulated during the scan loop) so this can never drift out of sync
    with what's actually in it."""
    total = len(report)
    not_found = sum(1 for r in report.values() if "note" in r)
    found = total - not_found
    with_candidates = sum(
        1 for r in report.values()
        if "note" not in r and flatten_candidates(r["candidates"])
    )
    no_candidates = found - with_candidates

    print("\n" + "=" * 70)
    print(" NATIVE OUTPUT SCRAPE SUMMARY")
    print("=" * 70)
    print(f" Compiler Version         : {COMPILER_VERSION}")
    print(f" MAME Source              : {mame_src}")
    print("-" * 70)
    print(f" ROMs Checked             : {total}")
    if total:
        found_pct = (found / total) * 100
        notfound_pct = (not_found / total) * 100
        print(f" Found In Driver Tree     : {found} ({found_pct:.1f}%)")
        print(f" Not Found In Driver Tree : {not_found} ({notfound_pct:.1f}%)")
        print(f" With Candidate(s)        : {with_candidates}")
        print(f" With No Candidates       : {no_candidates}")
    else:
        print(" No ROMs were checked.")
    print("-" * 70)
    print(f" Report File              : {report_path}")
    if applied:
        print(f" database_driver.lua      : Written -> {out_path}")
    else:
        print(f" database_driver.lua      : Not written (report-only - re-run with --apply)")
    print("=" * 70 + "\n")


def main():
    compiler_date = datetime.now().strftime("%Y.%m.%d")
    
    print("-" * 70)
    print("MAME STATE OUTPUT PROJECT (MSOP)".center(70))
    print("MSOP DATABASE DRIVER COMPILER".center(70))
    print("-" * 70)
    print(f" Compiler Version: {COMPILER_VERSION}")
    print(f" Compiler Date: {compiler_date}\n")
    print(" Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS")
    print(" License: GNU GENERAL PUBLIC LICENSE GPL-v3.0")
    print(" Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.")
    print("-" * 70)

    parser = argparse.ArgumentParser(
        description="Scrape a MAME source checkout for native output names per "
        "MSOP-supported ROM and compile database_driver.lua. Report-only by "
        "default; pass --apply to write the file for real."
    )
    parser.add_argument(
        "--mame-src",
        default=None,
        help="Path to a MAME source checkout (must contain src/mame/). "
        "Optional - if omitted, falls back to the MAME_SRC_PATH constant "
        "near the top of this script.",
    )
    parser.add_argument(
        "--game-json-dir",
        default=DEFAULT_GAME_JSON_DIR,
        help="Path to MSOP's game_json directory, used only to discover which "
        "ROMs to scrape for (auto-detected if omitted)",
    )
    parser.add_argument(
        "--output-dir",
        default=DEFAULT_OUTPUT_DIR,
        help="Directory to write database_driver.lua into under --apply "
        "(auto-detected to match msop_database_compiler.py's own convention)",
    )
    parser.add_argument(
        "--rom",
        action="append",
        default=None,
        help="Check one specific ROM name instead of every supported ROM "
        "(repeatable). Useful for validating a game that isn't in game_json/ "
        "yet, e.g. --rom ptblank2a",
    )
    parser.add_argument(
        "--out", default="native_output_scrape_report.json", help="Report output path"
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Write database_driver.lua directly (unconditional, deterministic "
        "- every processed ROM's entry is this run's findings, not merged with "
        "prior content). Without this flag, nothing is written except the report.",
    )
    args = parser.parse_args()

    mame_src = resolve_mame_src(args.mame_src)

    if args.rom:
        roms = args.rom
    else:
        if not args.game_json_dir or not os.path.isdir(args.game_json_dir):
            print(
                "ERROR: could not locate game_json/ - pass --game-json-dir or --rom explicitly.",
                file=sys.stderr,
            )
            sys.exit(1)
        roms = get_supported_roms(args.game_json_dir)

    print(f"\n Target MAME Source Directory: {mame_src}")
    print(" Building ROM->driver index (one pass over src/mame/**/*.cpp)...")
    driver_index = build_rom_driver_index(mame_src)
    print(f" Indexed {len(driver_index)} ROM(s) total across the driver tree.\n")

    report = {}

    for rom in roms:
        entry = driver_index.get(rom)
        if not entry:
            report[rom] = {"note": "ROM not found as a launchable GAME()/GAMEL() entry - "
                                    "check the exact ROM short name (a MAME 'parent' label "
                                    "used only as another entry's parent, like ptblank2, "
                                    "may never appear as its own entry)"}
            print(f"  {rom}: not found in driver tree")
            continue

        candidates = {"output_finder": [], "layout": []}

        for field, names in find_output_finder_names(entry["file"]):
            candidates["output_finder"].append({"field": field, "names": names})

        if entry["layout"]:
            names, err = extract_layout_output_names(entry["layout"])
            if err:
                candidates["layout_error"] = err
            elif names:
                candidates["layout"] = names

        total = sum(len(g["names"]) for g in candidates["output_finder"]) + len(candidates["layout"])
        report[rom] = {
            "driver_file": os.path.relpath(entry["file"], mame_src),
            "class": entry["class"],
            "layout_file": os.path.relpath(entry["layout"], mame_src) if entry["layout"] else None,
            "candidates": candidates,
        }

        if total:
            of_summary = ", ".join(f'{g["field"]}={g["names"]}' for g in candidates["output_finder"])
            print(f"  {rom}: {total} candidate(s) - {of_summary or '(layout only)'}")
        else:
            print(f"  {rom}: driver found ({os.path.basename(entry['file'])}) but no output_finder<>/layout candidates")

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=4)

    if not args.apply:
        print_summary(mame_src, report, applied=False, report_path=args.out, out_path=None)
        return

    driver_data = {
        rom: flatten_candidates(entry["candidates"])
        for rom, entry in report.items()
        if "note" not in entry
    }
    out_path = write_database_driver_lua(args.output_dir, driver_data)
    print_summary(mame_src, report, applied=True, report_path=args.out, out_path=out_path)


if __name__ == "__main__":
    main()
