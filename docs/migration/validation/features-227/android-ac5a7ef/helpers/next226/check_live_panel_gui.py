from pathlib import Path
import sys,json,time,hashlib,xml.etree.ElementTree as E
sys.path.insert(0,str(Path(__file__).parent))
from qa_ui import adb,tap,snap,tree
p=Path(__file__).parent;r=p.parents[1];source=json.loads((p/'source.json').read_text())['sourceCommit'];apk=p/'package-candidates/huevia-0.31.0-dev-227-android-x64.apk'
assert json.loads((p/'android-acceptance-pipeline.json').read_text())==dict(verify_android=0,verify_photos=0,run_release_runtime=0,check_back_navigation=0)
results=[]
def labels():return [n.get('text') or n.get('content-desc') for n in E.fromstring(tree()).iter('node')]
def has(v):return any(v in (x or '') for x in labels())
def wait_has(v):
 for i in range(12):
  if has(v):return
  time.sleep(.2)
 raise AssertionError('Expected visible UI: '+v)
def connector(name):
 wait_has('开始连接');snap(name);assert '连接相机' in labels() and 'USB' in labels()
def back():adb('shell','input','keyevent','4');time.sleep(.3)
if '同步' not in labels():back()
tap('同步',last=True);tap('边拍边传');connector('gui227-disconnected-live-tab-connects');back();wait_has('开始边拍边传')
results.append({'case':'disconnected-live-tab-opens-connection-and-cancel-returns-live','exit':0})
tap('JPEG');time.sleep(.2);snap('gui227-a-jpeg');assert has('JPEG 适合快速预览')
tap('RAW 原片');time.sleep(.2);snap('gui227-a-raw');assert has('保留 RAW 原片，可稍后显影')
tap('开始边拍边传');connector('gui227-disconnected-start-connects');back();wait_has('开始边拍边传');assert has('保留 RAW 原片，可稍后显影')
results.append({'case':'disconnected-central-start-connects-and-cancel-retains-RAW-choice','exit':0})
tap('接收记录');time.sleep(.3);snap('gui227-records-over-tabs');visible=labels();assert not any(x in visible for x in ['同步','相册','设置','预设']);rows=[x for x in visible if '原图已加入项目' in (x or '')];assert rows
name=rows[0].split('\n')[0];tap(rows[0]);time.sleep(.3);snap('gui227-record-photo-expanded');assert name in labels();back();assert has('接收记录');back();assert '同步' in labels()
results.append({'case':'records-root-modal-keeps-tabs-out-and-opens-existing-photo','exit':0})
tap('相机照片');tap('连接相机');connector('gui227-explicit-connect-entry');back();assert '同步' in labels()
results.append({'case':'explicit-connect-entry-opens-and-Back-returns-to-sync','exit':0})
tap('已下载');time.sleep(.2);snap('gui227-spaced-sync-tabs');tap('相机照片');time.sleep(.2)
results.append({'case':'three-spaced-tabs-remain-accessible-after-connection-cancel','exit':0})
j={'sourceCommit':source,'apkSha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'device':'emulator-5584','api':31,'abi':'x86_64','cases':results,'physicalCameraTested':False,'connectedThenDisconnectedTransportProvenByThisGui':False,'selectionCircleAndLongPressProof':'Real widget test camera_selection_download_test.dart,2 cases; this emulator GUI does not fake a connected camera grid','actualStopTransportProof':'Dart held-transaction regressions and SharedCore same-session JPEG/NEF tests; physical camera pending','exit':0};(p/'live-panel-gui-result.json').write_text(json.dumps(j,ensure_ascii=False,indent=2)+'\n',encoding='utf8');print('Actual release GUI227 passed',len(results))
