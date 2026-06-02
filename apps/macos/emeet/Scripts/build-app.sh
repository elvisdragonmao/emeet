#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

APP_NAME="emeet"
BUILD_DIR="$PROJECT_DIR/.build/app"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE="$MACOS_DIR/$APP_NAME"
SDK_PATH="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

sources=()
while IFS= read -r -d '' file; do
    sources+=("$file")
done < <(find "$PROJECT_DIR/Sources/emeet" -name "*.swift" -print0 | sort -z)

/usr/bin/xcrun swiftc \
    -swift-version 5 \
    -parse-as-library \
    -target "$ARCH-apple-macos14.0" \
    -sdk "$SDK_PATH" \
    "${sources[@]}" \
    -framework SwiftUI \
    -framework AppKit \
    -framework AVFoundation \
    -framework ScreenCaptureKit \
    -framework CoreMedia \
    -framework CoreAudio \
    -framework CoreGraphics \
    -o "$EXECUTABLE"

cp "$PROJECT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
