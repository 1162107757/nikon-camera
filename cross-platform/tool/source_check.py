"""Catch text encodings and malformed platform configuration before remote builds."""
from pathlib import Path
import json,plistlib,subprocess,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[2]
raw=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z','--','cross-platform','docs/migration','.github/workflows/cross-platform-core.yml','.github/workflows/cross-platform-mobile.yml'],cwd=ROOT)
names=set(raw.decode().split('\0'))-{''}
extensions={'.dart','.java','.m','.mm','.cpp','.h','.py','.sh','.md','.yaml','.yml','.json','.xml','.plist','.kts','.gradle','.podspec','.properties','.pbxproj'}
checked=0
for name in sorted(names):
    path=ROOT/name
    if path.suffix not in extensions or not path.is_file():continue
    text=path.read_text(encoding='utf-8-sig');checked+=1
    if path.suffix=='.json':json.loads(text)
    if path.suffix=='.plist':plistlib.loads(path.read_bytes())
    if path.suffix=='.xml':ET.fromstring(text)
print('Valid UTF-8 text and platform configuration: '+str(checked)+' files')
