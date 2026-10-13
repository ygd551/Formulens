# 开发 / 命令行使用的环境变量：source env.sh
# 模型与缓存都放在本项目目录内

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Python：默认使用 macapp/runtime 中的独立 Python（由 macapp/setup_runtime.sh 生成）。
# 也可以用 FORMULENS_PYTHON 指定其他环境（需已安装 mlx-vlm；整页解析还需要 paddleocr）。
if [ -n "${FORMULENS_PYTHON:-}" ]; then
  export PY="$FORMULENS_PYTHON"
  # conda 环境中 torch / sklearn 等可能各带一份 libomp，不设此项推理服务会崩溃
  export KMP_DUPLICATE_LIB_OK=TRUE
elif [ -x "$PROJECT_DIR/macapp/runtime/python/bin/python3" ]; then
  export PY="$PROJECT_DIR/macapp/runtime/python/bin/python3"
else
  export PY=python3
fi
export ENV_BIN="$(dirname "$PY")"

# 识别模型（本地路径，不联网）
export VL_MODEL_DIR="$PROJECT_DIR/models/PaddleOCR-VL-1.6"
export VL_SERVER_PORT="${VL_SERVER_PORT:-8111}"
export VL_SERVER_URL="http://127.0.0.1:$VL_SERVER_PORT/"

# 推理服务访问密钥：默认复用 Formulens 应用生成的密钥，命令行和应用可以共用同一个服务
FORMULENS_KEY_FILE="$HOME/Library/Application Support/Formulens/server.key"
if [ -z "${MLX_VLM_SERVER_API_KEY:-}" ] && [ -r "$FORMULENS_KEY_FILE" ]; then
  export MLX_VLM_SERVER_API_KEY="$(cat "$FORMULENS_KEY_FILE")"
fi

# 缓存目录，并禁止访问 HuggingFace（模型从 ModelScope 下载）
export PADDLE_PDX_CACHE_HOME="$PROJECT_DIR/models/paddlex"
export HF_HOME="$PROJECT_DIR/models/hf_cache"
export MODELSCOPE_CACHE="$PROJECT_DIR/models/modelscope_cache"
export HF_HUB_OFFLINE=1
export PADDLE_PDX_MODEL_SOURCE=bos
