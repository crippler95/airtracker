#!/usr/bin/env bash
set -euo pipefail

# Assemble AirTracker.app from the SwiftPM release build and ad-hoc codesign it.
# The motion (TCC) prompt only appears for a signed .app launched via LaunchServices,
# never for a bare `swift run` binary — so always launch the bundle this script builds.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/AirTracker.app"
CONTENTS="$APP/Contents"
CONFIG="${1:-release}"

# Set UNIVERSAL=1 to build a fat arm64+x86_64 binary (used for releases).
BUILD_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
    BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi

echo "==> swift build -c $CONFIG ${BUILD_FLAGS[*]}"
swift build -c "$CONFIG" --package-path "$ROOT" "${BUILD_FLAGS[@]}"

BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" "${BUILD_FLAGS[@]}" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN/AirTracker" "$CONTENTS/MacOS/AirTracker"
cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"

# SwiftPM emits resource bundles next to the binary. Bundle.module resolves them
# relative to the executable, so they must live in Contents/Resources.
shopt -s nullglob
bundles=("$BIN"/*.bundle)
if [ ${#bundles[@]} -eq 0 ]; then
    echo "warning: no resource bundles found in $BIN" >&2
else
    for b in "${bundles[@]}"; do cp -R "$b" "$CONTENTS/Resources/"; done
fi

if [ -f "$ROOT/assets/AppIcon.icns" ]; then
    cp "$ROOT/assets/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
fi

echo "==> Codesigning (ad-hoc)"
codesign --force --sign - --identifier com.szilard.airtracker "$APP"

echo "==> Done: $APP"
