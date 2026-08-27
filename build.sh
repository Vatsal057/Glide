#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  Glide — build.sh
#  Compiles all Swift sources and produces Glide.app
#  Compatible with macOS 13+ (Apple Silicon & Intel)
#
#  Usage:
#    ./build.sh
#        Build the app only.
#
#    ./build.sh restart
#        Build the app, then quit any running instance and launch
#        the freshly built app.
#
#    ./build.sh restart-only
#        Skip compilation and launch the already-built app.
#
#    ./build.sh --release
#        Build an optimized Universal (arm64 + x86_64) app.
#
#    ./build.sh --dmg
#        Build an optimized Universal app and create a DMG.
#
#    ./build.sh --help
#        Show this usage information.
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


# ─────────────────────────────────────────────────────────────
# Help
# ─────────────────────────────────────────────────────────────

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<EOF
Glide build script

Usage:
  ./build.sh
      Build the app only.

  ./build.sh restart
      Build the app, then restart the running app using the
      freshly built binary.

  ./build.sh restart-only
      Skip compilation and restart the already-built app.

  ./build.sh --release
      Build an optimized Universal (arm64 + x86_64) app.

  ./build.sh --dmg
      Build an optimized Universal app and create a DMG.

Notes:
  - "restart" ALWAYS builds before restarting.
  - "restart-only" is the ONLY command that skips the build.
EOF
    exit 0
fi


# ─────────────────────────────────────────────────────────────
# Restart existing app
# ─────────────────────────────────────────────────────────────

# Quits any running instance and relaunches the currently built app.
restart_app() {
    echo "==> Quitting any running $APP_NAME instance"

    osascript -e "tell application \"$APP_NAME\" to quit" \
        >/dev/null 2>&1 || true

    pkill -x "$APP_NAME" \
        >/dev/null 2>&1 || true

    for _ in {1..20}; do
        if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done

    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        echo "==> Force quitting stubborn $APP_NAME process"
        pkill -9 -x "$APP_NAME" \
            >/dev/null 2>&1 || true
    fi

    if [[ ! -x "$APP_EXECUTABLE" ]]; then
        echo "ERROR: Built executable not found at:"
        echo "  $APP_EXECUTABLE"
        echo ""
        echo "Run ./build.sh first, then run:"
        echo "  ./build.sh restart-only"
        exit 1
    fi

    echo "==> Opening built $APP_NAME"
    open "$APP_BUNDLE"

    cat <<EOF

Done.

App bundle:
  $APP_BUNDLE

EOF
}


# ─────────────────────────────────────────────────────────────
# Restart-only
# ─────────────────────────────────────────────────────────────

# IMPORTANT:
# This intentionally skips compilation.
#
# Use:
#   ./build.sh restart
# for the normal "build + restart" workflow.
#
# Use:
#   ./build.sh restart-only
# ONLY when you want to launch the existing build again.
if [[ "${1:-}" == "restart-only" ]]; then
    restart_app
    exit 0
fi


# ─────────────────────────────────────────────────────────────
# Build
# ─────────────────────────────────────────────────────────────

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building $APP_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"


# ─────────────────────────────────────────────────────────────
# Check swiftc
# ─────────────────────────────────────────────────────────────

if ! command -v swiftc &>/dev/null; then
    echo "❌  swiftc not found. Install Xcode or Xcode Command Line Tools."
    echo "    Run: xcode-select --install"
    exit 1
fi

SWIFT_VERSION=$(swiftc --version 2>&1 | head -1)
echo "Swift: $SWIFT_VERSION"


# ─────────────────────────────────────────────────────────────
# Clean previous build
# ─────────────────────────────────────────────────────────────

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS" "$RESOURCES"


# ─────────────────────────────────────────────────────────────
# Copy Info.plist
# ─────────────────────────────────────────────────────────────

cp "$SCRIPT_DIR/Info.plist" "$CONTENTS/Info.plist"


# ─────────────────────────────────────────────────────────────
# Copy app icon
# ─────────────────────────────────────────────────────────────

if [[ -f "$SCRIPT_DIR/assets/AppIcon.icns" ]]; then
    cp "$SCRIPT_DIR/assets/AppIcon.icns" "$RESOURCES/AppIcon.icns"
    echo "Icon: AppIcon.icns copied"
fi


# ─────────────────────────────────────────────────────────────
# Collect Swift sources
# ─────────────────────────────────────────────────────────────

SOURCES=()

while IFS= read -r -d $'\0'; do
    SOURCES+=("$REPLY")
done < <(
    find "$SCRIPT_DIR/Sources" -name "*.swift" -print0
)


# Verify all sources exist
for src in "${SOURCES[@]}"; do
    if [[ ! -f "$src" ]]; then
        echo "❌  Missing source: $src"
        exit 1
    fi
done


# ─────────────────────────────────────────────────────────────
# Determine SDK
# ─────────────────────────────────────────────────────────────

echo "Compiling…"

SDK_PATH="$(xcrun --show-sdk-path)"

# xcrun can resolve to a CommandLineTools SDK whose Swift module
# was built by a newer compiler than the installed swiftc.
#
# The active Xcode bundles an SDK matching its own swiftc, so
# prefer it when present; fall back to xcrun on CLT-only machines.
XCODE_SDK="$(
    xcode-select -p 2>/dev/null
)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

[[ -d "$XCODE_SDK" ]] && SDK_PATH="$XCODE_SDK"


# ─────────────────────────────────────────────────────────────
# Determine build mode
# ─────────────────────────────────────────────────────────────

IS_RELEASE=0

for arg in "$@"; do
    if [[ "$arg" == "--release" || "$arg" == "--dmg" ]]; then
        IS_RELEASE=1
    fi
done

if [[ "$IS_RELEASE" == 1 ]]; then
    ARCHS=(arm64 x86_64)
    SWIFT_OPT="-O"

    echo "Mode: Release (Universal, Optimized)"
else
    ARCHS=($(uname -m))
    SWIFT_OPT="-Onone"

    echo "Mode: Debug (Native arch only, Fast build)"
fi


# ─────────────────────────────────────────────────────────────
# Compile
# ─────────────────────────────────────────────────────────────

BINARIES=()

for arch in "${ARCHS[@]}"; do
    echo ""
    echo "==> Compiling $arch"

    out="$BUILD_DIR/$APP_NAME-$arch"

    # Multitouch bridge
    c_out="$BUILD_DIR/GlideMultitouchBridge-$arch.o"

    clang \
        -O3 \
        -target "$arch-apple-macosx13.0" \
        -isysroot "$SDK_PATH" \
        -c \
        "$SCRIPT_DIR/Sources/Gestures/Components/GlideMultitouchBridge.c" \
        -o "$c_out"

    # WindowServer bridge
    c2_out="$BUILD_DIR/GlideWindowServerBridge-$arch.o"

    clang \
        -O3 \
        -target "$arch-apple-macosx13.0" \
        -isysroot "$SDK_PATH" \
        -c \
        "$SCRIPT_DIR/Sources/Actions/Components/GlideWindowServerBridge.c" \
        -o "$c2_out"

    if swiftc \
        $SWIFT_OPT \
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
        2>&1
    then
        BINARIES+=("$out")
    elif [[ "$arch" == "$(uname -m)" ]]; then
        echo "❌  Native $arch build failed"
        exit 1
    else
        echo "⚠️  Skipping optional $arch build on this machine"
    fi
done


# ─────────────────────────────────────────────────────────────
# Create final app executable
# ─────────────────────────────────────────────────────────────

if [[ ${#BINARIES[@]} -eq 0 ]]; then
    echo "❌  No app binary was produced"
    exit 1

elif [[ ${#BINARIES[@]} -eq 1 ]]; then
    cp "${BINARIES[0]}" "$MACOS/$APP_NAME"

else
    lipo \
        -create \
        "${BINARIES[@]}" \
        -output "$MACOS/$APP_NAME"
fi

echo "✅  Compile succeeded"


# ─────────────────────────────────────────────────────────────
# Code sign
# ─────────────────────────────────────────────────────────────

echo "Signing…"

DEV_ID_CERT=$(
    security find-identity -v -p codesigning 2>/dev/null \
        | sed -n \
        's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' \
        | head -1
)

if [[ -z "$DEV_ID_CERT" ]]; then
    DEV_ID_CERT=$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -n \
            's/.*"\(Apple Development: [^"]*\)".*/\1/p' \
            | head -1
    )
fi

IDENTITY="${DEV_ID_CERT:--}"


if [[ "$IDENTITY" == "-" ]]; then

    echo "⚠️  No Developer ID or Apple Development cert — ad-hoc signing."
    echo "    Downloaded copies need Settings → Privacy & Security → Open Anyway (once)."

    codesign \
        --force \
        --sign - \
        --entitlements "$SCRIPT_DIR/Glide.entitlements" \
        "$APP_BUNDLE"

else

    echo "Identity: $IDENTITY"

    codesign \
        --force \
        --sign "$IDENTITY" \
        --options runtime \
        --timestamp \
        --entitlements "$SCRIPT_DIR/Glide.entitlements" \
        "$APP_BUNDLE"

fi


# ─────────────────────────────────────────────────────────────
# Verify signature
# ─────────────────────────────────────────────────────────────

codesign --verify --strict "$APP_BUNDLE"

if ! codesign \
    -d \
    --entitlements - \
    --xml \
    "$APP_BUNDLE" 2>/dev/null \
    | grep -q "com.apple.security.automation.apple-events"
then
    echo "❌  Entitlements missing after signing" >&2
    exit 1
fi

echo "✅  Signed"


# ─────────────────────────────────────────────────────────────
# Optional DMG
# ─────────────────────────────────────────────────────────────

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

    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$DMG_STAGE" \
        -ov \
        -format UDZO \
        "$DMG_PATH"

    rm -rf "$DMG_STAGE"


    # Notarize + staple when a Developer ID cert and stored
    # notarytool credentials exist.
    #
    # Setup:
    #
    #   xcrun notarytool store-credentials glide-notary \
    #     --apple-id <email> \
    #     --team-id <TEAMID> \
    #     --password <app-specific-pw>

    if [[ -n "$DEV_ID_CERT" ]] && \
       xcrun notarytool history \
           --keychain-profile glide-notary \
           >/dev/null 2>&1
    then

        echo "Notarizing…"

        xcrun notarytool submit \
            "$DMG_PATH" \
            --keychain-profile glide-notary \
            --wait

        xcrun stapler staple "$DMG_PATH"

        xcrun stapler validate "$DMG_PATH"

        echo "✅  Notarized and stapled"

    else

        echo "ℹ️  Skipping notarization (needs a Developer ID cert +"
        echo "    'xcrun notarytool store-credentials glide-notary' setup)."

    fi

    echo "✅  DMG: $DMG_PATH"
fi


# ─────────────────────────────────────────────────────────────
# Print result
# ─────────────────────────────────────────────────────────────

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


# ─────────────────────────────────────────────────────────────
# Optional restart
# ─────────────────────────────────────────────────────────────

# "restart" means BUILD + RESTART.
#
# This is intentionally at the very end so the freshly compiled,
# signed app is what gets launched.
if [[ "${1:-}" == "restart" ]]; then
    echo "==> Build complete — restarting $APP_NAME"
    restart_app
fi