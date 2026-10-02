#!/bin/bash
# 開発用の自己署名コード署名証明書「MyTypingPet Dev」をログインキーチェーンに作る (1 回だけ実行すればよい)。
#
# ad-hoc 署名だと macOS はアプリをバイナリのハッシュで見分けるので、ビルドし直すたびに入力監視の許可が外れる。
# この証明書で署名すると「識別子 + 証明書」で見分けられるようになり、許可が残る。
# 証明書はこの Mac の中だけで使うもので、信頼設定 (システムへの登録) はしない。
set -euo pipefail

name="MyTypingPet Dev"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$name" "$keychain" >/dev/null 2>&1; then
    echo "「${name}」はもうあります。"
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$tmp/cert.conf" -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null

# キーチェーンへ取り込むためだけの一時的なパスワード
pass="$(openssl rand -hex 16)"
# macOS のキーチェーンが読める古い暗号方式で書き出す (OpenSSL 3 の既定の方式は取り込めない)
openssl pkcs12 -export -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$name" \
    -out "$tmp/cert.p12" -passout "pass:$pass"

# codesign だけが秘密鍵を使えるようにして取り込む
security import "$tmp/cert.p12" -k "$keychain" -P "$pass" -T /usr/bin/codesign

echo "「${name}」を作りました。以降の ./scripts/build-app.sh はこの証明書で署名します。"
