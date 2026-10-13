#!/bin/zsh
# 生成独立安装包 dist/Formulens-<版本>.dmg：应用 + 自带 Python 运行环境 + PaddleOCR-VL-1.6 模型
# 首次使用前：./setup_runtime.sh 准备运行环境，../download_model.sh 下载模型
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
VERSION=1.0.0
APP=build/Formulens.app
RES="$APP/Contents/Resources"

[[ -x runtime/python/bin/python3 ]] || { echo "缺少 runtime/python，请先运行 ./setup_runtime.sh"; exit 1; }
[[ -f "$ROOT/models/PaddleOCR-VL-1.6/model.safetensors" ]] || { echo "缺少模型，请先运行 ../download_model.sh"; exit 1; }

# 检查运行环境中所有二进制要求的最低系统版本不高于 macOS 14
# （在新系统上 pip 默认会装新系统专用的 wheel，例如 mlx 的 macosx_26_0 版本）
MAX_MINOS=$(find runtime/python \( -name "*.so" -o -name "*.dylib" \) -exec vtool -show-build {} \; 2>/dev/null |
  awk '/minos/{print $2}' | sort -V | tail -1)
if [[ "$(printf '%s\n' "$MAX_MINOS" 14.0 | sort -V | tail -1)" != "14.0" ]]; then
  echo "运行环境中有组件要求 macOS $MAX_MINOS，高于 14.0。请重新运行 ./setup_runtime.sh"
  exit 1
fi

tools/check_l10n.sh
./build.sh

echo "› 清除开发路径"
/usr/libexec/PlistBuddy -c "Delete :FormulensProjectDir" "$APP/Contents/Info.plist"

echo "› 放入 Python 运行环境"
ditto runtime/python "$RES/python"
# 只保留 python 解释器：其他命令行脚本的首行写有构建机器上的绝对路径，应用也用不到
find "$RES/python/bin" -mindepth 1 ! -name "python3" ! -name "python3.12" -exec rm -rf {} +
# pip 从本地 wheel 安装时会记录来源路径
find "$RES/python" -name "direct_url.json" -delete
# 重新预编译 .pyc，去掉其中记录的构建路径；运行时不再写入应用包（保持签名完整）
find "$RES/python" -name "__pycache__" -type d -prune -exec rm -rf {} +
"$RES/python/bin/python3" -I -W ignore -m compileall -q -f -j 0 -s "$PWD/$RES/python" -p "/python" \
  "$PWD/$RES/python/lib/python3.12" >/dev/null || true

echo "› 放入模型和许可证"
mkdir -p "$RES/models/PaddleOCR-VL-1.6"
rsync -a --exclude ".eval_results" --exclude ".gitattributes" --exclude ".msc" --exclude ".mv" \
  "$ROOT/models/PaddleOCR-VL-1.6/" "$RES/models/PaddleOCR-VL-1.6/"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$RES/"

echo "› 检查个人信息"
LEAKS=$(grep -rlaF -e "$HOME" -e "/Users/$USER" "$APP" 2>/dev/null || true)
if [[ -n "$LEAKS" ]]; then
  echo "应用包中仍含有本机路径，停止打包："
  echo "$LEAKS" | head -20
  exit 1
fi
echo "  未发现本机路径"

IDENTITY=""
for name in "Formulens Local Signing" "SnipOCR Local Signing"; do  # 后者是改名前 make_cert.sh 创建的证书
  if security find-certificate -c "$name" >/dev/null 2>&1; then IDENTITY="$name"; break; fi
done
SIGN="${IDENTITY:--}"
echo "› 签名包内的可执行文件和动态库（$SIGN）"
find "$RES/python" -type f \( -perm -u+x -o -name "*.so" -o -name "*.dylib" \) -print0 |
  while IFS= read -r -d '' f; do
    if file -b "$f" | grep -q "Mach-O"; then
      codesign --force --sign "$SIGN" "$f" 2>/dev/null
    fi
  done
echo "› 签名应用"
codesign --force --sign "$SIGN" "$APP"
codesign --verify --deep --strict "$APP" && echo "  签名校验通过"

echo "› 生成 DMG"
mkdir -p dist
STAGE=build/dmg
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Formulens.app"
ln -s /Applications "$STAGE/应用程序"
DMG="Formulens-$VERSION.dmg"
rm -f "dist/$DMG" "dist/$DMG.sha256"
hdiutil create -volname "Formulens" -srcfolder "$STAGE" -fs APFS -format ULFO -ov "dist/$DMG" >/dev/null
rm -rf "$STAGE"
(cd dist && shasum -a 256 "$DMG" > "$DMG.sha256")

echo "✓ 安装包：$(pwd)/dist/$DMG（$(du -h "dist/$DMG" | cut -f1)）"
echo "  SHA-256：$(cut -d' ' -f1 "dist/$DMG.sha256")"
echo "  应用大小：$(du -sh "$APP" | cut -f1)"
