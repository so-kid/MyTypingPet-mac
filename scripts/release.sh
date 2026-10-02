#!/bin/bash
# リリース用の zip (build/MyTypingPet-mac-<バージョン>.zip) を作り、SHA-256 を表示する。
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

app=build/MyTypingPet.app

# 入力監視の許可がアップデート後も残るように、配布物は必ず証明書で署名する
if ! codesign -dr - "$app" 2>&1 | grep -q "certificate leaf"; then
    echo "エラー: 証明書で署名されていません。先に ./scripts/create-signing-cert.sh を実行してください。" >&2
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" scripts/Info.plist)"
zip="build/MyTypingPet-mac-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

echo "できました: $zip"
shasum -a 256 "$zip" | awk '{print "SHA-256: " toupper($1)}'
