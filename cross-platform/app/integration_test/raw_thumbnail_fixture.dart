import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:path/path.dart' as p;

import 'synthetic_dng.dart';
import 'synthetic_exif.dart';

Uint8List thumbnailDng({
  required String identity,
  int orientation = 1,
  Uint8List? jpeg,
}) {
  final raw = syntheticDng(identity: identity),
      original = ByteData.sublistView(raw);
  final count = original.getUint16(8, Endian.little);
  for (var index = 0; index < count; index++) {
    final at = 10 + index * 12;
    if (original.getUint16(at, Endian.little) == 274) {
      original.setUint16(at + 8, orientation, Endian.little);
    }
  }
  if (jpeg == null) return raw;
  // A standard TIFF IFD1 JPEG preview. The CFA/RAW bytes retain their original offsets.
  final start = (raw.length + 1) & ~1;
  const entries = 10;
  final payload = start + 2 + entries * 12 + 4;
  final result = Uint8List(payload + jpeg.length)..setRange(0, raw.length, raw);
  final data = ByteData.sublistView(result);
  data.setUint32(10 + count * 12, start, Endian.little);
  data.setUint16(start, entries, Endian.little);
  var next = start + 2;
  void tag(int id, int type, int value) {
    data.setUint16(next, id, Endian.little);
    data.setUint16(next + 2, type, Endian.little);
    data.setUint32(next + 4, 1, Endian.little);
    data.setUint32(next + 8, value, Endian.little);
    next += 12;
  }

  tag(254, 4, 1);
  tag(256, 4, 256);
  tag(257, 4, 192);
  tag(258, 3, 8);
  tag(259, 3, 6);
  tag(262, 3, 6);
  tag(274, 3, 1);
  tag(277, 3, 3);
  tag(513, 4, payload);
  tag(514, 4, jpeg.length);
  data.setUint32(next, 0, Endian.little);
  result.setRange(payload, result.length, jpeg);
  return result;
}

Future<void> verifyRawThumbnails(HueviaCore core, String pngSource) async {
  final folder = await Directory(
    '${core.root}/originals/raw-thumb-fixture-${DateTime.now().microsecondsSinceEpoch}',
  ).create();
  final created = <File>[];
  Future<Map<String, String>> snapshot(String directory) async {
    final root = Directory('${core.root}/$directory');
    if (!await root.exists()) return {};
    final result = <String, String>{};
    await for (final item in root.list(recursive: true, followLinks: false)) {
      if (item is File) {
        result[p.relative(item.path, from: root.path)] =
            (await sha256.bind(item.openRead()).first).toString();
      }
    }
    return result;
  }

  final fullDevelopments = await snapshot('raw-development');
  final versions = await core.call('version.list', {'owner': ''});
  Future<(int, int)> dimensions(String path) async {
    final codec = await ui.instantiateImageCodec(
      await File(path).readAsBytes(),
    );
    try {
      final frame = await codec.getNextFrame();
      final size = (frame.image.width, frame.image.height);
      frame.image.dispose();
      return size;
    } finally {
      codec.dispose();
    }
  }

  try {
    for (final orientation in [1, 2, 3, 4, 5, 6, 7, 8]) {
      final bytes = thumbnailDng(
        identity: 'RAW thumbnail fallback $orientation ${folder.path}',
        orientation: orientation,
      );
      final source = await File('${folder.path}/orientation-$orientation.dng')
          .writeAsBytes(bytes);
      created.add(source);
      final sha = sha256.convert(bytes).toString();
      final first = await core.call('media.rawThumbnail', {
        'path': source.path,
      });
      final path = first['path'] as String;
      expect(p.isWithin(p.join(core.root, 'raw-thumbnails'), path), true);
      expect(first['sourceSha'], sha);
      expect(first['embeddedPreview'], false);
      final size = await dimensions(path);
      expect(size.$1, greaterThan(0));
      expect(size.$2, greaterThan(0));
      expect(size.$1, lessThanOrEqualTo(512));
      expect(size.$2, lessThanOrEqualTo(512));
      expect(
        size.$1 > size.$2,
        orientation < 5,
        reason: 'RAW EXIF $orientation must be applied exactly once',
      );
      final before = await File(path).readAsBytes();
      expect(
        (await core.call('media.rawThumbnail', {'path': source.path}))['path'],
        path,
      );
      expect(await File(path).readAsBytes(), before);
      await File(path).writeAsString('corrupted disposable thumbnail');
      final repaired = await core.call('media.rawThumbnail', {
        'path': source.path,
      });
      expect(await dimensions(repaired['path'] as String), size);
      expect((await sha256.bind(source.openRead()).first).toString(), sha);
    }
    final frozenSourceSha =
        (await sha256.bind(File(pngSource).openRead()).first).toString();
    final jpegResult = await core.call('media.exportPreview', {
      'path': pngSource,
      'owner': '',
      'recipe': {'schema': 1},
      'size': 'full',
      'snapshot': true,
      'expectedSourceSha': frozenSourceSha,
    });
    late final Uint8List jpeg;
    try {
      final encoded = File(
        '${core.root}/previews/export-${jpegResult['id']}/encoded.jpg',
      );
      final bytes = await encoded.readAsBytes();
      expect(sha256.convert(bytes).toString(), jpegResult['sha256']);
      jpeg = jpegWithOrientation(bytes, 6);
    } finally {
      await core.call('media.exportPreviewClose', {'id': jpegResult['id']});
    }
    final embedded = thumbnailDng(
      identity: 'Embedded preview EXIF regression ${folder.path}',
      jpeg: jpeg,
    );
    final source = await File('${folder.path}/embedded-orientation.dng')
        .writeAsBytes(embedded);
    created.add(source);
    final result = await core.call('media.rawThumbnail', {'path': source.path});
    expect(
      result['embeddedPreview'],
      true,
      reason: 'This TIFF IFD1 fixture must exercise the embedded-JPEG branch',
    );
    final embeddedSize = await dimensions(result['path'] as String);
    expect(
      embeddedSize.$1 < embeddedSize.$2,
      true,
      reason: 'Embedded JPEG EXIF 6 overrides RAW orientation 1 without a second rotation',
    );
    expect(
      (await sha256.bind(source.openRead()).first).toString(),
      sha256.convert(embedded).toString(),
    );
    expect(
      await snapshot('raw-development'),
      fullDevelopments,
      reason: 'Grid thumbnails cannot create full editing RAW developments',
    );
    expect(
      await core.call('version.list', {'owner': ''}),
      versions,
      reason: 'Grid thumbnails never publish edited versions',
    );
  } finally {
    for (final file in created.reversed) {
      if (await file.exists()) await file.delete();
    }
    if (await folder.exists()) await folder.delete();
  }
}
