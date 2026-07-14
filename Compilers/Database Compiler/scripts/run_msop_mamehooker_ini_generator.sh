#!/usr/bin/env bash
# MSOP MAMEhooker INI Generator - launcher (Linux/macOS).
# Generates empty MAMEhooker .ini skeletons into output/<channel>/ini/. Pass --channel stable|beta
# (default stable), --report to diff against the shipped references, or --rom <name> for one game.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"
"$PY" "$DIR/msop_mamehooker_ini_generator.py" "$@"
echo
echo "Done - .ini skeletons generated under output/<channel>/ini/."
