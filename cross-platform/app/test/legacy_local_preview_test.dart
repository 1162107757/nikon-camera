import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/legacy_local_editor.dart';
import 'package:huevia/legacy_local_preview.dart';

class LocalPreviewCore extends HueviaCore {
  final calls = <(String, Json, String?)>[];
  final frames = <Completer<Json>>[];
  final cancelled = <String>[];
  Object? validationError;
  int active = 0, maximum = 0;
  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, toolsCopy(payload), jobId));
    if (operation == 'local.change') {
      if (validationError != null) {
        final failure = validationError!;
        validationError = null;
        throw failure;
      }
      final tools = object(payload['value']);
      return {
        'localData':
            (tools['masks'] as List).isEmpty &&
                (tools['clones'] as List).isEmpty
            ? 'base'
            : jsonEncode(tools),
        'sha256': 'validated',
        ...tools,
      };
    }
    if (operation != 'media.localPreview') {
      throw StateError('Unexpected operation $operation');
    }
    final reply = Completer<Json>();
    frames.add(reply);
    active++;
    if (active > maximum) maximum = active;
    try {
      return await reply.future;
    } finally {
      active--;
    }
  }
}

void main() {
  Json tools(int value) => {
    'masks': [
      {'exposure': value},
    ],
    'clones': [],
  };
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  LegacyLocalPreview preview(
    LocalPreviewCore core,
    List<String> discarded, {
    bool Function()? current,
  }) => LegacyLocalPreview(
    core: core,
    photo: const Photo('/own/original.jpg', 'own.jpg', {}),
    owner: '',
    recipe: {
      'schema': 1,
      'presetId': 'frozen',
      'geometry': {'turns': 1},
      'border': {'template': 3},
    },
    localState: {
      'localData': 'base',
      'sha256': 'base-sha',
      'masks': [],
      'clones': [],
    },
    initialFrame: {'path': 'initial.jpg', 'width': 800, 'height': 600},
    isCurrent: current ?? () => true,
    discard: (path) async {
      if (path != null) discarded.add(path);
    },
  );

  test('only newest pending tools render, one worker runs, and every command preserves the frozen binary base', () async {
    final core = LocalPreviewCore(), discarded = <String>[];
    final p = preview(core, discarded);
    p.offer(tools(1), interactive: true);
    await tick();
    expect(core.frames, hasLength(1));
    p.offer(tools(2), interactive: true);
    p.offer(tools(3), interactive: false);
    expect(p.ready, isFalse);
    core.frames[0].complete({'path': 'stale.jpg', 'width': 768, 'height': 576});
    await tick();
    expect(core.frames, hasLength(2));
    final validation = core.calls
        .where((row) => row.$1 == 'local.change')
        .toList();
    expect(validation, hasLength(2));
    expect(
      validation.every(
        (row) =>
            row.$2['localData'] == 'base' &&
            row.$2['expectedSha'] == 'base-sha' &&
            row.$2['action'] == 'replaceTools',
      ),
      isTrue,
    );
    final renders = core.calls
        .where((row) => row.$1 == 'media.localPreview')
        .toList();
    expect(renders[0].$2['maxEdge'], 768);
    expect(renders[1].$2['maxEdge'], 1280);
    expect(object(renders[1].$2['recipe'])['localData'], jsonEncode(tools(3)));
    expect(object(renders[1].$2['recipe'])['geometry'], {'turns': 1});
    expect(object(renders[1].$2['recipe'])['border'], {'template': 3});
    core.frames[1].complete({
      'path': 'latest.jpg',
      'width': 1280,
      'height': 960,
    });
    await tick();
    expect(core.maximum, 1);
    expect(p.ready, isTrue);
    expect(p.result['masks'], tools(3)['masks']);
    expect(discarded, containsAll(['stale.jpg', 'initial.jpg']));
    p.dispose();
    await tick();
    expect(discarded.where((path) => path == 'latest.jpg'), hasLength(1));
  });

  test('interactive output cannot be applied until the same tools receive a full-quality frame', () async {
    final core = LocalPreviewCore(), discarded = <String>[];
    final p = preview(core, discarded);
    p.offer(tools(1), interactive: true);
    await tick();
    core.frames[0].complete({'path': 'low.jpg', 'width': 768, 'height': 576});
    await tick();
    expect(p.busy, isFalse);
    expect(p.ready, isFalse);
    expect(() => p.result, throwsA(isA<AppFailure>()));
    p.offer(tools(1), interactive: false);
    await tick();
    expect(core.frames, hasLength(2));
    core.frames[1].complete({'path': 'full.jpg', 'width': 1280, 'height': 960});
    await tick();
    expect(p.ready, isTrue);
    expect(discarded, contains('low.jpg'));
    p.dispose();
  });

  test('account invalidation redacts the view and discards a late frame without starting another render', () async {
    var current = true;
    final core = LocalPreviewCore(), discarded = <String>[];
    final p = preview(core, discarded, current: () => current);
    p.offer(tools(1), interactive: false);
    await tick();
    current = false;
    p.invalidate();
    expect(p.frame, isNull);
    expect(p.ready, isFalse);
    p.offer(tools(2), interactive: false);
    core.frames.single.complete({
      'path': 'late-private.jpg',
      'width': 1280,
      'height': 960,
    });
    await tick();
    expect(discarded, containsAll(['initial.jpg', 'late-private.jpg']));
    expect(core.frames, hasLength(1));
    expect(core.cancelled, hasLength(1));
    p.dispose();
  });

  test('failed validation preserves the old photograph and retries without a draft save', () async {
    final core = LocalPreviewCore()
      ..validationError = const AppFailure('Invalid binary snapshot');
    final discarded = <String>[];
    final p = preview(core, discarded);
    p.offer(tools(1), interactive: false);
    await tick();
    expect(p.error, isA<AppFailure>());
    expect(p.ready, isFalse);
    expect(p.frame!['path'], 'initial.jpg');
    p.retry();
    await tick();
    core.frames.single.complete({
      'path': 'retried.jpg',
      'width': 1280,
      'height': 960,
    });
    await tick();
    expect(p.ready, isTrue);
    expect(core.calls.where((row) => row.$1 == 'draft.save'), isEmpty);
    p.dispose();
  });

  test(
    'retry regenerates a corrupt file even when validated tools are unchanged',
    () async {
      final core = LocalPreviewCore(), discarded = <String>[];
      final p = preview(core, discarded);
      expect(p.ready, isTrue);
      p.retry();
      await tick();
      expect(core.frames, hasLength(1));
      expect(p.ready, isFalse);
      core.frames.single.complete({
        'path': 'regenerated.jpg',
        'width': 800,
        'height': 600,
      });
      await tick();
      expect(p.ready, isTrue);
      expect(p.frame!['path'], 'regenerated.jpg');
      expect(discarded, contains('initial.jpg'));
      p.dispose();
    },
  );
}
