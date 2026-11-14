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
    expect(detail['detailToken'], isA<String>());
    final tilePayload = <String, dynamic>{
      'owner': owner,
      'path': detail['path'],
      'detailToken': detail['detailToken'],
      'expectedSourceSha': sourceSha,
      'region': {
        'left': 300 / 1600,
        'top': 240 / 1200,
        'right': 800 / 1600,
        'bottom': 640 / 1200,
      },
      'maxEdge': 256,
    };
    final tile = await core.call('media.detailTile', tilePayload);
    remember(tile);
    expect((tile['sourceWidth'], tile['sourceHeight']), (1600, 1200));
    expect(tile['sourceSha'], sourceSha);
    expect(tile['detailToken'], detail['detailToken']);
    expect(tile['temporary'], true);
    expect(
      (tile['decodedWidth'] as num) * (tile['decodedHeight'] as num),
      lessThanOrEqualTo(4 * 1024 * 1024),
    );
    expect(tile['decodedBytes'], lessThanOrEqualTo(4 * 1024 * 1024 * 4));
    final visible = await _read(temporary.last);
    expect((visible.width, visible.height), (250, 200));
    expect(
      visible.red,
      greaterThan(full.red + 50),
      reason: 'ROI must sample the edited bright rectangle, not the overview',
    );
    expect(tile['region'], tilePayload['region']);
    for (final invalid in [
      {...tilePayload, 'detailToken': 'unissued-capability'},
      {...tilePayload, 'owner': '${owner}different-owner'},
      {...tilePayload, 'path': source.path},
      {...tilePayload, 'maxEdge': 4096},
      {...tilePayload, 'expectedSourceSha': List.filled(64, '0').join()},
      {
        ...tilePayload,
        'region': {'left': 0.5, 'top': 0, 'right': 0.5, 'bottom': 1},
      },
    ]) {
      await expectLater(
        core.call('media.detailTile', invalid),
        throwsA(isA<AppFailure>()),
      );
    }
    final localRecipe = <String, dynamic>{
      ...recipe,
      'geometry': {'turns': 1},
      'border': {'template': 3},
    };
    final localPreview = await core.call('media.localPreview', {
      ...payload,
      'recipe': localRecipe,
      'maxEdge': 640,
    });
    remember(localPreview);
    expect((localPreview['width'], localPreview['height']), (640, 480));
    final localDetail = await core.call('media.detailRender', {
      ...payload,
      'recipe': localRecipe,
      'viewMode': 'local',
      'maxEdge': 640,
    });
    remember(localDetail);
    expect(
      (localDetail['width'], localDetail['height']),
      (1600, 1200),
      reason: 'Selection detail strips geometry/border exactly like localPreview, while retaining full pixels',
    );
    expect(
      (await _read(temporary.last)).red,
      closeTo(full.red, 3),
      reason:
          'Selection detail retains the same current global adjustment profile',
    );
    final localTile = await core.call('media.detailTile', {
      ...tilePayload,
      'path': localDetail['path'],
      'detailToken': localDetail['detailToken'],
    });
    remember(localTile);
    expect((await _read(temporary.last)).red, closeTo(visible.red, 3));
    final rotated = await core.call('media.detailRender', {
      ...payload,
      'recipe': {
        ...recipe,
        'geometry': {'turns': 1},
      },
    });
    remember(rotated);
    expect(
      (rotated['width'], rotated['height']),
      (1200, 1600),
      reason: 'Omitted viewMode keeps the ordinary composed review profile',
    );
    await expectLater(
      core.call('media.detailRender', {...payload, 'viewMode': 'unknown'}),
      throwsA(isA<AppFailure>()),
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
    // RAW detail reuses the real developer/cache, but never rawPrepare, a
    // persistent editing source, a draft or an export/version transaction.
    final rawDraft = await core.call('draft.load', {
      'path': raw.path,
      'owner': owner,
    });
    final developed = await core.call('media.rawDetail', {
      'path': raw.path,
      'owner': owner,
      'expectedSourceSha': rawSha,
      'settings': {'colorMode': 'NEUTRAL', 'exposure': 0},
    });
    remember(developed);
    expect(developed['temporary'], true);
    expect(developed['fullResolution'], true);
    expect((developed['width'], developed['height']), (256, 192));
    final rawTile = <String, dynamic>{
      'owner': owner,
      'path': developed['path'],
      'detailToken': developed['detailToken'],
      'expectedSourceSha': rawSha,
      'region': {'left': 0, 'top': 0, 'right': 1, 'bottom': 1},
      'maxEdge': 256,
    };
    final neutralTile = await core.call('media.detailTile', rawTile);
    remember(neutralTile);
    final neutral = await _read(temporary.last);
    final darker = await core.call('media.rawDetail', {
      'path': raw.path,
      'owner': owner,
      'expectedSourceSha': rawSha,
      'settings': {'colorMode': 'NEUTRAL', 'exposure': -10},
    });
    remember(darker);
    final darkerTile = await core.call('media.detailTile', {
      ...rawTile,
      'path': darker['path'],
      'detailToken': darker['detailToken'],
    });
    remember(darkerTile);
    expect(
      (await _read(temporary.last)).red,
      lessThan(neutral.red - 10),
      reason: 'Full RAW detail must honor the current staged exposure',
    );
    final rawEdited = await core.call('media.rawDetail', {
      'path': raw.path,
      'owner': owner,
      'expectedSourceSha': rawSha,
      'settings': {'colorMode': 'NEUTRAL', 'exposure': 0},
      'recipe': recipe,
      'viewMode': 'review',
    });
    remember(rawEdited);
    final editedPixels = await _read(temporary.last);
    expect(
      editedPixels.red,
      greaterThan(neutral.red + 10),
      reason: 'Direct RAW editing applies the frozen editing recipe after staged development',
    );
    expect(rawEdited['sourceSha'], rawSha);
    final rawLocal = await core.call('media.rawDetail', {
      'path': raw.path,
      'owner': owner,
      'expectedSourceSha': rawSha,
      'settings': {'colorMode': 'NEUTRAL', 'exposure': 0},
      'recipe': localRecipe,
      'viewMode': 'local',
    });
    remember(rawLocal);
    expect((rawLocal['width'], rawLocal['height']), (256, 192));
    expect(
      (await _read(temporary.last)).red,
      closeTo(editedPixels.red, 3),
      reason: 'RAW selection detail uses the same local profile, not the rotated/bordered review plane',
    );
    final rawReviewRotated = await core.call('media.rawDetail', {
      'path': raw.path,
      'owner': owner,
      'expectedSourceSha': rawSha,
      'settings': {'colorMode': 'NEUTRAL', 'exposure': 0},
      'recipe': {
        ...recipe,
        'geometry': {'turns': 1},
      },
    });
    remember(rawReviewRotated);
    expect((rawReviewRotated['width'], rawReviewRotated['height']), (192, 256));
    final rawEditedTile = await core.call('media.detailTile', {
      ...rawTile,
      'path': rawEdited['path'],
      'detailToken': rawEdited['detailToken'],
    });
    remember(rawEditedTile);
    expect(rawEditedTile['sourceSha'], rawSha);
    expect((await _read(temporary.last)).red, closeTo(editedPixels.red, 3));
    for (final extra in [
      {'recipe': recipe, 'viewMode': 'unknown'},
      {'recipe': 'invalid'},
    ]) {
      await expectLater(
        core.call('media.rawDetail', {
          'path': raw.path,
          'owner': owner,
          'expectedSourceSha': rawSha,
          'settings': <String, dynamic>{},
          ...extra,
        }),
        throwsA(isA<AppFailure>()),
      );
    }
    expect(
      await core.call('draft.load', {'path': raw.path, 'owner': owner}),
      rawDraft,
    );
    expect(await core.call('version.list', {'owner': owner}), versionsBefore);
    final afterRaw = await _persistent(core.root);
    for (final name in [
      'photo-edit-drafts',
      'photo-preset-history',
      'photo-versions',
      'exports',
    ]) {
      expect(afterRaw[name], persistentBefore[name]);
    }
    expect(await _hash(raw), rawSha);
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
