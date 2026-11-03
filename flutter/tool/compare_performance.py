"""Run isolated, already-built Release benchmarks sequentially on this Mac.

The benchmark apps must use tool/performance_main.dart and distinct bundle IDs.
Only synthetic empty directories are supplied. Never launches the installed app.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--before', type=Path, required=True)
parser.add_argument('--after', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--resume', action='store_true', help='Reuse only completed synthetic runs in this output directory')
args = parser.parse_args()
output = args.output.absolute()
output.mkdir(parents=True, exist_ok=True)
reports = {'before': [], 'after': []}
inputs = {}
reused = []
dart_app_hashes = {}
libproc = ctypes.CDLL(None)
libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
libproc.proc_pid_rusage.restype = ctypes.c_int


def native_sample(pid):
    # macOS SDK sys/resource.h: rusage_info_v0 is UUID[16] + 10 uint64s.
    # ri_resident_size is at byte 64; ri_phys_footprint at byte 72.
    usage = (ctypes.c_uint64 * 12)()
    if libproc.proc_pid_rusage(pid, 0, ctypes.byref(usage)) != 0:
        return None
    return {'timestamp': time.time(), 'rssMiB': usage[8] / 1048576,
            'physicalFootprintMiB': usage[9] / 1048576}
for label, application in [('before', args.before), ('after', args.after)]:
    application = application.absolute()
    executable = application / 'Contents/MacOS' / application.stem
    if not executable.is_file():
        raise RuntimeError(f'Benchmark executable not found: {executable}')
    inputs[label] = (executable, hashlib.sha256(executable.read_bytes()).hexdigest())
    dart_app = application / 'Contents/Frameworks/App.framework/Versions/A/App'
    dart_app_hashes[label] = hashlib.sha256(dart_app.read_bytes()).hexdigest()

# Alternate the order to reduce systematic warm-up/order effects. Do not run
# builds or tests while these measurements are in progress.
for repeat, order in [(2, ['before', 'after']), (3, ['after', 'before'])]:
    for label in order:
        directory = output / f'{label}-r{repeat}'
        completed = (directory / 'report.json').is_file() and (directory / 'native-memory-samples.json').is_file()
        if directory.exists() and not (args.resume and completed):
            raise RuntimeError(f'Refusing to reuse benchmark data: {directory}')
        env = os.environ.copy()
        env['SPACE_FLUTTER_DATA_DIRECTORY'] = str(directory)
        executable, _ = inputs[label]
        if args.resume and completed:
            print(f'Reusing completed {label}-r{repeat}', flush=True)
            reused.append(f'{label}-r{repeat}')
            samples = json.loads((directory / 'native-memory-samples.json').read_text())
        else:
            print(f'Starting {label}-r{repeat}', flush=True)
            samples = []
            with (output / f'{label}-r{repeat}.log').open('w') as log:
                process = subprocess.Popen([str(executable)], env=env, stdout=log, stderr=log)
                deadline = time.monotonic() + 100
                while process.poll() is None:
                    if time.monotonic() >= deadline:
                        process.kill()
                        process.wait()
                        raise TimeoutError(f'Benchmark timeout: {label}-r{repeat}')
                    sample = native_sample(process.pid)
                    if sample:
                        samples.append(sample)
                    time.sleep(.1)
                if process.returncode:
                    raise subprocess.CalledProcessError(process.returncode, str(executable))
            (directory / 'native-memory-samples.json').write_text(json.dumps(samples, indent=2))
        report = json.loads((directory / 'report.json').read_text())
        for row in report['results']:
            end = (directory / f"{row['scenario']}.json").stat().st_mtime
            during = [s for s in samples if end - row['seconds'] <= s['timestamp'] <= end]
            if not during:
                raise RuntimeError(f"No native samples for {row['scenario']}")
            row['physicalFootprintMiB'] = statistics.median(s['physicalFootprintMiB'] for s in during)
            row['physicalFootprintMaxMiB'] = max(s['physicalFootprintMiB'] for s in during)
        assert report['formalDataAccessed'] is False
        report['excludedNonForegroundScenarios'] = [row['scenario'] for row in report['results'] if not row.get('foregroundThroughout', row['lifecycle'] == 'resumed')]
        if report['excludedNonForegroundScenarios']:
            print(f"Excluded background scenarios: {report['excludedNonForegroundScenarios']}", flush=True)
        (directory / 'report-with-native-memory.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
        reports[label].append(report)
        print(f'Completed {label}-r{repeat}', flush=True)

comparison = {}
for label, runs in reports.items():
    grouped = {}
    for report in runs:
        for row in report['results']:
            if not row.get('foregroundThroughout', row['lifecycle'] == 'resumed'):
                continue
            grouped.setdefault(row['scenario'], []).append(row)
    comparison[label] = {
        scenario: {
            'validForegroundSamples': len(rows),
            **{field: statistics.median(row[field] for row in rows)
            for field in ['rssMiB', 'physicalFootprintMiB', 'physicalFootprintMaxMiB', 'cpuMeanPercent', 'imageCacheBytes',
                          'imageCacheCount', 'frameCount', 'buildP95Ms', 'rasterP95Ms']}
        } for scenario, rows in grouped.items()
    }
result = {
    'method': 'Two Release runs per version; medians of valid foreground scenario measurements; completed reused runs listed separately',
    'reusedCompletedRuns': reused,
    'foregroundPolicy': 'Exclude any scenario that was not resumed throughout its entire measurement interval',
    'formalDataAccessed': False,
    'executableSha256': {key: pair[1] for key, pair in inputs.items()},
    'dartAppSha256': dart_app_hashes,
    'comparison': comparison,
}
(output / 'comparison.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
print(json.dumps(result, ensure_ascii=False, indent=2), flush=True)
