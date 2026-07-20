#!/usr/bin/env bash
# MSOP Database Driver Compiler - launcher (Linux/macOS).
# Runs ONLY the driver compiler: it scrapes a MAME source checkout for each supported ROM's NATIVE
# output names and writes output/<channel>/stateoutput/database_driver.lua (plus the scrape-report
# JSON under output/<channel>/results/). It does NOT compile database.lua and does NOT regenerate the
# HOTR defaultLG templates or the MAMEhooker INIs - use run_stable.*/run_beta.*/run.* for those.
#
# MAME source: pass --mame-src "<path>" (the folder containing src/mame), or leave it off and the
# script falls back to the MAME_SRC_PATH constant near the top of msop_database_driver_compiler.py -
# set that once and you can run this with no arguments at all.
#
# Useful arguments (all passed straight through):
#   --channel stable|beta   which tree to read/write (default: stable)
#   --rom <name>            scrape a single ROM instead of every supported one (repeatable)
#   --no-scrape-report      skip the audit JSON (database_driver.lua is always written)
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"
"$PY" "$DIR/msop_database_driver_compiler.py" "$@"
echo
echo "Done - database_driver.lua written under output/<channel>/stateoutput/."
