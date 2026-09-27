#!/bin/zsh

set -euo pipefail

ROOT_DIR=${0:A:h:h}
APP_DIR="$ROOT_DIR/dist/TouchBarScreen.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp ".build/release/TouchBarScreen" "$MACOS_DIR/TouchBarScreen"
cp "Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
