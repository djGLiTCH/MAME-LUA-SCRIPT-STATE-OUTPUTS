#
# MAME STATE OUTPUT PROJECT (MSOP)
# MSOP DATABASE COMPILER
# Compiler Version: 3.4.2
# Compiler Date: 2026.07.20
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#
# Compiles the per-game '.json' config files in 'games/' into the two
# formats the rest of the project actually consumes: 'database.lua' (what
# the MSOP Lua plugin's init.lua actually require()'s at runtime) and
# 'database.json' (a single-file mirror of the same data, kept mainly for
# distribution/inspection - the Lua plugin never reads this one directly).
#
# Two modes, selected interactively at startup:
#   [1] games/*.json  -> database.lua + database.json  (the normal path
#       - edit individual game files, recompile to publish them)
#   [2] database.json     -> games/*.json + database.lua  (the reverse -
#       useful for splitting a single shared/downloaded database.json back
#       into per-game files for editing, or recovering games/ if it's
#       ever lost)
# Both modes always regenerate database.lua, so it can never silently drift
# out of sync with whichever JSON source you just edited.
#
# HEADLESS release-channel mode (no prompts - for batch scripts):
#   python msop_database_compiler.py stable  -> read input/stable/, write output/stable/, channel="stable"
#   python msop_database_compiler.py beta    -> read input/beta/,   write output/beta/,   channel="beta"
# The channel now selects the WHOLE input+output tree (input/<channel>/{stateoutput,database} ->
# output/<channel>/stateoutput), not just the plugin.json channel stamp, so a beta database AND its
# experimental plugin runtime stay fully isolated from stable. The stamp itself lands in
# input/<channel>/stateoutput/plugin.json (and the assembled output/<channel>/stateoutput/ copy), where
# the Configurator reads it to display which channel an installed plugin came from. run_stable.bat/.sh
# and run_beta.bat/.sh wrap the full per-channel pipeline (compile + generators). With NO argument the
# compiler runs interactively on the STABLE channel.
#
# Side effect worth knowing about: every run also re-syncs project metadata
# (see sync_project_metadata) - init.lua's own header/exports.version is
# treated as the single source of truth for the plugin's version and date,
# and gets propagated forward into init.lua's own PLUGIN_VERSION_NUM /
# PLUGIN_DATE_NUM constants (the MSOP_LuaVersion/MSOP_LuaDate outputs),
# plugin.json, readme.txt, and _default's LUA_VERSION/LUA_DATE if any of
# them have drifted out of step. This is why running this compiler can
# rewrite files that have nothing to do with game configuration - that's
# intentional, not a bug.
#
# plugin.json's "relay" member is the OPPOSITE case: it is a deploy-time
# stamp the MSOP Configurator patches into each INSTALLED copy (per MAME
# instance, from its version + output mode). It must never exist in the
# source or the shipped zip - a manual install has to self-detect - so the
# sync STRIPS it from input/stateoutput/plugin.json if it ever leaks in,
# which also guarantees the output/ copy ships pristine.
#
# This is a separate, independent tool from msop_native_outputs_compiler.py:
# this one never needs a MAME source checkout, only games/. The driver
# compiler is the one that scrapes MAME's own source for NATIVE outputs and
# writes the companion native_outputs_by_rom.lua file - see that script's own
# header for details. Nothing here depends on native_outputs_by_rom.lua existing,
# and nothing this script writes touches it.
#

import json
import os
import shutil
import sys
import traceback
import re
from datetime import datetime

# KEEP IN SYNC with the header comment above - stamped into database.lua's
# own generated header so a compiled file can be traced back to the exact
# compiler version that produced it.
COMPILER_VERSION = "3.4.2"
COMPILER_DATE = "2026.07.20"

# ==========================================
# PROJECT PATHS (root-anchored via __file__: scripts/ -> parent is the project root)
# ==========================================
BASE_DIR    = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Release channel selects the input+output tree so stable and beta never cross-contaminate: everything
# below lives under input/<channel>/ and output/<channel>/. Default "stable"; configure_channel("beta")
# (called from main() for the headless "beta" arg) repoints all four in one shot. The plugin runtime
# SOURCE (init.lua/plugin.json/readme.txt) is per-channel too, so a beta can carry experimental plugin
# code with no risk to the shipped stable source.
CHANNEL = "stable"
# Human-edited plugin runtime SOURCE (init.lua/plugin.json/readme.txt, versions aligned on run).
SOURCE_DIR   = os.path.join(BASE_DIR, "input", CHANNEL, "stateoutput")
# The game-data source: database.json plus the per-game games/ folder (two interchangeable formats).
DATABASE_DIR = os.path.join(BASE_DIR, "input", CHANNEL, "database")
INPUT_DIR    = os.path.join(DATABASE_DIR, "games")     # per-game JSON (mode 1 IN / mode 2 OUT)
# Built, deployable plugin folder for MSOP Plugin releases.
BUILD_DIR    = os.path.join(BASE_DIR, "output", CHANNEL, "stateoutput")


def configure_channel(channel):
    """Repoint SOURCE_DIR / DATABASE_DIR / INPUT_DIR / BUILD_DIR at input/<channel>/ and
    output/<channel>/. Call once in main() (before any compile) to switch the whole run's channel."""
    global CHANNEL, SOURCE_DIR, DATABASE_DIR, INPUT_DIR, BUILD_DIR
    CHANNEL      = channel
    SOURCE_DIR   = os.path.join(BASE_DIR, "input", channel, "stateoutput")
    DATABASE_DIR = os.path.join(BASE_DIR, "input", channel, "database")
    INPUT_DIR    = os.path.join(BASE_DIR, "input", channel, "database", "games")
    BUILD_DIR    = os.path.join(BASE_DIR, "output", channel, "stateoutput")

OUTPUT_LUA  = "database.lua"    # -> BUILD_DIR    (compiled runtime the plugin require()'s)
OUTPUT_JSON = "database.json"   # -> DATABASE_DIR (source-format mirror, interchangeable with games/)

# Plugin runtime files: human-edited in SOURCE_DIR, copied into BUILD_DIR on every compile so
# output/stateoutput/ is a complete, grab-and-ship plugin folder.
PLUGIN_FILES = ("init.lua", "plugin.json", "readme.txt")

def parse_version_tuple(v_str):
    """Parses a "X.Y.Z" version string into a comparable (X, Y, Z) int tuple.
    Falls back to (0, 0, 0) for anything malformed, so a bad or missing
    version string degrades to "lowest possible version" during comparison
    (see sync_project_metadata) rather than crashing the whole compile."""
    try:
        return tuple(map(int, v_str.split('.')))
    except:
        return (0, 0, 0)

def reject_duplicate_keys(ordered_pairs):
    """Custom JSON decoder hook to catch and reject duplicate keys. Plain
    json.load() silently keeps only the last occurrence of a repeated key,
    which would hide a real config mistake (e.g. two "AMMO" entries in the
    same game file) instead of surfacing it as the parse error it actually is."""
    dict_out = {}
    for key, value in ordered_pairs:
        if key in dict_out:
            raise ValueError(f"Duplicate key detected in JSON: '{key}'")
        dict_out[key] = value
    return dict_out

def format_lua_value(val, indent=1):
    """Recursively serializes a Python value into Lua table literal syntax
    (dict -> {["key"] = value, ...}, list -> {value, ...}, plus the usual
    scalar types). This is the one formatting routine both compiled files
    are built from - msop_native_outputs_compiler.py imports this function
    rather than reimplementing it (see that script's _load_format_lua_value)
    - so database.lua and native_outputs_by_rom.lua always share identical Lua
    syntax conventions."""
    indent_str = "    " * indent
    if isinstance(val, dict):
        lines = ["{"]
        pairs = []
        for k, v in val.items():
            pairs.append(f"{indent_str}    [\"{k}\"] = {format_lua_value(v, indent + 1)}")
        if pairs:
            lines.append(",\n".join(pairs))
        lines.append(indent_str + "}")
        return "\n".join(lines)
    elif isinstance(val, list):
        lines = ["{"]
        items = []
        for item in val:
            items.append(f"{indent_str}    {format_lua_value(item, indent + 1)}")
        if items:
            lines.append(",\n".join(items))
        lines.append(indent_str + "}")
        return "\n".join(lines)
    elif isinstance(val, bool):
        return "true" if val else "false"
    elif val is None:
        return "nil"
    elif isinstance(val, (int, float)):
        return str(val)
    elif isinstance(val, str):
        val_escaped = val.replace('\\', '\\\\').replace('"', '\\"')
        return f'"{val_escaped}"'
    else:
        return f'"{str(val)}"'

def build_lua_string(master_db, date_str):
    """Builds the full text of database.lua: the header block, then every
    ROM's config table - "_default" first (sorted separately so it's always
    the first entry regardless of where it'd otherwise fall alphabetically,
    since it's the one entry a reader most often needs to find quickly),
    followed by every other ROM in alphabetical order."""
    lua_lines = ["local database = {"]
    for t_name in sorted([k for k in master_db.keys() if k.startswith("_")]):
        lua_lines.append(f"    [\"{t_name}\"] = {format_lua_value(master_db[t_name], 1)},")
    for rom_name in sorted([k for k in master_db.keys() if not k.startswith("_")]):
        lua_lines.append(f"    [\"{rom_name}\"] = {format_lua_value(master_db[rom_name], 1)},")
    lua_lines.append("}\n\nreturn database\n")
    
    header = (
        "--\n-- MAME STATE OUTPUT PROJECT (MSOP)\n"
        "-- MSOP DATABASE LUA\n"
        f"-- Script Version: {COMPILER_VERSION}\n"
        f"-- Script Date: {COMPILER_DATE}\n"
        f"-- Compiled Date: {date_str}\n"
        "-- Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS\n"
        "-- License: GNU GENERAL PUBLIC LICENSE GPL-v3.0\n"
        "-- Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.\n--\n"
        "-- Auto-generated by msop_database_compiler.py from games/*.json\n"
        "-- (or a single database.json) - DO NOT HAND-EDIT. Edit those JSON\n"
        "-- sources instead and re-run that script to regenerate.\n--\n\n"
    )
    return header + "\n".join(lua_lines)

def sync_project_metadata(master_db, channel_override=None):
    """Synchronizes plugin version/date across the project, treating
    init.lua as the single source of truth and propagating forward into
    plugin.json, readme.txt, and _default's LUA_VERSION/LUA_DATE. Runs on
    every compile, both modes - see the module header for why that's
    intentional. Steps:
      1. Read init.lua's own header comment AND its `version = "X.Y.Z"`
         table field, take whichever parses as the higher version
         (parse_version_tuple), and write that back into BOTH spots in
         init.lua if they'd drifted out of sync with each other - this is
         what lets a hand-edit of just one of the two ever get corrected.
      2. Propagate the resolved version/date into plugin.json.
      3. Propagate it into readme.txt, plus stamp today's date as the
         Database Date there.
      4. Update _default's LUA_VERSION/LUA_DATE in the in-memory master_db
         (persisting _default.json itself back to disk, if at all, is the
         caller's job - see compile_from_folder).
    Every step is wrapped in its own try/except, so a problem with one file
    (e.g. plugin.json missing) doesn't prevent the others from being synced."""
    today = datetime.now()
    today_date_str = today.strftime("%Y.%m.%d")
    today_date_int = int(today.strftime("%Y%m%d"))
    
    sync_stats = {
        "db_date": today_date_str,
        "plugin_date": "Unknown",
        "version_str": "0.0.0",
        "channel": "Unknown",
        "init": "Not Found / Unchanged",
        "plugin": "Not Found / Unchanged",
        "readme": "Not Found / Unchanged",
        "readme_md": "Not Found / Unchanged",
        "default": "Up to date"
    }

    # 1. Extract from init.lua (Source of Truth for Plugin Version and Date)
    init_path = os.path.join(SOURCE_DIR, "init.lua")
    final_ver_str = "0.0.0"
    final_ver_int = 0
    plugin_date_str = "0000.00.00"
    
    if os.path.exists(init_path):
        try:
            with open(init_path, 'r', encoding='utf-8') as f:
                init_content = f.read()
            
            # Extract Versions
            comment_match = re.search(r'-- Plugin Version:\s*(\d+\.\d+\.\d+)', init_content)
            table_match = re.search(r'version\s*=\s*"(\d+\.\d+\.\d+)"', init_content)
            v_comment = parse_version_tuple(comment_match.group(1)) if comment_match else (0,0,0)
            v_table = parse_version_tuple(table_match.group(1)) if table_match else (0,0,0)
            highest_v = max(v_comment, v_table)
            
            if highest_v != (0,0,0):
                final_ver_str = f"{highest_v[0]}.{highest_v[1]}.{highest_v[2]}"
                final_ver_int = int(f"{highest_v[0]}{highest_v[1]}{highest_v[2]}")
            sync_stats["version_str"] = final_ver_str

            # Extract Plugin Date
            date_match = re.search(r'-- Plugin Date:\s*(\d{4}\.\d{2}\.\d{2})', init_content)
            if date_match:
                plugin_date_str = date_match.group(1)
            sync_stats["plugin_date"] = plugin_date_str

            # Align internal version mismatches in init.lua if any exist
            new_init = init_content
            if highest_v != (0,0,0):
                new_init = re.sub(r'(?m)^(-- Plugin Version:\s*)\d+\.\d+\.\d+', rf'\g<1>{final_ver_str}', new_init)
                new_init = re.sub(r'(?m)^(\s*version\s*=\s*")\d+\.\d+\.\d+(")', rf'\g<1>{final_ver_str}\g<2>', new_init)
                # PLUGIN_VERSION_NUM publishes the MSOP_LuaVersion output (900 == v9.0.0) -
                # the "KEEP IN SYNC" the constant's own comment asks for is automated here.
                new_init = re.sub(r'(?m)^(\s*local PLUGIN_VERSION_NUM\s*=\s*)\d+', rf'\g<1>{final_ver_int}', new_init)
            if plugin_date_str != "0000.00.00":
                # PLUGIN_DATE_NUM publishes the MSOP_LuaDate output (yyyymmdd int of the
                # header's Plugin Date) - same automation as PLUGIN_VERSION_NUM above.
                plugin_date_int = int(plugin_date_str.replace(".", ""))
                new_init = re.sub(r'(?m)^(\s*local PLUGIN_DATE_NUM\s*=\s*)\d+', rf'\g<1>{plugin_date_int}', new_init)

            if new_init != init_content:
                with open(init_path, 'w', encoding='utf-8') as f:
                    f.write(new_init)
                sync_stats["init"] = f"Updated (Plugin: v{final_ver_str} & {plugin_date_str}, incl. PLUGIN_VERSION_NUM/PLUGIN_DATE_NUM)"
            else:
                sync_stats["init"] = f"Up to date (Plugin: v{final_ver_str} & {plugin_date_str})"
        except Exception as e:
            sync_stats["init"] = f"Error -> {e}"

    # 2. Update plugin.json
    plugin_path = os.path.join(SOURCE_DIR, "plugin.json")
    if final_ver_str != "0.0.0" and os.path.exists(plugin_path):
        try:
            with open(plugin_path, 'r', encoding='utf-8') as f:
                plugin_data = json.load(f)
            updated = False
            
            if plugin_data.get("plugin", {}).get("version") != final_ver_str:
                plugin_data["plugin"]["version"] = final_ver_str
                updated = True
            if plugin_data.get("plugin", {}).get("dateplugin") != plugin_date_str:
                plugin_data["plugin"]["dateplugin"] = plugin_date_str
                updated = True
            if plugin_data.get("plugin", {}).get("datedatabase") != today_date_str:
                plugin_data["plugin"]["datedatabase"] = today_date_str
                updated = True

            # The "relay" member is a DEPLOY-TIME stamp the Configurator patches into each
            # installed copy (per MAME instance). It must never exist in the source or the
            # shipped zip - a manual install has to self-detect - so strip it if it ever
            # leaks into the input copy (e.g. someone copied plugin.json back from a live
            # MAME install). Output/ is assembled from this file, so this also guarantees
            # the shipped copy stays pristine.
            if "relay" in plugin_data.get("plugin", {}):
                del plugin_data["plugin"]["relay"]
                updated = True
                sync_stats["plugin_relay_stripped"] = True

            # Headless release-channel switch ("stable"/"beta" CLI argument): stamp the
            # requested channel so the assembled output/ copy ships tagged for the right
            # release. Without an override the existing value passes through untouched.
            if channel_override and plugin_data.get("plugin", {}).get("channel") != channel_override:
                plugin_data["plugin"]["channel"] = channel_override
                updated = True
            sync_stats["channel"] = plugin_data.get("plugin", {}).get("channel", "Unknown")

            if updated:
                with open(plugin_path, 'w', encoding='utf-8') as f:
                    json.dump(plugin_data, f, indent=4)
                strip_note = " - stray relay stamp STRIPPED (deploy-time only)" if sync_stats.get("plugin_relay_stripped") else ""
                sync_stats["plugin"] = f"Updated (Plugin: v{final_ver_str} & {plugin_date_str}, Database: {today_date_str}){strip_note}"
            else:
                sync_stats["plugin"] = f"Up to date (Plugin: v{final_ver_str} & {plugin_date_str}, Database: {today_date_str})"
        except Exception as e:
            sync_stats["plugin"] = f"Error -> {e}"

    # 3. Update readme.txt in the SOURCE folder
    readme_path = os.path.join(SOURCE_DIR, "readme.txt")
    if final_ver_str != "0.0.0" and os.path.exists(readme_path):
        try:
            with open(readme_path, 'r', encoding='utf-8') as f:
                readme_content = f.read()
            
            new_readme = readme_content
            new_readme = re.sub(r'(?m)^(Plugin Version:\s+)\d+\.\d+\.\d+', rf'\g<1>{final_ver_str}', new_readme)
            new_readme = re.sub(r'(?m)^(Plugin Date:\s+)\d{4}\.\d{2}\.\d{2}', rf'\g<1>{plugin_date_str}', new_readme)
            new_readme = re.sub(r'(?m)^(Database Date:\s*).*', rf'\g<1>{today_date_str}', new_readme)
            
            if new_readme != readme_content:
                with open(readme_path, 'w', encoding='utf-8') as f:
                    f.write(new_readme)
                sync_stats["readme"] = f"Updated (Plugin: v{final_ver_str} & {plugin_date_str}, Database: {today_date_str})"
            else:
                sync_stats["readme"] = f"Up to date (Plugin: v{final_ver_str} & {plugin_date_str}, Database: {today_date_str})"
        except Exception as e:
            sync_stats["readme"] = f"Error -> {e}"

    # 3b. Update README.md (the markdown mirror of readme.txt) in the SOURCE folder
    readme_md_path = os.path.join(SOURCE_DIR, "README.md")
    if final_ver_str != "0.0.0" and os.path.exists(readme_md_path):
        try:
            with open(readme_md_path, 'r', encoding='utf-8') as f:
                md_content = f.read()

            new_md = md_content
            new_md = re.sub(r'(?m)^(- \*\*Plugin Version:\*\* )\d+\.\d+\.\d+', rf'\g<1>{final_ver_str}', new_md)
            new_md = re.sub(r'(?m)^(- \*\*Plugin Date:\*\* )\d{4}\.\d{2}\.\d{2}', rf'\g<1>{plugin_date_str}', new_md)
            new_md = re.sub(r'(?m)^(- \*\*Database Date:\*\* ).*', rf'\g<1>{today_date_str}', new_md)

            if new_md != md_content:
                with open(readme_md_path, 'w', encoding='utf-8') as f:
                    f.write(new_md)
                sync_stats["readme_md"] = f"Updated (Plugin: v{final_ver_str} & {plugin_date_str}, Database: {today_date_str})"
            else:
                sync_stats["readme_md"] = f"Up to date (Plugin: v{final_ver_str} & {plugin_date_str}, Database: {today_date_str})"
        except Exception as e:
            sync_stats["readme_md"] = f"Error -> {e}"

    # 4. Inject into _default.json (Memory Update)
    if "_default" in master_db:
        updated_default = False
        updates = []
        if master_db["_default"].get("LUA_DATE") != today_date_int:
            master_db["_default"]["LUA_DATE"] = today_date_int
            updated_default = True
            updates.append(f"DB Date: {today_date_int}")
        if final_ver_int and master_db["_default"].get("LUA_VERSION") != final_ver_int:
            master_db["_default"]["LUA_VERSION"] = final_ver_int
            updated_default = True
            updates.append(f"Version: {final_ver_int}")
        
        if updated_default:
            sync_stats["default"] = f"Updated (Plugin: v{final_ver_int} & Database: {today_date_int})"
        else:
            sync_stats["default"] = f"Up to date (Plugin: v{final_ver_int} & Database: {today_date_int})"
    else:
        sync_stats["default"] = "Not Found in Database"

    return master_db, sync_stats

def print_summary(op_name, default_status, stats, sync_stats, json_export_status="", lua_export_status=""):
    """Prints the end-of-run console report: sync_project_metadata's results,
    then per-game processing stats (success/error counts), then the
    database.json/database.lua export status. op_name distinguishes
    "COMPILATION" (mode 1) from "SPLITTER" (mode 2) in the summary header."""
    print("\n" + "=" * 70)
    print(f" {op_name} SUMMARY")
    print("=" * 70)
    
    # Meta Sync Block
    ver_str = sync_stats['version_str']
    print(f" Plugin Version           : v{ver_str if ver_str != '0.0.0' else 'Unknown'}")
    print(f" Plugin Date              : {sync_stats['plugin_date']}")
    print(f" Database Date            : {sync_stats['db_date']}")
    print(f" Release Channel          : {sync_stats.get('channel', 'Unknown')}")
    print("-" * 70)
    print(f" init.lua Status          : {sync_stats['init']}")
    print(f" plugin.json Status       : {sync_stats['plugin']}")
    print(f" readme.txt Status        : {sync_stats['readme']}")
    print(f" README.md Status         : {sync_stats['readme_md']}")
    print(f" _default Meta Sync       : {sync_stats['default']}")
    print("-" * 70)
    
    # Core Operation Block
    print(f" _default.json File Status: {default_status}")
    
    if stats["total"] > 0:
        succ_pct = (stats["success"] / stats["total"]) * 100
        err_pct = (stats["error"] / stats["total"]) * 100
        print(f" Total Games Processed    : {stats['total']}")
        print(f" Success                  : {stats['success']} ({succ_pct:.1f}%)")
        print(f" Errors                   : {stats['error']} ({err_pct:.1f}%)")
    else:
        print(" No valid games found to process.")

    # Export Block
    if json_export_status or lua_export_status:
        print("-" * 70)
        if json_export_status:
            print(f" Database JSON Export     : {json_export_status}")
        if lua_export_status:
            print(f" Database Lua Export      : {lua_export_status}")
    print("=" * 70 + "\n")

def compile_from_folder(channel_override=None):
    """Mode 1: reads every *.json in games/ (validating each one for
    duplicate keys via reject_duplicate_keys), merges them into a single
    in-memory master_db dict keyed by ROM name (plus "_default"), then
    exports database.lua/database.json. _default.json is read first and
    tracked separately (default_status) so its own success/failure doesn't
    get folded into the per-game success/error counts in `stats`."""
    print(f"\n[MODE 1] Scanning '{INPUT_DIR}' for individual game JSON configurations...\n")
    if not os.path.exists(INPUT_DIR):
        print(f"[CRITICAL] Could not find '{INPUT_DIR}' directory.")
        return

    master_db = {}
    stats = {"total": 0, "success": 0, "error": 0}
    default_status = "Missing (Not found in directory)"

    # Process _default.json FIRST
    default_path = os.path.join(INPUT_DIR, "_default.json")
    if os.path.exists(default_path):
        try:
            with open(default_path, 'r', encoding='utf-8') as f:
                # Intercept duplicate keys during JSON parsing
                master_db["_default"] = json.load(f, object_pairs_hook=reject_duplicate_keys)
                default_status = "Found & Merged"
                print(" [SUCCESS] _default.json")
        except Exception as e:
            default_status = "Parse Error"
            print(f" [ERROR]   _default.json -> Parse Error: {e}")

    # Process all other JSON files
    for filename in sorted(os.listdir(INPUT_DIR)):
        if filename.endswith(".json") and filename != "_default.json":
            stats["total"] += 1
            filepath = os.path.join(INPUT_DIR, filename)
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    # Intercept duplicate keys during JSON parsing
                    master_db[filename[:-5]] = json.load(f, object_pairs_hook=reject_duplicate_keys)
                    stats["success"] += 1
                    print(f" [SUCCESS] {filename}")
            except Exception as e:
                stats["error"] += 1
                print(f" [ERROR]   {filename} -> {e}")

    # Inject Meta-Data Updates
    master_db, sync_stats = sync_project_metadata(master_db, channel_override)

    # If Mode 1 dynamically updated the _default block, save it back to the source folder to keep it synchronized
    if "Updated" in sync_stats["default"] and default_status == "Found & Merged":
        try:
            with open(default_path, 'w', encoding='utf-8') as f:
                json.dump(master_db["_default"], f, indent=4)
        except Exception:
            sync_stats["default"] += " (Warning: Could not save update to source folder)"

    # Export
    if stats["success"] > 0 or default_status == "Found & Merged":
        json_status, lua_status = export_files(master_db, sync_stats["db_date"])
        print_summary("COMPILATION", default_status, stats, sync_stats, json_status, lua_status)
    else:
        print_summary("COMPILATION", default_status, stats, sync_stats, "Skipped", "Skipped")

def split_from_master():
    """Mode 2, the reverse of compile_from_folder: reads a single
    database.json and writes out one games/<rom>.json per entry
    (including _default.json), then exports database.lua too so it reflects
    whatever was in the source database.json. Useful for recovering
    games/ from a shared/downloaded database.json, or splitting a
    consolidated file back out for per-game editing."""
    db_json_path = os.path.join(DATABASE_DIR, OUTPUT_JSON)
    print(f"\n[MODE 2] Splitting '{db_json_path}' into individual game JSON files...\n")
    
    if not os.path.exists(db_json_path):
        print(f"[CRITICAL] Could not find '{db_json_path}'.")
        return

    try:
        with open(db_json_path, 'r', encoding='utf-8') as f:
            # Catch duplicates if the user accidentally created them inside the master DB file
            master_db = json.load(f, object_pairs_hook=reject_duplicate_keys)
    except Exception as e:
        print(f"[CRITICAL] Failed to read Database JSON: {e}")
        return

    os.makedirs(INPUT_DIR, exist_ok=True)
    stats = {"total": 0, "success": 0, "error": 0}
    default_status = "Missing (Not found in database)"

    # Inject Meta-Data Updates BEFORE splitting, so extracted files carry the fresh date/version
    master_db, sync_stats = sync_project_metadata(master_db)

    for rom_key, rom_data in master_db.items():
        filepath = os.path.join(INPUT_DIR, f"{rom_key}.json")
        try:
            with open(filepath, 'w', encoding='utf-8') as f:
                json.dump(rom_data, f, indent=4)
            print(f" [SUCCESS] {rom_key}.json")
            
            if rom_key == "_default":
                default_status = "Successfully Extracted"
            else:
                stats["success"] += 1
                stats["total"] += 1
                
        except Exception as e:
            print(f" [ERROR]   {rom_key}.json -> {e}")
            if rom_key == "_default":
                default_status = "Write Error"
            else:
                stats["error"] += 1
                stats["total"] += 1

    # Export
    if stats["success"] > 0 or default_status == "Successfully Extracted":
        json_status, lua_status = export_files(master_db, sync_stats["db_date"])
        print_summary("SPLITTER", default_status, stats, sync_stats, json_status, lua_status)
    else:
        print_summary("SPLITTER", default_status, stats, sync_stats, "Skipped", "Skipped")

def export_files(master_db, date_str):
    """Writes both compiled outputs from the in-memory master_db:
    database.json (a plain JSON dump - not consumed by the Lua plugin
    itself, kept mainly for distribution/inspection) and database.lua (via
    build_lua_string - what init.lua actually require()'s at runtime).
    Always writes both together, regardless of which mode/direction
    triggered the compile, so the two outputs can never end up describing
    different data from each other."""
    try:
        os.makedirs(DATABASE_DIR, exist_ok=True)
        os.makedirs(BUILD_DIR, exist_ok=True)
        lua_export_path  = os.path.join(BUILD_DIR, OUTPUT_LUA)      # compiled runtime  -> output/stateoutput/
        json_export_path = os.path.join(DATABASE_DIR, OUTPUT_JSON)  # source mirror     -> input/database/

        # Write Database JSON (the source-format mirror, into input/stateoutput/)
        with open(json_export_path, 'w', encoding='utf-8') as f:
            json.dump(master_db, f, indent=4)
        json_status = "Success"

        # Write Lua Database (the compiled runtime, into output/stateoutput/)
        with open(lua_export_path, 'w', encoding='utf-8') as f:
            f.write(build_lua_string(master_db, date_str))
        lua_status = "Success"

        # Assemble the deployable plugin: copy the (freshly version-aligned) plugin runtime files from
        # SOURCE_DIR into BUILD_DIR so output/stateoutput/ is a complete, grab-and-ship plugin folder.
        for name in PLUGIN_FILES:
            src = os.path.join(SOURCE_DIR, name)
            if os.path.exists(src):
                shutil.copy2(src, os.path.join(BUILD_DIR, name))

        return json_status, lua_status
    except Exception as e:
        return f"Error -> {e}", f"Error -> {e}"

def print_banner():
    # Script Version/Date describe THIS compiler (the manual constants above), so the banner
    # prints them verbatim - matching what build_lua_string stamps into database.lua's header
    # and the sibling msop_native_outputs_compiler.py. (Do NOT reassign COMPILER_DATE to
    # datetime.now() here: a bare assignment made it a function-LOCAL, so the banner showed
    # today's date while the file kept the frozen constant - the two silently disagreed.)
    print("-" * 70)
    print("MAME STATE OUTPUT PROJECT (MSOP)".center(70))
    print("MSOP DATABASE COMPILER".center(70))
    print("-" * 70)
    print(f" Script Version: {COMPILER_VERSION}")
    print(f" Script Date: {COMPILER_DATE}\n")
    # NOTE: the compiled DATABASE date is deliberately not shown here - the banner runs before any
    # compile, so it isn't known yet (it is resolved by sync_project_metadata during the run). It is
    # reported at the end instead, as "Database Date" in print_summary.
    print(" Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS")
    print(" License: GNU GENERAL PUBLIC LICENSE GPL-v3.0")
    print(" Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.")
    print("-" * 70)

def main():
    # HEADLESS release-channel mode: "stable" or "beta" as the one argument stamps
    # plugin.json's channel accordingly and runs the normal mode-1 compile with no
    # prompts, so run_stable/run_beta launchers (and any batch flow) are one-shot.
    if len(sys.argv) > 1:
        arg = sys.argv[1].strip().lower().lstrip("-/")
        if arg in ("stable", "beta"):
            configure_channel(arg)
            print_banner()
            print(f" HEADLESS: channel -> {arg}  (input/{arg}/ -> output/{arg}/, mode 1, no prompts)")
            compile_from_folder(channel_override=arg)
            return
        print_banner()
        print(f" Unknown argument '{sys.argv[1]}'.\n")
        print(" Usage: python msop_database_compiler.py [stable|beta]")
        print("   stable  stamp plugin.json channel=stable, then compile (mode 1, no prompts)")
        print("   beta    stamp plugin.json channel=beta,   then compile (mode 1, no prompts)")
        print("   (no argument = the interactive mode menu)")
        sys.exit(2)

    # Interactive editing always targets the STABLE tree; beta is built headlessly via run_beta.
    configure_channel("stable")
    print_banner()
    print(" (interactive mode operates on the STABLE channel - use run_beta for beta)\n")
    print(" Please select your compilation direction:\n")
    print(" [ 1 ] Compile from the per-game JSON folder")
    print("       INPUT:  input/stable/database/games/*.json")
    print("       OUTPUT: input/stable/database/database.json  +  output/stable/stateoutput/database.lua\n")
    print(" [ 2 ] Compile from the single Database JSON")
    print("       INPUT:  input/stable/database/database.json")
    print("       OUTPUT: input/stable/database/games/*.json  +  output/stable/stateoutput/database.lua")
    print("-" * 70)

    choice = input("\n Select conversion operation (1 or 2): ").strip()

    if choice == '1':
        compile_from_folder()
    elif choice == '2':
        split_from_master()
    else:
        print(" Invalid selection. Exiting.")

if __name__ == "__main__":
    main()