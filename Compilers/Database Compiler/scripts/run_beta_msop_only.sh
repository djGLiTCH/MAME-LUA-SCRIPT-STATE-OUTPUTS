#!/usr/bin/env bash
# MSOP Database Compiler - BETA, MSOP-ONLY launcher (Linux/macOS). Builds the beta channel WITHOUT the
# MAME driver's native outputs:
#   1. database compiler   (input/beta/database/games  ->  output/beta/stateoutput/database.lua/json)
#   2. drops database_driver.lua from the plugin folder (does NOT run the driver compiler)
#   3. HOTR defaultLG        (beta database  ->  output/beta/defaultLG)         [never uses the driver]
#   4. MAMEhooker .ini       (beta database  ->  output/beta/ini, --no-driver)  [MSOP outputs only]
# The result reflects the plugin's own MSOP state outputs plus each game's curated
# ADDITIONAL_OUTPUT_FORWARDS - but NOT the scraped MAME native outputs. Use run_beta.* (with MAME_SRC
# set) instead when you DO want the MAME driver outputs.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"

echo "=== [BETA / MSOP-only] Database Compiler ==="
"$PY" "$DIR/msop_database_compiler.py" beta

DRV="$DIR/../output/beta/stateoutput/database_driver.lua"
if [ -f "$DRV" ]; then
  echo "=== [BETA / MSOP-only] removing database_driver.lua from the plugin folder ==="
  rm -f "$DRV"
fi

echo
echo "=== [BETA / MSOP-only] HOTR defaultLG Generator (-> output/beta/defaultLG) ==="
"$PY" "$DIR/msop_hotr_defaultlg_generator.py" --channel beta

echo
echo "=== [BETA / MSOP-only] MAMEhooker INI Generator (MSOP-only default -> output/beta/ini) ==="
"$PY" "$DIR/msop_mamehooker_ini_generator.py" --channel beta

echo
echo "Done - output/beta/ is a MSOP-ONLY build (no database_driver.lua, no MAME native outputs)."
echo "      Re-run run_beta.* with MAME_SRC set to restore the driver + native forwarding."
