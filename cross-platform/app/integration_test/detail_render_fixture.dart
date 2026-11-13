import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:path/path.dart' as p;

import 'synthetic_dng.dart';

/// Exercises the installed full renderer, not a preview/mocked response. PNG
/// covers the native raster path; the R8 instrumentation separately uses JPEG.
Future<void> verifyDetailRendering(HueviaCore core) async {
  final session = await core.call('account.current');
  final owner = session['user']?['id'] as String? ?? '';
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final source = File(p.join(core.root, 'originals', 'detail-$nonce.png'));
  final raw = File(p.join(core.root, 'originals', 'detail-$nonce.dng'));
  final temporary = <File>[];
  await source.parent.create(recursive: true);
  final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xff506478), ui.BlendMode.src);
  canvas.drawRect(
    const ui.Rect.fromLTWH(300, 240, 500, 400),
    ui.Paint()..color = const ui.Color(0xffc3ac87),
  );
  for (var i = 0; i < 8; i++) {
    canvas.drawRect(
      ui.Rect.fromLTWH(1592.0 + i, 1199, 1, 1),
      ui.Paint()..color = ui.Color(0xff000000 | ((nonce >> (i * 8)) & 255)),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(1600, 1200);
  try {
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    await source.writeAsBytes(png.buffer.asUint8List(), flush: true);
  } finally {
    image.dispose();
    picture.dispose();
  }
  await raw.writeAsBytes(syntheticDng(identity: 'detail-$nonce'), flush: true);
  final sourceSha = await _hash(source), rawSha = await _hash(raw);
  final draftBefore = await core.call('draft.load', {
    'path': source.path,
    'owner': owner,
  });
  final versionsBefore = await core.call('version.list', {'owner': owner});
  final persistentBefore = await _persistent(core.root);
  final schema = await core.call('core.schema');
  final parameters = (schema['parameters'] as List).map(object).toList();
  final exposure = parameters.singleWhere((row) => row['name'] == 'EXPOSURE');
  final values = List<int>.filled(parameters.length, 0);
  values[(exposure['index'] as num).toInt()] = 10;
  final recipe = <String, Object>{'schema': 1, 'values': values};
  final payload = <String, dynamic>{
    'path': source.path,
    'owner': owner,
    'recipe': recipe,
    'expectedSourceSha': sourceSha,
  };
  void remember(Json value) {
    final path = value['path'] as String;
    expect(p.isWithin(p.join(core.root, 'previews'), path), true);
    temporary.add(File(path));
  }

  try {
    final preview = await core.call('media.reviewPreview', {
      ...payload,
      'maxEdge': 640,
    });
    remember(preview);
    final small = await _read(temporary.last);
    expect(small.width, 640);
    expect(small.height, 480);
    final detail = await core.call('media.detailRender', {
      ...payload,
      // These ordinary export/preview controls cannot silently reduce detail.
      'maxEdge': 640,
      'size': 'share',
    });
    remember(detail);
    expect(detail['sourceSha'], sourceSha);
    expect(detail['temporary'], true);
    expect(detail['fullResolution'], true);
    expect(detail['width'], 1600);
    expect(detail['height'], 1200);
    final full = await _read(temporary.last);
    expect((full.width, full.height), (1600, 1200));
    expect(
      full.red,
      greaterThan(100),
      reason: 'The requested +1 EV must change actual full pixels',
    );
    expect(await _hash(source), sourceSha);
    expect(
      await core.call('draft.load', {'path': source.path, 'owner': owner}),
      draftBefore,
    );
    expect(await core.call('version.list', {'owner': owner}), versionsBefore);
    expect(await _persistent(core.root), persistentBefore);
    final previews = await _files(Directory(p.join(core.root, 'previews')));
    await expectLater(
      core.call('media.detailRender', {
        ...payload,
        'expectedSourceSha': List.filled(64, '0').join(),
      }),
      throwsA(isA<AppFailure>()),
    );
    final missingIdentity = {...payload}..remove('expectedSourceSha');
    await expectLater(
      core.call('media.detailRender', missingIdentity),
      throwsA(isA<AppFailure>()),
    );
    await expectLater(
      core.call('media.detailRender', {
        ...payload,
        'owner': '${owner}different-owner',
      }),
      throwsA(isA<AppFailure>()),
    );
    await expectLater(
      core.call('media.detailRender', {
        ...payload,
        'path': raw.path,
        'expectedSourceSha': rawSha,
      }),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.message,
          'explicit RAW development guidance',
          contains('显影'),
        ),
      ),
    );
    final job = 'detail-cancel-$nonce';
    final pending = core.call('media.detailRender', payload, job).then((value) {
      remember(value);
      return value;
    });
    final cancelled = expectLater(pending, throwsA(isA<AppFailure>()));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await core.cancel(job);
    await cancelled;
    expect(
      await _files(Directory(p.join(core.root, 'previews'))),
      previews,
      reason: 'Rejected and cancelled detail renders must not leak their temporary files',
    );
    expect(await _hash(source), sourceSha);
    expect(await _hash(raw), rawSha);
    expect(
      await core.call('draft.load', {'path': source.path, 'owner': owner}),
      draftBefore,
    );
    expect(await core.call('version.list', {'owner': owner}), versionsBefore);
    expect(
      await _persistent(core.root),
      persistentBefore,
      reason: 'Detail viewing never saves drafts, versions or RAW development caches',
    );
  } finally {
    for (final file in temporary.reversed) {
      if (await file.exists()) await file.delete();
    }
    if (await source.exists()) await source.delete();
    if (await raw.exists()) await raw.delete();
  }
}

Future<String> _hash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<Map<String, String>> _files(Directory directory) async {
  final values = <String, String>{};
  if (!await directory.exists()) return values;
  await for (final file in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (file is File) values[file.path] = await _hash(file);
  }
  return values;
}

Future<Map<String, Map<String, String>>> _persistent(String root) async => {
  for (final name in [
    'photo-edit-drafts',
    'photo-preset-history',
    'photo-versions',
    'raw-development',
    'exports',
  ])
    name: await _files(Directory(p.join(root, name))),
  // The Android original developer stores its cache beside huevia-shared.
  'android-raw-development': await _files(
    Directory(p.join(p.dirname(root), 'raw-development')),
  ),
};

Future<({int width, int height, int red})> _read(File file) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  try {
    final frame = await codec.getNextFrame();
    try {
      final pixels = (await frame.image.toByteData())!;
      return (
        width: frame.image.width,
        height: frame.image.height,
        red: pixels.getUint8((100 * frame.image.width + 100) * 4),
      );
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
