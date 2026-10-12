#!/usr/bin/env bash
# Builds the browser demo: a simulator build with the built-in mock bank, zipped for Appetize.io or a similar
# service. No Apple Developer account or code signing is needed; nothing connects to a backend.
#
#   scripts/build-demo.sh            → dist/LuxeBank-demo-simulator.zip
#
# Upload the zip as an iOS simulator app. Demo login: national ID 1-2345-67890-12-1, password LuxeDemo#2026,
# OTP 000000, then choose any 6-digit PIN that is not a sequence (e.g. 482193).
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
build=$(mktemp -d)
mkdir -p "$root/dist"

cd "$root/ios"
xcodegen generate --quiet
# Debug is the configuration with mock data (Release requires a real backend). Both simulator architectures,
# and no separate debug dylib, so the app runs on any simulator host.
xcodebuild build -project LuxeBank.xcodeproj -scheme LuxeBank -configuration Debug -sdk iphonesimulator \
  -derivedDataPath "$build" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO ENABLE_DEBUG_DYLIB=NO -quiet

app="$build/Build/Products/Debug-iphonesimulator/LuxeBank.app"
zip="$root/dist/LuxeBank-demo-simulator.zip"
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
lipo -archs "$app/LuxeBank"
ls -lh "$zip" | awk '{print $5, $9}'
