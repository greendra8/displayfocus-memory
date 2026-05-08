#!/usr/bin/env bash
set -euo pipefail

APP_NAME="DisplayFocusMemory"
RELEASE_ROOT="${RELEASE_ROOT:-/tmp/displayfocus-memory-release}"
APP_BUNDLE="$RELEASE_ROOT/DisplayFocusMemory.app"
ZIP_PATH="$RELEASE_ROOT/DisplayFocusMemory.zip"
OUTPUT_ZIP="build/DisplayFocusMemory.zip"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

swift build -c release

rm -rf "$RELEASE_ROOT"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
find "$APP_BUNDLE" -exec xattr -c {} +

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
mkdir -p build
cp "$ZIP_PATH" "$OUTPUT_ZIP"

echo "Built $APP_BUNDLE"
echo "Archived $ZIP_PATH"
echo "Copied archive to $OUTPUT_ZIP"
