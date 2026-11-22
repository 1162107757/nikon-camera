import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/updates_ios.dart';

void main() {
  final manifest = Uri.parse('https://example.com/ios/manifest.json');
  Json release() => {
    'schema': 1,
    'platform': 'ios',
    'distribution': 'unsigned-ipa',
    'bundleId': 'cc.huevia.next',
    'minimumIOS': '16.0',
    'versionName': '0.31.0-dev',
    'versionCode': 213,
    'downloadUrl': 'https://example.com/ios/Huevia.ipa',
    'sha256': 'a' * 64,
    'byteLength': 1000000,
    'notes': '实际交付说明',
  };
  IosRelease parse(Json row) =>
      IosRelease(row, manifest: manifest, bundleId: 'cc.huevia.next');
  test('Actual unsigned IPA metadata is bounded and platform-specific', () {
    expect(parse(release()).code, 213);
    expect(parse(release()).supportsOs('16.0'), true);
    expect(parse(release()).supportsOs('15.9.9'), false);
    for (final patch in <Json>[
      {'bundleId': 'another.app'},
      {'platform': 'android'},
      {'distribution': 'appstore'},
      {'sha256': 'z' * 64},
      {'byteLength': 1024 * 1024 * 1024 + 1},
      {'versionCode': 213.5},
      {'versionName': '../elsewhere'},
      {'minimumIOS': 'unknown'},
      {'notes': 'a' * 12001},
    ]) {
      expect(() => parse({...release(), ...patch}), throwsA(isA<AppFailure>()));
    }
  });
  test('Download trust is confined to manifest directory or actual repository assets', () {
    for (final url in [
      'https://github.com/1162107757/nikon-camera/releases/download/213/Huevia.ipa',
      'https://example.com/ios/Huevia.ipa',
    ]) {
      expect(
        parse({...release(), 'downloadUrl': url}).download.toString(),
        url,
      );
    }
    for (final url in [
      'http://example.com/ios/Huevia.ipa',
      'https://github.com.evil/1162107757/nikon-camera/releases/download/213/Huevia.ipa',
      'https://github.com/another/repo/releases/download/213/Huevia.ipa',
      'https://example.com/ios-other/Huevia.ipa',
      'https://example.com/ios/../secret.ipa',
      'https://example.com/ios/%2e%2e/secret.ipa',
      'https://user:secret@example.com/ios/Huevia.ipa',
      'https://example.com/ios/download.html',
    ]) {
      expect(
        () => parse({...release(), 'downloadUrl': url}),
        throwsA(isA<AppFailure>()),
      );
    }
  });
  test('Official update opens the same IPA on the website file route', () {
    const origin =
        'nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com';
    const id = 'dd87c30e-75e5-40a7-8eb4-e85cde60254e';
    final manifest = Uri.https(origin, '/preset-library/ios/releases/latest');
    final path = '/preset-library/ios/releases/$id/file';
    IosRelease parse(Json patch) => IosRelease(
      {...release(), 'id': id, 'downloadUrl': 'https://$origin$path', ...patch},
      manifest: manifest,
      bundleId: 'cc.huevia.next',
    );

    expect(parse({}).browserDownload, Uri.https('huevia.cc', path));
    expect(
      parse({'downloadUrl': 'https://huevia.cc$path'}).browserDownload,
      Uri.https('huevia.cc', path),
    );
    for (final patch in <Json>[
      {'id': '8c796314-d3ea-4b0f-9e22-8a1385961099'},
      {'downloadUrl': 'https://$origin$path?redirect=untrusted'},
      {'downloadUrl': 'https://$origin/preset-library/ios/releases/latest'},
      {'downloadUrl': 'https://huevia.cc.evil$path'},
      {'downloadUrl': 'https://$origin${path.replaceFirst('/ios/', '/next/')}'},
    ]) {
      expect(() => parse(patch), throwsA(isA<AppFailure>()));
    }
  });

  test(
    'A build increment remains visible when the display name is unchanged',
    () {
      expect(updateVersionLabel('0.31.0', 239), '0.31.0 · 构建 239');
      expect(updateVersionLabel('0.31.0', '241'), '0.31.0 · 构建 241');
      expect(updateVersionLabel('0.31.1', 242), '0.31.1 · 构建 242');
    },
  );
}
