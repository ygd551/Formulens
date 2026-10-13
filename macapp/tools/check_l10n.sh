#!/bin/zsh
# 检查代码中的每条界面文字 L("...") 都有简体中文翻译，并且没有多余的翻译
set -euo pipefail
cd "$(dirname "$0")/.."
STRINGS=Resources/zh-Hans.lproj/Localizable.strings
plutil -lint "$STRINGS" >/dev/null
/usr/bin/python3 -I - "$STRINGS" Sources/*.swift <<'PY'
import re, subprocess, sys, json
strings, sources = sys.argv[1], sys.argv[2:]
zh = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", strings]))
keys = set()
for f in sources:
    for m in re.finditer(r'L\("((?:[^"\\]|\\.)*)"', open(f, encoding="utf-8").read()):
        keys.add(m.group(1).encode().decode("unicode_escape").encode("latin-1").decode("utf-8"))
keys.discard("key")
missing = sorted(keys - zh.keys()); unused = sorted(zh.keys() - keys)
for k in missing: print("缺少翻译：", k)
for k in unused: print("多余翻译：", k)
print(f"共 {len(keys)} 条界面文字，{'全部已翻译' if not missing else f'{len(missing)} 条缺少翻译'}")
sys.exit(1 if missing else 0)
PY
