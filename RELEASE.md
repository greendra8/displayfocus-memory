# Release Checklist

Use this checklist for GitHub releases that are easy for users to install.

## One-Time Setup

Install the Developer ID certificate in Keychain Access. This machine currently uses:

```sh
Developer ID Application: Arintelli LTD (28Z4J6ZWFK)
```

Create the notarization keychain profile once:

```sh
xcrun notarytool store-credentials displayfocus-notary \
  --apple-id "you@example.com" \
  --team-id "28Z4J6ZWFK" \
  --password "app-specific-password"
```

## Build And Upload A Release

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Info.plist`.
2. Commit the version and release-script changes.
3. Tag the commit, for example:

```sh
git tag v0.1.6
git push origin main --tags
```

4. Build the signed, notarized, stapled zip:

```sh
SIGN_IDENTITY="Developer ID Application: Arintelli LTD (28Z4J6ZWFK)" \
  NOTARY_PROFILE="displayfocus-notary" \
  scripts/build-release.sh
```

5. Upload `build/DisplayFocusMemory.zip` to the GitHub release.

Do not upload `make app` output. That build is ad-hoc signed for local testing.
