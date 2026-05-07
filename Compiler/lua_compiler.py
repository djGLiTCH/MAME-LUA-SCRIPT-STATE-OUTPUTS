#
# UNIVERSAL MAME LUA SCRIPT FOR STATE OUTPUTS (DESIGNED FOR LIGHT GUNS)
# GitHub: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# Universal Script Compiler Version: 1.5.1
# Last Modified Date (YYYY.MM.DD): 2026.05.07
# Created by DJ GLiTCH, with additional testing by Muggins
# License: GNU GENERAL PUBLIC LICENSE 3.0
#

import json
import os
import copy
import re

# --- FOLDER CONFIGURATION ---
# Get the absolute path of the directory where this script is located
BASE_PATH = os.path.dirname(os.path.abspath(__file__))

# Source files (database and template) live in the same folder as this script
DATABASE_FILE = os.path.join(BASE_PATH, "lua_database.json")
TEMPLATE_FILE = os.path.join(BASE_PATH, "lua_script.lua")

# Export path moves up one level from the compiler folder into the main project root
OUTPUT_DIR = os.path.abspath(os.path.join(BASE_PATH, "..", "MAME", "scripts"))
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
    """Flattens a nested dictionary for easy template tag replacement (e.g. 'P1.AMMO')."""
    items = []
    for k, v in d.items():
        new_key = f"{parent_key}{sep}{k}" if parent_key else k
        if isinstance(v, dict):
            items.extend(flatten_dict(v, new_key, sep=sep).items())
        else:
            items.append((new_key, v))
    return dict(items)

def value_to_lua_injection(val):
    """Converts Python data types into raw strings meant for inline Lua template injection."""
    
    # 1. Handle actual Python Booleans (translates to unquoted true/false in Lua)
    if isinstance(val, bool):
        return "true" if val else "false"
        
    # 2. Handle Python None
    elif val is None:
        return "false"

    # 3. Handle Python Lists (translates to Lua tables with curly braces)
    elif isinstance(val, list):
        return "{" + ", ".join(str(item) for item in val) + "}"
        
    # 4. Handle Strings (Smart Quoting)
    elif isinstance(val, str):
        # Catch if a boolean was accidentally typed as a string in the JSON
        if val.lower() == "true":
            return "true"
        elif val.lower() == "false":
            return "false"
            
        # Hex addresses must be unquoted so Lua treats them as numbers
        elif val.startswith("0x"):
            return val
            
        # ALL other standard strings ("auto", "Dragon Gun", "lamp0") get wrapped in double quotes
        else:
            return f'"{val}"'
            
    # 5. Handle standard numbers (integers, floats)
    else:
        return str(val)

def extract_version_metadata(template_content):
    """Parses the header comments in script.lua to find the current version and date."""
    version_num = None
    date_num = None
    
    # Look for latest script version line, example: -- Universal MAME LUA Script Version: 6.6.0
    v_match = re.search(r'-- Universal MAME LUA Script Version:\s*(\d+)\.(\d+)\.(\d+)', template_content, re.IGNORECASE)
    if v_match:
        version_num = int(f"{v_match.group(1)}{v_match.group(2)}{v_match.group(3)}")
        
    # Look for latest script last modified date line, example: -- Last Modified Date (YYYY.MM.DD): 2026.05.07
    d_match = re.search(r'-- Last Modified Date \(YYYY\.MM\.DD\):\s*(\d{4})\.(\d{2})\.(\d{2})', template_content, re.IGNORECASE)
    if d_match:
        date_num = int(f"{d_match.group(1)}{d_match.group(2)}{d_match.group(3)}")
        
    return version_num, date_num

def compile_scripts():
    print("Starting Universal MAME LUA Script Compilation...")
    
    # Ensure output directory exists
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)

    # Load the JSON database
    try:
        with open(DATABASE_FILE, 'r', encoding='utf-8') as f:
            database = json.load(f)
    except FileNotFoundError:
        print(f"Error: Could not find {DATABASE_FILE} in current directory.")
        return

    # Load the LUA template
    try:
        with open(TEMPLATE_FILE, 'r', encoding='utf-8') as f:
            template_content = f.read()
    except FileNotFoundError:
        print(f"Error: Could not find {TEMPLATE_FILE} in current directory.")
        return

    # Extract master defaults from JSON
    default_config = database.get("_default", {})
    if not default_config:
        print("Warning: No '_default' block found in database.json.")

    # --- PULL METADATA FROM TEMPLATE HEADER AND UPDATE JSON ---
    lua_version, lua_date = extract_version_metadata(template_content)
    db_updated = False
    
    if lua_version is not None and default_config.get("LUA_VERSION") != lua_version:
        default_config["LUA_VERSION"] = lua_version
        db_updated = True
        print(f" -> Syncing LUA_VERSION to {lua_version} from template header.")
        
    if lua_date is not None and default_config.get("LUA_DATE") != lua_date:
        default_config["LUA_DATE"] = lua_date
        db_updated = True
        print(f" -> Syncing LUA_DATE to {lua_date} from template header.")

    # --- AUTOMATIC SEQUENTIAL LUA_ROM_ID GENERATOR ---
    excluded_keys = ["_default", "_quick_template"]
    valid_roms = [k for k in database.keys() if k not in excluded_keys]
    
    # 1. Find highest existing ID to maintain sequence
    current_max_id = 0
    for rom in valid_roms:
        if "LUA_ROM_ID" in database[rom] and isinstance(database[rom]["LUA_ROM_ID"], int):
            current_max_id = max(current_max_id, database[rom]["LUA_ROM_ID"])
            
    # 2. Assign new IDs to any ROM missing one
    for rom in valid_roms:
        if "LUA_ROM_ID" not in database[rom]:
            current_max_id += 1
            database[rom]["LUA_ROM_ID"] = current_max_id
            db_updated = True
            print(f" -> Assigned new LUA_ROM_ID: {current_max_id} to '{rom}'")
            
    # Update JSON if changes were made
    if db_updated:
        database["_default"] = default_config
        with open(DATABASE_FILE, 'w', encoding='utf-8') as f:
            json.dump(database, f, indent=4)
        print(" -> database.json updated with new metadata/IDs.\n")

    # --- CORE COMPILATION LOOP ---
    for rom_name, game_data in database.items():
        # Skip structural templates
        if rom_name in ["_quick_template"]:
            continue
            
        # 1. Merge game overrides onto defaults
        merged_config = deep_merge(default_config, game_data)
        
        # 2. Flatten for tag lookup (e.g. 'P1.AMMO')
        flat_config = flatten_dict(merged_config)
        
        # 3. Handle specific ROM name tag
        final_script = template_content.replace("{{ROM_NAME}}", f'"{rom_name}"')
        
        # 4. Process all template tags
        tags = set(re.findall(r'\{\{(.*?)\}\}', final_script))
        for tag in tags:
            if tag == "ROM_NAME":
                continue 
                
            # Handle comment tags
            if tag.endswith("_comment"):
                if tag in flat_config:
                    final_script = final_script.replace(f"{{{{{tag}}}}}", f" -- {flat_config[tag]}")
                else:
                    final_script = final_script.replace(f"{{{{{tag}}}}}", "")
            # Handle variables
            else:
                if tag in flat_config:
                    val_str = value_to_lua_injection(flat_config[tag])
                    final_script = final_script.replace(f"{{{{{tag}}}}}", val_str)
                else:
                    final_script = final_script.replace(f"{{{{{tag}}}}}", "false")
        
        # Save the finalized compiled script
        output_filepath = os.path.join(OUTPUT_DIR, f"{rom_name}.lua")
        with open(output_filepath, 'w', encoding='utf-8') as f:
            f.write(final_script)
            
        print(f" -> Compiled: {rom_name}.lua")
        
    print(f"\nCompilation complete! Scripts are in '{OUTPUT_DIR}'.")

if __name__ == "__main__":
    compile_scripts()