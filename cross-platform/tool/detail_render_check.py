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
        candidates = blocks(source, 'if(detail){')
        validation = [body for body in candidates if 'expectedSourceSha' in body and '显影' in body]
        rendered = [body for body in candidates if all(name in body for name in ['fullResolution', 'validateSource', 'return'])]
        assert len(validation) == 1 and len(rendered) == 1, (platform, 'explicit full-detail validation and render-return boundaries')
        detail = validation + rendered
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
        tile = blocks(source, 'private String detailTile(' if platform == 'android' else '- (NSDictionary *)detailTile:')
        assert len(tile) == 1
        body = tile[0]
        assert all(name in body for name in ['detailToken', 'expectedSourceSha', 'guardOwner', 'region', 'temporary'])
        assert not any(name in body for name in ['commitVersion', 'freezeEdit', 'markEditExported', 'rawPrepare', 'BitmapFactory.decodeFile', 'CGImageSourceCreateImageAtIndex', 'load('])
        if platform == 'android':
            assert all(name in body for name in ['BitmapRegionDecoder', 'decodeRegion', 'inSampleSize', 'detailTiles.verify', 'Files.deleteIfExists(target'])
        else:
            assert all(name in body for name in ['imageWithContentsOfURL', 'imageByCroppingToRect', 'createCGImage:image', 'kCIContextCacheIntermediates:@NO', 'verifyWithCcHueviaSharedSharedDetailTiles_Entry', 'removeItemAtPath:target'])
            assert body.index('imageByCroppingToRect') < body.index('createCGImage:image')
        assert 'media.rawDetail' in source and 'detailTiles' in source or ('media.rawDetail' in source and '_detailTiles' in source)
        checks += 5
        assert 'viewMode' in source and 'detailLocal' in source and '未知的细节构图模式' in source
        assert 'localView||detailLocal?' in compact or '(localView||detailLocal)?' in compact
        checks += 2
        raw = blocks(source, 'private String rawDevelop(' if platform == 'android' else 'if([operation isEqualToString:@"media.rawPreview"]')
        assert len(raw) == 1
        assert all(name in raw[0] for name in ['rawRecipe', 'localView', 'reviewView', 'sourceSha', 'detailToken'])
        assert not any(name in raw[0] for name in ['freezeEdit', 'commitVersion', 'markEditExported', 'rawPrepare'])
        if platform == 'android':
            recipe_render = blocks(source, 'private void renderRawRecipe(')
            assert len(recipe_render) == 1 and all(name in recipe_render[0] for name in ['frozen.profile()', 'PhotoExportSpec.full()', 'PhotoPresetRenderer', 'NativeRaster.render', 'expected.width'])
            assert not any(name in recipe_render[0] for name in ['freezeEdit', 'commitVersion', 'rawPrepare'])
        else:
            assert all(name in raw[0] for name in ['[rawRecipe profile]', 'rawRecipe->geometry_', 'rawRecipe->border_', 'renderPixelsWith', 'CcHueviaAlbumPhotoExportSpec full'])
        checks += 3
        assert 'normalizedOrientation' in body
        checks += 1
    fixture = (ROOT / 'cross-platform/app/integration_test/native_pipeline_test.dart').read_text(encoding='utf-8-sig')
    assert "import 'detail_render_fixture.dart';" in fixture and 'await verifyDetailRendering(core);' in fixture
    checks += 1
    print(f'Read-only detail render source boundary: {checks} checks passed')


if __name__ == '__main__':
    check()
