#!/usr/bin/env bash
# MSOP Database Compiler - BETA channel launcher (Linux/macOS). Runs the full BETA pipeline:
#   1. database compiler   (input/beta/database/games  ->  output/beta/stateoutput/database.lua/json)
#   2. driver compiler      (MAME source                ->  output/beta/stateoutput/native_outputs_by_rom.lua) [optional]
#   3. HOTR defaultLG        (beta database              ->  output/beta/defaultLG)
#   4. MAMEhooker .ini       (beta database              ->  output/beta/ini)
# BETA is intentionally isolated from STABLE (its own input/beta/ tree), so experimental games AND
# plugin code can't touch the shipped stable build. See run.sh for both channels, run_stable.sh for stable.
#
# Set MAME_SRC to your MAME source checkout (the folder that contains src/mame) to enable the driver
# step; leave it EMPTY to skip it. (The driver step matters for beta whenever beta adds new ROMs.)
set -e
MAME_SRC=""

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"

echo "=== [BETA] Database Compiler (input/beta/database/games <-> database.lua/json) ==="
"$PY" "$DIR/msop_database_compiler.py" beta

echo
if [ -z "$MAME_SRC" ]; then
  echo "=== [BETA] Driver Compiler SKIPPED - MAME_SRC not set in this launcher ==="
else
  echo "=== [BETA] Driver Compiler (MAME source -> native_outputs_by_rom.lua) ==="
  "$PY" "$DIR/msop_native_outputs_compiler.py" --channel beta --mame-src "$MAME_SRC"
fi

echo
echo "=== [BETA] HOTR defaultLG Generator (-> output/beta/defaultLG) ==="
"$PY" "$DIR/msop_hotr_defaultlg_generator.py" --channel beta

echo
echo "=== [BETA] MAMEhooker INI Generator (--include-driver -> output/beta/ini) ==="
"$PY" "$DIR/msop_mamehooker_ini_generator.py" --channel beta --include-driver

echo
echo "Done - output/beta/ is tagged BETA and ready to ship."
