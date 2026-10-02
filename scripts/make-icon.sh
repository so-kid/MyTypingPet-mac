#!/bin/bash
# Resources/AppIcon.icns を作り直す (既定の絵を変えたときだけ実行すればよい)。
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp scripts/make-icon.swift "$tmp/main.swift"
swiftc -swift-version 5 "$tmp/main.swift" Sources/MyTypingPet/DefaultArt.swift -o "$tmp/make-icon"
"$tmp/make-icon" "$tmp/AppIcon.iconset"
mkdir -p Resources
iconutil -c icns "$tmp/AppIcon.iconset" -o Resources/AppIcon.icns
echo "できました: Resources/AppIcon.icns"
