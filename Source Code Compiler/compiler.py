#
# UNIVERSAL MAME LUA SCRIPT FOR STATE OUTPUTS (DESIGNED FOR LIGHT GUNS)
# GitHub: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# Universal Script Compiler Version: 1.3.4
# Last Modified Date (YYYY.MM.DD): 2026.04.06
# Created by DJ GLiTCH, with additional testing by Muggins
# License: GNU GENERAL PUBLIC LICENSE 3.0
#

import json
import os
import copy
import re

# Configuration Paths
DATABASE_FILE = "database.json"
TEMPLATE_FILE = "script.lua"
OUTPUT_DIR = "./compiled_lua_scripts"

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
        
    # 3. Handle Strings (Smart Quoting Restored)
    elif isinstance(val, str):
        # Catch if a boolean was accidentally typed as a string in the JSON
        if val.lower() == "true":
            return "true"
        elif val.lower() == "false":
            return "false"
            
        # Hex addresses must be unquoted so Lua treats them as numbers
        elif val.startswith("0x"):
            return val
            
        # ALL other standard strings ("auto", "Area 51", "lamp0") get wrapped in double quotes
        else:
            return f'"{val}"'
            
    # 4. Handle standard numbers (integers, floats)
    else:
        return str(val)

def extract_version_metadata(template_content):
    """Parses the header comments in script.lua to find the current version and date."""
    version_num = None
    date_num = None
    
    # Look for latest script version line, example: -- Universal MAME LUA Script Version: 6.1.0
    v_match = re.search(r'-- Universal MAME LUA Script Version:\s*(\d+)\.(\d+)\.(\d+)', template_content, re.IGNORECASE)
    if v_match:
        version_num = int(f"{v_match.group(1)}{v_match.group(2)}{v_match.group(3)}")
        
    # Look for latest script last modified date line, example: -- Last Modified Date (YYYY.MM.DD): 2026.04.06
    d_match = re.search(r'-- Last Modified Date \(YYYY\.MM\.DD\):\s*(\d{4})\.(\d{2})\.(\d{2})', template_content, re.IGNORECASE)
    if d_match:
        date_num = int(f"{d_match.group(1)}{d_match.group(2)}{d_match.group(3)}")
        
    return version_num, date_num

def compile_scripts():
    print("Starting Universal MAME LUA Script Compilation...")
    
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)

    try:
        with open(DATABASE_FILE, 'r', encoding='utf-8') as f:
            database = json.load(f)
    except FileNotFoundError:
        print(f"Error: Could not find {DATABASE_FILE}")
        return

    try:
        with open(TEMPLATE_FILE, 'r', encoding='utf-8') as f:
            template_content = f.read()
    except FileNotFoundError:
        print(f"Error: Could not find {TEMPLATE_FILE}")
        return

    # Extract the master defaults from the JSON using the new "_default" key
    default_config = database.get("_default", {})
    if not default_config:
        print("Warning: No '_default' block found in database.json. Proceeding without base defaults. Noting the compiled LUA scripts will likely not work as expected.")

    # --- PULL METADATA FROM SCRIPT.LUA HEADER AND UPDATE JSON ---
    lua_version, lua_date = extract_version_metadata(template_content)
    db_updated = False
    
    if lua_version is not None and default_config.get("LUA_VERSION") != lua_version:
        default_config["LUA_VERSION"] = lua_version
        db_updated = True
        print(f" -> Syncing LUA_VERSION to {lua_version} from script.lua header.")
        
    if lua_date is not None and default_config.get("LUA_DATE") != lua_date:
        default_config["LUA_DATE"] = lua_date
        db_updated = True
        print(f" -> Syncing LUA_DATE to {lua_date} from script.lua header.")
        
    if db_updated:
        database["_default"] = default_config
        with open(DATABASE_FILE, 'w', encoding='utf-8') as f:
            json.dump(database, f, indent=4)
        print(" -> database.json successfully updated with new metadata.\n")
    # ------------------------------------------------------------------

    for rom_name, game_data in database.items():
        # Skip ONLY the structural template block. Allow "_default" to compile!
        if rom_name in ["_quick_template"]:
            continue
            
        # 1. Deep merge the game specific overrides on top of the master defaults
        merged_config = deep_merge(default_config, game_data)
        
        # 2. Flatten it so we can easily look up keys like "P1.AMMO"
        flat_config = flatten_dict(merged_config)
        
        # 3. Inject the ROM name into the header. Python ADDS the double quotes here.
        final_script = template_content.replace("{{ROM_NAME}}", f'"{rom_name}"')
        
        # 4. Find all {{TAGS}} in the Lua template and replace them with the actual values
        tags = set(re.findall(r'\{\{(.*?)\}\}', final_script))
        for tag in tags:
            if tag == "ROM_NAME":
                continue 
                
            # If the tag is a comment placeholder (e.g. {{P1.AMMO_comment}})
            if tag.endswith("_comment"):
                if tag in flat_config:
                    final_script = final_script.replace(f"{{{{{tag}}}}}", f" -- {flat_config[tag]}")
                else:
                    final_script = final_script.replace(f"{{{{{tag}}}}}", "")
                    
            # If the tag is a standard variable (e.g. {{P1.AMMO}})
            else:
                if tag in flat_config:
                    val_str = value_to_lua_injection(flat_config[tag])
                    final_script = final_script.replace(f"{{{{{tag}}}}}", val_str)
                else:
                    # Fallback safety if a variable is missing entirely
                    final_script = final_script.replace(f"{{{{{tag}}}}}", "false")
        
        # Save the standalone script
        output_filepath = os.path.join(OUTPUT_DIR, f"{rom_name}.lua")
        with open(output_filepath, 'w', encoding='utf-8') as f:
            f.write(final_script)
            
        print(f" -> Compiled: {rom_name}.lua")
        
    print(f"\nUniversal MAME LUA Script Compilation is complete! Check the '{OUTPUT_DIR}' folder.")

if __name__ == "__main__":
    compile_scripts()