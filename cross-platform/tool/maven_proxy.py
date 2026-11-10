"""Loopback-only build helper: fetch public Maven files with strict-HTTPS curl.

This avoids a local Java TLS transport failure without changing repository
contents, credentials, application networking, or remote certificate validation.
"""
from pathlib import Path,PurePosixPath
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
import json,os,re,subprocess,threading,time
ROOT=Path(__file__).resolve().parents[2]
CACHE=ROOT/'.tooling/cross-platform187/maven-http-cache'
ORIGINS={'google':'https://dl.google.com/dl/android/maven2/','central':'https://repo.maven.apache.org/maven2/','plugin':'https://plugins.gradle.org/m2/','flutter':'https://storage.googleapis.com/download.flutter.io/'}
locks={};guard=threading.Lock();negative={}
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_HEAD(self):self.serve(False)
    def do_GET(self):self.serve(True)
    def serve(self,body):
        path=self.path.lstrip('/');parts=path.split('/',1)
        if len(parts)!=2 or parts[0] not in ORIGINS or not re.fullmatch(r'[A-Za-z0-9_./+@-]+',parts[1]) or '..' in PurePosixPath(parts[1]).parts:
            self.send_error(400);return
        key=path;target=CACHE/path
        with guard:lock=locks.setdefault(key,threading.Lock())
        with lock:
            if negative.get(key,0)>time.monotonic():self.send_error(404);return
            if not target.is_file():
                target.parent.mkdir(parents=True,exist_ok=True);temporary=target.with_name(target.name+'.download')
                run=subprocess.run(['curl.exe' if os.name=='nt' else 'curl','--location','--silent','--show-error','--retry','2','--connect-timeout','15','--max-time','240','--max-filesize','536870912','--output',str(temporary),'--write-out','%{http_code}',ORIGINS[parts[0]]+parts[1]],capture_output=True,text=True)
                if run.returncode or run.stdout!='200':
                    temporary.unlink(missing_ok=True)
                    status=404 if run.stdout in ['404','410'] else 502
                    if status==404:negative[key]=time.monotonic()+300
                    self.send_error(status);return
                temporary.replace(target)
        self.send_response(200);self.send_header('Content-Length',str(target.stat().st_size));self.send_header('Content-Type','application/octet-stream');self.end_headers()
        if body:
            try:
                with target.open('rb') as file:
                    while block:=file.read(65536):self.wfile.write(block)
            except (BrokenPipeError,ConnectionResetError):pass
server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
port=server.server_address[1]
config=ROOT/'.tooling/cross-platform187/maven-proxy.json'
config.write_text(json.dumps({'port':port,'pid':os.getpid(),'origins':ORIGINS},indent=2)+'\n')
urls=['http://127.0.0.1:'+str(port)+'/'+name+'/' for name in ['google','central','plugin','flutter']]
repositories='\n'.join("maven { url = '"+url+"'; allowInsecureProtocol = true }" for url in urls)
init="gradle.beforeSettings { settings -> settings.pluginManagement.repositories {\n"+repositories+"\n}; settings.dependencyResolutionManagement.repositories {\n"+repositories+"\n} }\ngradle.settingsEvaluated { settings -> gradle.ext.hueviaProjectRepos = settings.dependencyResolutionManagement.repositoriesMode.get().name() == 'PREFER_PROJECT' }\ngradle.beforeProject { project -> if (gradle.ext.hueviaProjectRepos) { project.repositories {\n"+repositories+"\n} }; project.buildscript.repositories {\n"+repositories+"\n} }\n"
(ROOT/'.tooling/cross-platform187/maven-proxy.init.gradle').write_text(init)
print('Build artifact proxy listening only on 127.0.0.1:'+str(port),flush=True)
try:server.serve_forever()
finally:server.server_close()
