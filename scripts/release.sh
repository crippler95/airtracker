#!/usr/bin/env bash
set -euo pipefail

# Build a universal (arm64 + x86_64) AirTracker.app and zip it for distribution.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-$(grep -m1 'static let version' "$ROOT/Sources/AirTrackerCore/CLI.swift" | sed -E 's/.*"([^"]+)".*/\1/')}"
DIST="$ROOT/dist"
ZIP="$DIST/AirTracker-v${VERSION}-macos-universal.zip"

UNIVERSAL=1 "$ROOT/scripts/bundle.sh" release

echo "==> Verifying architectures"
lipo -info "$ROOT/build/AirTracker.app/Contents/MacOS/AirTracker"

echo "==> Zipping $ZIP"
mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$ROOT/build/AirTracker.app" "$ZIP"

echo "==> Done: $ZIP"
