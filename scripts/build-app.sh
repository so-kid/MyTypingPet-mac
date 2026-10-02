#!/bin/bash
# build/MyTypingPet.app を作る。
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
bin="$(swift build -c release --show-bin-path)/MyTypingPet"

app=build/MyTypingPet.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/MyTypingPet"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp scripts/Info.plist "$app/Contents/Info.plist"

# 入力監視の許可は署名に紐づく。scripts/create-signing-cert.sh で作った証明書があればそれで署名し、
# ビルドし直しても許可が残るようにする。なければ ad-hoc 署名 (ビルドのたびに許可が外れる)
identity="MyTypingPet Dev"
if security find-certificate -c "$identity" >/dev/null 2>&1; then
    codesign --force --sign "$identity" --identifier io.github.so-kid.MyTypingPet "$app"
else
    echo "注意: 証明書「${identity}」がないので ad-hoc 署名します。ビルドし直すと入力監視の許可が外れます。"
    echo "      ./scripts/create-signing-cert.sh を 1 回実行すると解消します。"
    codesign --force --sign - --identifier io.github.so-kid.MyTypingPet "$app"
fi

echo "できました: $app"
