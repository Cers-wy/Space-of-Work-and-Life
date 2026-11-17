#!/bin/zsh
# Space 2.3.6 macOS 发布打包（在用户终端执行：Agent 通道受 sandbox-exec 系统级限制）
# 用法: zsh tool/package_release_macos.sh
set -euo pipefail
cd "$(dirname "$0")/.."   # flutter/

FLUTTER="$PWD/../work/flutter-sdk-bootstrap/flutter/bin/flutter"
OUT="$PWD/../downloads"
WORK="$PWD/../work/space-release-2.3.6/package-macos"

echo "== [1/3] Release 构建生产入口 lib/main.dart（universal，约 3-6 分钟）=="
"$FLUTTER" build macos --release --target=lib/main.dart

echo "== [2/3] 打包 ZIP + DMG（深层 ad-hoc 签名 + 校验）=="
python3 tool/package_macos.py --work "$WORK"

echo "== [3/3] 更新 downloads/SHA256SUMS.txt =="
python3 - "$OUT" "$WORK" <<'PY'
import hashlib, sys
from pathlib import Path
out, work = Path(sys.argv[1]), Path(sys.argv[2])
info = (work / 'verification.json')
import json
v = json.loads(info.read_text())
names = [f"Space-{v['version']}-macOS-{v['architectures'][0] if len(v['architectures'])==1 else 'universal'}.zip",
         f"Space-{v['version']}-macOS-{v['architectures'][0] if len(v['architectures'])==1 else 'universal'}.dmg"]
sums = out / 'SHA256SUMS.txt'
lines = [l for l in sums.read_text().splitlines() if l.split('  ')[0] and all(n not in l for n in names)]
for n in names:
    p = out / n
    lines.append(f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {n}")
sums.write_text('\n'.join(lines) + '\n')
print('SHA256SUMS.txt 已更新：')
for l in lines[-2:]:
    print(' ', l)
PY

echo ""
echo "✅ 打包完成。产物与校验："
ls -lh "$OUT"/Space-2.3.6-macOS-*.{zip,dmg}
echo "打包核验: $WORK/verification.json"
