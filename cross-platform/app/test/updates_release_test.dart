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
    ]) {
      expect(
        () => parse({...release(), 'downloadUrl': url}),
        throwsA(isA<AppFailure>()),
      );
    }
    final actual = parse(release());
    expect(
      actual.trustedRedirect(
        Uri.parse(
          'https://release-assets.githubusercontent.com/assets/Huevia.ipa?sig=redacted',
        ),
      ),
      true,
    );
    expect(
      actual.trustedRedirect(
        Uri.parse('https://release-assets.githubusercontent.com.evil/file'),
      ),
      false,
    );
  });
}
