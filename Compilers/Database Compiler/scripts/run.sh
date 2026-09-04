#!/usr/bin/env bash
# MSOP Database Compiler - unified launcher (Linux/macOS): builds BOTH release channels end to end.
# For EACH channel (stable, then beta) it runs, in order:
#   1. database compiler   (input/<ch>/database/games  ->  output/<ch>/stateoutput/database.lua/json)
#   2. driver compiler      (MAME source                ->  output/<ch>/stateoutput/native_outputs_by_rom.lua) [optional]
#   3. HOTR defaultLG        (<ch> database              ->  output/<ch>/defaultLG)
#   4. MAMEhooker .ini       (<ch> database              ->  output/<ch>/ini)
# Single-channel launchers: run_stable.sh / run_beta.sh. Paths resolve from this script's own location.
#
# Set MAME_SRC to your MAME source checkout (the folder that contains src/mame) to enable the driver
# step for BOTH channels; leave it EMPTY to skip that step. (msop_native_outputs_compiler.py also has
# its own MAME_SRC_PATH default if you ever run it directly.)
set -e
MAME_SRC=""

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"

run_channel() {
  ch="$1"
  if [ ! -d "$DIR/../input/$ch/database/games" ]; then
    echo "==================== [$ch] SKIPPED - input/$ch/ not present ===================="
    echo
    return 0
  fi
  echo "==================== [$ch] ===================="
  echo "=== [$ch] Database Compiler (input/$ch/database/games <-> database.lua/json) ==="
  "$PY" "$DIR/msop_database_compiler.py" "$ch"

  echo
  if [ -z "$MAME_SRC" ]; then
    echo "=== [$ch] Driver Compiler SKIPPED - MAME_SRC not set in this launcher ==="
  else
    echo "=== [$ch] Driver Compiler (MAME source -> native_outputs_by_rom.lua) ==="
    "$PY" "$DIR/msop_native_outputs_compiler.py" --channel "$ch" --mame-src "$MAME_SRC"
  fi

  echo
  echo "=== [$ch] HOTR defaultLG Generator (-> output/$ch/defaultLG) ==="
  "$PY" "$DIR/msop_hotr_defaultlg_generator.py" --channel "$ch"

  echo
  echo "=== [$ch] MAMEhooker INI Generator (driver natives by default -> output/$ch/ini) ==="
  "$PY" "$DIR/msop_mamehooker_ini_generator.py" --channel "$ch"
  echo
}

run_channel stable
run_channel beta

echo "Done - both channels built (output/stable/ + output/beta/)."
