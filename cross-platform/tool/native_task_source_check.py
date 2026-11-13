"""Reject legacy setters of the readonly native task cancellation contract."""
from pathlib import Path
import re
import subprocess


WRITE = re.compile(r"\.\s*cancelled\s*(?:=(?!=)|\+=|-=|\|=|&=|\+\+|--)|\bsetCancelled\s*:|setValue\s*:[^;]{0,200}forKey\s*:\s*@\"cancelled\"")
INDEPENDENT_FIXTURE = "cross-platform/core/test/wifi_apple.m"


def check(root=None, names=None):
    root = Path(root) if root else Path(__file__).resolve().parents[2]
    if names is None:
        raw = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', 'cross-platform'], cwd=root)
        names = set(raw.decode().split('\0')) - {''}
    header = (root / 'cross-platform/native/ios/Classes/HueviaTask.h').read_text(encoding='utf-8-sig')
    assert re.search(r'@property\s*\([^)]*\breadonly\b[^)]*\)\s*BOOL\s+cancelled\b', header), 'HueviaTask.cancelled must remain readonly'
    assert re.search(r'-\s*\(\s*BOOL\s*\)\s*cancelIfActive\s*;', header), 'Native task cancel API is missing'
    assert re.search(r'-\s*\(\s*void\s*\)\s*finish\s*;', header), 'Native task completion API is missing'
    checked = 0
    independent = 0
    for name in sorted(names):
        path = root / name
        if not name.startswith('cross-platform/') or path.suffix not in {'.m', '.mm', '.h'} or 'Generated' in path.parts or not path.is_file():
            continue
        text = path.read_text(encoding='utf-8-sig')
        checked += 1
        for match in WRITE.finditer(text):
            line = text.count('\n', 0, match.start()) + 1
            if name == INDEPENDENT_FIXTURE:
                # This fixture deliberately implements its own writable boolean
                # supplier. It does not import or instantiate HueviaTask.
                assert not re.search(r'\bHueviaTask\b', text), f'{name} may not exempt HueviaTask writes'
                declaration = re.search(r'@interface\s+HueviaCameraCancellationFlag\b(?:(?!@end).)*@end', text, re.S)
                assert declaration and re.search(r'@property\s*\((?![^)]*\breadonly\b)[^)]*\)\s*BOOL\s+cancelled\s*;', declaration.group()), 'Independent Wi-Fi flag must have its own writable property'
                assert re.search(r'HueviaCameraCancellationFlag\s*\*\s*permissionCancel\b', text), 'Independent Wi-Fi flag receiver changed'
                assert re.search(r'\bpermissionCancel\s*$', text[:match.start()]), f'Unknown cancellation setter at {name}:{line}'
                independent += 1
                continue
            raise AssertionError(f'Legacy readonly task cancellation write at {name}:{line}; use cancelIfActive')
    print(f'Readonly HueviaTask cancellation API: {checked} Apple sources checked; {independent} independently typed fixture setter retained')


if __name__ == '__main__':
    check()
