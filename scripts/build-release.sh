#!/usr/bin/env bash
set -euo pipefail

APP_NAME="DisplayFocusMemory"
APP_BUNDLE="build/DisplayFocusMemory.app"
ZIP_PATH="build/DisplayFocusMemory.zip"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "Built $APP_BUNDLE"
echo "Archived $ZIP_PATH"
