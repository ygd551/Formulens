#!/bin/zsh
# 从 ModelScope 下载 PaddleOCR-VL-1.6 模型到 models/PaddleOCR-VL-1.6，并逐个校验 SHA-256。
# 校验清单：checksums/PaddleOCR-VL-1.6.sha256（与 HuggingFace 官方仓库的文件哈希一致）
set -euo pipefail
cd "$(dirname "$0")"
DEST=models/PaddleOCR-VL-1.6
BASE="https://www.modelscope.cn/models/PaddlePaddle/PaddleOCR-VL-1.6/resolve/master"
MANIFEST=checksums/PaddleOCR-VL-1.6.sha256

mkdir -p "$DEST"
while read -r sum name; do
  [[ -z "$name" ]] && continue
  if [[ -f "$DEST/$name" ]] && [[ "$(shasum -a 256 "$DEST/$name" | cut -d' ' -f1)" == "$sum" ]]; then
    echo "✓ $name（已存在）"
    continue
  fi
  echo "› 下载 $name"
  curl -fL --retry 3 -C - -o "$DEST/$name.part" "$BASE/$name"
  if [[ "$(shasum -a 256 "$DEST/$name.part" | cut -d' ' -f1)" != "$sum" ]]; then
    echo "✗ $name 校验失败，已删除。请重新运行本脚本。"
    rm -f "$DEST/$name.part"
    exit 1
  fi
  mv "$DEST/$name.part" "$DEST/$name"
done < "$MANIFEST"
echo "✓ 模型已就绪：$DEST"
