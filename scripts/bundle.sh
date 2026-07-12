#!/usr/bin/env bash
set -euo pipefail

# Assemble AirTracker.app from the SwiftPM release build and ad-hoc codesign it.
# The motion (TCC) prompt only appears for a signed .app launched via LaunchServices,
# never for a bare `swift run` binary — so always launch the bundle this script builds.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/AirTracker.app"
CONTENTS="$APP/Contents"
CONFIG="${1:-release}"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG" --package-path "$ROOT"

BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN/AirTracker" "$CONTENTS/MacOS/AirTracker"
cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"

# SwiftPM emits the resource bundle next to the binary. Bundle.module resolves it
# relative to the executable, so it must live in Contents/Resources.
if [ -d "$BIN/AirTracker_AirTracker.bundle" ]; then
    cp -R "$BIN/AirTracker_AirTracker.bundle" "$CONTENTS/Resources/"
else
    echo "warning: resource bundle AirTracker_AirTracker.bundle not found in $BIN" >&2
fi

echo "==> Codesigning (ad-hoc)"
codesign --force --sign - --identifier com.szilard.airtracker "$APP"

echo "==> Done: $APP"
