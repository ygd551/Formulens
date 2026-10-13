#!/bin/zsh
# 开发用：只编译应用本体并安装（使用本仓库的 models/ 和 Python 环境，不打包 Python 和模型）
# 正式安装包请用 ./package.sh 生成 DMG
set -euo pipefail
cd "$(dirname "$0")"
./build.sh

osascript -e 'tell application id "local.formulens.app" to quit' 2>/dev/null || true
sleep 1
pkill -x Formulens 2>/dev/null || true

# 同时删除改名前的旧版本（Snip OCR）
rm -rf "/Applications/Formulens.app" "/Applications/Snip OCR.app" "/Applications/SnipOCR.app"
ditto build/Formulens.app "/Applications/Formulens.app"
echo "✓ 已安装到 /Applications/Formulens.app（开发版）"
open "/Applications/Formulens.app"
