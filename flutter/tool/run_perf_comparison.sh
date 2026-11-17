#!/bin/zsh
# Space 烟雾卡片性能对比测量：同一源码分别以旧/新时钟构建 Release 探针并采样。
# 用法：
#   zsh tool/run_perf_comparison.sh            # 全流程（基线构建+采样 → 优化构建+采样 → 对比）
#   zsh tool/run_perf_comparison.sh after-only # 只重跑优化采样（复用已有基线数据，约 3-4 分钟）
# 测量须知：探针窗口失焦时会自动暂停并在顶部显示黄色横幅，
# 点击该窗口使其回到最前后采样自动继续；旧数据只归档不删除。
set -e
ROOT="$HOME/Documents/ChatGPT/个人工作台"
FLUTTER="$ROOT/work/flutter-sdk-bootstrap/flutter/bin/flutter"
APP="$ROOT/flutter/build/macos/Build/Products/Release/Space.app"
OUT="$ROOT/work/space-perf-20261117"
PY=python3
MODE="${1:-full}"

unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy
export PUB_CACHE="$ROOT/work/flutter-sdk-bootstrap/pub-cache"

cd "$ROOT/flutter"
mkdir -p "$OUT"

archive_if_needed() {  # $1 = 目录；非空则整体移走归档（不删除）
  if [ -d "$1" ] && [ -n "$(ls -A "$1" 2>/dev/null)" ]; then
    mv "$1" "$1.invalid-$(date +%H%M%S)"
    echo "（旧数据已归档：$(basename "$1").invalid-*）"
  fi
}

verify_clock() {  # $1=report.json $2=期望时钟 $3=阶段名
  local got
  got=$($PY -c "import json;print(json.load(open('$1')).get('smokeClock','missing'))")
  if [ "$got" != "$2" ]; then
    echo "!! $3 构建实际编译进二进制的烟雾时钟是 '$got'，期望 '$2'。"
    echo "   说明 --dart-define 未生效或构建缓存异常，本轮 A/B 无效，中止（数据保留在 $1）"
    exit 1
  fi
  echo "✓ $3 时钟校验通过：$got"
}

if [ "$MODE" = "full" ]; then
  echo "== [1/5] 基线构建（旧版每卡独立 20Hz 时钟） =="
  "$FLUTTER" build macos --release --target=tool/performance_main.dart \
    --dart-define=SPACE_LEGACY_SMOKE_CLOCK=true

  echo "== [2/5] 基线采样（请保持探针窗口在最前；出现黄色横幅时点击该窗口继续） =="
  archive_if_needed "$OUT/before-data"
  $PY tool/run_perf_probe.py "$APP" "$OUT/before-data" baseline
  verify_clock "$OUT/before-data/report-baseline.json" "legacy-per-card-20hz" "基线"
elif [ "$MODE" = "after-only" ]; then
  if [ ! -s "$OUT/before-data/report-baseline.json" ]; then
    echo "缺少基线数据 before-data/report-baseline.json，请先用完整模式跑一遍"
    exit 1
  fi
else
  echo "未知模式：$MODE（可选 full | after-only）"
  exit 1
fi

echo "== [3/5] 优化构建（共享 13.3Hz 时钟） =="
"$FLUTTER" build macos --release --target=tool/performance_main.dart

echo "== [4/5] 优化采样（请保持探针窗口在最前；出现黄色横幅时点击该窗口继续） =="
archive_if_needed "$OUT/after-data"
$PY tool/run_perf_probe.py "$APP" "$OUT/after-data" optimized
verify_clock "$OUT/after-data/report-optimized.json" "shared-13.3hz" "优化"

echo "== [5/5] 对比 =="
$PY - "$OUT" <<'EOF'
import json, sys
from pathlib import Path
out = Path(sys.argv[1])
before = json.loads((out / 'before-data' / 'report-baseline.json').read_text())
after = json.loads((out / 'after-data' / 'report-optimized.json').read_text())
rows = []
for b in before['results']:
    a = next(x for x in after['results'] if x['scenario'] == b['scenario'])
    rows.append((b['scenario'], b, a))
def flag(r):
    return '' if r.get('foregroundThroughout') else '(失焦!)'
print(f"{'场景':<22}{'CPU% 前/后':>20}{'内存MiB 前/后':>22}{'rasterP95 前/后':>20}")
for name, b, a in rows:
    print(f"{name:<22}"
          f"{b['cpuMeanPercent']:>7.2f}/{a['cpuMeanPercent']:<10.2f}"
          f"{b['psRssMiB']:>9.1f}/{a['psRssMiB']:<10.1f}"
          f"{b['rasterP95Ms']:>9.2f}/{a['rasterP95Ms']:<9.2f}"
          f" {flag(b)}{flag(a)}")
invalid = [n for n, b, a in rows
           if not b.get('foregroundThroughout') or not a.get('foregroundThroughout')]
b0 = next(r for r in before['results'] if r['scenario'] == 'board-idle')
a0 = next(r for r in after['results'] if r['scenario'] == 'board-idle')
print(f"board-idle 诊断: 时钟 {before.get('smokeClock')} → {after.get('smokeClock')}, "
      f"窗口 {b0.get('windowLogicalSize')} → {a0.get('windowLogicalSize')}, "
      f"挂载烟雾卡 {b0.get('cardFlowSmokeEnabled')} → {a0.get('cardFlowSmokeEnabled')} (共 {b0.get('cardFlowTotal')} → {a0.get('cardFlowTotal')})")
if invalid:
    print('!! 前台有效性缺失的场景：', invalid, '（标注(失焦!)的样本不可作为结论，需用对应模式重跑）')
else:
    print('全部 14 个场景均为有效前台采样。')
summary = {
    'mode': before.get('mode'),
    'rows': [
        {'scenario': n,
         'baseline': {k: b.get(k) for k in ('cpuMeanPercent', 'psRssMiB', 'rssMiB', 'buildP95Ms', 'rasterP95Ms', 'overBudgetFrames', 'foregroundThroughout')},
         'optimized': {k: a.get(k) for k in ('cpuMeanPercent', 'psRssMiB', 'rssMiB', 'buildP95Ms', 'rasterP95Ms', 'overBudgetFrames', 'foregroundThroughout')}}
        for n, b, a in rows
    ],
}
(out / 'comparison.json').write_text(
    json.dumps(summary, indent=2, ensure_ascii=False) + '\n')
print(f"已写入 {out / 'comparison.json'}")
EOF
