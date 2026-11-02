"""Read-only integrity and interoperability sanity checks. Python standard library only."""
from pathlib import Path
import base64
import hashlib
import json
import re
import sqlite3
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def digest(data):
    return hashlib.sha256(data).hexdigest()

def main():
    source = json.loads((ROOT/'SOURCE-MANIFEST.json').read_text())
    assert len(source['files']) == 45
    for item in source['files']:
        assert digest((ROOT/item['path']).read_bytes()) == item['sha256'], item['path']
    if (ROOT/'BUNDLE-MANIFEST.json').exists():
        bundle = json.loads((ROOT/'BUNDLE-MANIFEST.json').read_text())
        for item in bundle['files']:
            assert digest((ROOT/item['path']).read_bytes()) == item['sha256'], item['path']
    docs = sorted((ROOT/'docs').glob('*.md'))
    assert len(docs) == 8
    assert not (ROOT/'history').exists()
    for doc in list(ROOT.glob('*.md')) + docs + [ROOT/'native/README.md', ROOT/'fixtures/README.md']:
        for target in re.findall(r'\]\(([^)]+)\)', doc.read_text()):
            if target.startswith(('http:', 'https:', '#')):
                continue
            target = target.split('#')[0]
            assert (doc.parent/target).exists(), (doc.name, target)
    acceptance = (ROOT/'docs/05-验收用例.md').read_text()
    numbers = [int(x) for x in re.findall(r'^\| (\d{3}) \|', acceptance, flags=re.M)]
    assert numbers == list(range(1, 191))
    versions = []
    for path in sorted((ROOT/'fixtures').glob('*-json-v*.json')):
        backup = json.loads(path.read_text())
        versions.append(backup['version'])
        assert len(backup['tasks']) == 1
        assert backup['tasks'][0]['completedAt'] is None
    assert sorted(versions) == [1, 2, 3, 4, 5, 6]
    facts = json.loads((ROOT/'fixtures/EXPECTED.json').read_text())
    data = base64.b64decode((ROOT/'fixtures/06-synthetic-sqlite.base64.txt').read_text(), validate=True)
    assert digest(data) == facts['sqliteSHA256']
    assert data.startswith(b'SQLite format 3\x00')
    with tempfile.TemporaryDirectory(prefix='space-interop-') as folder:
        db_path = Path(folder)/'synthetic.sqlite'
        db_path.write_bytes(data)
        with sqlite3.connect(f'file:{db_path}?mode=ro', uri=True) as db:
            assert db.execute('PRAGMA quick_check').fetchone()[0] == 'ok'
            assert db.execute('PRAGMA user_version').fetchone()[0] == 3
            assert db.execute('SELECT count(*) FROM tasks').fetchone()[0] == 1
            payload = json.loads(db.execute('SELECT payload FROM tasks').fetchone()[0])
            assert payload['richDescription'] and len(payload['attachments']) == 2
    portable = (ROOT/'fixtures/09-github-portable.json').read_bytes()
    assert digest(portable) == facts['githubFingerprint']
    portable_object = json.loads(portable)
    assert not portable_object.get('settings') and not portable_object.get('workspaceID')
    packet = base64.b64decode((ROOT/'fixtures/07-github-packet.base64.txt').read_text(), validate=True)
    assert packet.startswith(b'SPACE-GITHUB-1\n')
    envelope = json.loads((ROOT/'fixtures/08-sp-envelope.json').read_text())
    assert envelope['format'] == 1 and len(base64.b64decode(envelope['sealed'])) > 28
    clean = facts['testSPCode'].replace('-', '')[2:]
    assert digest(clean.encode()) == facts['spReceiptID']
    print('PASS: 45 source/resource/document hashes, 8 linked docs, 190 continuous acceptance cases, JSON V1-V6, synthetic SQLite integrity, portable fingerprint, packet structure.')
    print('Cryptographic decryption/RTFD round-trip additionally checked by GenerateInteropFixtures.swift on macOS; this script does not prove a new platform implementation.')

if __name__ == '__main__':
    main()
