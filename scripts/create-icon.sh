#!/usr/bin/env bash
# Generate AppIcon.icns from logo.png

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_LOGO="$SCRIPT_DIR/../logo.png"
ICON_SET_DIR="$SCRIPT_DIR/../AppIcon.iconset"
OUTPUT_ICNS="$SCRIPT_DIR/../AppIcon.icns"

if [ ! -f "$SOURCE_LOGO" ]; then
    echo "Error: logo.png not found at $SOURCE_LOGO"
    exit 1
fi

echo "Creating icon set from $SOURCE_LOGO..."

# Create iconset directory
mkdir -p "$ICON_SET_DIR"

# Clear existing png files to avoid stale iconset artifacts.
rm -f "$ICON_SET_DIR"/*.png

# Generate required macOS .iconset files.
sips -z 16 16 "$SOURCE_LOGO" --out "$ICON_SET_DIR/icon_16x16.png" > /dev/null
sips -z 32 32 "$SOURCE_LOGO" --out "$ICON_SET_DIR/icon_16x16@2x.png" > /dev/null
sips -z 32 32 "$SOURCE_LOGO" --out "$ICON_SET_DIR/icon_32x32.png" > /dev/null
sips -z 64 64 "$SOURCE_LOGO" --out "$ICON_SET_DIR/icon_32x32@2x.png" > /dev/null
sips -z 128 128 "$SOURCE_LOGO" --out "$ICON_SET_DIR/icon_128x128.png" > /dev/null
sips -z 256 256 "$SOURCE_LOGO" --out "$ICON_SET_DIR/icon_128x128@2x.png" > /dev/null
sips -z 256 256 "$SOURCE_LOGO" --out "$ICON_SET_DIR/icon_256x256.png" > /dev/null
sips -z 512 512 "$SOURCE_LOGO" --out "$ICON_SET_DIR/icon_256x256@2x.png" > /dev/null
sips -z 512 512 "$SOURCE_LOGO" --out "$ICON_SET_DIR/icon_512x512.png" > /dev/null
sips -z 1024 1024 "$SOURCE_LOGO" --out "$ICON_SET_DIR/icon_512x512@2x.png" > /dev/null

# Create .icns from iconset
iconutil -c icns "$ICON_SET_DIR" -o "$OUTPUT_ICNS"

echo "✅ Icon created: $OUTPUT_ICNS"
echo "Icon set directory: $ICON_SET_DIR"
