"""Small manual acceptance driver. Operates only the dedicated API31 test emulator."""
from pathlib import Path
import argparse
import json
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
OUTPUT = ROOT / '.tooling/legacy-jpeg196/qa'
ADB = ['D:/dev/Android/Sdk/platform-tools/adb.exe', '-P', '5038', '-s', '127.0.0.1:5585']


def call(*args):
    return subprocess.run(ADB + list(args), check=True, capture_output=True, timeout=30).stdout


def view():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    call('shell', 'rm', '-f', '/sdcard/legacy195-view.xml')
    result = call('shell', 'uiautomator', 'dump', '/sdcard/legacy195-view.xml')
    if b'dumped to:' not in result:
        raise RuntimeError('No fresh emulator UI snapshot')
    data = call('shell', 'cat', '/sdcard/legacy195-view.xml')
    (OUTPUT / 'current.xml').write_bytes(data)
    return list(ET.fromstring(data).iter('node'))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('action', choices=['view', 'tap', 'text', 'back', 'capture'])
    p.add_argument('value', nargs='?')
    args = p.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    if args.action == 'view':
        print(json.dumps([(n.get('text') or n.get('content-desc'), n.get('bounds')) for n in view()
                          if n.get('text') or n.get('content-desc')][:32], ensure_ascii=False))
    elif args.action == 'tap':
        nodes = [n for n in view() if n.get('text') == args.value or n.get('content-desc') == args.value]
        clicks = [n for n in nodes if n.get('clickable') == 'true']
        nodes = clicks or nodes
        if len(nodes) != 1:
            raise RuntimeError(f'Expected one UI element {args.value!r}; got {len(nodes)}')
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', nodes[0].get('bounds', '')))
        call('shell', 'input', 'tap', str((x1+x2)//2), str((y1+y2)//2))
        print('Tapped ' + args.value)
    elif args.action == 'text':
        call('shell', 'input', 'keyevent', '123', *(['67'] * 64))
        call('shell', 'input', 'text', args.value)
        print('Entered test field')
    elif args.action == 'back':
        call('shell', 'input', 'keyevent', '4')
    elif args.action == 'capture':
        if not args.value or not re.fullmatch(r'[a-zA-Z0-9_-]+', args.value):
            raise ValueError('Expected simple capture name')
        view()
        (OUTPUT / (args.value + '.xml')).write_bytes((OUTPUT / 'current.xml').read_bytes())
        (OUTPUT / (args.value + '.png')).write_bytes(call('exec-out', 'screencap', '-p'))
        print(str(OUTPUT / (args.value + '.png')))


if __name__ == '__main__':
    main()
