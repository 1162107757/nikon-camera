import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';

/// Runs the installed platform models and renderer; no fake detector or codec.
Future<void> verifyRetouchPipeline(HueviaCore core) async {
  final session = await core.call('account.current');
  final owner = session['user']?['id'] as String? ?? '';
  for (final scene in [0, 1]) {
    final sample = await core.call('media.templateSource', {'index': scene});
    final path = await core.importFile(
      XFile(sample['path'] as String),
      preset: false,
    );
    final before = (await sha256.bind(File(path).openRead()).first).toString();
    final oldDraft = await core.call('draft.load', {
      'path': path,
      'owner': owner,
    });
    final analyzed = await core.call('media.retouchAnalyze', {
      'path': path,
      'owner': owner,
      'localData': '',
      'mode': 'face',
    });
    final faces = object(analyzed['portrait'])['faces'] as List;
    expect(
      faces,
      isNotEmpty,
      reason: 'Built-in portrait $scene must run the installed face model',
    );
    expect(faces.every((face) => object(face)['hasLandmarks'] == true), true);
    if (Platform.isIOS) {
      expect(analyzed['analysisEngine'], 'TensorFlowLiteC-2.17.0-CPU');
      expect(analyzed['meshPoints'], 468);
    }
    final skin = await core.call('media.retouchAnalyze', {
      'path': path,
      'owner': owner,
      'localData': analyzed['localData'],
      'mode': 'skin',
    });
    expect(object(skin['portrait'])['hasSkinMask'], true);
    final adjusted = await core.call('media.retouchChange', {
      'path': path,
      'owner': owner,
      'localData': skin['localData'],
      'action': 'face',
      'index': 0,
      'value': {
        'brightness': 20,
        'smoothing': 35,
        'EYE_DETAIL': 40,
        'TEETH': 30,
      },
    });
    final face = object((object(adjusted['portrait'])['faces'] as List).first);
    expect(face['brightness'], 20);
    expect(face['EYE_DETAIL'], 40);
    final rendered = await core.call('media.reviewPreview', {
      'path': path,
      'owner': owner,
      'recipe': {...Recipe().data, 'localData': adjusted['localData']},
      'maxEdge': 960,
    });
    expect(await File(rendered['path'] as String).length(), greaterThan(1000));
    final healed = await core.call('media.retouchHeal', {
      'path': path,
      'owner': owner,
      'localData': adjusted['localData'],
      'x': .5,
      'y': .5,
      'radius': .01,
    });
    expect(healed['localData'], isNot(adjusted['localData']));
    final patched = await core.call('media.retouchPatch', {
      'path': path,
      'owner': owner,
      'localData': healed['localData'],
      'points': [.7, .3, .71, .3],
      'radius': .01,
    });
    expect(patched['patchCount'], 1);
    final restored = await core.call('media.retouchDescribe', {
      'path': path,
      'owner': owner,
      'localData': adjusted['localData'],
    });
    expect(
      restored['patchCount'],
      0,
    ); // Undo retains the exact immutable before-state.
    expect((await sha256.bind(File(path).openRead()).first).toString(), before);
    expect(
      await core.call('draft.load', {'path': path, 'owner': owner}),
      oldDraft,
      reason: 'Tentative portrait/patch operations must not save a draft',
    );
    final job =
        'retouch-cancel-$scene-${DateTime.now().microsecondsSinceEpoch}';
    final pending = core.call('media.retouchAnalyze', {
      'path': path,
      'owner': owner,
      'localData': adjusted['localData'],
      'mode': 'skin',
    }, job);
    final cancellation = expectLater(pending, throwsA(isA<AppFailure>()));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await core.cancel(job);
    await cancellation;
    expect((await sha256.bind(File(path).openRead()).first).toString(), before);
  }
  final landscape = await core.call('media.templateSource', {'index': 2});
  final noFace = await core.importFile(
    XFile(landscape['path'] as String),
    preset: false,
  );
  final result = await core.call('media.retouchAnalyze', {
    'path': noFace,
    'owner': owner,
    'localData': '',
    'mode': 'face',
  });
  expect(
    object(result['portrait'])['faces'],
    isEmpty,
    reason: 'No synthetic face may be returned for the landscape',
  );
}
