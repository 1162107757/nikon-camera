import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/raw_reference.dart';
import 'package:path/path.dart' as p;

void main() {
  test('Reference uses root-relative persistence and restores a moved iOS container', () {
    final reference = RawJpegReference.checked(
      {
        'path': '/old/originals/reference.jpg',
        'sha256': 'a' * 64,
        'sourceSha': 'b' * 64,
      },
      '/old',
      name: 'DSC_1234.JPG',
    );
    final stored = reference.stored('/old');
    expect(stored['relativePath'], 'originals/reference.jpg');
    final restored = RawJpegReference.restore({
      'rawJpegReference': stored,
    }, '/new');
    expect(restored?.path, p.normalize('/new/originals/reference.jpg'));
    expect(restored?.name, 'DSC_1234.JPG');
    expect(restored?.payload['sourceSha'], 'b' * 64);
  });
  test('Reference rejects escaped paths and malformed content identities', () {
    final data = {
      'path': '/private/originals/reference.jpg',
      'sha256': 'a' * 64,
      'sourceSha': 'b' * 64,
    };
    expect(
      () => RawJpegReference.checked({
        ...data,
        'path': '/outside/reference.jpg',
      }, '/private'),
      throwsA(isA<AppFailure>()),
    );
    expect(
      () => RawJpegReference.checked({...data, 'sha256': 'bad'}, '/private'),
      throwsA(isA<AppFailure>()),
    );
    expect(
      RawJpegReference.restore({
        'rawJpegReference': {
          'relativePath': '../reference.jpg',
          'sha256': 'a' * 64,
          'sourceSha': 'b' * 64,
        },
      }, '/private'),
      isNull,
    );
    expect(RawJpegReference.restore({}, '/private'), isNull);
  });
}
