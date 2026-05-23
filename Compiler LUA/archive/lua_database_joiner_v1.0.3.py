#
# JSON DATABASE JOINER
# Version: 1.0.3
# Last Modified Date (YYYY.MM.DD): 2026.05.21
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#

import json
import os

# Configuration
INPUT_DIR = "game_json"
OUTPUT_FILE = "lua_database.json"

def join_database():
    print("Starting the JSON Database Joiner...\n")
    
    if not os.path.exists(INPUT_DIR):
        print(f"Error: Could not find the '{INPUT_DIR}' folder in the current directory.")
        return

    master_database = {}
    stats = {"total": 0, "success": 0, "error": 0}
    default_status = "Missing (Not found in directory)"
    
    print(f"Scanning '{INPUT_DIR}' for JSON configurations...")

    # Load _default.json first so it naturally stays at the top of the compiled master file
    default_path = os.path.join(INPUT_DIR, "_default.json")
    if os.path.exists(default_path):
        stats["total"] += 1
        try:
            with open(default_path, 'r', encoding='utf-8') as f:
                master_database["_default"] = json.load(f)
                stats["success"] += 1
                default_status = "Found & Merged"
                print(" [SUCCESS] _default")
        except json.JSONDecodeError:
            stats["error"] += 1
            default_status = "Parse Error"
            print(" [ERROR]   _default")

    # Iterate through every other file in the directory, sorting alphabetically
    for filename in sorted(os.listdir(INPUT_DIR)):
        if filename.endswith(".json") and filename != "_default.json":
            stats["total"] += 1
            rom_name = filename[:-5]
            filepath = os.path.join(INPUT_DIR, filename)
            
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    master_database[rom_name] = json.load(f)
                    stats["success"] += 1
                    print(f" [SUCCESS] {rom_name}")
            except json.JSONDecodeError:
                stats["error"] += 1
                print(f" [ERROR]   {rom_name}")

    if stats["total"] == 0:
        print(f"Error: No valid JSON files found in '{INPUT_DIR}'.")
        return

    write_status = "Failed"
    try:
        with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
            json.dump(master_database, f, indent=4)
            write_status = "Success"
    except Exception as e:
        print(f"\n[CRITICAL ERROR] Failed to write to {OUTPUT_FILE}: {e}")

    # --- CLI SUMMARY OUTPUT ---
    print("\n" + "="*55)
    print(" JOINER SUMMARY")
    print("="*55)
    print(f" _default.json Status     : {default_status}")
    if stats["total"] > 0:
        succ_pct = (stats["success"] / stats["total"]) * 100
        err_pct  = (stats["error"] / stats["total"]) * 100

        print(f" Total JSON Files Found   : {stats['total']}")
        print(f" Success (Merged)         : {stats['success']} ({succ_pct:.1f}%)")
        print(f" Errors (Parse Failures)  : {stats['error']} ({err_pct:.1f}%)")
        print("-" * 55)
        print(f" Master Database Export   : {write_status}")
    print("="*55)
    
    # Conditional Bottom Log
    if write_status == "Success":
        print(f"\nSuccess! Merged configurations saved to '{OUTPUT_FILE}'.")
        if stats["error"] > 0:
            print(f"Note: {stats['error']} ({err_pct:.1f}%) of json files encountered an error during parsing and could not be processed.")

if __name__ == "__main__":
    join_database()