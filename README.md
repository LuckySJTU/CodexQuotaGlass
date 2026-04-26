# CodexQuotaGlass

CodexQuotaGlass is a native macOS menu bar app for showing Codex usage quota. It displays the five-hour and weekly remaining quota in the menu bar, a Liquid Glass-style detail panel, and desktop widgets.

The app keeps its own auth file at:

```text
~/Library/Application Support/CodexQuotaGlass/auth.json
```

It can authenticate in two ways:

- Browser login through OpenAI/Codex OAuth.
- "从 Codex 快捷登录", which imports an existing local `~/.codex/auth.json` once into the app's private auth store.

## Requirements

- macOS 14 or newer.
- Xcode 26.4 or newer for the full app bundle and WidgetKit extension.
- Swift 6 toolchain.
- A personal Apple Development signing team if you want the desktop widget to appear in the macOS widget gallery.

## Repository Layout

```text
Package.swift                         SwiftPM package for source-level builds
CodexQuotaGlass.xcodeproj             Xcode project for app + framework + widget
Sources/CodexQuotaGlass               Menu bar app source
Sources/CodexQuotaKit                 Shared quota/auth/cache library
Extensions/CodexQuotaWidgets          WidgetKit extension
Xcode/CodexQuotaGlass                 App Info.plist and AppIcon asset catalog
script/build_and_run.sh               Local unsigned build/run helper
script/install_signed_debug_app.sh    Signed build, install, widget registration helper
```

## SwiftPM Build

SwiftPM is useful for fast compile verification of the shared code and menu bar executable:

```bash
swift build
```

Products:

- `CodexQuotaGlass`: executable target for the app logic.
- `CodexQuotaKit`: shared library target for auth, usage fetch, formatting, and cache.

SwiftPM does not produce a real macOS `.app` bundle with the WidgetKit extension. Use the Xcode project for anything involving desktop widgets, signing, or installation.

## Xcode Compile Check

This checks the full Xcode project without requiring code signing:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project CodexQuotaGlass.xcodeproj \
  -scheme CodexQuotaGlass \
  -configuration Debug \
  -derivedDataPath DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The unsigned build verifies compilation, but it will not install or register the desktop widget.

## Run Locally

For a quick unsigned local app run:

```bash
./script/build_and_run.sh
```

Useful modes:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --debug
```

By default this writes build output to `DerivedData/`, which is ignored by Git.

## Signing Setup

Desktop widgets require a signed app installed in `/Applications`.

1. Open `CodexQuotaGlass.xcodeproj` in Xcode.
2. Select the `CodexQuotaGlass` app target.
3. Open Signing & Capabilities.
4. Enable "Automatically manage signing".
5. Select your Team.
6. Confirm App Groups is enabled.
7. Select the `CodexQuotaWidgets` extension target.
8. Use the same Team and App Groups capability.
9. Build the `CodexQuotaGlass` scheme for `My Mac`.

The app group is defined as:

```text
$(TeamIdentifierPrefix)CodexQuotaGlass
```

At build time Xcode expands this to a Team ID-prefixed value such as:

```text
C4ZGXC6MY9.CodexQuotaGlass
```

Both the app and widget read the expanded value from their bundled Info.plist files, so the shared quota cache stays aligned across targets.

## Install Signed Build

After signing is configured, install the Release build into `/Applications`:

```bash
CONFIGURATION=Release \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
./script/install_signed_debug_app.sh
```

The script:

- Builds the app with Xcode.
- Stops any running `CodexQuotaGlass` process.
- Copies the app to `/Applications/CodexQuotaGlass.app`.
- Registers the WidgetKit extension.
- Launches the app.

If the widget gallery is already open, close and reopen it, then search for `Codex Quota`.

## Verify Installation

```bash
codesign -vvv --strict /Applications/CodexQuotaGlass.app \
  /Applications/CodexQuotaGlass.app/Contents/PlugIns/CodexQuotaWidgets.appex

pluginkit -m -A -D -v -p com.apple.widgetkit-extension | grep -i "CodexQuota"

plutil -p /Applications/CodexQuotaGlass.app/Contents/Info.plist
```

The installed app should contain:

```text
/Applications/CodexQuotaGlass.app/Contents/Resources/AppIcon.icns
/Applications/CodexQuotaGlass.app/Contents/Resources/Assets.car
```

## Build a DMG

Build and install a signed Release app first:

```bash
CONFIGURATION=Release \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
./script/install_signed_debug_app.sh
```

Then create a distributable DMG in the repository root:

```bash
mkdir -p dist/dmg-root
ditto /Applications/CodexQuotaGlass.app dist/dmg-root/CodexQuotaGlass.app
hdiutil create \
  -volname CodexQuotaGlass \
  -srcfolder dist/dmg-root \
  -ov \
  -format UDZO \
  CodexQuotaGlass.dmg
```

`CodexQuotaGlass.dmg` is ignored by Git and should be distributed separately unless you intentionally publish it as a release artifact.

## Authentication Notes

Browser login uses a local callback server on:

```text
http://localhost:1455/auth/callback
```

The app requests the OAuth scopes:

```text
openid profile email offline_access
```

After login, the app saves tokens only to its private Application Support auth file. Widgets never receive tokens; they only read cached quota values from the app group container.

## Troubleshooting

If the widget does not appear:

```bash
pluginkit -m -A -D -v -p com.apple.widgetkit-extension | grep -i "CodexQuota"
```

If multiple entries appear, remove stale builds and reinstall:

```bash
pluginkit -r /path/to/stale/CodexQuotaWidgets.appex
CONFIGURATION=Release ./script/install_signed_debug_app.sh
```

If browser login fails with port unavailable, another process is already listening on `localhost:1455`. Stop the other login flow or restart the app and try again.
