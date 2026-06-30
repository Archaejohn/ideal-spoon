#!/usr/bin/env bash
# Run the full GUT suite headless and print a pass/fail summary.
# Usage: bash tools/run_tests.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_VERSION="${GODOT_VERSION:-4.3}"
BIN="$ROOT/tools/bin"

# Resolve godot exe across platforms
GODOT="$(ls "$BIN"/Godot_v* 2>/dev/null | head -n1 || true)"
[ -z "$GODOT" ] && GODOT="$(command -v godot || true)"
if [ -z "$GODOT" ]; then
  echo "No Godot binary found. Run tools/fetch_godot.sh first." >&2
  exit 1
fi

"$GODOT" --headless --path "$ROOT/game" --import || true
"$GODOT" --headless --path "$ROOT/game" \
  -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests -ginclude_subdirs -gexit_on_success -gexit
