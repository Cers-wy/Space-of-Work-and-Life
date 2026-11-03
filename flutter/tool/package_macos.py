"""Package an already built macOS Release; never reads user databases."""
from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
source = root / 'build/macos/Build/Products/Release/Space Flutter.app'
info = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
version = info['CFBundleShortVersionString']
assert info['CFBundleIdentifier'] == 'com.cers.space.flutter'
output = root.parent / 'output/flutter'
output.mkdir(parents=True, exist_ok=True)
name = f'Space-Flutter-{version}-macOS-arm64'
distribution = output / name
assert not distribution.exists(), '分发目录已存在，请先审阅，不自动覆盖'
distribution.mkdir()
application = distribution / 'Space Flutter.app'
subprocess.run(['ditto', str(source), str(application)], check=True)
subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(application)], check=True)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(application)], check=True)
shutil.copy2(root / 'INSTALL-macOS.md', distribution / '安装说明.md')
shutil.copy2(root / 'THIRD_PARTY_NOTICES.txt', distribution / 'THIRD_PARTY_NOTICES.txt')
archive = output / (name + '.zip')
assert not archive.exists()
subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent',
                str(distribution), str(archive)], check=True)
stage = root.parent / 'work/dmg-packaging' / name
assert not stage.exists(), 'DMG暂存目录已存在'
stage.mkdir(parents=True)
subprocess.run(['ditto', str(application), str(stage / application.name)], check=True)
(stage / 'Applications').symlink_to('/Applications')
shutil.copy2(root / 'INSTALL-macOS.md', stage / '安装说明.md')
image = output / (name + '.dmg')
assert not image.exists()
subprocess.run(['hdiutil', 'create', '-volname', f'Space Flutter {version}',
                '-srcfolder', str(stage), '-ov', '-format', 'UDZO', str(image)], check=True)
subprocess.run(['hdiutil', 'verify', str(image)], check=True)
checksums = {}
for artifact in [archive, image]:
    digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
    artifact.with_suffix(artifact.suffix + '.sha256').write_text(f'{digest}  {artifact.name}\n')
    checksums[artifact.name] = digest
(output / f'{name}-verification.json').write_text(json.dumps({
    'version': version, 'build': info['CFBundleVersion'],
    'bundle_id': info['CFBundleIdentifier'], 'checksums': checksums,
    'code_signature': 'adhoc; codesign --verify --deep --strict passed',
}, ensure_ascii=False, indent=2))
print(json.dumps({'distribution': str(distribution), 'checksums': checksums}, ensure_ascii=False))
