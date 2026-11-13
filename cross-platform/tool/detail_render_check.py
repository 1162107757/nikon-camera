"""Guard the read-only full-render boundary; actual pixels run on both devices."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def blocks(text, marker):
    result = []
    for match in re.finditer(re.escape(marker), text):
        start = text.index('{', match.start())
        depth, quoted, escaped = 0, None, False
        for index in range(start, len(text)):
            char = text[index]
            if quoted:
                if escaped:
                    escaped = False
                elif char == '\\':
                    escaped = True
                elif char == quoted:
                    quoted = None
                continue
            if char in ('"', "'"):
                quoted = char
            elif char == '{':
                depth += 1
            elif char == '}':
                depth -= 1
                if not depth:
                    result.append(text[start:index + 1])
                    break
    return result


def check():
    paths = [
        ('android', ROOT / 'cross-platform/app/android/app/src/main/java/cc/huevia/sharedapp/NativeMedia.java'),
        ('ios', ROOT / 'cross-platform/native/ios/Classes/HueviaMedia.mm'),
    ]
    checks = 0
    for platform, path in paths:
        source = path.read_text(encoding='utf-8-sig')
        compact = re.sub(r'\s+', '', source)
        detail = blocks(source, 'if(detail){')
        assert len(detail) == 2, (platform, 'explicit detail validation and render-return boundaries')
        for body in detail:
            assert not any(name in body for name in ['commitVersion', 'freezeEdit', 'markEditExported', 'RawDeveloper.develop', 'HueviaRawDevelop', 'markExported']), (platform, 'no persistent write path inside detail')
            checks += 1
        assert 'expectedSourceSha' in detail[0] and 'validateSource' in detail[0] and 'guardOwner' in detail[0]
        assert '显影' in detail[0] and 'if(raw' in detail[0]
        assert all(name in detail[1] for name in ['sourceSha', 'temporary', 'fullResolution', 'validateSource', 'guardOwner', 'return'])
        assert 'reviewView||snapshot||detail?' in compact or '(reviewView||snapshot||detail)?' in compact
        if platform == 'android':
            assert 'spec=detail?PhotoExportSpec.full()' in compact
            assert 'preview||detail?"previews":"exports"' in compact
            assert 'if(detail&&detailMoved&&!detailComplete)Files.deleteIfExists(target.toPath())' in compact
            assert 'preview&&(previewEdge<128||previewEdge>1280)' in compact
        else:
            assert 'spec=detail?[CcHueviaAlbumPhotoExportSpecfull]' in compact
            assert 'preview||detail?@"previews":@"exports"' in compact
            assert 'if(moved&&!complete)' in detail[1] and 'removeItemAtPath:target' in detail[1]
            assert 'load(path,_root,preview?previewEdge:0)' in compact
        checks += 8
    fixture = (ROOT / 'cross-platform/app/integration_test/native_pipeline_test.dart').read_text(encoding='utf-8-sig')
    assert "import 'detail_render_fixture.dart';" in fixture and 'await verifyDetailRendering(core);' in fixture
    checks += 1
    print(f'Read-only detail render source boundary: {checks} checks passed')


if __name__ == '__main__':
    check()
