#!/bin/zsh
# 启动 MLX-VLM 推理服务（仅本机可访问；设置了 MLX_VLM_SERVER_API_KEY 时要求密钥）
source "$(dirname "$0")/env.sh"
exec "$PY" -I -B -m mlx_vlm.server --host 127.0.0.1 --port "$VL_SERVER_PORT"
