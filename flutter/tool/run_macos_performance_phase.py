"""Run one isolated foreground measurement; do not target an installed app.

macOS open -a activation was explicitly authorized by the user. Keeping this
tool call alive until the phase completes avoids restoring the user's previous
front application in the middle of a sample.
"""
import argparse
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('directory', type=Path)
parser.add_argument('application', type=Path)
args = parser.parse_args()
directory, application = args.directory.resolve(), args.application.resolve()
assert 'work' in directory.parts and 'space233' in directory.name
assert 'build/macos/Build/Products/Profile/Space.app' in str(application)
limit = time.monotonic() + 15
while True:
    if (directory / 'result.json').exists():
        print('All phases completed')
        raise SystemExit(0)
    if not (directory / 'waiting.json').exists():
        if time.monotonic() > limit:
            raise SystemExit('Probe has not reached its first phase')
        time.sleep(.1)
        continue
    waiting = json.loads((directory / 'waiting.json').read_text())['scenario']
    done = directory / (waiting + '.done')
    if not done.exists() or not json.loads(done.read_text())['foregroundThroughout']:
        break
    if time.monotonic() > limit:
        raise SystemExit('Probe did not advance to the next phase')
    time.sleep(.1)
if done.exists():
    previous = json.loads(done.read_text())
    assert not previous['foregroundThroughout'], 'Phase already passed; do not silently reuse it'
    done.unlink()
subprocess.run(['open', '-a', str(application)], check=True)
time.sleep(.7)
subprocess.run(['open', '-a', str(application)], check=True)
(directory / (waiting + '.go')).touch()
deadline = time.monotonic() + 28
while time.monotonic() < deadline:
    if (directory / 'error.txt').exists():
        raise SystemExit((directory / 'error.txt').read_text())
    if done.exists():
        try:
            result = json.loads(done.read_text())
        except json.JSONDecodeError:
            time.sleep(.05)
            continue
        print(json.dumps(result))
        if not result['foregroundThroughout'] or result['lifecycle'] != 'resumed':
            raise SystemExit('Invalid foreground sample; must not mark as passed')
        break
    time.sleep(.1)
else:
    raise SystemExit('No completed phase within 28s; inspect focus before retrying')
