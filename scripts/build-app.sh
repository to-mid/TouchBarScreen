#!/bin/zsh

set -euo pipefail

ROOT_DIR=${0:A:h:h}
APP_DIR="$ROOT_DIR/dist/TouchBarScreen.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy \
    -c "Print :CFBundleShortVersionString" \
    "$INFO_PLIST")
ARCHIVE_NAME="TouchBarScreen-v${VERSION}-macos.zip"
ARCHIVE_PATH="$ROOT_DIR/dist/$ARCHIVE_NAME"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH"
mkdir -p "$MACOS_DIR"
cp ".build/release/TouchBarScreen" "$MACOS_DIR/TouchBarScreen"
cp "$INFO_PLIST" "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ARCHIVE_PATH"

cd "$ROOT_DIR/dist"
shasum -a 256 "$ARCHIVE_NAME" > "$CHECKSUM_PATH"

echo "$APP_DIR"
echo "$ARCHIVE_PATH"
echo "$CHECKSUM_PATH"
