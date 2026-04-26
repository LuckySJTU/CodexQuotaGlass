#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexQuotaGlass"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/CodexQuotaGlass.xcodeproj"
DERIVED_DATA="$ROOT_DIR/DerivedData"
CONFIGURATION="${CONFIGURATION:-Release}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"
INSTALL_APP="/Applications/$APP_NAME.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
WIDGET_APPEX="Contents/PlugIns/CodexQuotaWidgets.appex"

export DEVELOPER_DIR

xcodebuild \
  -project "$PROJECT" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

rm -rf "$INSTALL_APP"
ditto "$BUILT_APP" "$INSTALL_APP"

pluginkit -r "$BUILT_APP/$WIDGET_APPEX" >/dev/null 2>&1 || true
"$LSREGISTER" -f -R -trusted "$INSTALL_APP"
pluginkit -a "$INSTALL_APP/$WIDGET_APPEX"

/usr/bin/open -n "$INSTALL_APP"

echo "Installed and launched $CONFIGURATION build at $INSTALL_APP"
echo "If the widget gallery is already open, close and reopen it, then search for Codex Quota."
