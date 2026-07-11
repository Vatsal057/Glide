#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  Glide — build.sh
#  Compiles all Swift sources and produces Glide.app
#  Compatible with macOS 13+ (Apple Silicon & Intel)
# ─────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Glide"
BUNDLE_ID="com.glide.app"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
APP_EXECUTABLE="$MACOS/$APP_NAME"

# Quits any running instance, resets Accessibility/Automation permissions
# (so macOS re-prompts for a freshly rebuilt binary), and relaunches.
restart_app() {
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
        echo "Run ./build.sh first, then run this again." >&2
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
}

# ── Restart-only: skip the build entirely ────
if [[ "${1:-}" == "--restart-only" ]]; then
    restart_app
    exit 0
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building $APP_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Check swiftc ──────────────────────────────
if ! command -v swiftc &>/dev/null; then
    echo "❌  swiftc not found. Install Xcode or Xcode Command Line Tools."
    echo "    Run: xcode-select --install"
    exit 1
fi

SWIFT_VERSION=$(swiftc --version 2>&1 | head -1)
echo "Swift: $SWIFT_VERSION"

# ── Clean previous build ─────────────────────
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"

# ── Copy Info.plist ──────────────────────────
cp "$SCRIPT_DIR/Info.plist" "$CONTENTS/Info.plist"

# ── Copy app icon ────────────────────────────
if [[ -f "$SCRIPT_DIR/assets/AppIcon.icns" ]]; then
    cp "$SCRIPT_DIR/assets/AppIcon.icns" "$RESOURCES/AppIcon.icns"
    echo "Icon: AppIcon.icns copied"
fi

# ── Collect Swift sources ────────────────────
SOURCES=()
while IFS=  read -r -d $'\0'; do
    SOURCES+=("$REPLY")
done < <(find "$SCRIPT_DIR/Sources" -name "*.swift" -print0)

# Verify all sources exist
for src in "${SOURCES[@]}"; do
    if [[ ! -f "$src" ]]; then
        echo "❌  Missing source: $src"
        exit 1
    fi
done

# ── Compile ──────────────────────────────────
echo "Compiling…"

SDK_PATH="$(xcrun --show-sdk-path)"
ARCHS=(arm64 x86_64)
BINARIES=()

for arch in "${ARCHS[@]}"; do
    out="$BUILD_DIR/$APP_NAME-$arch"
    if swiftc \
        -O \
        -target "$arch-apple-macosx13.0" \
        -sdk "$SDK_PATH" \
        -framework Cocoa \
        -framework SwiftUI \
        -framework IOKit \
        -framework CoreGraphics \
        -framework UniformTypeIdentifiers \
        -o "$out" \
        "${SOURCES[@]}" \
        2>&1; then
        BINARIES+=("$out")
    elif [[ "$arch" == "$(uname -m)" ]]; then
        echo "❌  Native $arch build failed"
        exit 1
    else
        echo "⚠️  Skipping optional $arch build on this machine"
    fi
done

if [[ ${#BINARIES[@]} -eq 0 ]]; then
    echo "❌  No app binary was produced"
    exit 1
elif [[ ${#BINARIES[@]} -eq 1 ]]; then
    cp "${BINARIES[0]}" "$MACOS/$APP_NAME"
else
    lipo -create "${BINARIES[@]}" -output "$MACOS/$APP_NAME"
fi

echo "✅  Compile succeeded"

# ── Ad-hoc code sign ─────────────────────────
echo "Signing…"
codesign --force --sign - \
    --entitlements "$SCRIPT_DIR/Glide.entitlements" \
    "$APP_BUNDLE" 2>/dev/null || \
codesign --force --sign - "$APP_BUNDLE"

echo "✅  Signed"

# ── Optional DMG for distribution ────────────
if [[ "${1:-}" == "--dmg" ]]; then
    echo "Creating DMG…"
    DMG_STAGE="$BUILD_DIR/dmg-stage"
    DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
    rm -rf "$DMG_STAGE" "$DMG_PATH"
    mkdir -p "$DMG_STAGE"
    cp -R "$APP_BUNDLE" "$DMG_STAGE/"
    ln -s /Applications "$DMG_STAGE/Applications"
    cat > "$DMG_STAGE/READ ME - How to Install.txt" <<'EOF'
How to install Glide
====================

1. Drag Glide.app onto the Applications folder icon.

2. Because Glide is a free open-source app (not notarized by Apple),
   macOS may say the app is "damaged" on first launch. It is not.
   Open Terminal and run this one line to fix it:

       xattr -cr /Applications/Glide.app

3. Open Glide from Applications. When prompted, grant Accessibility
   access in System Settings -> Privacy & Security -> Accessibility.

4. Look for the hand icon in your menu bar. Enjoy!
EOF
    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"
    rm -rf "$DMG_STAGE"
    echo "✅  DMG: $DMG_PATH"
fi

# ── Print result ─────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  App bundle: $APP_BUNDLE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  1. Run:  open \"$APP_BUNDLE\""
echo "  2. macOS will prompt for Accessibility permission."
echo "  3. Go to System Settings → Privacy & Security → Accessibility"
echo "     and enable Glide."
echo "  4. The hand icon will appear in your menu bar."
echo ""
echo "Optional — move to Applications:"
echo "  cp -r \"$APP_BUNDLE\" /Applications/"
echo ""

# ── Optional restart ─────────────────────────
if [[ "${1:-}" == "--restart" ]]; then
    restart_app
fi
