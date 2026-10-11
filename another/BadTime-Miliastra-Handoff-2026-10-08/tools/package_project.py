"""Create and verify a portable ZIP of project files, excluding caches and prior deliveries."""
from pathlib import Path
from hashlib import sha256
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'deliverables'
NAME = 'BadTime-Miliastra-Handoff-2026-10-08'
MANIFEST = ROOT / 'PACKAGE_MANIFEST.json'
SKIP = {'deliverables', '.git', '.venv', 'venv', '__pycache__', '.pytest_cache',
        '.agents', '.codex', '.aws', '.idea', '.vscode'}

def project_files():
    for p in sorted(ROOT.rglob('*')):
        relative = p.relative_to(ROOT)
        if p.is_file() and p != MANIFEST and not any(x in SKIP for x in relative.parts):
            if p.suffix not in {'.pyc', '.pyo', '.zip', '.tar', '.gz'}:
                yield p

files = list(project_files())
manifest = {
    'project': 'Bad Time battle / Miliastra client Lua',
    'snapshot_date': '2026-10-08',
    'build': '2026-10-08-review-3-text-pause-stab',
    'entry': 'main.lua',
    'handoff_document': 'docs/项目交接与开发说明.md',
    'file_count_excluding_manifest': len(files),
    'files': [{'path': p.relative_to(ROOT).as_posix(), 'bytes': p.stat().st_size,
               'sha256': sha256(p.read_bytes()).hexdigest()} for p in files],
    'excluded': sorted(SKIP),
    'notes': ['No parent knowledge base or Python environment is included.',
              'No official game project save, UI templates, audio assets or server node graph is included.',
              'The manifest does not hash itself.'],
}
MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
OUT.mkdir(exist_ok=True)
archive = OUT / f'{NAME}.zip'
with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for p in files + [MANIFEST]:
        z.write(p, NAME + '/' + p.relative_to(ROOT).as_posix())
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None, 'ZIP CRC check failed'
    assert len(z.namelist()) == len(files) + 1, 'Unexpected archive member count'
    for item in manifest['files']:
        data = z.read(NAME + '/' + item['path'])
        assert len(data) == item['bytes'] and sha256(data).hexdigest() == item['sha256'], item['path']
    assert json.loads(z.read(NAME + '/PACKAGE_MANIFEST.json')) == manifest
digest = sha256(archive.read_bytes()).hexdigest()
(OUT / f'{NAME}.sha256.txt').write_text(f'{digest}  {archive.name}\n', encoding='utf-8')
print(f'PASS ZIP integrity and SHA256: {len(files)+1} files, {archive.stat().st_size:,} bytes')
print(archive)
