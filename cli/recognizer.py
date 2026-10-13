"""调用本地 MLX-VLM 推理服务（OpenAI 兼容接口）识别截图，并整理成 LaTeX / Markdown。"""

import base64
import io
import json
import os
import re
import time
import urllib.error
import urllib.request

from PIL import Image

SERVER_URL = os.environ.get("VL_SERVER_URL", "http://127.0.0.1:8111/").rstrip("/")
MODEL = os.environ.get("VL_MODEL_DIR") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models", "PaddleOCR-VL-1.6")
if not os.path.isdir(MODEL):
    raise SystemExit(f"找不到模型目录：{MODEL}\n请先运行 ./download_model.sh，或 source env.sh 后再运行。")
# 推理服务访问密钥（env.sh 默认读取 Formulens 应用生成的 server.key）
_KEY_FILE = os.path.expanduser("~/Library/Application Support/Formulens/server.key")
API_KEY = os.environ.get("MLX_VLM_SERVER_API_KEY", "")
if not API_KEY and os.path.isfile(_KEY_FILE):
    with open(_KEY_FILE) as f:
        API_KEY = f.read().strip()
HEADERS = {"Authorization": f"Bearer {API_KEY}"} if API_KEY else {}

# PaddleOCR-VL 的任务提示词
PROMPTS = {
    "formula": "Formula Recognition:",
    "text": "OCR:",
    "table": "Table Recognition:",
    "chart": "Chart Recognition:",
}
MODES = ("auto", "formula", "text", "table")

_SINGLE_MATH = re.compile(r"^\s*(\\\(|\\\[|\$\$|\$)(.*)(\\\)|\\\]|\$\$|\$)\s*$", re.S)


def server_alive(timeout: float = 1.0) -> bool:
    try:
        with urllib.request.urlopen(urllib.request.Request(SERVER_URL + "/health", headers=HEADERS), timeout=timeout):
            return True
    except Exception:
        return False


def _to_data_url(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.convert("RGB").save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def _prepare(img: Image.Image) -> Image.Image:
    """小截图放大一些，识别更稳；超大图缩小，避免占用过多内存。"""
    img = img.convert("RGB")
    w, h = img.size
    if max(w, h) < 200:
        s = 200 / max(w, h)
        img = img.resize((round(w * s), round(h * s)), Image.LANCZOS)
    elif max(w, h) > 2400:
        s = 2400 / max(w, h)
        img = img.resize((round(w * s), round(h * s)), Image.LANCZOS)
    return img


def _call(img: Image.Image, task: str, max_tokens: int | None = None) -> str:
    # 公式通常很短；限制长度，防止模型陷入重复输出
    if max_tokens is None:
        max_tokens = 1024 if task == "formula" else 4096
    payload = {
        "model": MODEL,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "image_url", "image_url": {"url": _to_data_url(img)}},
                {"type": "text", "text": PROMPTS[task]},
            ],
        }],
        "max_tokens": max_tokens,
        "temperature": 0,
    }
    req = urllib.request.Request(
        SERVER_URL + "/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", **HEADERS},
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise SystemExit("推理服务拒绝访问（401）：访问密钥不匹配。请设置 MLX_VLM_SERVER_API_KEY，"
                             "或使用 Formulens 应用的密钥（~/Library/Application Support/Formulens/server.key）。")
        raise
    return data["choices"][0]["message"]["content"].strip()


def _strip_math(s: str) -> str | None:
    """整段只是一个公式时，返回去掉定界符的 LaTeX；否则返回 None。"""
    m = _SINGLE_MATH.match(s)
    if not m:
        return None
    inner = m.group(2)
    # 防止把 "\(a\) and \(b\)" 误判为单个公式
    if re.search(r"\\\)|\\\(|\\\[|\\\]", inner):
        return None
    return inner.strip()


def _is_mostly_math(s: str) -> bool:
    """识别结果里除公式外基本没有正常文字（即使定界符不配对也能判断）"""
    outside = re.sub(r"\\\[(.+?)\\\]", " ", s, flags=re.S)
    outside = re.sub(r"\\\((.+?)\\\)", " ", outside, flags=re.S)
    if outside == s and not any(d in s for d in ("\\(", "\\[", "$")):
        return False
    for d in ("\\(", "\\)", "\\[", "\\]", "$"):
        outside = outside.replace(d, " ")
    outside = re.sub(r"\\[A-Za-z]+\{[^{}]*\}", " ", outside)
    words = re.findall(r"(?<![\\A-Za-z])[A-Za-z]{3,}", outside)
    cjk = re.findall(r"[\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]", outside)
    return not words and not cjk


def _trim_delimiters(s: str) -> str:
    t = s.strip()
    for l, r in (("\\[", "\\]"), ("\\(", "\\)"), ("$$", "$$"), ("$", "$")):
        if t.startswith(l):
            t = t[len(l):]
        if t.endswith(r):
            t = t[: -len(r)]
    return t.strip()


def _to_markdown_math(s: str) -> str:
    s = re.sub(r"\\\[(.+?)\\\]", lambda m: "$$" + m.group(1).strip() + "$$", s, flags=re.S)
    s = re.sub(r"\\\((.+?)\\\)", lambda m: "$" + m.group(1).strip() + "$", s, flags=re.S)
    return s


def _otsl_to_markdown(s: str) -> str:
    rows = []
    for line in s.split("<nl>"):
        if not line.strip():
            continue
        cells = re.split(r"<(fcel|ecel|lcel|ucel|xcel)>", line)[1:]
        row = []
        for tag, text in zip(cells[0::2], cells[1::2]):
            row.append(_to_markdown_math(text.strip()) if tag == "fcel" else "")
        rows.append(row)
    if not rows:
        return s
    n = max(len(r) for r in rows)
    rows = [r + [""] * (n - len(r)) for r in rows]
    out = ["| " + " | ".join(rows[0]) + " |", "|" + " --- |" * n]
    out += ["| " + " | ".join(r) + " |" for r in rows[1:]]
    return "\n".join(out)


def recognize(img: Image.Image, mode: str = "auto") -> dict:
    """返回 {mode, kind, latex, markdown, raw, seconds}。kind: formula / text / table"""
    t0 = time.time()
    img = _prepare(img)

    as_formula = False
    if mode == "table":
        raw = _call(img, "table")
        md = _otsl_to_markdown(raw)
        kind, latex = "table", md
    else:
        if mode == "formula":
            raw = _call(img, "formula")
            as_formula = True
        else:
            raw = _call(img, "text")
            if mode == "auto" and "<fcel>" in raw:
                raw = _call(img, "table")
            elif mode == "auto" and _is_mostly_math(raw):
                # 除公式外没有正常文字：用公式模式重识别，精度更高
                raw = _call(img, "formula")
                as_formula = True
        if "<fcel>" in raw:
            md = _otsl_to_markdown(raw)
            kind, latex = "table", md
        else:
            pure = _strip_math(raw)
            if pure is None and as_formula:
                pure = _trim_delimiters(raw)
            if pure is not None:
                kind, latex, md = "formula", pure, "$$\n" + pure + "\n$$"
            else:
                kind, latex, md = "text", raw, _to_markdown_math(raw)

    return {
        "mode": mode,
        "kind": kind,
        "latex": latex,
        "markdown": md,
        "raw": raw,
        "seconds": round(time.time() - t0, 2),
    }


if __name__ == "__main__":
    import sys

    path, mode = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else "auto")
    print(json.dumps(recognize(Image.open(path), mode), ensure_ascii=False, indent=2))
