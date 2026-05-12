#!/usr/bin/env bash
set -euo pipefail

APP_NAME="DisplayFocusMemory"
RELEASE_ROOT="${RELEASE_ROOT:-/tmp/displayfocus-memory-release}"
APP_BUNDLE="$RELEASE_ROOT/DisplayFocusMemory.app"
NOTARY_ZIP="$RELEASE_ROOT/DisplayFocusMemory-notary.zip"
OUTPUT_ZIP="build/DisplayFocusMemory.zip"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-displayfocus-notary}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  cat >&2 <<'EOF'
SIGN_IDENTITY is required for public releases.

Example:
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE="displayfocus-notary" \
  scripts/build-release.sh

For local ad-hoc testing, use:
  make app
EOF
  exit 1
fi

swift build -c release

rm -rf "$RELEASE_ROOT"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
find "$APP_BUNDLE" -exec xattr -c {} +

codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --strict --deep --verbose=2 "$APP_BUNDLE"

rm -f "$NOTARY_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"

xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

mkdir -p build
rm -f "$OUTPUT_ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$OUTPUT_ZIP"

echo "Built $APP_BUNDLE"
echo "Signed with $SIGN_IDENTITY"
echo "Notarized with keychain profile $NOTARY_PROFILE"
echo "Stapled $APP_BUNDLE"
echo "Created release archive $OUTPUT_ZIP"
