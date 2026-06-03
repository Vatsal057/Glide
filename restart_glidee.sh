#!/bin/bash
# Relaunch the existing built Glide app and reset Accessibility permissions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Glide"
BUNDLE_ID="com.glide.app"
APP_BUNDLE="$SCRIPT_DIR/build/$APP_NAME.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "==> Quitting any running $APP_NAME instance"
osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

for _ in {1..20}; do
    if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    echo "==> Force quitting stubborn $APP_NAME process"
    pkill -9 -x "$APP_NAME" >/dev/null 2>&1 || true
fi

if [[ ! -x "$APP_EXECUTABLE" ]]; then
    echo "ERROR: Built executable not found at $APP_EXECUTABLE" >&2
    echo "Run ./build.sh first, then run this script again." >&2
    exit 1
fi

echo "==> Resetting Accessibility permission for $BUNDLE_ID"
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "==> Resetting Automation permission for $BUNDLE_ID"
tccutil reset AppleEvents "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "==> Opening built $APP_NAME"
open "$APP_BUNDLE"

sleep 2

echo "==> Opening Accessibility settings"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" >/dev/null 2>&1 || true

cat <<EOF

Done.

Accessibility permission has been reset for:
  $BUNDLE_ID

If Glide still appears in the list, remove it manually and then
enable the newly launched instance when prompted.

App bundle:
  $APP_BUNDLE

EOF