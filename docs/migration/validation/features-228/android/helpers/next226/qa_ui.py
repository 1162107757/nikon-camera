from pathlib import Path
import subprocess, re, xml.etree.ElementTree as E

r = Path(__file__).resolve().parents[2]
d = r / '.tooling/next228/ui'
d.mkdir(exist_ok=True)
a = [r'D:/dev/Android/Sdk/platform-tools/adb.exe', '-s', 'emulator-5584']
def adb(*args):
    return subprocess.check_output([*a, *args], timeout=25)
def tree():
    import time
    last = None
    for attempt in range(3):
        try:
            dump = adb('shell','uiautomator','dump','/sdcard/huevia227-ui.xml')
            if b'dumped to:' not in dump or b'ERROR' in dump:
                raise RuntimeError('No fresh hierarchy: '+dump.decode('utf8',errors='replace'))
            raw = adb('shell','cat','/sdcard/huevia227-ui.xml')
            assert E.fromstring(raw).tag == 'hierarchy'
            return raw
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired, RuntimeError, E.ParseError) as error:
            last = error
            time.sleep(.3)
    raise RuntimeError('No fresh UI hierarchy after three attempts') from last
def tap(label, last=False):
    nodes = [n for n in E.fromstring(tree()).iter('node') if label in (n.get('text'), n.get('content-desc'))]
    assert nodes, f'Visible label not found: {label}'
    n = nodes[-1 if last else 0]
    x1,y1,x2,y2 = map(int,re.findall(r'\d+',n.get('bounds')))
    adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
def snap(name):
    raw = tree()
    (d/(name+'.xml')).write_bytes(raw)
    (d/(name+'.png')).write_bytes(adb('exec-out','screencap','-p'))
    labels = [(n.get('text') or n.get('content-desc'),n.get('bounds')) for n in E.fromstring(raw).iter('node') if n.get('text') or n.get('content-desc')]
    print(name, labels[:50])
    return labels
