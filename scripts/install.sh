#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_SCRIPT="$ROOT_DIR/scripts/package.sh"
PRODUCT_NAME="PDF Editor"
APP_NAME="$PRODUCT_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
SOURCE_APP="$DIST_DIR/$APP_NAME"
DEST_DIR="/Applications"
DEST_APP="$DEST_DIR/$APP_NAME"
FORCE=0
ICON_TARGET="$SOURCE_APP/Contents/Resources/AppIcon.icns"
ICON_SOURCE="$ROOT_DIR/PdfEditorIcon.png"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=1
            shift
            ;;
        -h|--help)
            cat <<USAGE
Usage: $(basename "$0") [--force]

Builds the app bundle (if needed) and copies it into /Applications.
  --force    overwrite an existing installation without prompting.
USAGE
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ ! -d "$SOURCE_APP" ]]; then
    printf '› App bundle not found at %s\n' "$SOURCE_APP"
    printf '› Building bundle via package script\n'
    bash "$PACKAGE_SCRIPT"
fi

if [[ -d "$SOURCE_APP" && ! -f "$ICON_TARGET" && -f "$ICON_SOURCE" ]]; then
    printf '› App bundle missing icon; rebuilding via package script\n'
    bash "$PACKAGE_SCRIPT"
fi

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "Failed to locate built app bundle at $SOURCE_APP" >&2
    exit 1
fi

if [[ ! -f "$ICON_TARGET" ]]; then
    echo "Expected icon missing at $ICON_TARGET" >&2
    exit 1
fi

if [[ -d "$DEST_APP" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
        printf '› Removing existing installation at %s\n' "$DEST_APP"
        rm -rf "$DEST_APP"
    else
        echo "An installation already exists at $DEST_APP"
        echo "Re-run with --force to overwrite it."
        exit 1
    fi
fi

printf '› Copying %s to %s\n' "$SOURCE_APP" "$DEST_DIR"
ditto "$SOURCE_APP" "$DEST_APP"

printf '✔ Installed to %s\n' "$DEST_APP"
printf '   Launch with: open "%s"\n' "$DEST_APP"
