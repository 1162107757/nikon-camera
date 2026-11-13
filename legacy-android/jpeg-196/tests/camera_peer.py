"""Owned read-only PTP/IP fixture for the legacy Android JPEG 195 repair.

Dependency: Python 3.11+ and Pillow (python -m pip install Pillow).
Start: python legacy-android/jpeg-196/tests/camera_peer.py run1
Camera: emulator host 10.0.2.2:15752; control: http://127.0.0.1:15753
Control GET /status; POST /action with {"action":"set","scenario":"mixed"}.
Scenarios: mixed, empty-partial, all-unavailable, healthy. Refresh/reconnect the
app after changing a scenario. No preset/property writes or captures exist.
All logs are confined to .tooling/legacy-jpeg196/peer/<new-tag>/; old tags cannot
be overwritten. Stop with Ctrl+C to write the final summary.

JPEG pixels and tiny TIFF/CFA RAW bytes are generated locally. Synthetic RAW is
not a real camera NEF or an imaging/LibRaw compatibility test. This peer is not
physical Nikon/Fuji or Wi-Fi routing acceptance.
"""
from __future__ import annotations

import argparse
from collections import Counter
import datetime
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
from pathlib import Path
import re
import socket
import socketserver
import struct
import threading
import time

from PIL import Image
import PIL

WORKSPACE=Path(__file__).resolve().parents[3]
OUTPUT=WORKSPACE/'.tooling/legacy-jpeg196/peer'
GUID=bytes.fromhex('195a102030405060708090a0b0c0d0e0')
SCENARIOS=('mixed','empty-partial','all-unavailable','healthy')
JPEG_HANDLES=(302,303)
NEF_HANDLES=tuple(range(1,302))


def u16(value):return struct.pack('<H',value)
def u32(value):return struct.pack('<I',value)
def u64(value):return struct.pack('<Q',value)
def ptp_string(value):
    if not value:return b'\0'
    units=len(value.encode('utf-16le'))//2
    if units>254:raise ValueError('PTP fixture string exceeds dataset limit')
    return bytes([units+1])+(value+'\0').encode('utf-16le')
def packet(kind,payload=b''):return u32(len(payload)+8)+u32(kind)+payload
def sha(data):return hashlib.sha256(data).hexdigest()
def read_exact(sock,count):
    result=bytearray()
    while len(result)<count:
        part=sock.recv(count-len(result))
        if not part:raise EOFError('fixture connection closed')
        result.extend(part)
    return bytes(result)
def receive(sock):
    length,kind=struct.unpack('<II',read_exact(sock,8))
    if not 8<=length<=1024*1024:raise ValueError('invalid incoming PTP/IP packet length')
    return kind,read_exact(sock,length-8)


def owned_jpeg(variant,extra=131072):
    image=Image.new('RGB',(224,168))
    image.putdata([((x*255//223 if variant==0 else 35+(y*160//167)),
                    (y*255//167 if variant!=1 else 210-x*130//223),
                    (220 if (x//24+y//24+variant)%2 else 35))
                   for y in range(168) for x in range(224)])
    buffer=io.BytesIO();image.save(buffer,'JPEG',quality=91)
    preview=buffer.getvalue()
    token=f'Owned legacy195 JPEG fixture variant={variant}\n'.encode('ascii')
    padding=(token*(extra//len(token)+1))[:extra]
    comments=b''.join(b'\xff\xfe'+struct.pack('>H',len(padding[index:index+60000])+2)+padding[index:index+60000]
                      for index in range(0,len(padding),60000))
    return preview,preview[:-2]+comments+preview[-2:]


def owned_cfa(handle):
    """Tiny classic TIFF with Nikon make and a CFA plane; all pixels are synthetic."""
    width,height=16,12
    make=b'NIKON\0';model=b'OWNED QA195 SYNTHETIC CFA\0';description=f'Owned synthetic sensor handle {handle}\0'.encode('ascii')
    rows=[(0x0100,4,1,u32(width)),(0x0101,4,1,u32(height)),(0x0102,3,1,u16(16)),
          (0x0103,3,1,u16(1)),(0x0106,3,1,u16(32803)),(0x010e,2,len(description),description),
          (0x010f,2,len(make),make),(0x0110,2,len(model),model),(0x0111,4,1,None),
          (0x0112,3,1,u16(1)),(0x0115,3,1,u16(1)),(0x0116,4,1,u32(height)),
          (0x0117,4,1,u32(width*height*2)),(0x828d,3,2,u16(2)+u16(2)),
          (0x828e,1,4,b'\0\1\1\2')]
    offset=8+2+len(rows)*12+4;extra=bytearray();encoded=[]
    for tag,kind,count,value in rows:
        if value is None:encoded.append((tag,kind,count,None));continue
        if len(value)<=4:encoded.append((tag,kind,count,value.ljust(4,b'\0')))
        else:
            encoded.append((tag,kind,count,u32(offset+len(extra))));extra.extend(value)
            if len(extra)%2:extra.append(0)
    sensor_offset=offset+len(extra)
    directory=u16(len(rows))+b''.join(u16(tag)+u16(kind)+u32(count)+(u32(sensor_offset) if value is None else value)
                                     for tag,kind,count,value in encoded)+u32(0)
    sensor=b''.join(u16(4000+(x*173+y*211+handle*19)%45000) for y in range(height) for x in range(width))
    return b'II'+u16(42)+u32(8)+directory+bytes(extra)+sensor


class Object:
    def __init__(self,handle,format_,name,data,preview,width,height):
        self.handle,self.format,self.name,self.data=handle,format_,name,data
        self.preview,self.width,self.height=preview,width,height
        self.storage=2
    @property
    def raw(self):return self.name.lower().endswith('.nef')
    def metadata(self):
        captured=(datetime.datetime(2026,11,13,11)+datetime.timedelta(seconds=self.handle)).strftime('%Y%m%dT%H%M%S')
        return b''.join([u32(self.storage),u16(self.format),u16(0),u32(len(self.data)),u16(0x3801),
                         u32(len(self.preview)),u32(224),u32(168),u32(self.width),u32(self.height),
                         u32(16 if self.raw else 24),u32(0),u16(0),u32(0),u32(self.handle),
                         ptp_string(self.name),ptp_string(captured),ptp_string(captured),ptp_string('')])


def make_objects():
    preview,standard=owned_jpeg(0);generic_preview,generic=owned_jpeg(1)
    raw_preview,_=owned_jpeg(2,0)
    objects={handle:Object(handle,0xb103,f'QA195_{handle:04d}.NEF',owned_cfa(handle),raw_preview,16,12)
             for handle in NEF_HANDLES}
    objects[302]=Object(302,0x3801,'QA195_STANDARD.JPG',standard,preview,224,168)
    objects[303]=Object(303,0x3000,'QA195_GENERIC.JPEG',generic,generic_preview,224,168)
    return objects


def available_storage(scenario,storage):
    return storage in (1,2) and scenario!='all-unavailable' and (storage!=1 or scenario=='healthy')
def handles_for(scenario,storage,format_):
    if not available_storage(scenario,storage):return 0x2013,[]
    if storage==1:return 0x2001,[]
    if format_==0x3801:
        # Healthy is a direct nonempty JPEG inventory control. Mixed deliberately
        # reproduces firmware returning successful-empty despite independent JPEGs.
        return 0x2001,list(JPEG_HANDLES) if scenario=='healthy' else []
    if format_==0:return 0x2001,list(NEF_HANDLES)+(list(JPEG_HANDLES) if scenario!='empty-partial' else [])
    return 0x2014,[]
def visible_object(scenario,handle):
    return scenario!='all-unavailable' and (handle in NEF_HANDLES or handle in JPEG_HANDLES and scenario!='empty-partial')


def new_counters():
    return {'operations':Counter(),'responses':Counter(),'handleQueries':Counter(),'handleQueryObjects':Counter(),
            'metadata':Counter(),'thumbnails':Counter(),'largeThumbnails':Counter(),
            'downloadAttempts':Counter(),'downloadCompleted':Counter(),'downloadBytes':Counter(),
            'downloadSha256':{},'unsupportedOperations':Counter()}


class Fixture:
    def __init__(self,tag,scenario):
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,63}',tag):raise ValueError('use a plain new run tag')
        if scenario not in SCENARIOS:raise ValueError('unsupported scenario')
        expected=(OUTPUT/tag).absolute();resolved=expected.resolve()
        if expected!=resolved or not resolved.is_relative_to(WORKSPACE.resolve()):raise ValueError('run log directory escaped workspace')
        resolved.mkdir(parents=True,exist_ok=False)
        self.directory=resolved;self.log=resolved/'operations.jsonl'
        self.lock=threading.RLock();self.scenario=scenario;self.epoch=1;self.objects=make_objects()
        self.counts=new_counters();self.by_epoch={};self.connections={};self.events={};self.connection_sequence=0
        self.completed_connections=0;self.event_pongs=0;self.delay=.025;self.chunk_bytes=8192
        fixture={'schema':1,'description':'Owned synthetic JPEG and classic TIFF/CFA, not physical Nikon/Fuji or real NEF/LibRaw acceptance',
                 'sourceSha256':sha(Path(__file__).read_bytes()),'pillowVersion':PIL.__version__,
                 'guidSha256':sha(GUID),'initialScenario':scenario,'objects':[{'handle':obj.handle,'format':hex(obj.format),
                 'storage':obj.storage,'name':obj.name,'bytes':len(obj.data),'sha256':sha(obj.data),'raw':obj.raw}
                 for obj in self.objects.values()]}
        (resolved/'fixture.json').write_text(json.dumps(fixture,indent=2)+'\n',encoding='utf-8')
        self.record(phase='fixture-created',scenario=scenario)
    def record(self,**values):
        with self.lock:
            row={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'scenario':self.scenario,'scenarioEpoch':self.epoch,**values}
            with self.log.open('a',encoding='utf-8') as output:output.write(json.dumps(row,ensure_ascii=False)+'\n')
    def count(self,epoch,scenario,field,key,value=1):
        with self.lock:
            current=self.by_epoch.setdefault(str(epoch),{'scenario':scenario,'counts':new_counters()})['counts']
            self.counts[field][str(key)]+=value;current[field][str(key)]+=value
    def snapshot(self):
        with self.lock:
            expected=[302,303] if self.scenario in ('mixed','healthy') else []
            return json.loads(json.dumps({'schema':1,'fixture':'owned legacy JPEG196 read-only PTP/IP',
                'scenario':self.scenario,'scenarioEpoch':self.epoch,'guidSha256':sha(GUID),
                'jpegHandles':expected,'nefHandleCount':0 if self.scenario=='all-unavailable' else len(NEF_HANDLES),
                'orderedMixedInventory':'NEF handles1..301, then standard JPEG302, then generic0x3000 JPEG303',
                'connectionsAccepted':self.connection_sequence,'commandConnections':sorted(self.connections),'eventConnections':sorted(self.events),
                'eventPongs':self.event_pongs,'counts':self.counts,'scenarioRuns':self.by_epoch,
                'jpegSources':[{'handle':handle,'name':self.objects[handle].name,'format':hex(self.objects[handle].format),
                                'bytes':len(self.objects[handle].data),'sha256':sha(self.objects[handle].data)} for handle in JPEG_HANDLES],
                'directory':str(self.directory),'scope':'Controlled synthetic peer; does not prove actual Nikon behavior, Android routing, old-app data retention or image quality.'}))
    def set_scenario(self,value):
        if value not in SCENARIOS:raise ValueError('scenario must be mixed, empty-partial, all-unavailable or healthy')
        with self.lock:
            previous=self.scenario;self.scenario=value;self.epoch+=1
            self.record(action='set-scenario',previousScenario=previous)
        return {'scenario':value,'scenarioEpoch':self.epoch,'refreshOrReconnectRequired':True}
    def close_connections(self):
        with self.lock:sockets=list(self.connections.values())+[value[0] for value in self.events.values()]
        for sock in sockets:
            try:sock.shutdown(socket.SHUT_RDWR)
            except OSError:pass
            try:sock.close()
            except OSError:pass
    @staticmethod
    def device():
        operations=(0x1001,0x1002,0x1003,0x1004,0x1005,0x1007,0x1008,0x1009,0x100a,0x90c4)
        return b''.join([u16(100),u32(10),u16(100),ptp_string('Owned legacy JPEG196 QA'),u16(0),u32(len(operations)),
                         *(u16(operation) for operation in operations),u32(0),u32(0),u32(0),u32(0),
                         ptp_string('NIKON CORPORATION'),ptp_string('Z 6_2 JPEG196 QA'),ptp_string('1'),ptp_string('')])


class Peer(socketserver.BaseRequestHandler):
    def handle(self):
        fixture=self.server.fixture;sock=self.request;connection=None;channel='handshake'
        sock.setsockopt(socket.IPPROTO_TCP,socket.TCP_NODELAY,1)
        try:
            kind,data=receive(sock)
            if kind==1:
                channel='command'
                with fixture.lock:
                    fixture.connection_sequence+=1;connection=fixture.connection_sequence;fixture.connections[connection]=sock
                sock.sendall(packet(2,u32(connection)+GUID+('LegacyJPEG196QA\0').encode('utf-16le')+u32(0x10000)))
                fixture.record(channel=channel,phase='ready',connection=connection)
                self.commands(fixture,sock,connection)
            elif kind==3 and len(data)==4:
                channel='event';connection=struct.unpack('<I',data)[0]
                with fixture.lock:
                    if connection not in fixture.connections:raise ValueError('event channel has no command owner')
                    sending=threading.Lock();fixture.events[connection]=(sock,sending)
                sock.sendall(packet(4));fixture.record(channel=channel,phase='ready',connection=connection)
                stopped=threading.Event()
                def ping():
                    while not stopped.wait(5):
                        try:
                            with sending:sock.sendall(packet(13))
                            fixture.record(channel='event',phase='ping',connection=connection)
                        except OSError:return
                threading.Thread(target=ping,daemon=True).start()
                try:
                    while True:
                        kind,data=receive(sock)
                        if kind==13:
                            with sending:sock.sendall(packet(14))
                        elif kind==14:
                            with fixture.lock:fixture.event_pongs+=1
                            fixture.record(channel='event',phase='pong',connection=connection)
                        else:raise ValueError('unsupported client event packet')
                finally:stopped.set()
            else:raise ValueError('unsupported PTP/IP handshake')
        except (EOFError,ConnectionError,OSError):fixture.record(channel=channel,phase='closed',connection=connection)
        except Exception as failure:fixture.record(channel=channel,phase='fixture-error',connection=connection,error=type(failure).__name__,detail=str(failure)[:200])
        finally:
            with fixture.lock:
                if channel=='command':fixture.connections.pop(connection,None)
                elif channel=='event':fixture.events.pop(connection,None)
    def commands(self,fixture,sock,connection):
        while True:
            kind,data=receive(sock)
            if kind==13:sock.sendall(packet(14));continue
            if kind!=6 or len(data)<10 or (len(data)-10)%4:raise ValueError('malformed operation request')
            phase,operation,transaction=struct.unpack_from('<IHI',data)
            parameters=list(struct.unpack('<'+'I'*((len(data)-10)//4),data[10:]))
            with fixture.lock:scenario,epoch=fixture.scenario,fixture.epoch
            fixture.count(epoch,scenario,'operations',hex(operation))
            fixture.record(channel='command',connection=connection,phase='request',operation=hex(operation),transaction=transaction,
                           parameters=parameters,scenario=scenario,scenarioEpoch=epoch)
            payload=None;code=0x2001;obj=None
            if operation==0x1001 and not parameters:payload=fixture.device()
            elif operation in (0x1002,0x1003):pass
            elif operation==0x1004 and not parameters:payload=u32(2)+u32(1)+u32(2)
            elif operation==0x1005 and len(parameters)==1:
                storage=parameters[0]
                if not available_storage(scenario,storage):code=0x2013
                else:payload=u16(2)+u16(2)+u16(1)+u64(1024**3)+u64(512*1024**2)+u32(999)+ptp_string('Owned QA card')+ptp_string('QA195_'+str(storage))
            elif operation==0x1007 and len(parameters)==3:
                storage,format_,association=parameters;key=f'storage={storage},format=0x{format_:04x},association={association}'
                fixture.count(epoch,scenario,'handleQueries',key)
                if association not in (0,0xffffffff):code=0x2009;handles=[]
                else:code,handles=handles_for(scenario,storage,format_)
                if code==0x2001:
                    payload=u32(len(handles))+b''.join(u32(handle) for handle in handles)
                    fixture.count(epoch,scenario,'handleQueryObjects',key,len(handles))
            elif operation in (0x1008,0x1009,0x100a,0x90c4) and len(parameters)==1:
                handle=parameters[0];obj=fixture.objects.get(handle)
                if obj is None:code=0x2009
                elif not available_storage(scenario,obj.storage):code=0x2013
                elif not visible_object(scenario,handle):code=0x2009
                elif operation==0x1008:
                    payload=obj.metadata();fixture.count(epoch,scenario,'metadata',handle)
                elif operation in (0x100a,0x90c4):
                    payload=obj.preview;fixture.count(epoch,scenario,'largeThumbnails' if operation==0x90c4 else 'thumbnails',handle)
            else:
                # This includes SetDevicePropValue, captures, uploads and Nikon
                # preset/property operations. They are not advertised or executed.
                code=0x2005;fixture.count(epoch,scenario,'unsupportedOperations',hex(operation))
            if operation==0x1009 and code==0x2001:
                fixture.count(epoch,scenario,'downloadAttempts',obj.handle)
                source=obj.data;sock.sendall(packet(9,u32(transaction)+u64(len(source))))
                for offset in range(0,len(source),fixture.chunk_bytes):
                    chunk=source[offset:offset+fixture.chunk_bytes]
                    sock.sendall(packet(12 if offset+len(chunk)==len(source) else 10,u32(transaction)+chunk))
                    fixture.count(epoch,scenario,'downloadBytes',obj.handle,len(chunk))
                    if fixture.delay:time.sleep(fixture.delay)
                fixture.count(epoch,scenario,'downloadCompleted',obj.handle)
                with fixture.lock:
                    fixture.counts['downloadSha256'][str(obj.handle)]=sha(source)
                    fixture.by_epoch[str(epoch)]['counts']['downloadSha256'][str(obj.handle)]=sha(source)
                fixture.record(channel='command',connection=connection,phase='object-sent',handle=obj.handle,bytes=len(source),sha256=sha(source),
                               scenario=scenario,scenarioEpoch=epoch)
                sock.sendall(packet(7,u16(code)+u32(transaction)))
            else:
                response=packet(7,u16(code)+u32(transaction))
                if payload is not None:response=packet(9,u32(transaction)+u64(len(payload)))+packet(12,u32(transaction)+payload)+response
                sock.sendall(response)
            fixture.count(epoch,scenario,'responses',f'operation=0x{operation:04x},code=0x{code:04x}')
            fixture.record(channel='command',connection=connection,phase='response',operation=hex(operation),transaction=transaction,
                           code=hex(code),bytes=len(payload) if payload is not None else None,scenario=scenario,scenarioEpoch=epoch)


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address=True
    daemon_threads=True
    def handle_error(self,request,client_address):self.fixture.record(phase='fixture-error',error='UnhandledHandlerException')


class Control(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def reply(self,code,value):
        payload=json.dumps(value,ensure_ascii=False).encode('utf-8')
        self.send_response(code);self.send_header('Content-Type','application/json; charset=utf-8');self.send_header('Content-Length',str(len(payload)))
        self.end_headers();self.wfile.write(payload)
    def do_GET(self):
        if self.path!='/status':return self.reply(404,{'error':'not found'})
        self.reply(200,self.server.fixture.snapshot())
    def do_POST(self):
        if self.path!='/action':return self.reply(404,{'error':'not found'})
        try:
            length=int(self.headers.get('Content-Length','0'))
            if not 1<=length<=4096:raise ValueError('invalid request body length')
            value=json.loads(self.rfile.read(length))
            if not isinstance(value,dict) or value.get('action') not in ('set','scenario','set-scenario'):raise ValueError('only set-scenario is supported')
            result=self.server.fixture.set_scenario(value.get('scenario'))
            self.reply(200,{'ok':True,**result,'status':self.server.fixture.snapshot()})
        except (ValueError,TypeError,KeyError) as failure:self.reply(400,{'error':str(failure)[:200]})


def main():
    parser=argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('tag',help='new run tag; existing log directories are never overwritten')
    parser.add_argument('--scenario',choices=SCENARIOS,default='mixed')
    parser.add_argument('--port',type=int,default=15752);parser.add_argument('--control-port',type=int,default=15753)
    args=parser.parse_args()
    if not 1<=args.port<=65535 or not 1<=args.control_port<=65535 or args.port==args.control_port:parser.error('distinct valid local ports are required')
    fixture=Fixture(args.tag,args.scenario)
    with Server(('127.0.0.1',args.port),Peer) as server,ThreadingHTTPServer(('127.0.0.1',args.control_port),Control) as control:
        server.fixture=control.fixture=fixture
        thread=threading.Thread(target=control.serve_forever,daemon=True);thread.start()
        ready={'ready':True,'camera':f'10.0.2.2:{args.port}','control':f'http://127.0.0.1:{args.control_port}',
               'scenario':args.scenario,'logDirectory':str(fixture.directory)}
        (fixture.directory/'ready.json').write_text(json.dumps(ready,indent=2)+'\n',encoding='utf-8')
        print(json.dumps(ready),flush=True)
        try:server.serve_forever()
        except KeyboardInterrupt:pass
        finally:
            fixture.close_connections();control.shutdown();thread.join(timeout=3)
            (fixture.directory/'summary.json').write_text(json.dumps(fixture.snapshot(),indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':main()
