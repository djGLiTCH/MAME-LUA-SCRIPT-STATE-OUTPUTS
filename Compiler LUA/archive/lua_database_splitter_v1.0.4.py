#
# JSON DATABASE SPLITTER
# Version: 1.0.4
# Last Modified Date (YYYY.MM.DD): 2026.05.23
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#

import json
import os

# Configuration
INPUT_FILE = "lua_database.json"
OUTPUT_DIR = "game_json_import"

def split_database():
    print("Starting the JSON Database Splitter...\n")
    
    if not os.path.exists(INPUT_FILE):
        print(f"Error: Could not find '{INPUT_FILE}' in the current directory.")
        return

    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)
        print(f"Created directory: {OUTPUT_DIR}/")

    stats = {"total": 0, "success": 0, "error": 0}
    default_status = "Missing (Not found in master)"

    try:
        with open(INPUT_FILE, 'r', encoding='utf-8') as f:
            database = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON in {INPUT_FILE}: {e}")
        return

    for rom_name, game_data in database.items():
        stats["total"] += 1
        output_filepath = os.path.join(OUTPUT_DIR, f"{rom_name}.json")
        
        try:
            with open(output_filepath, 'w', encoding='utf-8') as f:
                json.dump(game_data, f, indent=4)
            print(f" [SUCCESS] {rom_name}")
            stats["success"] += 1
            if rom_name == "_default":
                default_status = "Successfully Extracted"
        except Exception:
            print(f" [ERROR]   {rom_name}")
            stats["error"] += 1
            if rom_name == "_default":
                default_status = "Write Error"

    # --- CLI SUMMARY OUTPUT ---
    print("\n" + "="*55)
    print(" SPLITTER SUMMARY")
    print("="*55)
    print(f" _default.json Status     : {default_status}")
    if stats["total"] > 0:
        succ_pct = (stats["success"] / stats["total"]) * 100
        err_pct  = (stats["error"] / stats["total"]) * 100

        print(f" Total Game Configs Found : {stats['total']}")
        print(f" Success (Extracted)      : {stats['success']} ({succ_pct:.1f}%)")
        print(f" Errors (Write Failures)  : {stats['error']} ({err_pct:.1f}%)")
    else:
        print(f" No configurations found inside {INPUT_FILE}.")
    print("="*55)
    
    # Conditional Bottom Log
    if stats["error"] > 0:
        print(f"\n{stats['error']} ({err_pct:.1f}%) of json files encountered an error during extraction and could not be processed.")
    elif stats["success"] > 0:
        print(f"\nSuccess! You can now safely delete '{INPUT_FILE}'.")

if __name__ == "__main__":
    split_database()