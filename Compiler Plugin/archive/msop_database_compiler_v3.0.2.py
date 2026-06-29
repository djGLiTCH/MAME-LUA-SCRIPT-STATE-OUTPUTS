#
# MAME STATE OUTPUT PROJECT
# MSOP DATABASE COMPILER
# Compiler Version: 3.0.2
# Compiler Date: 2026.06.29
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#

import json
import os
import traceback
import re
from datetime import datetime

# SMART PATH AUTO-DETECTION
if os.path.exists("game_json") and os.path.isdir("game_json"):
    INPUT_DIR = "game_json"
    OUTPUT_DIR = "."
else:
    INPUT_DIR = os.path.join("stateoutput", "game_json")
    OUTPUT_DIR = "stateoutput"

OUTPUT_LUA = "database.lua"
OUTPUT_JSON = "database.json"

def parse_version_tuple(v_str):
    try:
        return tuple(map(int, v_str.split('.')))
    except:
        return (0, 0, 0)

def reject_duplicate_keys(ordered_pairs):
    """Custom JSON decoder hook to catch and reject duplicate keys."""
    dict_out = {}
    for key, value in ordered_pairs:
        if key in dict_out:
            raise ValueError(f"Duplicate key detected in JSON: '{key}'")
        dict_out[key] = value
    return dict_out

def format_lua_value(val, indent=1):
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
    lua_lines = ["local database = {"]
    for t_name in sorted([k for k in master_db.keys() if k.startswith("_")]):
        lua_lines.append(f"    [\"{t_name}\"] = {format_lua_value(master_db[t_name], 1)},")
    for rom_name in sorted([k for k in master_db.keys() if not k.startswith("_")]):
        lua_lines.append(f"    [\"{rom_name}\"] = {format_lua_value(master_db[rom_name], 1)},")
    lua_lines.append("}\n\nreturn database\n")
    
    header = (
        "--\n-- MAME STATE OUTPUT PROJECT\n"
        "-- MSOP DATABASE LUA\n"
        f"-- Database Release Date: {date_str}\n"
        "-- Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS\n"
        "-- License: GNU GENERAL PUBLIC LICENSE GPL-v3.0\n"
        "-- Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.\n--\n\n"
    )
    return header + "\n".join(lua_lines)

def sync_project_metadata(master_db):
    """Synchronizes versions and dates across project files using init.lua as the source of truth."""
    today = datetime.now()
    today_date_str = today.strftime("%Y.%m.%d")
    today_date_int = int(today.strftime("%Y%m%d"))
    
    sync_stats = {
        "db_date": today_date_str,
        "plugin_date": "Unknown",
        "version_str": "0.0.0",
        "init": "Not Found / Unchanged",
        "plugin": "Not Found / Unchanged",
        "readme": "Not Found / Unchanged",
        "default": "Up to date"
    }

    # 1. Extract from init.lua (Source of Truth for Plugin Version and Date)
    init_path = os.path.join(OUTPUT_DIR, "init.lua")
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
            
            if new_init != init_content:
                with open(init_path, 'w', encoding='utf-8') as f:
                    f.write(new_init)
                sync_stats["init"] = f"Updated (Plugin: v{final_ver_str})"
            else:
                sync_stats["init"] = f"Up to date (Plugin: v{final_ver_str} & {plugin_date_str})"
        except Exception as e:
            sync_stats["init"] = f"Error -> {e}"

    # 2. Update plugin.json
    plugin_path = os.path.join(OUTPUT_DIR, "plugin.json")
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
            
            if updated:
                with open(plugin_path, 'w', encoding='utf-8') as f:
                    json.dump(plugin_data, f, indent=4)
                sync_stats["plugin"] = f"Updated (Plugin: v{final_ver_str} & {plugin_date_str}, Database: {today_date_str})"
            else:
                sync_stats["plugin"] = f"Up to date (Plugin: v{final_ver_str} & {plugin_date_str}, Database: {today_date_str})"
        except Exception as e:
            sync_stats["plugin"] = f"Error -> {e}"

    # 3. Update readme.txt
    readme_path = "readme.txt" if os.path.exists("readme.txt") else os.path.join(OUTPUT_DIR, "readme.txt")
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
            sync_stats["default"] = f"Updated (Plugin: v{final_ver_int} & Datbase: {today_date_int})"
        else:
            sync_stats["default"] = f"Up to date (Plugin: v{final_ver_int} & Datbase: {today_date_int})"
    else:
        sync_stats["default"] = "Not Found in Database"

    return master_db, sync_stats

def print_summary(op_name, default_status, stats, sync_stats, json_export_status="", lua_export_status=""):
    print("\n" + "=" * 70)
    print(f" {op_name} SUMMARY")
    print("=" * 70)
    
    # Meta Sync Block
    ver_str = sync_stats['version_str']
    print(f" Plugin Version           : v{ver_str if ver_str != '0.0.0' else 'Unknown'}")
    print(f" Plugin Date              : {sync_stats['plugin_date']}")
    print(f" Database Date            : {sync_stats['db_date']}")
    print("-" * 70)
    print(f" init.lua Status          : {sync_stats['init']}")
    print(f" plugin.json Status       : {sync_stats['plugin']}")
    print(f" readme.txt Status        : {sync_stats['readme']}")
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

def compile_from_folder():
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
    master_db, sync_stats = sync_project_metadata(master_db)

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
    db_json_path = os.path.join(OUTPUT_DIR, OUTPUT_JSON)
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
    try:
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        lua_export_path = os.path.join(OUTPUT_DIR, OUTPUT_LUA)
        json_export_path = os.path.join(OUTPUT_DIR, OUTPUT_JSON)

        # Write Database JSON
        with open(json_export_path, 'w', encoding='utf-8') as f:
            json.dump(master_db, f, indent=4)
        json_status = "Success"

        # Write Lua Database
        with open(lua_export_path, 'w', encoding='utf-8') as f:
            f.write(build_lua_string(master_db, date_str))
        lua_status = "Success"
            
        return json_status, lua_status
    except Exception as e:
        return f"Error -> {e}", f"Error -> {e}"

def main():
    print("-" * 70)
    print(" " * 14 + "MAME STATE OUTPUT PROJECT")
    print(" " * 16 + "MSOP DATABASE COMPILER")
    print("-" * 70)
    print(" Please select your compilation direction:\n")
    print(" [ 1 ] Compile from folder with individual game JSONs")
    print(f"       INPUT:  '{INPUT_DIR}' folder (individual game JSONs)")
    print(f"       OUTPUT 1: '{OUTPUT_JSON}' (Database JSON)")
    print(f"       OUTPUT 2: '{OUTPUT_LUA}' (Database Lua for use with MSOP Plugin)\n")
    print(" [ 2 ] Compile from single Database JSON")
    print(f"       INPUT:  '{OUTPUT_JSON}' (Database JSON file)")
    print(f"       OUTPUT 1: '{INPUT_DIR}' folder (individual game JSONs)")
    print(f"       OUTPUT 2: '{OUTPUT_LUA}' (Database Lua for use with MSOP Plugin)")
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