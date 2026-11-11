"""Package only a verified iPhoneOS ARM64 app as an unsigned self-signing IPA."""
from pathlib import Path,PurePosixPath
import hashlib,json,os,plistlib,re,struct,subprocess,zipfile
ROOT=Path(__file__).resolve().parents[2]
app=ROOT/'cross-platform/app/build/ios/iphoneos/Runner.app'
out=ROOT/'cross-platform/.build/mobile-apple';out.mkdir(parents=True,exist_ok=True)
info=plistlib.loads((app/'Info.plist').read_bytes())
if info.get('CFBundleSupportedPlatforms')!=['iPhoneOS']:raise SystemExit('Expected iPhoneOS app; simulator apps cannot become device IPAs')
if info.get('CFBundleIdentifier')!='cc.huevia.next':raise SystemExit('Unexpected development bundle identifier')
executable=app/info['CFBundleExecutable'];binary=executable.read_bytes()
magic,cputype,subtype,kind,ncmds,size,flags,reserved=struct.unpack_from('<8I',binary)
if magic!=0xfeedfacf or cputype!=0x100000c:raise SystemExit('Expected an ARM64 Mach-O device executable')
cursor=32;platforms=[]
for _ in range(ncmds):
    command,length=struct.unpack_from('<II',binary,cursor)
    if length<8 or cursor+length>len(binary):raise SystemExit('Invalid Mach-O load commands')
    if command==0x32:platforms.append(struct.unpack_from('<I',binary,cursor+8)[0])
    cursor+=length
if platforms!=[2]:raise SystemExit('Mach-O is not built for iPhoneOS')
version=info['CFBundleShortVersionString'];build=info['CFBundleVersion']
if not re.fullmatch(r'[0-9A-Za-z.-]+',version) or not re.fullmatch(r'[0-9]+',build):raise SystemExit('Unexpected development version')
ipa=out/f'huevia-{version}-{build}-unsigned.ipa'
with zipfile.ZipFile(ipa,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for path in sorted(app.rglob('*')):
        if path.is_symlink():raise SystemExit('Unexpected app symlink; archive handling requires review')
        if path.is_file():z.write(path,'Payload/Huevia.app/'+path.relative_to(app).as_posix())
with zipfile.ZipFile(ipa) as z:
    if z.testzip() is not None:raise SystemExit('IPA archive integrity check failed')
report={'developmentBuild':True,'fullParityComplete':False,'bundleIdentifier':info['CFBundleIdentifier'],'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'platform':'iPhoneOS','architecture':'arm64','minimumOS':info.get('MinimumOSVersion'),'sha256':hashlib.sha256(ipa.read_bytes()).hexdigest(),'bytes':ipa.stat().st_size}
report['sourceCommit']=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
report['flutterRevision']=json.loads((ROOT/'cross-platform/toolchain.json').read_text())['flutterRevision']
(out/'ipa-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
