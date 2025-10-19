#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT_NAME="PDF Editor"
EXECUTABLE_NAME="pdf-editor"
BUNDLE_ID="com.codex.pdfeditor"
VERSION_SHORT="1.0"
VERSION_BUILD="1"
BUILD_CONFIG="release"
BUILD_DIR="$ROOT_DIR/.build/$BUILD_CONFIG"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$PRODUCT_NAME.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
ICON_SOURCE="$ROOT_DIR/PdfEditorIcon.png"
ICON_NAME="AppIcon"
ICON_OUTPUT="$RESOURCES_DIR/$ICON_NAME.icns"

printf '› Building %s (%s)\n' "$PRODUCT_NAME" "$BUILD_CONFIG"
SWIFT_FLAGS=(--configuration "$BUILD_CONFIG")

swift build "${SWIFT_FLAGS[@]}"

if [[ ! -x "$BUILD_DIR/$EXECUTABLE_NAME" ]]; then
    echo "Failed to locate built executable at $BUILD_DIR/$EXECUTABLE_NAME" >&2
    exit 1
fi

mkdir -p "$DIST_DIR"

printf '› Assembling app bundle at %s\n' "$APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$PRODUCT_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION_SHORT</string>
    <key>CFBundleVersion</key>
    <string>$VERSION_BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_NAME</string>
</dict>
</plist>
PLIST

if [[ -f "$ICON_SOURCE" ]]; then
    printf '› Generating app icon from %s\n' "$ICON_SOURCE"
    if ! command -v sips >/dev/null 2>&1; then
        echo "sips tool not found; cannot create icon set" >&2
        exit 1
    fi
    if ! command -v iconutil >/dev/null 2>&1; then
        echo "iconutil tool not found; cannot create icns" >&2
        exit 1
    fi

    TMP_ICON_ROOT="$(mktemp -d)"
    trap 'rm -rf "$TMP_ICON_ROOT"' EXIT
    ICONSET_DIR="$TMP_ICON_ROOT/$ICON_NAME.iconset"
    mkdir -p "$ICONSET_DIR"

    declare -a BASE_SIZES=(16 32 128 256 512)
    for size in "${BASE_SIZES[@]}"; do
        sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z "$double" "$double" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
    done

    iconutil -c icns -o "$ICON_OUTPUT" "$ICONSET_DIR"
    cp "$ICON_SOURCE" "$RESOURCES_DIR/$ICON_NAME.png"

    rm -rf "$TMP_ICON_ROOT"
    trap - EXIT
else
    echo "Icon source not found at $ICON_SOURCE" >&2
    exit 1
fi

printf '✔ Created %s\n' "$APP_BUNDLE"
printf '   (You can now run: open "%s")\n' "$APP_BUNDLE"
