#!/usr/bin/env bash
# MSOP games.json Sync - launcher (Linux/macOS).
# Aligns the "Channels" of updates/msop-games.json with a channel's game database. Pass --channel
# stable|beta (default stable), --check to report without writing, or --backfill (one-off seeding).
# The full launchers (run_stable.sh / run_beta.sh / run.sh) already run this as their last step.
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python)"
"$PY" "$DIR/msop_games_json_sync.py" "$@"
echo
echo "Done - games.json checked against the channel database."
