#
# MAME State Output Lua Script Compiler
# Script Compiler Version: 2.0.6
# Last Modified Date (YYYY.MM.DD): 2026.05.19
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#

import json
import os
import copy
import re

# --- FOLDER CONFIGURATION ---
BASE_PATH = os.path.dirname(os.path.abspath(__file__))
DATABASE_DIR = os.path.join(BASE_PATH, "game_json")
TEMPLATE_FILE = os.path.join(BASE_PATH, "lua_script.lua")

if not os.path.exists(TEMPLATE_FILE) and os.path.exists(TEMPLATE_FILE + ".txt"):
    TEMPLATE_FILE = TEMPLATE_FILE + ".txt"

OUTPUT_DIR = os.path.abspath(os.path.join(BASE_PATH, "game_lua_export"))
# ----------------------------

def deep_merge(base, override):
    """Recursively merges the override dictionary into the base dictionary."""
    merged = copy.deepcopy(base)
    for k, v in override.items():
        if isinstance(v, dict) and k in merged and isinstance(merged[k], dict):
            merged[k] = deep_merge(merged[k], v)
        else:
            merged[k] = copy.deepcopy(v)
    return merged

def flatten_dict(d, parent_key='', sep='.'):
    """Flattens a nested dictionary for tag lookup (e.g. 'P1.AMMO')"""
    items = []
    for k, v in d.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            items.extend(flatten_dict(v, new_key, sep=sep).items())
        else:
            items.append((new_key, v))
    return dict(items)

def value_to_lua_injection(val):
    if isinstance(val, bool):
        return "true" if val else "false"
    elif val is None:
        return "false"
    elif isinstance(val, list):
        return "{" + ", ".join(str(item) for item in val) + "}"
    elif isinstance(val, str):
        if val.lower() == "true": return "true"
        elif val.lower() == "false": return "false"
        elif val.startswith("0x"): return val
        else: return f'"{val}"'
    else:
        return str(val)

def extract_version_metadata(template_content):
    """Parses the header comments in lua_script.lua to find the current version and date."""
    version_num, date_num = None, None
    v_match = re.search(r'-- Script Template Version:\s*(\d+)\.(\d+)\.(\d+)', template_content, re.IGNORECASE)
    if v_match:
        version_num = int(f"{v_match.group(1)}{v_match.group(2)}{v_match.group(3)}")
    d_match = re.search(r'-- Last Modified Date \(YYYY\.MM\.DD\):\s*(\d{4})\.(\d{2})\.(\d{2})', template_content, re.IGNORECASE)
    if d_match:
        date_num = int(f"{d_match.group(1)}{d_match.group(2)}{d_match.group(3)}")
    return version_num, date_num

def compile_scripts():
    print("Starting the MAME State Output Lua Script Compiler...\n")
    
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)

    if not os.path.exists(DATABASE_DIR):
        os.makedirs(DATABASE_DIR)
        print(f"Error: Could not find '{DATABASE_DIR}' folder. A new empty folder has been created. Please split your JSON config files and place them there.")
        return

    try:
        with open(TEMPLATE_FILE, 'r', encoding='utf-8') as f:
            template_content = f.read()
    except FileNotFoundError:
        print(f"Error: Could not find template file '{TEMPLATE_FILE}' in current directory.")
        return

    # Initialize compilation logs
    rom_results = {}
    default_status = "OK"
    missing_content_flag = False

    # Load all individual JSON files
    database = {}
    filepaths = {}
    for filename in os.listdir(DATABASE_DIR):
        if filename.endswith(".json"):
            rom_name = filename[:-5]
            
            # Treat as a valid game if it doesn't start with '_', OR if it is specifically '_default'
            is_game_rom = not filename.startswith('_') or rom_name == '_default'
            
            # Open a logbook for every game ROM found
            if is_game_rom:
                rom_results[rom_name] = {"status": "Pending", "messages": []}
                
            filepath = os.path.join(DATABASE_DIR, filename)
            filepaths[rom_name] = filepath
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    database[rom_name] = json.load(f)
            except json.JSONDecodeError as e:
                if is_game_rom:
                    rom_results[rom_name]["status"] = "Error"
                    rom_results[rom_name]["messages"].append(f"JSON Parse Error: {e}")
                    # Print immediately since this skips the core compilation loop
                    print(f" [ERROR]   {rom_name}.json")
                    print(f"     - JSON Parse Error: {e}")
                if filename == "_default.json":
                    default_status = "PARSE ERROR"

    default_config = database.get("_default", {})
    if not default_config and default_status != "PARSE ERROR":
        default_status = "MISSING"
        print(" [WARNING] No '_default.json' found or loaded in game_json folder.\n")

    # --- PULL METADATA FROM TEMPLATE HEADER AND UPDATE _DEFAULT.JSON ---
    lua_version, lua_date = extract_version_metadata(template_content)
    db_updated = False
    
    if default_status == "OK":
        if lua_version is not None and default_config.get("LUA_VERSION") != lua_version:
            default_config["LUA_VERSION"] = lua_version
            db_updated = True
            
        if lua_date is not None and default_config.get("LUA_DATE") != lua_date:
            default_config["LUA_DATE"] = lua_date
            db_updated = True

        if db_updated and "_default" in filepaths:
            with open(filepaths["_default"], 'w', encoding='utf-8') as f:
                json.dump(default_config, f, indent=4)
            print(" [INFO]    _default.json successfully updated with new metadata from template header.\n")

    # --- AUTOMATIC SEQUENTIAL LUA_ROM_ID GENERATOR ---
    # Include _default in the valid ROMs list so it doesn't get skipped
    valid_roms = [k for k in database.keys() if not k.startswith('_') or k == '_default']
    
    current_max_id = 0
    for rom in valid_roms:
        if "LUA_ROM_ID" in database[rom] and isinstance(database[rom]["LUA_ROM_ID"], int):
            current_max_id = max(current_max_id, database[rom]["LUA_ROM_ID"])
            
    for rom in valid_roms:
        if "LUA_ROM_ID" not in database[rom]:
            current_max_id += 1
            database[rom]["LUA_ROM_ID"] = current_max_id
            
            # Log the warning internally (Printed during the core loop)
            rom_results[rom]["status"] = "Warning"
            rom_results[rom]["messages"].append(f"Missing LUA_ROM_ID (Auto-assigned: {current_max_id} and saved)")
            
            with open(filepaths[rom], 'w', encoding='utf-8') as f:
                json.dump(database[rom], f, indent=4)

    # --- CORE COMPILATION LOOP ---
    for rom_name, game_data in database.items():
        # Skip if it starts with '_' AND is not '_default'
        if rom_name.startswith('_') and rom_name != '_default':
            continue
            
        # Skip compilation if JSON parsing failed earlier
        if rom_results[rom_name]["status"] == "Error":
            continue
            
        try:
            merged_config = deep_merge(default_config, game_data)
            flat_config = flatten_dict(merged_config)
            final_script = template_content.replace("{{ROM_NAME}}", f'"{rom_name}"')
            
            tags = set(re.findall(r'\{\{(.*?)\}\}', final_script))
            rom_missing_tags = []
            
            for tag in tags:
                if tag == "ROM_NAME":
                    continue 
                    
                if tag.endswith("_comment"):
                    if tag in flat_config:
                        final_script = final_script.replace(f"{{{{{tag}}}}}", f" -- {flat_config[tag]}")
                    else:
                        final_script = final_script.replace(f"{{{{{tag}}}}}", "")
                else:
                    if tag in flat_config:
                        val_str = value_to_lua_injection(flat_config[tag])
                        final_script = final_script.replace(f"{{{{{tag}}}}}", val_str)
                    else:
                        final_script = final_script.replace(f"{{{{{tag}}}}}", "false")
                        rom_missing_tags.append(tag)
            
            output_filepath = os.path.join(OUTPUT_DIR, f"{rom_name}.lua")
            with open(output_filepath, 'w', encoding='utf-8') as f:
                f.write(final_script)
                
            # Finalize logging for this ROM
            if rom_missing_tags:
                missing_content_flag = True
                rom_results[rom_name]["status"] = "Error"
                # Only list the first 3 missing tags to keep the CLI clean
                display_tags = ", ".join(rom_missing_tags[:3])
                if len(rom_missing_tags) > 3: display_tags += "..."
                rom_results[rom_name]["messages"].append(f"Missing {len(rom_missing_tags)} required template tags (e.g., {display_tags})")
            elif rom_results[rom_name]["status"] == "Warning":
                pass # Status is already 'Warning', messages already populated by ID generator
            else:
                rom_results[rom_name]["status"] = "Success"
                
        except Exception as e:
            rom_results[rom_name]["status"] = "Error"
            rom_results[rom_name]["messages"].append(f"Compilation Exception: {e}")

        # Print the final result and any accumulated messages right away
        status_tag = f"[{rom_results[rom_name]['status'].upper()}]"
        print(f" {status_tag:<9} {rom_name}.lua")
        for msg in rom_results[rom_name]["messages"]:
            print(f"     - {msg}")

    # --- CALCULATE FINAL STATS ---
    stats = {"total": len(rom_results), "success": 0, "warning": 0, "error": 0}
    for data in rom_results.values():
        if data["status"] == "Success": stats["success"] += 1
        elif data["status"] == "Warning": stats["warning"] += 1
        elif data["status"] == "Error": stats["error"] += 1

    # --- COMPILE DEFAULT SUMMARY FLAGS ---
    default_flags = []
    if default_status == "MISSING": default_flags.append("MISSING")
    elif default_status == "PARSE ERROR": default_flags.append("PARSE ERROR")
    if missing_content_flag: default_flags.append("MISSING CONTENT")
    default_summary_str = ", ".join(default_flags) if default_flags else "OK"

    # --- CLI SUMMARY OUTPUT ---
    print("\n" + "="*55)
    print(" COMPILATION SUMMARY")
    print("="*55)
    print(f" _default.json Status         : {default_summary_str}")
    if stats["total"] > 0:
        succ_pct = (stats["success"] / stats["total"]) * 100
        warn_pct = (stats["warning"] / stats["total"]) * 100
        err_pct  = (stats["error"] / stats["total"]) * 100

        print(f" Total Game Configs Processed : {stats['total']}")
        print(f" Success                      : {stats['success']} ({succ_pct:.1f}%)")
        print(f" Warnings (Auto-Corrected)    : {stats['warning']} ({warn_pct:.1f}%)")
        print(f" Errors (Failed to Compile)   : {stats['error']} ({err_pct:.1f}%)")
    else:
        print(" No Game ROM JSON files found to process.")
    print("="*55)
    print(f"\nMAME State Output Lua Script compilation is complete! Scripts are in '{OUTPUT_DIR}'.")

if __name__ == "__main__":
    compile_scripts()