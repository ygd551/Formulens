#!/bin/zsh
# 准备打包用的独立 Python 运行环境：macapp/runtime/python（约 650MB）
# - python-build-standalone 3.12，下载后校验 SHA-256（checksums/python-runtime.sha256）
# - 依赖按 runtime-requirements.lock 安装：每个包固定版本并校验 SHA-256，
#   任何一个文件与记录不符都会安装失败
# - 锁定的二进制包都是 macOS 14 版本，保证安装包能在 macOS 14 及以上运行
# - 不包含 opencv-python：它内置的 ffmpeg 含 GPL 组件（x264、x265 等），
#   mlx-vlm 只在视频和其他模型中用到它，PaddleOCR-VL 识别图片不需要
#
# 更新依赖：修改 runtime-constraints.txt 后，参照 README「更新依赖」重新生成锁定文件
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"

PY_TAG=20261009
PY_FILE="cpython-3.12.15+${PY_TAG}-aarch64-apple-darwin-install_only.tar.gz"
PY_URL="https://github.com/astral-sh/python-build-standalone/releases/download/${PY_TAG}/${PY_FILE//+/%2B}"
PY_SHA=$(awk -v f="$PY_FILE" '$2 == f {print $1}' "$ROOT/checksums/python-runtime.sha256")

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "› 下载 Python（$PY_FILE）"
curl -fL --retry 3 -o "$TMP/python.tar.gz" "$PY_URL"
if [[ "$(shasum -a 256 "$TMP/python.tar.gz" | cut -d' ' -f1)" != "$PY_SHA" ]]; then
  echo "✗ Python 安装包校验失败"
  exit 1
fi

rm -rf runtime && mkdir -p runtime
tar -xzf "$TMP/python.tar.gz" -C runtime
PY=runtime/python/bin/python3

echo "› 安装依赖（校验 SHA-256）"
"$PY" -I -m pip install -q --no-warn-script-location --require-hashes --no-deps --only-binary=:all: \
  -r runtime-requirements.lock

echo "✓ 运行环境已就绪：$(pwd)/runtime/python（$(du -sh runtime/python | cut -f1)）"
