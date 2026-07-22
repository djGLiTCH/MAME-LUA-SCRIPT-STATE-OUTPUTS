#!/usr/bin/env bash
# MSOP Database Compiler - STABLE, MSOP-ONLY launcher (Linux/macOS). Builds the stable channel WITHOUT
# the MAME driver's native outputs:
#   1. database compiler   (input/stable/database/games  ->  output/stable/stateoutput/database.lua/json)
#   2. drops native_outputs_by_rom.lua + native_outputs_by_driver.lua from the plugin folder (does NOT run the driver compiler)
#   3. HOTR defaultLG        (stable database  ->  output/stable/defaultLG)         [never uses the driver]
#   4. MAMEhooker .ini       (stable database  ->  output/stable/ini, --no-driver)  [MSOP outputs only]
# The result reflects the plugin's own MSOP state outputs (recoil/reload/ammo/life/damage/credits/
# lampstart) plus each game's curated ADDITIONAL_OUTPUT_FORWARDS - but NOT the scraped MAME native
# outputs. Use run_stable.* (with MAME_SRC set) instead when you DO want the MAME driver outputs.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"

echo "=== [STABLE / MSOP-only] Database Compiler ==="
"$PY" "$DIR/msop_database_compiler.py" stable

DRV="$DIR/../output/stable/stateoutput/native_outputs_by_rom.lua"
DRVSRC="$DIR/../output/stable/stateoutput/native_outputs_by_driver.lua"
if [ -f "$DRV" ]; then
  echo "=== [STABLE / MSOP-only] removing native_outputs_by_rom.lua from the plugin folder ==="
  rm -f "$DRV"
fi
if [ -f "$DRVSRC" ]; then
  echo "=== [STABLE / MSOP-only] removing native_outputs_by_driver.lua from the plugin folder ==="
  rm -f "$DRVSRC"
fi

echo
echo "=== [STABLE / MSOP-only] HOTR defaultLG Generator (-> output/stable/defaultLG) ==="
"$PY" "$DIR/msop_hotr_defaultlg_generator.py" --channel stable

echo
echo "=== [STABLE / MSOP-only] MAMEhooker INI Generator (MSOP-only default -> output/stable/ini) ==="
"$PY" "$DIR/msop_mamehooker_ini_generator.py" --channel stable

echo
echo "Done - output/stable/ is a MSOP-ONLY build (no native_outputs_by_rom*.lua, no MAME native outputs)."
echo "      Re-run run_stable.* with MAME_SRC set to restore the driver + native forwarding."
