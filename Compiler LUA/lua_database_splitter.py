#
# JSON DATABASE SPLITTER
# Version: 1.0.0
# Last Modified Date (YYYY.MM.DD): 2026.05.19
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#

import json
import os

# Configuration
INPUT_FILE = "lua_database.json"
OUTPUT_DIR = "game_json"

def split_database():
    # Check if the input file exists
    if not os.path.exists(INPUT_FILE):
        print(f"Error: Could not find '{INPUT_FILE}' in the current directory.")
        return

    # Create the output directory if it doesn't exist
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)
        print(f"Created directory: {OUTPUT_DIR}/")

    # Load the master JSON file
    try:
        with open(INPUT_FILE, 'r', encoding='utf-8') as f:
            database = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON in {INPUT_FILE}: {e}")
        return

    count = 0
    # Iterate through every ROM key in the database
    for rom_name, game_data in database.items():
        output_filepath = os.path.join(OUTPUT_DIR, f"{rom_name}.json")
        
        # Save the individual game configuration to its own file
        with open(output_filepath, 'w', encoding='utf-8') as f:
            json.dump(game_data, f, indent=4)
            
        print(f"Saved: {output_filepath}")
        count += 1

    print(f"\nSuccess! Extracted {count} configurations into the '{OUTPUT_DIR}' folder.")
    print(f"You can now safely delete '{INPUT_FILE}'.")

if __name__ == "__main__":
    split_database()