from pathlib import Path
import subprocess,time,threading,json,sys,xml.etree.ElementTree as E,re
r=Path(__file__).resolve().parents[2];o=Path(__file__).parent;sys.path.insert(0,str(o));from qa_ui import adb,tree
name,label=sys.argv[1:3];d=o/'gui-continuity'/name;d.mkdir(parents=True,exist_ok=True)
raw=tree();(d/'before.xml').write_bytes(raw);nodes=[n for n in E.fromstring(raw).iter('node') if label in (n.get('text'),n.get('content-desc'))];assert nodes,(label,len(nodes));n=nodes[int(sys.argv[3]) if len(sys.argv)>3 else 0];x1,y1,x2,y2=map(int,re.findall(r'\d+',n.get('bounds')));samples=[];t=time.monotonic()
def capture():
 for i in range(24):
  start=time.monotonic()-t;b=adb('exec-out','screencap','-p');(d/(str(i).zfill(2)+'.png')).write_bytes(b);samples.append({'index':i,'startedSeconds':start,'completedSeconds':time.monotonic()-t});time.sleep(.06)
th=threading.Thread(target=capture);th.start();time.sleep(.3);tapAt=time.monotonic()-t;adb('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2));th.join();(d/'after.xml').write_bytes(tree());(d/'timing.json').write_text(json.dumps({'tapAtSeconds':tapAt,'label':label,'bounds':n.get('bounds'),'frames':samples},ensure_ascii=False,indent=2));print(name,len(samples),'duration',samples[-1]['completedSeconds'])
