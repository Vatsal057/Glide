#!/bin/bash
# ─────────────────────────────────────────────────────────────
#  GestureFlow — build.sh
#  Compiles all Swift sources and produces GestureFlow.app
#  Compatible with macOS 13+ (Apple Silicon & Intel)
# ─────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="GestureFlow"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

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
SOURCES=(
    "$SCRIPT_DIR/Sources/main.swift"
    "$SCRIPT_DIR/Sources/MultitouchBridge.swift"
    "$SCRIPT_DIR/Sources/Settings.swift"
    "$SCRIPT_DIR/Sources/ActionExecutor.swift"
    "$SCRIPT_DIR/Sources/GestureEngine.swift"
    "$SCRIPT_DIR/Sources/PreferencesWindow.swift"
    "$SCRIPT_DIR/Sources/PreferencesUI.swift"
    "$SCRIPT_DIR/Sources/AppDelegate.swift"
)

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
    --entitlements "$SCRIPT_DIR/GestureFlow.entitlements" \
    "$APP_BUNDLE" 2>/dev/null || \
codesign --force --sign - "$APP_BUNDLE"

echo "✅  Signed"

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
echo "     and enable GestureFlow."
echo "  4. The hand icon will appear in your menu bar."
echo ""
echo "Optional — move to Applications:"
echo "  cp -r \"$APP_BUNDLE\" /Applications/"
echo ""
