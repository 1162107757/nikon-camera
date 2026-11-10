"""Loopback-only build helper: fetch public Maven files with strict-HTTPS curl.

This avoids a local Java TLS transport failure without changing repository
contents, credentials, application networking, or remote certificate validation.
"""
from pathlib import Path,PurePosixPath
from http.server import ThreadingHTTPServer,BaseHTTPRequestHandler
import argparse,hashlib,json,os,re,shutil,subprocess,threading,time
ROOT=Path(__file__).resolve().parents[2]
CACHE=ROOT/'.tooling/cross-platform187/maven-http-cache'
ORIGINS={'google':'https://dl.google.com/dl/android/maven2/','central':'https://repo.maven.apache.org/maven2/','plugin':'https://plugins.gradle.org/m2/','flutter':'https://storage.googleapis.com/download.flutter.io/'}
locks={};guard=threading.Lock();negative={}
def existing_artifact(relative,target):
    parts=PurePosixPath(relative).parts
    if len(parts)<4:return False
    group='.'.join(parts[:-3]);artifact,version,name=parts[-3:]
    checksum=next((suffix for suffix in ['.sha1','.sha256','.sha512'] if name.endswith(suffix)),None)
    original_name=name[:-len(checksum)] if checksum else name
    cached=target.with_name(original_name)
    if checksum and cached.is_file():
        with cached.open('rb') as file: digest=hashlib.file_digest(file,checksum[1:]).hexdigest()
        target.write_text(digest,encoding='ascii');return True
    base=Path(os.environ.get('GRADLE_USER_HOME',str(Path.home()/'.gradle')))/'caches/modules-2/files-2.1'/group/artifact/version
    if not base.is_dir():return False
    for source in base.glob('*/'+original_name):
        if not source.is_file() or not re.fullmatch('[a-f0-9]{40}',source.parent.name):continue
        with source.open('rb') as file:
            if hashlib.file_digest(file,'sha1').hexdigest()!=source.parent.name:continue
        temporary=target.with_name(target.name+'.cached-'+str(threading.get_ident()))
        if checksum:
            with source.open('rb') as file: digest=hashlib.file_digest(file,checksum[1:]).hexdigest()
            temporary.write_text(digest,encoding='ascii')
        else:shutil.copyfile(source,temporary)
        temporary.replace(target);return True
    return False
curl_proxy=[]
if os.name=='nt':
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,r'Software\Microsoft\Windows\CurrentVersion\Internet Settings') as key:
            address=winreg.QueryValueEx(key,'ProxyServer')[0];enabled=winreg.QueryValueEx(key,'ProxyEnable')[0]
        if enabled and re.fullmatch(r'127\.0\.0\.1:\d+',address):curl_proxy=['--proxy','http://'+address]
    except OSError:pass
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
                target.parent.mkdir(parents=True,exist_ok=True);temporary=target.with_name(target.name+'.download-'+str(os.getpid())+'-'+str(threading.get_ident()))
                existing_artifact(parts[1],target)
            if not target.is_file():
                run=subprocess.run(['curl.exe' if os.name=='nt' else 'curl',*curl_proxy,'--location','--silent','--show-error','--retry','2','--retry-all-errors','--connect-timeout','10','--max-time','60','--max-filesize','536870912','--output',str(temporary),'--write-out','%{http_code}',ORIGINS[parts[0]]+parts[1]],capture_output=True,text=True)
                if run.returncode or run.stdout!='200':
                    temporary.unlink(missing_ok=True)
                    status=404 if run.stdout in ['404','410'] else 502
                    if status==404:negative[key]=time.monotonic()+300
                    else:
                        with (CACHE/'transport-errors.jsonl').open('a',encoding='utf-8') as report:
                            report.write(json.dumps({'path':key,'http':run.stdout,'curlExit':run.returncode})+'\n')
                    self.send_error(status);return
                temporary.replace(target)
        self.send_response(200);self.send_header('Content-Length',str(target.stat().st_size));self.send_header('Content-Type','application/octet-stream');self.end_headers()
        if body:
            try:
                with target.open('rb') as file:
                    while block:=file.read(65536):self.wfile.write(block)
            except (BrokenPipeError,ConnectionResetError):pass
parser=argparse.ArgumentParser();parser.add_argument('--port',type=int,default=0);options=parser.parse_args()
if options.port!=0 and not 1024<=options.port<=65535:raise SystemExit('Invalid loopback port')
ThreadingHTTPServer.allow_reuse_address=True
server=ThreadingHTTPServer(('127.0.0.1',options.port),Handler)
port=server.server_address[1]
config=ROOT/'.tooling/cross-platform187/maven-proxy.json'
config.write_text(json.dumps({'port':port,'pid':os.getpid(),'origins':ORIGINS},indent=2)+'\n')
urls=['http://127.0.0.1:'+str(port)+'/'+name+'/' for name in ['google','central','plugin','flutter']]
google_groups=['androidx[.].*','com[.]android([.].*)?','com[.]google[.]android([.].*)?','com[.]google[.]firebase([.].*)?','com[.]google[.]testing([.].*)?','com[.]google[.]prefab([.].*)?','org[.]chromium[.]net']
def repository(name,url):
    if name=='google':filters='; '.join("includeGroupByRegex '"+group+"'" for group in google_groups)
    elif name=='flutter':filters="includeGroup 'io.flutter'"
    else:filters="excludeGroup 'io.flutter'; "+'; '.join("excludeGroupByRegex '"+group+"'" for group in google_groups)
    return "maven { url = '"+url+"'; allowInsecureProtocol = true; content { "+filters+" } }"
repositories='\n'.join(repository(name,url) for name,url in zip(['google','central','plugin','flutter'],urls))
rewrite="""def hueviaRoute = { repos -> repos.all { repo ->
 if (repo instanceof org.gradle.api.artifacts.repositories.MavenArtifactRepository) {
  def address = repo.url.toString()
  def routes = ['https://dl.google.com/dl/android/maven2/':'google', 'https://dl.google.com/android/maven2/':'google', 'https://repo.maven.apache.org/maven2/':'central', 'https://repo1.maven.org/maven2/':'central', 'https://plugins.gradle.org/m2/':'plugin', 'https://storage.googleapis.com/download.flutter.io/':'flutter']
  routes.each { origin, name -> if(address == origin || address + '/' == origin) {
   repo.url = 'http://127.0.0.1:PORT/' + name + '/'; repo.allowInsecureProtocol = true
   repo.content {
    if(name == 'google') { GOOGLE_FILTERS }
    else if(name == 'flutter') { includeGroup 'io.flutter' }
    else { excludeGroup 'io.flutter'; CENTRAL_FILTERS }
   }
  } }
 }
} }
""".replace('PORT',str(port)).replace('GOOGLE_FILTERS','; '.join("includeGroupByRegex '"+group+"'" for group in google_groups)).replace('CENTRAL_FILTERS','; '.join("excludeGroupByRegex '"+group+"'" for group in google_groups))
init=rewrite+"gradle.beforeSettings { settings -> hueviaRoute(settings.pluginManagement.repositories); hueviaRoute(settings.dependencyResolutionManagement.repositories); settings.pluginManagement.repositories {\n"+repositories+"\n}; settings.dependencyResolutionManagement.repositories {\n"+repositories+"\n} }\ngradle.settingsEvaluated { settings -> gradle.ext.hueviaProjectRepos = settings.dependencyResolutionManagement.repositoriesMode.get().name() == 'PREFER_PROJECT' }\ngradle.beforeProject { project -> hueviaRoute(project.repositories); hueviaRoute(project.buildscript.repositories); if (gradle.ext.hueviaProjectRepos) { project.repositories {\n"+repositories+"\n} }; project.buildscript.repositories {\n"+repositories+"\n} }\n"
(ROOT/'.tooling/cross-platform187/maven-proxy.init.gradle').write_text(init)
print('Build artifact proxy listening only on 127.0.0.1:'+str(port),flush=True)
try:server.serve_forever()
finally:server.server_close()
