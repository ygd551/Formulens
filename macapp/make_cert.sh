#!/bin/zsh
# 在登录钥匙串中创建本机代码签名证书「Formulens Local Signing」（只需运行一次）。
# 用它签名后，「录屏与系统录音」授权在重新编译后仍然有效。
# 删除：打开「钥匙串访问」，搜索 Formulens Local Signing，删除证书和对应的私钥。
set -euo pipefail
NAME="Formulens Local Signing"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "证书已存在：$NAME"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/cert.p12" -passout pass:formulens -name "$NAME"
security import "$TMP/cert.p12" -k ~/Library/Keychains/login.keychain-db -P formulens -T /usr/bin/codesign

echo "✓ 已创建证书：$NAME"
echo "  接下来运行 ./install.sh 重新安装，然后在系统设置中重新授权一次。"
