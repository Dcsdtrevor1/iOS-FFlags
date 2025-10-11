#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
SRC_DIR="$PROJECT_ROOT/src"
OUT_DIR="$PROJECT_ROOT/build/ios-arm64"
DYLIB_NAME="libRobloxFFlags.dylib"
FFLAGS_JSON="$PROJECT_ROOT/config/fflags.json"
HEADER_OUT="$SRC_DIR/FFlagsData.h"

mkdir -p "$OUT_DIR"

if [[ ! -f "$FFLAGS_JSON" ]]; then
  echo "[build] Missing $FFLAGS_JSON" >&2
  exit 1
fi

python3 - "$FFLAGS_JSON" "$HEADER_OUT" <<'PY'
import json, sys, pathlib
src = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    f.write('// Auto-generated. Do not edit by hand.\n')
    f.write('static const char *kFFlagsJSON = ' + json.dumps(src) + ';\n')
print(f"[build] Wrote {sys.argv[2]}")
PY

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)

xcrun -sdk iphoneos clang \
  -arch arm64 \
  -isysroot "$SDK_PATH" \
  -miphoneos-version-min=12.0 \
  -fobjc-arc \
  -framework Foundation \
  -shared "$SRC_DIR/FFlagInjector.m" \
  -install_name @rpath/$DYLIB_NAME \
  -o "$OUT_DIR/$DYLIB_NAME"

echo "[build] Built: $OUT_DIR/$DYLIB_NAME"