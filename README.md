# DisplayFocus Memory

A tiny macOS menu-bar app that remembers window focus per monitor.

macOS has one global focused window. DisplayFocus Memory remembers the last normal focused window for each physical display, then restores that window when the pointer crosses into that display.

## Install

1. Download `DisplayFocusMemory.zip` from the [latest release](https://github.com/greendra8/displayfocus-memory/releases/latest).
2. Unzip it.
3. Move `DisplayFocusMemory.app` to your `Applications` folder.
4. Open it.
5. Grant Accessibility permission when macOS asks.

The app appears in the menu bar as `DFM`.

## Build From Source

You only need this if you want to modify the app or build it yourself.

```sh
git clone https://github.com/greendra8/displayfocus-memory.git
cd displayfocus-memory
make app
open build/DisplayFocusMemory.app
```

To check the Swift package without creating an app bundle:

```sh
swift build
```

## Release Build

For local testing, `make app` creates an ad-hoc signed app. Do not upload that app for users.

For public distribution, use `scripts/build-release.sh`. It signs the app with Developer ID, submits it for notarization, staples the notarization ticket, then creates the final GitHub release zip at `build/DisplayFocusMemory.zip`.

See `RELEASE.md` for the full release checklist.

Create a notarization keychain profile once:

```sh
xcrun notarytool store-credentials displayfocus-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Then build the release:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE="displayfocus-notary" \
  scripts/build-release.sh
```

Upload `build/DisplayFocusMemory.zip` to GitHub Releases.

## Behavior

- Tracks the global focused app/window through Accessibility APIs.
- Maps focused windows to physical displays by largest frame overlap.
- Tracks global mouse movement and restores focus only when the mouse crosses displays.
- Uses a configurable restore delay, defaulting to `125 ms`.
- Avoids Dock, menu bar/system UI, hidden apps, minimized windows, non-standard windows, desktop elements, and windows that are not currently on-screen in the visible Space.
- Does not replay clicks, focus windows under the cursor, switch Spaces intentionally, or attempt true independent focus.

## Permissions

The app asks for Accessibility permission on first manual launch when permission is missing. When it starts automatically at login, it checks permission silently so macOS does not show the Accessibility prompt on every boot. If needed, use `Request Accessibility Permission` in the menu to open the macOS permission flow again.

## Settings

The menu includes:

- Enable/disable
- Restore delay
- Start at Login
- Optional app ignore list
- Only restore on external displays

`Start at Login` requires running from the built `.app` bundle.
