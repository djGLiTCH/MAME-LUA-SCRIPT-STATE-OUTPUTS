#
# MAME STATE OUTPUT PROJECT
# GAME JSON FOLDER to DATABASE LUA COMPILER
# Version: 2.6.1
# Last Modified Date (YYYY.MM.DD): 2026.05.24
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#

import json
import os
import traceback
import re
from datetime import datetime

# --- SMART PATH AUTO-DETECTION ---
# Supports running the script from the project root OR directly inside the 'stateoutput' folder
if os.path.exists("game_json") and os.path.isdir("game_json"):
    INPUT_DIR = "game_json"
    OUTPUT_DIR = "."
else:
    INPUT_DIR = os.path.join("stateoutput", "game_json")
    OUTPUT_DIR = "stateoutput"

OUTPUT_LUA = "database.lua"
OUTPUT_JSON = "database.json"

def parse_version_tuple(v_str):
    """Converts a string 'X.Y.Z' into a mathematical tuple (X, Y, Z) for reliable comparison."""
    try:
        return tuple(map(int, v_str.split('.')))
    except:
        return (0, 0, 0)

def format_lua_value(val, indent=1):
    """Recursively formats Python/JSON objects into Lua syntax without trailing commas."""
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

def compile_database():
    # --- GET CURRENT DATE ---
    today = datetime.now()
    date_str = today.strftime("%Y.%m.%d")
    date_int = int(today.strftime("%Y%m%d"))

    # --- CLI STARTUP HEADER ---
    print("-" * 75)
    print(" MAME STATE OUTPUT DATABASE COMPILER")
    print(f" Compiled from {INPUT_DIR} folder")
    print(f" Last Modified Date (YYYY.MM.DD): {date_str}")
    print(" Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS")
    print(" License: GNU GENERAL PUBLIC LICENSE GPL-v3.0")
    print(" Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.")
    print("-" * 75 + "\n")

    # --- AUTO-UPDATE SCRIPT HEADER DATE ---
    try:
        with open(__file__, 'r', encoding='utf-8') as f:
            script_content = f.read()
        
        new_script_content = re.sub(
            r'(?m)^(# Last Modified Date \(YYYY\.MM\.DD\):\s*)\d{4}\.\d{2}\.\d{2}',
            rf'\g<1>{date_str}',
            script_content
        )
        
        if new_script_content != script_content:
            with open(__file__, 'w', encoding='utf-8') as f:
                f.write(new_script_content)
            print(f" [INFO] Script header automatically updated to {date_str}.")
    except Exception as e:
        print(f" [WARNING] Could not automatically update script header date: {e}")
    
    if not os.path.exists(INPUT_DIR):
        print(f" [CRITICAL] Could not find '{INPUT_DIR}' directory. Please ensure your split JSON files are in this folder.")
        return

    master_db = {}
    stats = {"total": 0, "success": 0, "error": 0}
    error_log = []

    print(f"Scanning '{INPUT_DIR}' for configurations...")
    
    filenames = os.listdir(INPUT_DIR)
    template_files = sorted([f for f in filenames if f.endswith(".json") and f.startswith("_")])
    game_files = sorted([f for f in filenames if f.endswith(".json") and not f.startswith("_")])
    
    if not template_files and not game_files:
        print(f" [CRITICAL] No JSON files found in '{INPUT_DIR}'.")
        return

    # 1. PARSE ALL JSON FILES
    for filename in template_files + game_files:
        if not filename.startswith("_"): stats["total"] += 1
        filepath = os.path.join(INPUT_DIR, filename)
        status_tag = "[PENDING]"
        error_details = ""
        
        try:
            with open(filepath, 'r', encoding='utf-8') as f:
                master_db[filename[:-5]] = json.load(f)
            status_tag = "[SUCCESS]"
            if not filename.startswith("_"): stats["success"] += 1
        except Exception as e:
            if not filename.startswith("_"): stats["error"] += 1
            status_tag = "[ERROR]"
            error_details = traceback.format_exc().strip().split('\n')[-1]
            error_log.append(f"{filename} -> {error_details}")

        print(f" {status_tag:<9} {filename}")
        if status_tag == "[ERROR]":
            print(f"     - {error_details}")

    # 2. METADATA EXTRACTION & SYNCHRONIZATION (init.lua, plugin.json, readme.txt, _default.json)
    init_path = os.path.join(OUTPUT_DIR, "init.lua")
    plugin_json_path = os.path.join(OUTPUT_DIR, "plugin.json")
    
    # Locate readme.txt (could be in root or in stateoutput directory)
    readme_path = "readme.txt"
    if not os.path.exists(readme_path):
        readme_path = os.path.join(OUTPUT_DIR, "readme.txt")

    final_ver_str = "0.0.0"
    final_ver_int = 0
    
    init_status_text = "Not Found / Unchanged"
    plugin_status_text = "Not Found / Unchanged"
    readme_status_text = "Not Found / Unchanged"
    default_status_text = "Not Found"

    # --- A. Process init.lua (Extract Highest Version & Update Date/Versions) ---
    if os.path.exists(init_path):
        try:
            with open(init_path, 'r', encoding='utf-8') as f:
                init_content = f.read()
                
            # Find both versions in init.lua
            comment_match = re.search(r'-- Version:\s*(\d+\.\d+\.\d+)', init_content)
            table_match = re.search(r'version\s*=\s*"(\d+\.\d+\.\d+)"', init_content)
            
            v_comment = parse_version_tuple(comment_match.group(1)) if comment_match else (0,0,0)
            v_table = parse_version_tuple(table_match.group(1)) if table_match else (0,0,0)
            
            # Determine mathematically highest version
            highest_v = max(v_comment, v_table)
            
            if highest_v != (0,0,0):
                final_ver_str = f"{highest_v[0]}.{highest_v[1]}.{highest_v[2]}"
                final_ver_int = int(f"{highest_v[0]}{highest_v[1]}{highest_v[2]}")
            
            new_init_content = init_content
            
            # Update Date Header
            new_init_content = re.sub(
                r'(?m)^(-- Last Modified Date \(YYYY\.MM\.DD\):\s*)\d{4}\.\d{2}\.\d{2}',
                rf'\g<1>{date_str}',
                new_init_content
            )
            
            # Synchronize both versions to the highest found
            if highest_v != (0,0,0):
                new_init_content = re.sub(r'(?m)^(-- Version:\s*)\d+\.\d+\.\d+', rf'\g<1>{final_ver_str}', new_init_content)
                new_init_content = re.sub(r'(?m)^(\s*version\s*=\s*")\d+\.\d+\.\d+(")', rf'\g<1>{final_ver_str}\g<2>', new_init_content)
            
            if new_init_content != init_content:
                with open(init_path, 'w', encoding='utf-8') as f:
                    f.write(new_init_content)
                init_status_text = f"Updated (Date: {date_str}, Version: {final_ver_str})"
                print(f"\n [INFO] Synchronized 'init.lua' to Date: {date_str}, Version: {final_ver_str}")
            else:
                init_status_text = f"Up to date (v{final_ver_str})"
                
        except Exception as e:
            print(f"\n [WARNING] Could not parse or update init.lua: {e}")
            init_status_text = "Error"
    else:
        print(f"\n [WARNING] '{init_path}' not found. Cannot extract dynamic version.")

    # --- B. Process plugin.json (Update Date & Version) ---
    if final_ver_str != "0.0.0" and os.path.exists(plugin_json_path):
        try:
            with open(plugin_json_path, 'r', encoding='utf-8') as f:
                plugin_data = json.load(f)
            
            updated_plugin = False
            
            if plugin_data.get("plugin", {}).get("version") != final_ver_str:
                plugin_data["plugin"]["version"] = final_ver_str
                updated_plugin = True
                
            if plugin_data.get("plugin", {}).get("date") != date_str:
                plugin_data["plugin"]["date"] = date_str
                updated_plugin = True
                
            if updated_plugin:
                with open(plugin_json_path, 'w', encoding='utf-8') as f:
                    json.dump(plugin_data, f, indent=4)
                plugin_status_text = f"Updated (Date: {date_str}, Version: {final_ver_str})"
                print(f"\n [INFO] Auto-updated 'plugin.json' to Date: {date_str}, Version: {final_ver_str}")
            else:
                plugin_status_text = "Up to date"
        except Exception as e:
            print(f"\n [WARNING] Failed to update 'plugin.json': {e}")
            plugin_status_text = "Error"

    # --- C. Process readme.txt (Update Date & Version) ---
    if final_ver_str != "0.0.0" and os.path.exists(readme_path):
        try:
            with open(readme_path, 'r', encoding='utf-8') as f:
                readme_content = f.read()
            
            new_readme_content = readme_content
            # Target lines starting with exactly "Version:" or "Date:"
            new_readme_content = re.sub(r'(?m)^(Version:\s+)\d+\.\d+\.\d+', rf'\g<1>{final_ver_str}', new_readme_content)
            new_readme_content = re.sub(r'(?m)^(Date:\s+)\d{4}\.\d{2}\.\d{2}', rf'\g<1>{date_str}', new_readme_content)
            
            if new_readme_content != readme_content:
                with open(readme_path, 'w', encoding='utf-8') as f:
                    f.write(new_readme_content)
                readme_status_text = f"Updated (Date: {date_str}, Version: {final_ver_str})"
                print(f"\n [INFO] Auto-updated 'readme.txt' to Date: {date_str}, Version: {final_ver_str}")
            else:
                readme_status_text = "Up to date"
        except Exception as e:
            print(f"\n [WARNING] Failed to update 'readme.txt': {e}")
            readme_status_text = "Error"

    # --- D. Process _default.json (Update Date & Version) ---
    if "_default" in master_db:
        updated_default = False
        updates_list = []
        
        if master_db["_default"].get("LUA_DATE") != date_int:
            master_db["_default"]["LUA_DATE"] = date_int
            updated_default = True
            updates_list.append(f"Date: {date_int}")

        if final_ver_int and master_db["_default"].get("LUA_VERSION") != final_ver_int:
            master_db["_default"]["LUA_VERSION"] = final_ver_int
            updated_default = True
            updates_list.append(f"Version: {final_ver_int}")

        if updated_default:
            try:
                default_path = os.path.join(INPUT_DIR, "_default.json")
                with open(default_path, 'w', encoding='utf-8') as f:
                    json.dump(master_db["_default"], f, indent=4)
                
                updates_str = ", ".join(updates_list)
                default_status_text = f"Updated ({updates_str})"
                print(f"\n [INFO] Auto-updated '_default.json' ({updates_str}).")
            except Exception as e:
                print(f"\n [WARNING] Failed to write updated '_default.json': {e}")
                default_status_text = "Update Failed"
        else:
            default_status_text = "Up to date"
    else:
         print(f"\n [WARNING] No '_default.json' configuration found in '{INPUT_DIR}'.")

    # 3. BUILD LUA DATABASE STRING
    lua_lines = ["local database = {"]
    
    # Process templates first for a clean file structure
    for t_name in sorted([k for k in master_db.keys() if k.startswith("_")]):
        formatted_data = format_lua_value(master_db[t_name], 1)
        lua_lines.append(f"    [\"{t_name}\"] = {formatted_data},")
        
    # Process game ROMs
    for rom_name in sorted([k for k in master_db.keys() if not k.startswith("_")]):
        formatted_data = format_lua_value(master_db[rom_name], 1)
        lua_lines.append(f"    [\"{rom_name}\"] = {formatted_data},")

    lua_lines.append("}\n\nreturn database\n")
    lua_content = f"--\n-- MAME STATE OUTPUT DATABASE\n-- Compiled from {INPUT_DIR} folder\n-- Last Modified Date (YYYY.MM.DD): {date_str}\n-- Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS\n-- License: GNU GENERAL PUBLIC LICENSE GPL-v3.0\n-- Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.\n--\n\n" + "\n".join(lua_lines)
    
    # 4. EXPORT FILES INTO OUTPUT_DIR
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    lua_export_path = os.path.join(OUTPUT_DIR, OUTPUT_LUA)
    json_export_path = os.path.join(OUTPUT_DIR, OUTPUT_JSON)

    lua_write_status = "Failed"
    json_write_status = "Failed"
    
    # Export Lua
    try:
        with open(lua_export_path, 'w', encoding='utf-8') as f:
            f.write(lua_content)
        lua_write_status = "Success"
    except Exception as e:
        error_log.append(f"Lua Write Error: {e}")

    # Export Joined JSON (Backup)
    try:
        with open(json_export_path, 'w', encoding='utf-8') as f:
            json.dump(master_db, f, indent=4)
        json_write_status = "Success"
    except Exception as e:
        error_log.append(f"JSON Join Write Error: {e}")

    # --- CLI SUMMARY OUTPUT ---
    print("\n" + "="*55)
    print(" LUA COMPILER SUMMARY")
    print("="*55)
    print(f" Compile Date             : {date_str}")
    print(f" Engine Version           : v{final_ver_str if final_ver_str != '0.0.0' else 'Unknown'}")
    print("-" * 55)
    print(f" _default.json Status     : {default_status_text}")
    print(f" init.lua Status          : {init_status_text}")
    print(f" plugin.json Status       : {plugin_status_text}")
    print(f" readme.txt Status        : {readme_status_text}")
    print("-" * 55)
    
    if stats["total"] > 0:
        succ_pct = (stats["success"] / stats["total"]) * 100
        err_pct  = (stats["error"] / stats["total"]) * 100

        print(f" Total ROMs Processed     : {stats['total']}")
        print(f" Success (Compiled)       : {stats['success']} ({succ_pct:.1f}%)")
        print(f" Errors (Parse Fails)     : {stats['error']} ({err_pct:.1f}%)")
        print("-" * 55)
        print(f" Plugin Database Lua      : {lua_write_status} ({lua_export_path})")
        print(f" Backup Database JSON     : {json_write_status} ({json_export_path})")
    else:
        print(f" No game configurations found inside '{INPUT_DIR}'.")
    print("="*55)

    if stats["error"] > 0 or lua_write_status == "Failed":
        print("\nDetailed Error Log:")
        for err in error_log:
            print(f"  - {err}")
            
    if lua_write_status == "Success":
        print(f"\n[SUCCESS] Compilation complete! MAME database updated at '{lua_export_path}'.")

if __name__ == "__main__":
    compile_database()