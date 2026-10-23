#!/bin/bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: ./scripts/build-app.sh [--debug]

Build AudioSpectrum.app into dist/ and sign it locally with an ad-hoc signature.
The default configuration is release; --debug builds with debugging information.
USAGE
}

CONFIGURATION="release"
case "${1:-}" in
    "") ;;
    --debug) CONFIGURATION="debug"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 1 ;;
esac
if [[ $# -ne 0 ]]; then
    usage >&2
    exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "AudioSpectrum requires macOS 14.2 or later." >&2
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/AudioSpectrum.app"

for tool in swift codesign iconutil; do
    if ! /usr/bin/xcrun --find "$tool" >/dev/null 2>&1; then
        echo "Missing $tool. Install Xcode 15.2 or later and select its developer directory." >&2
        exit 1
    fi
done

SDK_VERSION="$(/usr/bin/xcrun --sdk macosx --show-sdk-version)"
IFS=. read -r SDK_MAJOR SDK_MINOR _ <<< "$SDK_VERSION"
if (( SDK_MAJOR < 14 || (SDK_MAJOR == 14 && SDK_MINOR < 2) )); then
    echo "The macOS SDK must be 14.2 or later (found $SDK_VERSION). Select a newer Xcode." >&2
    exit 1
fi

cd "$PROJECT_ROOT"
export MACOSX_DEPLOYMENT_TARGET=14.2
echo "Building AudioSpectrum ($CONFIGURATION)..."
/usr/bin/xcrun swift build --configuration "$CONFIGURATION" --product AudioSpectrum
BIN_DIR="$(/usr/bin/xcrun swift build --configuration "$CONFIGURATION" --show-bin-path)"

mkdir -p "$DIST_DIR"
STAGING_DIR="$(mktemp -d "$DIST_DIR/.build-app.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/AudioSpectrum.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/AudioSpectrum" "$STAGED_APP/Contents/MacOS/AudioSpectrum"
cp "$PROJECT_ROOT/Resources/Info.plist" "$STAGED_APP/Contents/Info.plist"
chmod 755 "$STAGED_APP/Contents/MacOS/AudioSpectrum"
/usr/bin/plutil -lint "$STAGED_APP/Contents/Info.plist"

echo "Generating app icon..."
/usr/bin/xcrun swift "$PROJECT_ROOT/scripts/generate-icon.swift" "$STAGING_DIR/AppIcon.iconset"
/usr/bin/xcrun iconutil -c icns "$STAGING_DIR/AppIcon.iconset" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"

echo "Signing app locally..."
/usr/bin/codesign --force --sign - --timestamp=none "$STAGED_APP"
/usr/bin/codesign --verify --strict --verbose=2 "$STAGED_APP"

# Only replace this script's generated output after the new bundle is complete.
if [[ -e "$APP_BUNDLE" || -L "$APP_BUNDLE" ]]; then
    rm -rf "$APP_BUNDLE"
fi
mv "$STAGED_APP" "$APP_BUNDLE"
echo "Built: $APP_BUNDLE"
echo "Copy AudioSpectrum.app into Applications, then open it in Finder."
