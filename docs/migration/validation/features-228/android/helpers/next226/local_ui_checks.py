from pathlib import Path
import json, os, subprocess

r = Path(__file__).resolve().parents[2]
p = Path(__file__).parent
f = r / '.tooling/cross-platform187/flutter-sdk/bin'
e = dict(os.environ, PUB_CACHE=str(r / '.tooling/cross-platform187/pub-cache'),
         JAVA_HOME='D:/dev/Java/jdk-17.0.19', PYTHONUTF8='1', PYTHONIOENCODING='utf-8')
steps = [
    ('format', [str(f/'dart.bat'), 'format', 'lib/camera.dart', 'lib/sync_content_viewport.dart',
                'lib/camera_selection_download.dart', 'test/camera_sync_autoload_test.dart',
                'test/camera_selection_download_test.dart']),
    ('analyze', [str(f/'flutter.bat'), 'analyze', '--no-pub']),
    ('sync-layout', [str(f/'flutter.bat'), 'test', 'test/camera_sync_autoload_test.dart', '--reporter', 'expanded', '--concurrency=1']),
    ('download-circle', [str(f/'flutter.bat'), 'test', 'test/camera_selection_download_test.dart', '--reporter', 'expanded', '--concurrency=1']),
]
results = []
for name, args in steps:
    with (p/(name+'.log')).open('w', encoding='utf8') as out:
        task = subprocess.Popen(args, cwd=r/'cross-platform/app', env=e, stdout=out, stderr=subprocess.STDOUT)
        try:
            code = task.wait(timeout=100)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill.exe','/PID',str(task.pid),'/T','/F'],stdout=out,stderr=subprocess.STDOUT)
            code = 124
    (p/(name+'.exit')).write_text(str(code)+'\n')
    results.append(dict(step=name, exit=code))
    (p/'local-ui-results.json').write_text(json.dumps(results,indent=2)+'\n')
    print(name, code, flush=True)
    if code and name in ['format', 'analyze']:
        raise SystemExit(code)
