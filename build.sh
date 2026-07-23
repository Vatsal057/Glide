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
# xcrun can resolve to a CommandLineTools SDK whose Swift module was built by a
# newer compiler than the installed swiftc (fails with "SDK is not supported by
# the compiler"). The active Xcode always bundles an SDK matching its own swiftc,
# so prefer it when present; fall back to xcrun on CLT-only machines (e.g. CI).
XCODE_SDK="$(xcode-select -p 2>/dev/null)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
[[ -d "$XCODE_SDK" ]] && SDK_PATH="$XCODE_SDK"
ARCHS=(arm64 x86_64)
BINARIES=()

for arch in "${ARCHS[@]}"; do
    out="$BUILD_DIR/$APP_NAME-$arch"
    
    c_out="$BUILD_DIR/GlideMultitouchBridge-$arch.o"
    clang -O3 -target "$arch-apple-macosx13.0" -isysroot "$SDK_PATH" -c "$SCRIPT_DIR/Sources/Gestures/Components/GlideMultitouchBridge.c" -o "$c_out"

    c2_out="$BUILD_DIR/GlideWindowServerBridge-$arch.o"
    clang -O3 -target "$arch-apple-macosx13.0" -isysroot "$SDK_PATH" -c "$SCRIPT_DIR/Sources/Actions/Components/GlideWindowServerBridge.c" -o "$c2_out"

    if swiftc \
        -O \
        -target "$arch-apple-macosx13.0" \
        -sdk "$SDK_PATH" \
        -import-objc-header "$SCRIPT_DIR/Sources/App/Internal/Glide-Bridging-Header.h" \
        -framework Cocoa \
        -framework SwiftUI \
        -framework IOKit \
        -framework CoreGraphics \
        -framework UniformTypeIdentifiers \
        -o "$out" \
        "${SOURCES[@]}" \
        "$c_out" \
        "$c2_out" \
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

# ── Code sign ────────────────────────────────
# Developer ID (notarizable, zero user friction) → ad-hoc. No Apple
# Development rung: verified on macOS 26 that below Developer ID +
# notarization, every signature gets the identical "Not Opened" dialog
# and the same Settings → Open Anyway path — a dev cert buys nothing.
echo "Signing…"

DEV_ID_CERT=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)

IDENTITY="${DEV_ID_CERT:--}"

if [[ "$IDENTITY" == "-" ]]; then
    echo "⚠️  No Developer ID certificate — ad-hoc signing."
    echo "    Downloaded copies need Settings → Privacy & Security → Open Anyway (once)."
    codesign --force --sign - \
        --entitlements "$SCRIPT_DIR/Glide.entitlements" \
        "$APP_BUNDLE"
else
    echo "Identity: $IDENTITY"
    codesign --force --sign "$IDENTITY" \
        --options runtime --timestamp \
        --entitlements "$SCRIPT_DIR/Glide.entitlements" \
        "$APP_BUNDLE"
fi

# Verify: signature valid AND entitlements survived signing.
codesign --verify --strict "$APP_BUNDLE"
if ! codesign -d --entitlements - --xml "$APP_BUNDLE" 2>/dev/null \
    | grep -q "com.apple.security.automation.apple-events"; then
    echo "❌  Entitlements missing after signing" >&2
    exit 1
fi

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

2. Glide is a free open-source app and is not notarized by Apple,
   so macOS blocks it on first launch. It is NOT damaged. To open it
   (needed only once):

   - Double-click Glide. macOS says it was "Not Opened" - click Done.
   - Open System Settings -> Privacy & Security, scroll down to
     "Glide.app was blocked", and click "Open Anyway".

   On macOS 14 or older you can instead right-click (Control-click)
   Glide in Applications, choose "Open", then click "Open".

   If an older Mac claims the app is "damaged", run this one line
   in Terminal:

       xattr -cr /Applications/Glide.app

3. Open Glide from Applications. When prompted, grant Accessibility
   access in System Settings -> Privacy & Security -> Accessibility.

4. Look for the hand icon in your menu bar. Enjoy!
EOF
    hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"
    rm -rf "$DMG_STAGE"

    # Notarize + staple when a Developer ID cert and stored
    # notarytool credentials exist (paid Apple Developer account):
    #   xcrun notarytool store-credentials glide-notary \
    #     --apple-id <email> --team-id <TEAMID> --password <app-specific-pw>
    if [[ -n "$DEV_ID_CERT" ]] && \
       xcrun notarytool history --keychain-profile glide-notary >/dev/null 2>&1; then
        echo "Notarizing…"
        xcrun notarytool submit "$DMG_PATH" --keychain-profile glide-notary --wait
        xcrun stapler staple "$DMG_PATH"
        xcrun stapler validate "$DMG_PATH"
        echo "✅  Notarized and stapled"
    else
        echo "ℹ️  Skipping notarization (needs a Developer ID cert +"
        echo "    'xcrun notarytool store-credentials glide-notary' setup)."
    fi

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
