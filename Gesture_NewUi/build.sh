#!/bin/bash
set -e

echo "=== Cleaning previous builds ==="
rm -rf build

echo "=== Building Gesture Project ==="
xcodebuild -project Gesture.xcodeproj -scheme Gesture -configuration Debug -destination 'generic/platform=macOS' build SYMROOT="$(pwd)/build"

echo "=== Build Successful ==="
echo "Built application is located at: $(pwd)/build/Debug/Gesture.app"
