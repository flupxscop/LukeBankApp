#!/usr/bin/env bash
# Measures LuxeBank's stability, speed and resource use (docs/app-quality-metrics.md).
#
#   scripts/measure-app.sh [destination]      default: the first booted iPhone simulator
#
# 1. Runs AppMetricsUITests (launch, unlock → dashboard, scrolling, resources, soak) and prints every metric.
# 2. Builds a Release binary for devices and reports the app's size.
# Simulator numbers run on the Mac's CPU: compare runs with each other, and use a physical iPhone for release figures.
set -euo pipefail
cd "$(dirname "$0")/../ios"

booted=$(xcrun simctl list devices booted | grep -m1 -oE '[0-9A-F-]{36}' || true)
destination=${1:-"id=${booted:?Boot an iPhone simulator or pass a destination}"}
out=$(mktemp -d)

xcodegen generate --quiet
TEST_RUNNER_LUXEBANK_MEASURE=1 xcodebuild test -project LuxeBank.xcodeproj -scheme LuxeBank -destination "$destination" \
  -only-testing:LuxeBankUITests/AppMetricsUITests -resultBundlePath "$out/metrics.xcresult" > "$out/test.log" 2>&1 \
  || { grep -E "error:|failed" "$out/test.log" | head -20; echo "Measurement run failed; log: $out/test.log"; exit 1; }

echo "== Measurements (average of the iterations) =="
grep -E "measured \[" "$out/test.log" \
  | sed -E "s/.*AppMetricsUITests (test[A-Za-z]+)\]' measured \[([^]]+)\] average: ([0-9.]+), relative standard deviation: ([0-9.]+%).*/\1 | \2 | \3 | ±\4/" \
  | sort -u

echo "== Stability =="
grep -E "Test Case .*AppMetricsUITests test[A-Za-z]+\]' (passed|failed|skipped)" "$out/test.log" \
  | sed -E "s/.*AppMetricsUITests (test[A-Za-z]+)\]' (passed|failed|skipped).*/\1 | \2/" | sort -u

echo "== App size (Release, arm64 device) =="
xcodebuild build -project LuxeBank.xcodeproj -scheme LuxeBank -configuration Release -sdk iphoneos -derivedDataPath "$out/release" \
  CODE_SIGNING_ALLOWED=NO > "$out/release.log" 2>&1 || { tail -5 "$out/release.log"; exit 1; }
app="$out/release/Build/Products/Release-iphoneos/LuxeBank.app"
du -sk "$app" | awk '{printf "Bundle: %.1f MB\n", $1 / 1024}'
ls -l "$app/LuxeBank" | awk '{printf "Executable: %.1f MB\n", $5 / 1048576}'
(cd "$out" && mkdir -p Payload && cp -R "$app" Payload/ && zip -qr LuxeBank.ipa Payload && ls -l LuxeBank.ipa | awk '{printf "Compressed (download estimate): %.1f MB\n", $5 / 1048576}')
echo "Result bundle: $out/metrics.xcresult"
