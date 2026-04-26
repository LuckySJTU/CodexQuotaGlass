# WidgetKit Targets

`CodexQuotaWidgets` is a target in `../CodexQuotaGlass.xcodeproj`. It stays outside `Package.swift` because SwiftPM cannot register a macOS WidgetKit extension with the system.

The extension target uses:

- `Extensions/CodexQuotaWidgets/CodexQuotaWidgets.swift`
- `Extensions/CodexQuotaWidgets/Info.plist`
- `Extensions/CodexQuotaWidgets/CodexQuotaWidgets.entitlements`
- `CodexQuotaKit.framework`

The main app uses its private auth file in `~/Library/Application Support/CodexQuotaGlass/auth.json` to request usage from ChatGPT, writes only the resulting quota snapshot to `quota.json` in the shared app group container, and asks WidgetKit to reload widgets. The private auth file can be created either by one-time import from `~/.codex/auth.json` or by the app's browser login flow.

For system registration, open the Xcode project, select the same Team for both the app and widget extension targets, enable App Groups for both targets, then run the app target or install a signed debug build with `../script/install_signed_debug_app.sh`.
