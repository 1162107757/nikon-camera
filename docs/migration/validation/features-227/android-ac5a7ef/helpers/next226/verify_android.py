from pathlib import Path
import os,subprocess,zipfile,struct,json,hashlib
root=Path(__file__).resolve().parents[2]
sdk=Path(r'D:\dev\Android\Sdk\build-tools\36.1.0')
env=dict(os.environ,JAVA_HOME=r'D:\dev\Java\jdk-17.0.19')
env['PATH']=env['JAVA_HOME']+r'\bin'+os.pathsep+env['PATH']
results=[]
for abi in ['arm64','x64']:
    apk=root/'.tooling/next227/package-candidates'/f'huevia-0.31.0-dev-227-android-{abi}.apk'
    for tool,args in [('apksigner.bat',['verify','--verbose','--print-certs']),('zipalign.exe',['-c','-P','16','4'])]:
        result=subprocess.run([str(sdk/tool),*args,str(apk)],env=env,capture_output=True)
        (root/'.tooling/next227'/f'{abi}-{tool}-final.log').write_bytes(result.stdout+result.stderr)
        if result.returncode:raise RuntimeError(f'{abi}: {tool} failed ({result.returncode})')
    libraries=[];raw=apk.read_bytes()
    certificate=(root/'.tooling/next227'/f'{abi}-apksigner.bat-final.log').read_text(encoding='utf-8',errors='replace')
    assert '76398947a8b493df81ebf2e90ad7b62e3eefee5fcf6cf865feaaa9bef8127b75' in certificate
    metadata=subprocess.check_output([str(sdk/'aapt2.exe'),'dump','badging',str(apk)],env=env,text=True,encoding='utf-8')
    assert [line for line in metadata.splitlines() if line.startswith('application-label:')] == ["application-label:'Huevia'"], 'The packaged Android display name must be Huevia'
    expectedAbi='arm64-v8a' if abi=='arm64' else 'x86_64'
    assert "package: name='cc.huevia.next' versionCode='227' versionName='0.31.0-dev'" in metadata
    assert f"native-code: '{expectedAbi}'" in metadata
    assert next(line for line in metadata.splitlines() if line.startswith('native-code:')).strip()==f"native-code: '{expectedAbi}'"
    with zipfile.ZipFile(apk) as z:
        for item in z.infolist():
            if not(item.filename.startswith('lib/') and item.filename.endswith('.so')):continue
            binary=z.read(item);assert binary[:4]==b'\x7fELF'
            if binary[4]==2:
                off=struct.unpack_from('<Q',binary,32)[0];size,count=struct.unpack_from('<HH',binary,54);alignOffset=48
                offsetOffset,addressOffset,form=8,16,'<Q'
            else:
                off=struct.unpack_from('<I',binary,28)[0];size,count=struct.unpack_from('<HH',binary,42);alignOffset=28
                offsetOffset,addressOffset,form=4,8,'<I'
            aligns=[]
            for i in range(count):
                at=off+size*i
                if struct.unpack_from('<I',binary,at)[0]!=1:continue
                align=struct.unpack_from(form,binary,at+alignOffset)[0]
                pos=struct.unpack_from(form,binary,at+offsetOffset)[0];address=struct.unpack_from(form,binary,at+addressOffset)[0]
                assert align>=16384 and (pos-address)%align==0,item.filename
                aligns.append(align)
            assert aligns,item.filename
            names,extra=struct.unpack_from('<HH',raw,item.header_offset+26)
            dataOffset=item.header_offset+30+names+extra
            if item.compress_type==zipfile.ZIP_STORED:assert dataOffset%16384==0,item.filename
            libraries.append({'file':item.filename,'loadAlignments':aligns,'uncompressed':item.compress_type==zipfile.ZIP_STORED,'zipDataOffset':dataOffset})
    assert len(libraries)==8 and all(v['file'].startswith('lib/'+expectedAbi+'/') for v in libraries)
    results.append({'abi':abi,'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'displayName':'Huevia','applicationLabelVerified':True,'apksignerVerified':True,'zipalign16KiBVerified':True,'allLoadSegments16KiBVerified':True,'libraries':libraries})
target=root/'docs/migration/validation/features-227/android-signing-alignment.json'
target.write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
print(json.dumps([{'abi':v['abi'],'verified':True,'libraries':len(v['libraries'])} for v in results]))
