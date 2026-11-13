import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';

/// Runs the installed platform models and renderer; no fake detector or codec.
Future<void> verifyRetouchPipeline(HueviaCore core) async {
  final session = await core.call('account.current');
  final owner = session['user']?['id'] as String? ?? '';
  await _verifyPersonalToneCards(core, owner);
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
      'diagnostics': Platform.isIOS,
    });
    final faces = object(analyzed['portrait'])['faces'] as List;
    expect(
      faces,
      isNotEmpty,
      reason:
          'Built-in portrait $scene must run the installed face model; '
          'native stages: ${analyzed['diagnostics']}',
    );
    expect(faces.every((face) => object(face)['hasLandmarks'] == true), true);
    expect((object(faces.first)['landmarks'] as List).length, 936);
    final selection = await core.call('media.retouchAnalyze', {
      'path': path,
      'owner': owner,
      'expectedSourceSha': before,
      'localData': analyzed['localData'],
      'mode': 'overlay',
      'index': 0,
    });
    final overlay = object(selection['selectionOverlay']);
    final overlayWidth = overlay['width'] as int;
    final overlayHeight = overlay['height'] as int;
    expect(overlayWidth, inInclusiveRange(1, 240));
    expect(overlayHeight, inInclusiveRange(1, 320));
    expect(
      base64Decode(overlay['rgba'] as String).length,
      overlayWidth * overlayHeight * 4,
    );
    expect(overlay['premultiplied'], true);
    expect(selection['localData'], analyzed['localData']);
    final hit = await core.call('media.retouchAnalyze', {
      'path': path,
      'owner': owner,
      'expectedSourceSha': before,
      'localData': analyzed['localData'],
      'mode': 'hitFace',
      'x': object(faces.first)['cx'],
      'y': object(faces.first)['cy'],
    });
    expect(hit['hitFace'], inInclusiveRange(-1, faces.length - 1));
    expect(hit['localData'], analyzed['localData']);
    if (Platform.isIOS) {
      expect(analyzed['analysisEngine'], 'TensorFlowLiteC-2.17.0-CPU');
      expect(analyzed['meshPoints'], 468);
    }
    final skin = await core.call('media.retouchAnalyze', {
      'path': path,
      'owner': owner,
      'localData': analyzed['localData'],
      'mode': 'skin',
      'diagnostics': Platform.isIOS,
    });
    expect(object(skin['portrait'])['hasSkinMask'], true);
    final candidates = await core.call('media.retouchAnalyze', {
      'path': path,
      'owner': owner,
      'expectedSourceSha': before,
      'localData': skin['localData'],
      'mode': 'autoBlemish',
    });
    final heals = candidates['healCandidates'] as List;
    expect(heals.length, lessThanOrEqualTo(24));
    expect(candidates['localData'], skin['localData']);
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
    Future<Map<String, dynamic>> menu(
      Map<String, dynamic> prior,
      String action,
      Map<String, dynamic> value, {
      int index = 0,
      bool perFace = true,
    }) => core.call('media.retouchChange', {
      'path': path,
      'owner': owner,
      'expectedSourceSha': before,
      'localData': prior['localData'],
      'tonePerFace': perFace,
      'action': action,
      'index': index,
      'value': value,
    });
    Map<String, dynamic> firstFace(Map<String, dynamic> value) =>
        object((object(value['portrait'])['faces'] as List).first);
    final disabled = await menu(adjusted, 'face', {'enabled': false});
    expect(firstFace(disabled)['enabled'], false);
    final enabled = await menu(disabled, 'face', {'enabled': true});
    expect(firstFace(enabled)['enabled'], true);
    expect(firstFace(enabled)['brightness'], 20);
    final custom = await menu(enabled, 'face', {
      'toneRgb': 0xbba080,
      'toneAmount': .41,
    });
    expect(firstFace(custom)['toneId'], 10);
    expect(firstFace(custom)['toneRgb'], 0xbba080);
    final strength = await menu(custom, 'face', {'toneAmount': .63});
    expect(firstFace(strength)['toneRgb'], 0xbba080);
    final whole = await menu(strength, 'toneScope', {'perFace': false});
    expect(object(whole['portrait'])['tonePerFace'], false);
    expect(object(object(whole['portrait'])['skin'])['toneRgb'], 0xbba080);
    expect(firstFace(whole)['toneId'], 0);
    final person = await menu(whole, 'toneScope', {
      'perFace': true,
    }, perFace: false);
    expect(object(person['portrait'])['tonePerFace'], true);
    expect(firstFace(person)['toneRgb'], 0xbba080);
    expect(firstFace(person)['toneAmount'], .63);
    final bodySkin = await core.call('media.retouchAnalyze', {
      'path': path,
      'owner': owner,
      'expectedSourceSha': before,
      'localData': person['localData'],
      'tonePerFace': true,
      'mode': 'faceBody',
    });
    expect(firstFace(bodySkin)['hasBodySkinMask'], true);
    expect(firstFace(bodySkin)['brightness'], 20);
    expect(firstFace(bodySkin)['toneRgb'], 0xbba080);
    final bodyColor = await menu(bodySkin, 'face', {'toneBody': true});
    expect(firstFace(bodyColor)['toneBody'], true);
    expect(firstFace(bodyColor)['toneAmount'], .63);
    final faceColor = await menu(bodyColor, 'face', {'toneBody': false});
    expect(firstFace(faceColor)['toneBody'], false);
    expect(firstFace(faceColor)['toneRgb'], 0xbba080);
    final cx = (firstFace(faceColor)['cx'] as num).toDouble();
    final cy = (firstFace(faceColor)['cy'] as num).toDouble();
    final painted = await menu(bodyColor, 'faceStroke', {
      'points': [cx, cy, (cx + .01).clamp(0, 1), cy],
      'radius': .01,
      'erase': false,
    });
    expect(firstFace(painted)['strokeCount'], 1);
    final erased = await menu(painted, 'faceStroke', {
      'points': [cx, cy],
      'radius': .005,
      'erase': true,
    });
    expect(firstFace(erased)['strokeCount'], 2);
    final rendered = await core.call('media.reviewPreview', {
      'path': path,
      'owner': owner,
      'recipe': {...Recipe().data, 'localData': erased['localData']},
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
    expect((object(patched['portrait'])['heals'] as List).length, 1);
    final unhealed = await menu(patched, 'removeHeal', {});
    expect(object(unhealed['portrait'])['heals'], isEmpty);
    expect(unhealed['patchCount'], 1);
    final cleared = await menu(patched, 'clearPortrait', {});
    expect(object(cleared['portrait'])['faces'], isEmpty);
    expect(object(cleared['portrait'])['heals'], isEmpty);
    expect(cleared['patchCount'], 1);
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

Future<void> _verifyPersonalToneCards(HueviaCore core, String owner) async {
  final initial = await core.call('toneCards.list', {'owner': owner});
  final cards = initial['cards'] as List;
  expect(
    cards.length,
    lessThan(12),
    reason: 'The QA sandbox needs one free card slot',
  );
  final initialIds = cards.map((value) => object(value)['id']).toSet();
  final colors = cards.map((value) => object(value)['rgb']).toSet();
  var rgb = 0x147a62;
  while (colors.contains(rgb)) {
    rgb++;
  }
  final stamp = DateTime.now().microsecondsSinceEpoch.toString();
  final name = 'QA${stamp.substring(stamp.length - 8)}';
  String? created;
  try {
    final saved = await core.call('toneCards.save', {
      'owner': owner,
      'name': name,
      'rgb': rgb,
    });
    final entry = (saved['cards'] as List)
        .map(object)
        .singleWhere((value) => !initialIds.contains(value['id']));
    created = entry['id'] as String;
    expect(entry['name'], name);
    expect(entry['rgb'], rgb);
    final reloaded = await core.call('toneCards.list', {'owner': owner});
    expect(
      (reloaded['cards'] as List)
          .map(object)
          .singleWhere((value) => value['id'] == created),
      entry,
    );
    await expectLater(
      core.call('toneCards.list', {'owner': 'different-owner-$name'}),
      throwsA(isA<AppFailure>()),
    );
  } finally {
    if (created != null) {
      await core.call('toneCards.remove', {'owner': owner, 'id': created});
    }
  }
  expect((await core.call('toneCards.list', {'owner': owner}))['cards'], cards);
}
