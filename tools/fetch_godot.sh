#!/usr/bin/env bash
# Fetch a pinned Godot 4.x headless binary and the GUT addon into the repo.
# Usage: bash tools/fetch_godot.sh
# Downloads land in tools/bin/ (git-ignored). GUT is vendored into game/addons/gut/.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.3}"
GUT_VERSION="${GUT_VERSION:-9.3.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/tools/bin"
mkdir -p "$BIN"

uname_s="$(uname -s)"
case "$uname_s" in
  Linux*)  ZIP="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"; EXE="Godot_v${GODOT_VERSION}-stable_linux.x86_64" ;;
  Darwin*) ZIP="Godot_v${GODOT_VERSION}-stable_macos.universal.zip"; EXE="Godot.app/Contents/MacOS/Godot" ;;
  MINGW*|MSYS*|CYGWIN*) ZIP="Godot_v${GODOT_VERSION}-stable_win64.exe.zip"; EXE="Godot_v${GODOT_VERSION}-stable_win64.exe" ;;
  *) echo "Unsupported OS: $uname_s" >&2; exit 1 ;;
esac

if [ ! -e "$BIN/$EXE" ]; then
  echo "Downloading Godot $GODOT_VERSION ..."
  curl -fsSL "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${ZIP}" -o "$BIN/godot.zip"
  unzip -o "$BIN/godot.zip" -d "$BIN" >/dev/null
  rm -f "$BIN/godot.zip"
fi
echo "Godot binary: $BIN/$EXE"

# Vendor GUT
if [ ! -d "$ROOT/game/addons/gut" ]; then
  echo "Downloading GUT $GUT_VERSION ..."
  curl -fsSL "https://github.com/bitwes/Gut/archive/refs/tags/v${GUT_VERSION}.zip" -o "$BIN/gut.zip"
  unzip -o "$BIN/gut.zip" -d "$BIN" >/dev/null
  mkdir -p "$ROOT/game/addons"
  cp -r "$BIN/Gut-${GUT_VERSION}/addons/gut" "$ROOT/game/addons/gut"
  rm -rf "$BIN/gut.zip" "$BIN/Gut-${GUT_VERSION}"
  echo "GUT vendored into game/addons/gut"
fi
echo "Done."
