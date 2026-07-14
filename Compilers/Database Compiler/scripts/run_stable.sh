#!/usr/bin/env bash
# MSOP Database Compiler - STABLE channel launcher (Linux/macOS). Runs the full STABLE pipeline:
#   1. database compiler   (input/stable/database/games  ->  output/stable/stateoutput/database.lua/json)
#   2. driver compiler      (MAME source                  ->  output/stable/stateoutput/database_driver.lua) [optional]
#   3. HOTR defaultLG        (stable database              ->  output/stable/defaultLG)
#   4. MAMEhooker .ini       (stable database              ->  output/stable/ini)
# See run.sh to build BOTH channels at once, and run_beta.sh for beta.
#
# Set MAME_SRC to your MAME source checkout (the folder that contains src/mame) to enable the driver
# step; leave it EMPTY to skip it.
set -e
MAME_SRC=""

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"

echo "=== [STABLE] Database Compiler (input/stable/database/games <-> database.lua/json) ==="
"$PY" "$DIR/msop_database_compiler.py" stable

echo
if [ -z "$MAME_SRC" ]; then
  echo "=== [STABLE] Driver Compiler SKIPPED - MAME_SRC not set in this launcher ==="
else
  echo "=== [STABLE] Driver Compiler (MAME source -> database_driver.lua) ==="
  "$PY" "$DIR/msop_database_driver_compiler.py" --channel stable --mame-src "$MAME_SRC"
fi

echo
echo "=== [STABLE] HOTR defaultLG Generator (-> output/stable/defaultLG) ==="
"$PY" "$DIR/msop_hotr_defaultlg_generator.py" --channel stable

echo
echo "=== [STABLE] MAMEhooker INI Generator (--include-driver -> output/stable/ini) ==="
"$PY" "$DIR/msop_mamehooker_ini_generator.py" --channel stable --include-driver

echo
echo "Done - output/stable/ is tagged STABLE and ready to ship."
