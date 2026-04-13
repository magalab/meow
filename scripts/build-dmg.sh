#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-Meow}"
BINARY_NAME="${BINARY_NAME:-Meow}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-tech.lury.meow}"
VERSION="${VERSION:-0.1.0}"
TARGET="${TARGET:-}"

if [ -z "$TARGET" ]; then
    case "$(uname -m)" in
        arm64)
            TARGET="arm64-apple-macosx"
            ;;
        x86_64)
            TARGET="x86_64-apple-macosx"
            ;;
        *)
            echo "Error: Unsupported architecture $(uname -m). Set TARGET manually."
            exit 1
            ;;
    esac
fi

TARGET_ARCH="${TARGET%%-*}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${APP_NAME}_${VERSION}_${TARGET_ARCH}.dmg"
DMG_STAGING_DIR="$DIST_DIR/dmg-root"

echo "Building $APP_NAME ($VERSION) for $TARGET..."

cd "$PROJECT_DIR"

# Generate app icon if not exists
if [ ! -f "AppIcon.icns" ]; then
    echo "Generating app icon..."
    bash "$SCRIPT_DIR/create-icon.sh" || echo "Warning: Failed to create icon"
fi

swift build -c release

BUILD_RELEASE_DIR=".build/$TARGET/release"
if [ ! -d "$BUILD_RELEASE_DIR" ]; then
    if [ -d ".build/release" ]; then
        BUILD_RELEASE_DIR=".build/release"
    else
        echo "Error: Release build directory not found for target $TARGET"
        ls -la .build || true
        exit 1
    fi
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_RELEASE_DIR/$BINARY_NAME" "$APP_DIR/Contents/MacOS/$BINARY_NAME"

# Copy app icon
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "✅ App icon copied"
else
    echo "⚠ App icon not found"
fi

# Copy localization resources from the build bundle
RESOURCE_BUNDLE="$BUILD_RELEASE_DIR/Meow_Meow.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    echo "Copying localization resources from $RESOURCE_BUNDLE..."
    # Find all .lproj directories and copy them
    find "$RESOURCE_BUNDLE" -maxdepth 1 -type d -name "*.lproj" -exec cp -R {} "$APP_DIR/Contents/Resources/" \;
    echo "Contents of Resources dir:"
    ls -la "$APP_DIR/Contents/Resources/"
else
    echo "Warning: Resource bundle not found at $RESOURCE_BUNDLE"
    echo "Available directories in $BUILD_RELEASE_DIR:"
    ls -la "$BUILD_RELEASE_DIR" | grep -E "bundle|lproj" || echo "No bundles found"
fi

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${APP_BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>${BINARY_NAME}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSRequiresIPhoneOS</key><false/>
</dict>
</plist>
EOF

if [ -n "${MACOS_SIGN_IDENTITY:-}" ]; then
    echo "Signing app bundle with identity: ${MACOS_SIGN_IDENTITY}"
    codesign --force --deep --sign "${MACOS_SIGN_IDENTITY}" "$APP_DIR"
fi

rm -f "$DMG_PATH"

# Build a standard installer layout: app bundle + Applications symlink.
rm -rf "$DMG_STAGING_DIR"
mkdir -p "$DMG_STAGING_DIR"
cp -R "$APP_DIR" "$DMG_STAGING_DIR/"
ln -s /Applications "$DMG_STAGING_DIR/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING_DIR" -ov -format UDZO "$DMG_PATH"

if [ -n "${MACOS_SIGN_IDENTITY:-}" ]; then
    echo "Signing DMG with identity: ${MACOS_SIGN_IDENTITY}"
    codesign --force --sign "${MACOS_SIGN_IDENTITY}" "$DMG_PATH"
fi

rm -rf "$DMG_STAGING_DIR"

echo "Done."
echo "App: $APP_DIR"
echo "DMG: $DMG_PATH"
