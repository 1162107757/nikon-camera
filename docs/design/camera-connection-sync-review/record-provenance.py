"""Record origins and embed metadata; does not change raster pixel data."""
from pathlib import Path
import hashlib
import json
import subprocess

root = Path(__file__).resolve().parent
workspace = Path(r'D:\dev\ai-project\nikon-camera')
embed = Path(r'C:\Users\11621\.codex\skills\impeccable\scripts\embed-prompt.mjs')
records = []
for asset in sorted((root / 'assets').glob('*.jpg')):
    source = workspace / 'app/src/main/assets/preset-showcase' / asset.name
    origin = f'Existing project photography, copied from {source}; used only as synthetic UI demonstration background. No new generation or photographic claim.'
    subprocess.run(['node', str(embed), str(asset), '--prompt', origin], check=True, capture_output=True, text=True)
    records.append({'file': str(asset.relative_to(root)), 'origin': str(source), 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
for asset in sorted((root / 'review').glob('*.png')):
    origin = f'Browser screenshot of standalone local Huevia HTML prototype, {asset.name}. Source: http://127.0.0.1:4319/ ; capture recipes review-check.cjs and remote-recovery-check.cjs; board/cover screenshots render their corresponding local HTML routes. Phone screens 375x812 except named board/cover/narrow captures. All camera and task data synthetic; no native runtime or camera verification.'
    subprocess.run(['node', str(embed), str(asset), '--prompt', origin], check=True, capture_output=True, text=True)
    records.append({'file': str(asset.relative_to(root)), 'origin': origin})
for key, filename in [('A', 'A-capsule.png'), ('B', 'B-circle.png'), ('C', 'C-edge-tab.png')]:
    asset = root / 'collapsed-options' / filename
    prompt_file = asset.parent / f'{key}.prompt.txt'
    subprocess.run(['node', str(embed), str(asset), '--prompt-file', str(prompt_file)], check=True, capture_output=True, text=True)
    records.append({'file': str(asset.relative_to(root)), 'origin': 'Built-in ImageGen; references review/android-light-sync-entry.png and review/android-dark-sync-entry.png from before the selected B circle was implemented.', 'prompt': str(prompt_file.relative_to(root)), 'selected': key == 'B'})
for record in records:
    record['sha256'] = hashlib.sha256((root / record['file']).read_bytes()).hexdigest()
(root / 'asset-provenance.json').write_text(json.dumps({'scope': 'Design prototype and three generated direction images only', 'assets': records}, ensure_ascii=False, indent=2), encoding='utf8')
print(f'Embedded and recorded provenance for {len(records)} rasters; pixel data unchanged.')
