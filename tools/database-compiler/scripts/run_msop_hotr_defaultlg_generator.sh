#!/usr/bin/env bash
# MSOP HOTR defaultLG Generator - launcher (Linux/macOS).
# Generates Hook Of The Reaper defaultLG files into output/<channel>/defaultLG/. Pass --channel
# stable|beta (default stable), --report to diff against the shipped examples, or --rom <name>.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"
"$PY" "$DIR/msop_hotr_defaultlg_generator.py" "$@"
echo
echo "Done - defaultLG generated under output/<channel>/defaultLG/."
