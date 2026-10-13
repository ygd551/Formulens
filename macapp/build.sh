#!/bin/zsh
# 编译 Formulens.app 到 macapp/build/
set -euo pipefail
cd "$(dirname "$0")"
PROJECT_DIR="$(cd .. && pwd)"
APP=build/Formulens.app
VERSION=1.0.0

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "› 编译 Swift"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  Sources/*.swift -o "$APP/Contents/MacOS/Formulens"

echo "› 复制资源"
cp -R Resources/* "$APP/Contents/Resources/"

echo "› 生成图标"
swift tools/make_icon.swift build/icon_1024.png
mkdir -p build/AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon_1024.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon_1024.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
  <key>CFBundleName</key><string>Formulens</string>
  <key>CFBundleDisplayName</key><string>Formulens</string>
  <key>CFBundleIdentifier</key><string>local.formulens.app</string>
  <key>CFBundleExecutable</key><string>Formulens</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSScreenCaptureUsageDescription</key><string>Captures the screen area you select to recognize formulas and text</string>
  <key>FormulensProjectDir</key><string>${PROJECT_DIR}</string>
</dict>
</plist>
EOF

# 有本机签名证书（make_cert.sh 生成）时使用它：系统权限按「应用 ID + 证书」记录，重新编译后不用重新授权。
# 否则用 ad-hoc 签名：每次编译后都要重新授权「录屏与系统录音」。
IDENTITY=""
for name in "Formulens Local Signing" "SnipOCR Local Signing"; do  # 后者是改名前 make_cert.sh 创建的证书
  if security find-certificate -c "$name" >/dev/null 2>&1; then IDENTITY="$name"; break; fi
done
if [[ -n "$IDENTITY" ]]; then
  echo "› 签名（$IDENTITY）"
  codesign --force --deep --sign "$IDENTITY" "$APP"
else
  echo "› 签名（ad-hoc；运行 ./make_cert.sh 可避免每次编译后重新授权）"
  codesign --force --deep --sign - "$APP"
fi
echo "✓ 完成：$(pwd)/$APP"
