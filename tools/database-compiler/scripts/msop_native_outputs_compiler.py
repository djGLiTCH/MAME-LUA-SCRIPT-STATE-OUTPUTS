#
# MAME STATE OUTPUT PROJECT (MSOP)
# MSOP DATABASE DRIVER COMPILER
# Compiler Version: 1.4.2
# Compiler Date: 2026.09.04
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#
# Scrapes a MAME source checkout for NATIVE output names (outputs a game
# driver's own C++ creates - e.g. "recoil0", "lamp0", "Player1_Gun_Recoil" -
# as opposed to anything MSOP's Lua plugin creates itself) and compiles them
# into native_outputs_by_rom.lua, a companion file to database.lua that init.lua
# loads and merges with database.lua's own (hand-curated, never touched by
# this tool) ADDITIONAL_OUTPUT_FORWARDS field.
#
# Deliberately a SEPARATE tool from msop_database_compiler.py: that compiler
# only needs games/ and has no MAME-source dependency at all, so anyone
# without a local MAME checkout can still compile database.lua/database.json
# normally. This tool is the only one that needs a MAME source checkout, and
# running it is entirely optional - native_outputs_by_rom.lua degrades to "no
# native output forwarding" gracefully if it's missing or stale, it's never
# load-bearing for anything else the plugin does.
#
# Unlike games/ (which always lives at a fixed location relative to this
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
# declares an output_finder<> field in one and initialises it in the other)
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
# Every run writes native_outputs_by_rom.lua directly: every ROM found (via games/
# or --rom) gets its entry unconditionally overwritten with exactly what this run
# found - not merged with whatever was there before. Re-running this after MAME's
# source or MSOP's game list changes reproduces the same result from scratch every
# time, without anyone needing to hand-curate which candidates look right. The
# extra mame_driver_native_output_scrape_report.json audit file is written only
# when GENERATE_SCRAPE_REPORT (below) is True (override per run with
# --scrape-report / --no-scrape-report).
#

import argparse
import importlib.util
import json
import os
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime

# KEEP IN SYNC with the header comment above - stamped into
# native_outputs_by_rom.lua's own generated header so a compiled file can be
# traced back to the exact compiler version that produced it.
COMPILER_VERSION = "1.4.2"
COMPILER_DATE = "2026.09.04"
COMPILED_DATE = datetime.now().strftime("%Y.%m.%d")

# PROJECT PATHS (root-anchored via __file__: scripts/ -> parent is the project root, matching
# msop_database_compiler.py). games/ is read only to discover which ROMs to scrape for - this
# tool never writes into it.
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The games list, the deployable plugin folder, and the scrape-report audit all live per release
# channel under input/<channel>/ and output/<channel>/. --channel (default "stable") picks the tree;
# --games-dir / --output-dir / --out still override any of them explicitly for one-off runs.
def channel_games_dir(channel):   return os.path.join(BASE_DIR, "input", channel, "database", "games")
def channel_output_dir(channel):  return os.path.join(BASE_DIR, "output", channel, "stateoutput")   # native_outputs_by_rom.lua
def channel_report_path(channel): return os.path.join(BASE_DIR, "output", channel, "results", "mame_driver_native_output_scrape_report.json")

OUTPUT_LUA = "native_outputs_by_rom.lua"

# v1.4.0 - the DRIVER-keyed companion. output_finder<> fields are declared per driver
# SOURCE FILE, not per ROM (namcos12.cpp declares "Player%u_Gun_Recoil" once and every
# ROM it builds shares it), so keying by driver basename covers every ROM in that file -
# clones, parents that are never launchable in their own right, and any ROM MAME adds to
# an existing driver later - from ~520 entries instead of ~10,000. init.lua looks this up
# via manager.machine.system.source_file when a ROM has no entry of its own, which is what
# lets pass-through mode forward natives for games MSOP has no profile for.
OUTPUT_LUA_MAME_DRIVER = "native_outputs_by_driver.lua"

# Set this to your local MAME source checkout's path (the folder that
# contains src/mame/), e.g. r"C:\Users\me\mame" or "/home/me/mame", so you
# don't have to pass --mame-src every time. Leave empty to require
# --mame-src on every run instead.
MAME_SRC_PATH = r"C:\msys64\home\djgli\mame"

# When True, each run also writes mame_driver_native_output_scrape_report.json -
# a human-readable, per-ROM audit of exactly what was scraped (driver file, C++
# state class, layout file, and every candidate output name). It is purely a
# debugging/auditing aid; native_outputs_by_rom.lua does not depend on it. Set this to
# False to skip creating that file entirely. --scrape-report / --no-scrape-report
# on the command line override this per run. (native_outputs_by_rom.lua is always
# written regardless of this setting.)
GENERATE_SCRAPE_REPORT = True

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
    directory) instead of reimplementing it, so native_outputs_by_rom.lua and
    database.lua always share identical formatting conventions."""
    compiler_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "msop_database_compiler.py"
    )
    spec = importlib.util.spec_from_file_location("msop_database_compiler", compiler_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.format_lua_value


def get_supported_roms(games_dir):
    """Every game JSON under games/ RECURSIVELY (the root plus any subfolders, e.g.
    games/lightgun/ and games/racing/), except _-prefixed templates. Sorted, deduped."""
    roms = set()
    for dirpath, dirnames, filenames in os.walk(games_dir):
        dirnames.sort()
        for name in filenames:
            if not name.endswith(".json"):
                continue
            stem = name[:-5]
            if stem.startswith("_"):
                continue
            roms.add(stem)
    return sorted(roms)


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
        "this script (msop_native_outputs_compiler.py) and set "
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
    """Finds every output_finder<> field declared+initialised reachable from
    driver_file, plus a same-named header in the same directory if one
    exists (MAME sometimes declares the field in the .h and initialises it
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
    deduped, order-preserving list - the exact value native_outputs_by_rom.lua's
    entry for this ROM gets set to."""
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


def build_mame_driver_index(mame_src, progress_every=500):
    """Scrapes EVERY driver .cpp in src/mame/ for output_finder<> names, keyed by the
    driver's basename without extension ("namco/namcos12.cpp" -> "namcos12") - the same
    key MAME itself uses for source/<name>.ini, and what init.lua derives from
    manager.machine.system.source_file.

    Layout-derived names are deliberately NOT merged in here: a .lay file is attached to
    an individual ROM by its GAME()/GAMEL() macro, so it is per-ROM truth and stays in the
    ROM-keyed table. This one carries only what the driver source itself declares, which
    is genuinely shared by every ROM the file builds.

    Files with no output_finder<> at all are omitted entirely rather than written as empty
    tables - an absent key and an empty list mean the same thing to the Lua side, and
    skipping them keeps the emitted file to the ~520 drivers that actually have outputs."""
    index = {}
    mame_dir = os.path.join(mame_src, "src", "mame")
    scanned = 0
    for dirpath, _, filenames in os.walk(mame_dir):
        for fn in sorted(filenames):
            if not fn.endswith(".cpp"):
                continue
            scanned += 1
            if progress_every and scanned % progress_every == 0:
                print(f"   ...scanned {scanned} driver file(s)")
            path = os.path.join(dirpath, fn)
            names, seen = [], set()
            for _field, group in find_output_finder_names(path):
                for n in group:
                    if n not in seen:
                        seen.add(n)
                        names.append(n)
            if names:
                index[os.path.splitext(fn)[0]] = names
    print(f"   scanned {scanned} driver file(s) total")
    return index


def write_native_outputs_by_driver_lua(output_dir, mame_driver_data):
    """Writes native_outputs_by_driver.lua: {driver basename -> [output names]}, in the same
    format as native_outputs_by_rom.lua so both read identically."""
    format_lua_value = _load_format_lua_value()

    lines = ["local native_outputs_by_driver = {"]
    for src_name in sorted(mame_driver_data.keys()):
        lines.append(f'    ["{src_name}"] = {format_lua_value(mame_driver_data[src_name], 1)},')
    lines.append("}\n\nreturn native_outputs_by_driver\n")

    header = (
        "--\n-- MAME STATE OUTPUT PROJECT (MSOP)\n"
        "-- MSOP MAME DATABASE DRIVER (BY SOURCE FILE) LUA\n"
        f"-- Script Version: {COMPILER_VERSION}\n"
        f"-- Script Date: {COMPILER_DATE}\n"
        f"-- Compiled Date: {COMPILED_DATE}\n"
        "-- Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS\n"
        "-- License: GNU GENERAL PUBLIC LICENSE GPL-v3.0\n"
        "-- Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.\n--\n"
        "-- Auto-generated by msop_native_outputs_compiler.py from a MAME source\n"
        "-- checkout - DO NOT HAND-EDIT. Re-run that script to regenerate.\n--\n"
        "-- Keyed by DRIVER SOURCE FILE basename (namco/namcos12.cpp -> \"namcos12\"),\n"
        "-- because MAME declares output_finder<> fields once per driver and every ROM\n"
        "-- that driver builds shares them. init.lua consults this in PASS-THROUGH mode\n"
        "-- (a ROM with no MSOP profile) via manager.machine.system.source_file, after\n"
        "-- first trying native_outputs_by_rom.lua's own per-ROM entry.\n--\n"
        "-- Over-inclusion is safe and expected: a driver may declare outputs a given ROM\n"
        "-- never drives. Forward_Native_Outputs only forwards a name MAME's own output\n"
        "-- table confirms exists for the running machine, and never re-sends an\n"
        "-- unchanged value.\n--\n"
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
    out_path = os.path.join(output_dir, OUTPUT_LUA_MAME_DRIVER)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(header + "\n".join(lines))
    return out_path


def write_native_outputs_by_rom_lua(output_dir, driver_data):
    """Writes native_outputs_by_rom.lua: {rom_name -> [output names]}, in the same
    sorted-key / format_lua_value style as database.lua's own build_lua_string,
    via _load_format_lua_value() so both files always format identically."""
    format_lua_value = _load_format_lua_value()

    lines = ["local native_outputs_by_rom = {"]
    for rom_name in sorted(driver_data.keys()):
        lines.append(f'    ["{rom_name}"] = {format_lua_value(driver_data[rom_name], 1)},')
    lines.append("}\n\nreturn native_outputs_by_rom\n")

    header = (
        "--\n-- MAME STATE OUTPUT PROJECT (MSOP)\n"
        "-- MSOP MAME DATABASE DRIVER LUA\n"
        f"-- Script Version: {COMPILER_VERSION}\n"
        f"-- Script Date: {COMPILER_DATE}\n"
        f"-- Compiled Date: {COMPILED_DATE}\n"
        "-- Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS\n"
        "-- License: GNU GENERAL PUBLIC LICENSE GPL-v3.0\n"
        "-- Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.\n--\n"
        "-- Auto-generated by msop_native_outputs_compiler.py from a MAME source\n"
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


def print_summary(mame_src, report, report_path, out_path):
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
    print(f" native_outputs_by_rom.lua      : {out_path}")
    if report_path:
        print(f" Scrape Report File       : {report_path}")
    else:
        print(f" Scrape Report File       : Not written (scrape report disabled)")
    print("=" * 70 + "\n")


def main():
    
    print("-" * 70)
    print("MAME STATE OUTPUT PROJECT (MSOP)".center(70))
    print("MSOP DATABASE DRIVER COMPILER".center(70))
    print("-" * 70)
    print(f" Script Version: {COMPILER_VERSION}")
    print(f" Script Date: {COMPILER_DATE}")
    print(f" Compiled Date: {COMPILED_DATE}\n")
    print(" Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS")
    print(" License: GNU GENERAL PUBLIC LICENSE GPL-v3.0")
    print(" Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.")
    print("-" * 70)

    parser = argparse.ArgumentParser(
        description="Scrape a MAME source checkout for native output names per "
        "MSOP-supported ROM and (re)compile native_outputs_by_rom.lua on every run. "
        "Also writes an optional scrape-report JSON (see --scrape-report)."
    )
    parser.add_argument(
        "--mame-src",
        default=None,
        help="Path to a MAME source checkout (must contain src/mame/). "
        "Optional - if omitted, falls back to the MAME_SRC_PATH constant "
        "near the top of this script.",
    )
    parser.add_argument(
        "--channel",
        choices=("stable", "beta"),
        default="stable",
        help="Which release channel's tree to read/write: input/<channel>/database/games and "
        "output/<channel>/stateoutput (default: stable). --games-dir/--output-dir/--out override.",
    )
    parser.add_argument(
        "--games-dir",
        default=None,
        help="Path to MSOP's games directory, used only to discover which ROMs to scrape for "
        "(defaults to input/<channel>/database/games)",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Directory to write native_outputs_by_rom.lua into "
        "(defaults to output/<channel>/stateoutput/, the deployable plugin folder)",
    )
    parser.add_argument(
        "--rom",
        action="append",
        default=None,
        help="Check one specific ROM name instead of every supported ROM "
        "(repeatable). Useful for validating a game that isn't in games/ "
        "yet, e.g. --rom ptblank2a",
    )
    parser.add_argument(
        "--out",
        default=None,
        help="Path for the scrape-report JSON (defaults to output/<channel>/results/; only "
        "used when the report is enabled)",
    )
    parser.add_argument(
        "--no-mame-driver-table",
        action="store_true",
        help="Skip building native_outputs_by_driver.lua (the driver-keyed table scraped across "
        "the whole MAME driver tree). That scan is the slow part of a run, so this is useful "
        "when you only want to refresh the per-ROM table.",
    )
    parser.add_argument(
        "--scrape-report",
        action=argparse.BooleanOptionalAction,
        default=GENERATE_SCRAPE_REPORT,
        help="Also write the mame_driver_native_output_scrape_report.json audit "
        "file (use --no-scrape-report to skip it). Defaults to the "
        "GENERATE_SCRAPE_REPORT constant near the top of this script. "
        "native_outputs_by_rom.lua is always written either way.",
    )
    args = parser.parse_args()

    # Any path left unspecified falls back to this channel's tree.
    games_dir  = args.games_dir  or channel_games_dir(args.channel)
    output_dir = args.output_dir or channel_output_dir(args.channel)
    report_out = args.out        or channel_report_path(args.channel)

    mame_src = resolve_mame_src(args.mame_src)

    if args.rom:
        roms = args.rom
    else:
        if not games_dir or not os.path.isdir(games_dir):
            print(
                "ERROR: could not locate games/ - pass --games-dir or --rom explicitly.",
                file=sys.stderr,
            )
            sys.exit(1)
        roms = get_supported_roms(games_dir)

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

    # Always (re)generate native_outputs_by_rom.lua - it's this script's primary output and is
    # rebuilt deterministically from scratch every run (each ROM's entry is exactly this
    # run's findings, never merged with prior content).
    driver_data = {
        rom: flatten_candidates(entry["candidates"])
        for rom, entry in report.items()
        if "note" not in entry
    }
    out_path = write_native_outputs_by_rom_lua(output_dir, driver_data)

    # v1.4.0: the DRIVER-keyed companion, scraped across the WHOLE driver tree rather than
    # just the ROMs in games/. This is what lets init.lua's pass-through mode forward native
    # outputs for a game MSOP has no profile for - it is looked up by the running machine's
    # source_file when the ROM itself has no entry. Independent of `roms` above, so it is the
    # same complete file whether this run scraped one ROM or all of them.
    mame_driver_path = None
    if not args.no_mame_driver_table:
        print("\n Building DRIVER-keyed index (output_finder<> across every src/mame/**/*.cpp)...")
        mame_driver_data = build_mame_driver_index(mame_src)
        print(f" Indexed {len(mame_driver_data)} driver file(s) declaring native outputs.")
        mame_driver_path = write_native_outputs_by_driver_lua(output_dir, mame_driver_data)

    # The scrape-report JSON is an optional auditing aid - only written when enabled
    # (GENERATE_SCRAPE_REPORT constant, or --scrape-report / --no-scrape-report per run).
    report_path = None
    if args.scrape_report:
        report_parent = os.path.dirname(report_out)
        if report_parent:
            os.makedirs(report_parent, exist_ok=True)
        with open(report_out, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=4)
        report_path = report_out

    print_summary(mame_src, report, report_path=report_path, out_path=out_path)
    if mame_driver_path:
        print(f" Driver-keyed table: {mame_driver_path}")


if __name__ == "__main__":
    main()
