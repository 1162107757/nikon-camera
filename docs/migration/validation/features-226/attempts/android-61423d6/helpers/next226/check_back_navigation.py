from pathlib import Path
import hashlib, json, re, sys, time

r = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(r / '.tooling/next226'))
from qa_ui import adb, tap, tree, snap

p = r / '.tooling/next226'
component = 'cc.huevia.next/cc.huevia.sharedapp.MainActivity'
apk = r / '.tooling/next226/package-candidates/huevia-0.31.0-dev-226-android-x64.apk'
source = json.loads((p / 'source.json').read_text('utf-8'))['sourceCommit']

def status():
    raw = adb('shell', 'dumpsys', 'activity', 'activities').decode('utf-8', errors='replace')
    records = re.findall(r'ActivityRecord\{([^}]+cc\.huevia\.next/cc\.huevia\.sharedapp\.MainActivity[^}]+)\}', raw)
    record = records[0] if records else None
    resumed = next((s.strip() for s in raw.splitlines() if 'mResumedActivity:' in s), '')
    return {'pid': adb('shell', 'pidof', 'cc.huevia.next').decode().strip(),
            'activityRecord': record, 'resumed': resumed,
            'foreground': 'cc.huevia.next/' in resumed}

def reopen():
    adb('shell', 'am', 'start', '-n', component)
    time.sleep(.7)

reopen()
time.sleep(1.5)
for setup_step in range(4):
    setup_tree = tree().decode('utf-8')
    if all(label in setup_tree for label in ['同步', '设置', '相册', '预设']):
        break
    adb('shell', 'input', 'keyevent', '4')
    time.sleep(.5)
initial = status()
assert initial['foreground'] and initial['activityRecord']
cases = []
for label in ['同步', '设置', '相册', '预设']:
    tap(label, last=True)
    time.sleep(.2)
    before = status()
    adb('shell', 'input', 'keyevent', '4')
    time.sleep(.6)
    background = status()
    assert not background['foreground'], (label, background)
    assert background['pid'] == before['pid'], (label, 'process changed')
    assert background['activityRecord'] == before['activityRecord'], (label, 'activity destroyed')
    reopen()
    after = status()
    assert after['foreground'] and after['activityRecord'] == before['activityRecord']
    assert after['pid'] == before['pid']
    visible = snap('back226-resumed-' + {'同步':'sync','设置':'settings','相册':'album','预设':'presets'}[label])
    assert visible[0][0] == label, (label, visible[0])
    cases.append({'rootTab': label, 'before': before, 'background': background, 'after': after,
                  'sameActivityAndProcess': True})

tap('同步', last=True)
tap('连接相机')
time.sleep(.4)
nested = status()
assert b'USB' in tree()
adb('shell', 'input', 'keyevent', '4')
time.sleep(.4)
returned = status()
assert returned['foreground'] and returned['activityRecord'] == nested['activityRecord']
assert '相机工具'.encode() in tree()
snap('back226-connection-returned-sync')
if '下载队列'.encode() not in tree():
    tap('相机工具')
tap('下载队列\n暂无进行中的下载')
time.sleep(.3)
assert '暂无下载任务'.encode() in tree()
adb('shell', 'input', 'keyevent', '4')
time.sleep(.4)
modal = status()
assert modal['foreground'] and modal['activityRecord'] == nested['activityRecord']
assert '相机工具'.encode() in tree()
snap('back226-queue-returned-sync')
tap('预设', last=True)
snap('back226-restored-home')
report = {'sourceCommit': source, 'apkSha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
    'androidApi': 31, 'physicalCameraTested': False, 'rootCases': cases,
    'connectionPageBackReturnsToSync': True, 'queueBackReturnsToSync': True,
    'rootBackMovesTaskToBackground': True, 'sameActivityAndProcessRetained': True,
    'finalScreen': '我的预设', 'exit': 0}
(p / 'back-navigation-result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', 'utf-8')
print(json.dumps({'rootCases': len(cases), 'nestedCases': 2, 'exit': 0, 'source': source}))
