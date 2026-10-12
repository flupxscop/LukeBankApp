#!/usr/bin/env bash
# Records the README demo: runs DemoRecordingUITests on a simulator while capturing the screen, then makes a GIF.
#
#   scripts/record-demo.sh [simulator-udid]      default: the first booted iPhone simulator
#
# Output: docs/demo/luxebank-demo.mp4 (full quality, not committed) and docs/demo/luxebank-demo.gif.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
udid=${1:-$(xcrun simctl list devices booted | grep -m1 -oE '[0-9A-F-]{36}' || true)}
: "${udid:?Boot an iPhone simulator or pass its UDID}"
mkdir -p "$root/docs/demo"
video="$root/docs/demo/luxebank-demo.mp4"
build=$(mktemp -d)

cd "$root/ios"
xcodegen generate --quiet
xcodebuild build-for-testing -project LuxeBank.xcodeproj -scheme LuxeBank -destination "id=$udid" -derivedDataPath "$build" -quiet

# A tidy status bar for the recording.
xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
trap 'xcrun simctl status_bar "$udid" clear' EXIT

# Register the demo customer off camera.
TEST_RUNNER_LUXEBANK_DEMO=1 xcodebuild test-without-building -project LuxeBank.xcodeproj -scheme LuxeBank -destination "id=$udid" \
  -derivedDataPath "$build" -only-testing:LuxeBankUITests/DemoRecordingUITests/testA_Prepare -quiet

# Open the app on its lock screen before filming; the tour activates it instead of relaunching.
xcrun simctl launch "$udid" com.luxebank.app -AppleLanguages "(en)" -AppleLocale en_US -DisablePushPrompt > /dev/null
sleep 5

rm -f "$video"
xcrun simctl io "$udid" recordVideo --codec h264 --force "$video" &
recorder=$!
sleep 2
TEST_RUNNER_LUXEBANK_DEMO=1 xcodebuild test-without-building -project LuxeBank.xcodeproj -scheme LuxeBank -destination "id=$udid" \
  -derivedDataPath "$build" -only-testing:LuxeBankUITests/DemoRecordingUITests/testB_Tour -quiet || { kill -INT $recorder; exit 1; }
sleep 1
kill -INT $recorder
wait $recorder || true

swift "$root/scripts/video-to-gif.swift" "$video" "$root/docs/demo/luxebank-demo.gif" 300 8 2
