#
# MAME STATE OUTPUT PROJECT
# JSON FOLDER to LUA DATABASE COMPILER
# Version: 2.3.2
# Last Modified Date (YYYY.MM.DD): 2026.05.23
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#

import json
import os
import traceback
import re
from datetime import datetime

INPUT_DIR = "game_json"
OUTPUT_DIR = "stateoutuput"
OUTPUT_LUA = "database.lua"
OUTPUT_JSON = "database.json"

def format_lua_value(val, indent=1):
    """Recursively formats Python/JSON objects into Lua syntax."""
    indent_str = "    " * indent
    
    if isinstance(val, dict):
        lines = ["{"]
        for k, v in val.items():
            lines.append(f"{indent_str}    [\"{k}\"] = {format_lua_value(v, indent + 1)},")
        lines.append(indent_str + "}")
        return "\n".join(lines)
        
    elif isinstance(val, list):
        lines = ["{"]
        for item in val:
            lines.append(f"{indent_str}    {format_lua_value(item, indent + 1)},")
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
    default_status = "MISSING"

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
                
                if rom_name == "_default":
                    default_status = "OK"
                    
            except json.JSONDecodeError as e:
                status_tag = "[ERROR]"
                error_details = f"JSON Syntax Error: {e}"
                error_log.append(f"{filename} -> {error_details}")
                if rom_name == "_default":
                    default_status = "PARSE ERROR"
            except Exception as e:
                status_tag = "[ERROR]"
                error_details = traceback.format_exc().strip().split('\n')[-1]
                error_log.append(f"{filename} -> {error_details}")
                if rom_name == "_default":
                    default_status = "FILE ERROR"

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

    # 2. UPDATE _DEFAULT.JSON DATE
    if "_default" in master_db:
        if master_db["_default"].get("LUA_DATE") != date_int:
            master_db["_default"]["LUA_DATE"] = date_int
            try:
                default_path = os.path.join(INPUT_DIR, "_default.json")
                with open(default_path, 'w', encoding='utf-8') as f:
                    json.dump(master_db["_default"], f, indent=4)
                print(f"\n [INFO] Auto-updated LUA_DATE in '_default.json' to {date_int}.")
            except Exception as e:
                print(f"\n [WARNING] Failed to write updated date to '_default.json': {e}")
    elif default_status == "MISSING":
         print(f"\n [WARNING] No '_default.json' configuration found in '{INPUT_DIR}'.")

    # 3. BUILD LUA DATABASE
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
    
    # 4. EXPORT FILES
    lua_write_status = "Failed"
    json_write_status = "Failed"
    
    # Export Lua
    try:
        with open(OUTPUT_LUA, 'w', encoding='utf-8') as f:
            f.write(lua_content)
        lua_write_status = "Success"
    except Exception as e:
        error_log.append(f"Lua Write Error: {e}")

    # Export Joined JSON (Backup)
    try:
        with open(OUTPUT_JSON, 'w', encoding='utf-8') as f:
            json.dump(master_db, f, indent=4)
        json_write_status = "Success"
    except Exception as e:
        error_log.append(f"JSON Join Write Error: {e}")

    # --- CLI SUMMARY OUTPUT ---
    print("\n" + "="*55)
    print(" LUA COMPILER SUMMARY")
    print("="*55)
    print(f" Run Date                 : {date_str}")
    print(f" _default Config Status   : {default_status}")
    if stats["total"] > 0:
        succ_pct = (stats["success"] / stats["total"]) * 100
        err_pct  = (stats["error"] / stats["total"]) * 100

        print(f" Total ROMs Processed     : {stats['total']}")
        print(f" Success (Compiled)       : {stats['success']} ({succ_pct:.1f}%)")
        print(f" Errors (Parse Fails)     : {stats['error']} ({err_pct:.1f}%)")
        print("-" * 55)
        print(f" Master Lua Export        : {lua_write_status}")
        print(f" Joined JSON Backup Export: {json_write_status}")
    else:
        print(f" No game configurations found inside '{INPUT_DIR}'.")
    print("="*55)

    if stats["error"] > 0 or lua_write_status == "Failed":
        print("\nDetailed Error Log:")
        for err in error_log:
            print(f"  - {err}")
            
    if lua_write_status == "Success":
        print(f"\n[SUCCESS] Compilation complete! You can now copy '{OUTPUT_LUA}' directly into your MAME plugins folder.")

if __name__ == "__main__":
    compile_database()