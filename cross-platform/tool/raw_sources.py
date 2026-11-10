"""Prepare pinned, unchanged LibRaw sources and the original custom white-balance math."""
from pathlib import Path
import hashlib,re,zipfile,json
ROOT=Path(__file__).resolve().parents[2]
archive=ROOT/'app/src/main/assets/third-party/libraw/LibRaw-0.22.3-source.zip'
expected='114ca5cf9f774114cb99ce7acbb521af5f6895e76372098ea4bef5741bd089ac'
if hashlib.sha256(archive.read_bytes()).hexdigest()!=expected:raise SystemExit('Pinned LibRaw source hash mismatch')
work=ROOT/'cross-platform/.build/raw-apple';work.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(archive) as z:
    for info in z.infolist():
        target=(work/info.filename).resolve()
        if not target.is_relative_to(work.resolve()):raise SystemExit('LibRaw archive path escaped build directory')
    z.extractall(work)
source=next(work.glob('LibRaw-*'))
text=(ROOT/'app/src/main/cpp/huevia_raw.cpp').read_text(encoding='utf-8-sig')
start=text.index('double gaussian(');end=text.index('\n}\n}',start)+2
functions=text[start:end].replace('bool whiteBalance(JNIEnv* env,LibRaw& raw,','void sharedWhiteBalance(LibRaw& raw,')
functions=re.sub(r'io\(env,("[^"\n]*")\);return false;',r'throw std::runtime_error(\1);',functions).replace('return true;','return;')
if any(token in functions for token in ['JNIEnv','io(env','return false']):raise SystemExit('RAW bridge extraction requires review')
generated=ROOT/'cross-platform/native/ios/Generated';generated.mkdir(parents=True,exist_ok=True)
(generated/'HueviaWhiteBalance.inc').write_text(functions+'\n',encoding='utf-8')
block=re.search(r'^lib_libraw_a_SOURCES\s*=\s*(.*?)\n\s*\n',(source/'Makefile.am').read_text(),re.M|re.S).group(1)
sources=re.findall(r'src/[^\s\\]+\.cpp',block)
if len(sources)<70:raise SystemExit('Cannot identify complete LibRaw source list')
(work/'sources.json').write_text(json.dumps({'root':str(source),'sources':sources,'sha256':expected},indent=2)+'\n')
print('Verified LibRaw 0.22.3 and prepared '+str(len(sources))+' original sources')
