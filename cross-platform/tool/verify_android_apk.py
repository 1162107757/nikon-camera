"""Reject a package that advertises native ABIs without its Flutter engine/AOT."""
from pathlib import Path
import argparse,hashlib,json,zipfile

ABIS={'android-arm':('armeabi-v7a',40,1),'android-arm64':('arm64-v8a',183,2),'android-x64':('x86_64',62,2)}

def verify(apk,abi,mode):
    apk=Path(apk);name,machine,elf_class=ABIS[abi]
    with zipfile.ZipFile(apk) as archive:
        libraries=[item for item in archive.namelist() if item.startswith('lib/') and item.endswith('.so')]
        actual={item.split('/')[1] for item in libraries}
        if actual!={name}:raise ValueError('APK contains unexpected native ABIs: '+','.join(sorted(actual)))
        for required in ['libflutter.so']+(['libapp.so'] if mode=='release' else []):
            if 'lib/'+name+'/'+required not in libraries:raise ValueError('APK is missing '+required+' for '+name)
        for library in libraries:
            with archive.open(library) as stream:header=stream.read(20)
            if len(header)!=20 or header[:4]!=b'\x7fELF' or header[4]!=elf_class or header[5]!=1 or int.from_bytes(header[18:20],'little')!=machine:
                raise ValueError('Native library architecture mismatch: '+library)
        if mode=='release' and 'assets/flutter_assets/kernel_blob.bin' in archive.namelist():raise ValueError('Release APK contains a debug Dart kernel')
    digest=hashlib.sha256()
    with apk.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):digest.update(chunk)
    return {'apk':str(apk),'bytes':apk.stat().st_size,'sha256':digest.hexdigest(),'abi':name,'mode':mode,'nativeLibraries':len(libraries),'verified':True}

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('apk',type=Path);parser.add_argument('--abi',choices=list(ABIS),required=True);parser.add_argument('--mode',choices=['debug','release'],required=True)
    options=parser.parse_args();print(json.dumps(verify(options.apk,options.abi,options.mode)))
