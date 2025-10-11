#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
DYLIB_PATH="$PROJECT_ROOT/build/ios-arm64/libRobloxFFlags.dylib"
IPA_PATH=${1:?"Usage: inject.sh <IPA_PATH> <CODESIGN_IDENTITY>"}
CODESIGN_ID=${2:?"Usage: inject.sh <IPA_PATH> <CODESIGN_IDENTITY>"}

if [[ ! -f "$DYLIB_PATH" ]]; then
  echo "[inject] Missing dylib at $DYLIB_PATH. Build it first via scripts/build.sh" >&2
  exit 1
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

cp "$IPA_PATH" "$WORKDIR/app.ipa"
(cd "$WORKDIR" && unzip -q app.ipa)

APP_DIR="$WORKDIR/Payload/Roblox.app"
FW_DIR="$APP_DIR/Frameworks"
BIN_PATH="$APP_DIR/Roblox"
mkdir -p "$FW_DIR"
cp "$DYLIB_PATH" "$FW_DIR/"

NEW_LOAD='@executable_path/Frameworks/libRobloxFFlags.dylib'

if command -v insert_dylib >/dev/null 2>&1; then
  echo "[inject] Adding LC_LOAD_DYLIB via insert_dylib"
  insert_dylib --weak "$NEW_LOAD" "$BIN_PATH" "$BIN_PATH.tmp" --inplace --overwrite || insert_dylib "$NEW_LOAD" "$BIN_PATH" "$BIN_PATH.tmp" --inplace --overwrite
elif command -v optool >/dev/null 2>&1; then
  echo "[inject] Adding LC_LOAD_DYLIB via optool"
  optool install -c load -p "$NEW_LOAD" -t "$BIN_PATH"
else
  echo "[inject] Missing insert_dylib/optool. Install one and retry." >&2
  exit 1
fi

/usr/bin/codesign -d --entitlements :- "$APP_DIR" > "$WORKDIR/entitlements.plist" || true

if ls "$FW_DIR"/* 1> /dev/null 2>&1; then
  for f in "$FW_DIR"/*; do
    echo "[inject] Signing: $f"
    /usr/bin/codesign -f -s "$CODESIGN_ID" --keychain "$HOME/Library/Keychains/login.keychain-db" --timestamp=none "$f"
  done
fi

/usr/bin/codesign -f -s "$CODESIGN_ID" --keychain "$HOME/Library/Keychains/login.keychain-db" --timestamp=none --entitlements "$WORKDIR/entitlements.plist" "$APP_DIR"
OUT_IPA="$PROJECT_ROOT/Roblox-fflags-resigned.ipa"
(cd "$WORKDIR" && zip -ry "$OUT_IPA" Payload)

echo "[inject] Done: $OUT_IPA"
