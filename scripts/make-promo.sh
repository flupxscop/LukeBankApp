#!/usr/bin/env bash
# Renders the LuxeBank promo film from the demo recording (1920×1080, 30 fps, silent):
#   dist/luxebank-promo.mp4         full quality (10 Mbit/s)
#   docs/demo/luxebank-promo.mp4    web version linked from the README (1.5 Mbit/s)
#   docs/demo/luxebank-promo.jpg    README poster
#
#   scripts/make-promo.sh            (run scripts/record-demo.sh first if docs/demo/luxebank-demo.mp4 is missing)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
demo="$root/docs/demo/luxebank-demo.mp4"
[[ -f "$demo" ]] || { echo "Missing $demo; run scripts/record-demo.sh first"; exit 1; }
work=$(mktemp -d)
mkdir -p "$root/dist"

ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
"$ictool" "$root/ios/LuxeBank/Resources/AppIcon.icon" --export-image --output-file "$work/icon.png" \
  --platform iOS --rendition Default --width 512 --height 512 --scale 1 > /dev/null

swiftc -O "$root/scripts/make-promo.swift" -o "$work/make-promo" 2> "$work/build.log" || { cat "$work/build.log"; exit 1; }
"$work/make-promo" "$demo" "$work/icon.png" "$root/dist/luxebank-promo.mp4"
"$work/make-promo" "$demo" "$work/icon.png" "$root/docs/demo/luxebank-promo.mp4" 1500000
swift "$root/scripts/promo-poster.swift" "$root/docs/demo/luxebank-promo.mp4" 4.6 "$root/docs/demo/luxebank-promo.jpg"
