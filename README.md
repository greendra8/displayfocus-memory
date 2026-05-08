# DisplayFocus Memory

A tiny macOS menu-bar utility that approximates per-monitor focus.

macOS has one global focused window. DisplayFocus Memory remembers the last normal focused window for each physical display, then restores that window when the pointer crosses into that display.

## Build

```sh
swift build
```

To build a runnable `.app` bundle:

```sh
make app
open build/DisplayFocusMemory.app
```

The app is `LSUIElement`, so it appears only in the menu bar as `DFM`.

## Install

For now, clone and build locally:

```sh
git clone https://github.com/greendra8/displayfocus-memory.git
cd displayfocus-memory
make app
open build/DisplayFocusMemory.app
```

On first launch, grant Accessibility permission in System Settings.

Published releases can provide a prebuilt, signed, notarized app bundle. If a release is signed with a Developer ID certificate and notarized by Apple, users can download and run it without building locally.

## Release Build

For local testing, `make app` creates an ad-hoc signed app. For public distribution, sign with Developer ID:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/build-release.sh
xcrun notarytool submit build/DisplayFocusMemory.zip --keychain-profile displayfocus-notary --wait
xcrun stapler staple build/DisplayFocusMemory.app
```

## Behavior

- Tracks the global focused app/window through Accessibility APIs.
- Maps focused windows to physical displays by largest frame overlap.
- Tracks global mouse movement and restores focus only when the mouse crosses displays.
- Uses a configurable restore delay, defaulting to `125 ms`.
- Avoids Dock, menu bar/system UI, hidden apps, minimized windows, non-standard windows, desktop elements, and windows that are not currently on-screen in the visible Space.
- Does not replay clicks, focus windows under the cursor, switch Spaces intentionally, or attempt true independent focus.

## Permissions

The app asks for Accessibility permission on first launch. Without it, DisplayFocus Memory stays idle and reports that permission is required from the menu-bar tooltip.

## Settings

The menu includes:

- Enable/disable
- Restore delay
- Start at Login
- Optional app ignore list
- Only restore on external displays

`Start at Login` requires running from the built `.app` bundle.
