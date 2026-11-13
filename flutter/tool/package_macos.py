"""Package the verified Space Release without reading application data."""
import argparse
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'build/macos/Build/Products/Release/Space.app')
parser.add_argument('--output', type=Path, default=root.parent / 'downloads')
parser.add_argument('--work', type=Path, default=root.parent / 'work/space210/package-macos')
args = parser.parse_args()
source, output, work = args.source.resolve(), args.output.resolve(), args.work.resolve()
info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
assert info['CFBundleIdentifier'] == 'com.cers.space.flutter'
assert info['CFBundleName'] == 'Space'
output.mkdir(parents=True, exist_ok=True)
architectures = subprocess.check_output(
    ['lipo', '-archs', str(source / 'Contents/MacOS/Space')], text=True,
).strip().split()
architecture = 'universal' if set(architectures) == {'arm64', 'x86_64'} else architectures[0]
name = f'Space-{version}-macOS-{architecture}'
distribution = work / name
assert not distribution.exists(), 'Staging directory already exists; retain and review it first'
distribution.mkdir(parents=True)
application = distribution / 'Space.app'
subprocess.run(['ditto', str(source), str(application)], check=True)
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(application)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(application)], check=True)
shutil.copy2(root / 'INSTALL-macOS.md', distribution / '安装说明.md')
shutil.copy2(root / 'THIRD_PARTY_NOTICES.txt', distribution / 'THIRD_PARTY_NOTICES.txt')
archive = output / (name + '.zip')
assert not archive.exists(), 'Distribution already exists; do not silently overwrite it'
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(distribution), str(archive)], check=True)
stage = work / 'dmg-stage'
assert not stage.exists()
stage.mkdir()
subprocess.run(['ditto', str(application), str(stage / 'Space.app')], check=True)
(stage / 'Applications').symlink_to('/Applications')
shutil.copy2(root / 'INSTALL-macOS.md', stage / '安装说明.md')
shutil.copy2(root / 'THIRD_PARTY_NOTICES.txt', stage / 'THIRD_PARTY_NOTICES.txt')
image = output / (name + '.dmg')
assert not image.exists()
subprocess.run(['hdiutil', 'create', '-volname', f'Space {version}', '-srcfolder', str(stage), '-ov', '-format', 'UDZO', str(image)], check=True)
subprocess.run(['hdiutil', 'verify', str(image)], check=True)
checksums = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [archive, image]}
(work / 'verification.json').write_text(json.dumps({
    'version': version, 'build': info['CFBundleVersion'], 'bundle_id': info['CFBundleIdentifier'],
    'architectures': architectures,
    'checksums': checksums, 'code_signature': 'adhoc; codesign --verify --deep --strict passed',
}, ensure_ascii=False, indent=2))
print(json.dumps({'distribution': str(distribution), 'checksums': checksums}, ensure_ascii=False))
