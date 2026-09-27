#!/usr/bin/env bash
set -e

APP_NAME="solaris"
DIST_DIR="dist"
STAGE_DIR="$DIST_DIR/$APP_NAME"
ZIP_PATH="$DIST_DIR/$APP_NAME.zip"

echo "Building release binary..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
./bin/odin/odin.exe build ./src -out:"$STAGE_DIR/$APP_NAME.exe" -o:speed -subsystem:windows

echo "Copying assets..."
cp -r assets "$STAGE_DIR/assets"

echo "Zipping to $ZIP_PATH..."
rm -f "$ZIP_PATH"
powershell.exe -NoProfile -Command "Compress-Archive -Path '$STAGE_DIR/*' -DestinationPath '$ZIP_PATH' -Force"

echo "Done: $ZIP_PATH"
