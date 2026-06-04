#
# MAME STATE OUTPUT PROJECT
# GAME JSON FOLDER to DATABASE LUA COMPILE
# Version: 2.5.1
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

def format_lua_value(val, indent=1):
    """Recursively formats Python/JSON objects into Lua syntax without trailing commas."""
    indent_str = "    " * indent
    
    if isinstance(val, dict):
        lines = ["{"]
        # Collect all key-value lines first
        pairs = []
        for k, v in val.items():
            pairs.append(f"{indent_str}    [\"{k}\"] = {format_lua_value(v, indent + 1)}")
        
        # Join pairs with a comma and newline to ensure commas appear ONLY between items
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

    # 1a. PARSE FOUNDATIONAL TEMPLATES
    if template_files:
        print("\nProcessing foundational templates...")
        for filename in template_files:
            rom_name = filename[:-5]
            filepath = os.path.join(INPUT_DIR, filename)
            status_tag = "[PENDING]"
            error_details = ""
            
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    rom_data = json.load(f)
                    
                master_db[rom_name] = rom_data
                status_tag = "[SUCCESS]"
                    
            except json.JSONDecodeError as e:
                status_tag = "[ERROR]"
                error_details = f"JSON Syntax Error: {e}"
                error_log.append(f"{filename} -> {error_details}")
            except Exception as e:
                status_tag = "[ERROR]"
                error_details = traceback.format_exc().strip().split('\n')[-1]
                error_log.append(f"{filename} -> {error_details}")

            print(f" {status_tag:<9} {filename}")
            if status_tag == "[ERROR]":
                print(f"     - {error_details}")

    # 1b. PARSE GAME ROMS
    if game_files:
        print("\nProcessing game ROM configurations...")
        for filename in game_files:
            rom_name = filename[:-5]
            stats["total"] += 1
            filepath = os.path.join(INPUT_DIR, filename)
            status_tag = "[PENDING]"
            error_details = ""
            
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    rom_data = json.load(f)
                    
                master_db[rom_name] = rom_data
                stats["success"] += 1
                status_tag = "[SUCCESS]"
                
            except json.JSONDecodeError as e:
                stats["error"] += 1
                status_tag = "[ERROR]"
                error_details = f"JSON Syntax Error: {e}"
                error_log.append(f"{filename} -> {error_details}")
            except Exception as e:
                stats["error"] += 1
                status_tag = "[ERROR]"
                error_details = traceback.format_exc().strip().split('\n')[-1]
                error_log.append(f"{filename} -> {error_details}")

            print(f" {status_tag:<9} {filename}")
            if status_tag == "[ERROR]":
                print(f"     - {error_details}")

    # 2. EXTRACT & UPDATE METADATA (init.lua, plugin.json, _default.json)
    init_path = os.path.join(OUTPUT_DIR, "init.lua")
    plugin_json_path = os.path.join(OUTPUT_DIR, "plugin.json")
    
    extracted_version_int = None
    extracted_version_str = None
    
    init_status_text = "Not Found / Unchanged"
    plugin_status_text = "Not Found / Unchanged"
    default_status_text = "Not Found"
    
    # Process init.lua (Extract Version & Update Date)
    if os.path.exists(init_path):
        try:
            with open(init_path, 'r', encoding='utf-8') as f:
                init_content = f.read()
                
            # Parse Version
            match = re.search(r'version\s*=\s*"(\d+)\.(\d+)\.(\d+)"', init_content)
            if match:
                extracted_version_str = f"{match.group(1)}.{match.group(2)}.{match.group(3)}"
                extracted_version_int = int(f"{match.group(1)}{match.group(2)}{match.group(3)}")

            # Update Date Header
            new_init_content = re.sub(
                r'(?m)^(-- Last Modified Date \(YYYY\.MM\.DD\):\s*)\d{4}\.\d{2}\.\d{2}',
                rf'\g<1>{date_str}',
                init_content
            )

            if new_init_content != init_content:
                with open(init_path, 'w', encoding='utf-8') as f:
                    f.write(new_init_content)
                init_status_text = f"Updated (Date: {date_str})"
                print(f"\n [INFO] Auto-updated 'init.lua' header date to {date_str}.")
            else:
                init_status_text = "Up to date"
                
        except Exception as e:
            print(f"\n [WARNING] Could not parse or update init.lua: {e}")
            init_status_text = "Error"
    else:
        print(f"\n [WARNING] '{init_path}' not found. Cannot extract dynamic version.")

    # Process plugin.json (Update Version)
    if extracted_version_str and os.path.exists(plugin_json_path):
        try:
            with open(plugin_json_path, 'r', encoding='utf-8') as f:
                plugin_data = json.load(f)
            
            if plugin_data.get("plugin", {}).get("version") != extracted_version_str:
                plugin_data["plugin"]["version"] = extracted_version_str
                
                with open(plugin_json_path, 'w', encoding='utf-8') as f:
                    json.dump(plugin_data, f, indent=4)
                plugin_status_text = f"Updated (Version: {extracted_version_str})"
                print(f"\n [INFO] Auto-updated 'plugin.json' version to '{extracted_version_str}'.")
            else:
                plugin_status_text = "Up to date"
        except Exception as e:
            print(f"\n [WARNING] Failed to update 'plugin.json': {e}")
            plugin_status_text = "Error"

    # Process _default.json (Update Date & Version)
    if "_default" in master_db:
        updated_default = False
        updates_list = []
        
        if master_db["_default"].get("LUA_DATE") != date_int:
            master_db["_default"]["LUA_DATE"] = date_int
            updated_default = True
            updates_list.append(f"Date: {date_int}")

        if extracted_version_int and master_db["_default"].get("LUA_VERSION") != extracted_version_int:
            master_db["_default"]["LUA_VERSION"] = extracted_version_int
            updated_default = True
            updates_list.append(f"Version: {extracted_version_int}")

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
    print(f" Engine Version           : v{extracted_version_str if extracted_version_str else 'Unknown'}")
    print("-" * 55)
    print(f" _default.json Status     : {default_status_text}")
    print(f" init.lua Status          : {init_status_text}")
    print(f" plugin.json Status       : {plugin_status_text}")
    print("-" * 55)
    
    if stats["total"] > 0:
        succ_pct = (stats["success"] / stats["total"]) * 100
        err_pct  = (stats["error"] / stats["total"]) * 100

        print(f" Total ROMs Processed     : {stats['total']}")
        print(f" Success (Compiled)       : {stats['success']} ({succ_pct:.1f}%)")
        print(f" Errors (Parse Fails)     : {stats['error']} ({err_pct:.1f}%)")
        print("-" * 55)
        print(f" Master Lua Export        : {lua_write_status} ({lua_export_path})")
        print(f" Joined JSON Backup Export: {json_write_status} ({json_export_path})")
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