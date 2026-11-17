"""Launch the Release performance probe and collect its report.

Read-only with respect to user data: the probe requires an explicitly empty
directory and creates synthetic data there. `open -a` activation follows the
previously authorized pattern from tool/run_macos_performance_phase.py.

Usage:
  python3 tool/run_perf_probe.py <app-bundle> <data-dir> <label>
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

app = Path(sys.argv[1]).resolve()
data = Path(sys.argv[2]).resolve()
label = sys.argv[3]

if data.exists():
    if any(data.iterdir()):
        raise SystemExit(f'Data directory must be empty: {data}')
else:
    data.mkdir(parents=True)

binary = app / 'Contents' / 'MacOS' / 'Space'
proc = subprocess.Popen(
    [str(binary)],
    env={**os.environ, 'SPACE_FLUTTER_DATA_DIRECTORY': str(data)},
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
time.sleep(1.5)
subprocess.run(['open', '-a', str(app)], check=True)
time.sleep(0.7)
subprocess.run(['open', '-a', str(app)], check=True)
print(
    '探针窗口已启动：若窗口顶部出现黄色「测量已暂停」横幅，'
    '请点击该窗口使其置于最前，采样会自动继续；'
    '测量期间短暂切走也没关系，回来点击即可。',
    flush=True,
)

deadline = time.monotonic() + 1200
while time.monotonic() < deadline:
    error = data / 'error.txt'
    report = data / 'report.json'
    if error.exists():
        print(error.read_text())
        proc.terminate()
        raise SystemExit(1)
    if report.exists():
        payload = json.loads(report.read_text())
        out = data / f'report-{label}.json'
        out.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + '\n')
        print(f'wrote {out}')
        for r in payload.get('results', []):
            keep = {
                k: r[k]
                for k in (
                    'scenario', 'seconds', 'cpuMeanPercent', 'rssMiB',
                    'psRssMiB', 'buildP95Ms', 'rasterP95Ms',
                    'overBudgetFrames', 'budgetSampleCount',
                    'foregroundThroughout', 'lifecycle',
                )
                if k in r
            }
            print(json.dumps(keep, ensure_ascii=False))
        time.sleep(2)
        proc.terminate()
        raise SystemExit(0)
    time.sleep(0.5)
proc.terminate()
raise SystemExit('Probe did not finish within 1200s')
