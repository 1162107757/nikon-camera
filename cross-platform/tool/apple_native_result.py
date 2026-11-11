"""Accept only the real Flutter final result from this isolated simulator run."""
from pathlib import Path
import json,sys,time

def validate(value,run_id,source,fixture):
    if value.get('schema')!=1 or value.get('runId')!=run_id or value.get('sourceCommit')!=source or value.get('fixtureSha256')!=fixture:
        raise ValueError('Simulator result identity does not match this build and fixture')
    results=value.get('results')
    if value.get('success') is not True or not isinstance(results,dict) or len(results)!=1 or any(result!='success' for result in results.values()):
        raise ValueError('Native Flutter pipeline failed: '+repr(results))
    return value

def main():
    if sys.argv[1]=='--ready':
        path,run_id,source,target=Path(sys.argv[2]),*sys.argv[3:]
        deadline=time.monotonic()+90
        while time.monotonic()<deadline:
            if path.is_file() and path.stat().st_size<=8192:
                try:value=json.loads(path.read_text(encoding='utf-8'))
                except (OSError,json.JSONDecodeError):time.sleep(.2);continue
                if value.get('schema')!=1 or value.get('phase')!='ready' or value.get('runId')!=run_id or value.get('sourceCommit')!=source:
                    raise SystemExit('Warm-up identity does not match this native test run')
                Path(target).write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8');print('Native test app initialized before authorization');return
            time.sleep(.5)
        raise SystemExit('Native test app did not initialize within 90 seconds')
    path,run_id,source,fixture,target=Path(sys.argv[1]),*sys.argv[2:]
    deadline=time.monotonic()+360
    while time.monotonic()<deadline:
        if path.is_file():
            if path.stat().st_size>128*1024:raise SystemExit('Simulator result exceeds 128 KiB')
            try:value=json.loads(path.read_text(encoding='utf-8'))
            except (OSError,json.JSONDecodeError):time.sleep(.2);continue
            validate(value,run_id,source,fixture)
            Path(target).write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')
            print('PASS Apple native Flutter pipeline: 1 real scenario; final result, source and PhotoKit fixture verified')
            return
        time.sleep(1)
    raise SystemExit('Native Flutter pipeline did not produce a final result within 360 seconds')
if __name__=='__main__':main()
