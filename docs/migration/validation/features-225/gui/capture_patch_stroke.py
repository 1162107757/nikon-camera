from pathlib import Path
import subprocess,time,threading,json,sys,xml.etree.ElementTree as E,re
r=Path(__file__).resolve().parents[2];o=Path(__file__).parent;sys.path.insert(0,str(o));from qa_ui import adb,tree
name,label=sys.argv[1:3];d=o/'gui-continuity'/name;d.mkdir(parents=True,exist_ok=True)
raw=tree();(d/'before.xml').write_bytes(raw);assert b'Huevia223-detail-chart' in raw;n={'bounds':'[470,890][495,950]'};x1=y1=x2=y2=0;samples=[];t=time.monotonic()
def capture():
 for i in range(24):
  start=time.monotonic()-t;b=adb('exec-out','screencap','-p');(d/(str(i).zfill(2)+'.png')).write_bytes(b);samples.append({'index':i,'startedSeconds':start,'completedSeconds':time.monotonic()-t});time.sleep(.06)
th=threading.Thread(target=capture);th.start();time.sleep(.3);tapAt=time.monotonic()-t;adb('shell','input','swipe','485','890','485','940','450');th.join();(d/'after.xml').write_bytes(tree());(d/'timing.json').write_text(json.dumps({'tapAtSeconds':tapAt,'label':label,'bounds':n.get('bounds'),'frames':samples},ensure_ascii=False,indent=2));print(name,len(samples),'duration',samples[-1]['completedSeconds'])
