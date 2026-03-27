#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# build.sh  —  Compile ThreeFingerQuit and create a runnable .app bundle
# Usage:  chmod +x build.sh && ./build.sh
# ─────────────────────────────────────────────────────────────────────────────
set -e

APP_NAME="Glide"
BUNDLE_NAME="${APP_NAME}.app"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
APP_DIR="${BUILD_DIR}/${BUNDLE_NAME}"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"

echo "🔨 Building ${BUNDLE_NAME}…"

# ── 1. Clean & scaffold ───────────────────────────────────────────────────────
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# ── 2. Compile ────────────────────────────────────────────────────────────────
swiftc \
    -O \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -target arm64-apple-macosx12.0 \
    -framework Cocoa \
    "${SCRIPT_DIR}/"*.swift \
    -o "${MACOS_DIR}/${APP_NAME}"

# If you're on an Intel Mac, swap the -target line above for:
#   -target x86_64-apple-macosx12.0
# Or build a Universal binary (arm64 + x86_64):
#   Remove -target entirely and add: -arch arm64 -arch x86_64

# ── 3. Copy Info.plist ────────────────────────────────────────────────────────
cp "${SCRIPT_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist"

# ── 4. Create PkgInfo ─────────────────────────────────────────────────────────
printf 'APPL????' > "${APP_DIR}/Contents/PkgInfo"

# ── 5. Ad-hoc code sign (required for accessibility API) ─────────────────────
echo "✍️  Signing…"
codesign --force --deep --sign - "${APP_DIR}"

echo ""
echo "✅ Built successfully → ${APP_DIR}"
echo ""
echo "Next steps:"
echo "  1. Copy ${BUNDLE_NAME} to your /Applications folder (optional)"
echo "  2. Double-click it to launch"
echo "  3. macOS will ask for Accessibility permission — grant it in:"
echo "     System Settings → Privacy & Security → Accessibility"
echo "  4. The 🖐️ icon will appear in your menu bar"
echo ""
echo "  Tip: To launch at login, open the app and go to:"
echo "    System Settings → General → Login Items → add ThreeFingerQuit"
