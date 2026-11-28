import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/batch_export.dart';
import 'package:huevia/domain.dart';
import 'package:path/path.dart' as p;

class _PresetCore extends HueviaCore {
  final prepared = <Json>[];
  final exported = <Json>[];
  bool failSecond = false;
  @override
  Future<void> cancel(String jobId) async {}
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'editor.prepare') {
      prepared.add(object(payload));
      return {'id': object(payload['preset'])['sha256']};
    }
    if (operation == 'draft.load') {
      final recipe = Recipe()
        ..setValue(0, payload['path'].toString().endsWith('a.jpg') ? 2 : 3);
      return {'recipe': recipe.data};
    }
    if (operation == 'media.export') {
      exported.add(object(payload));
      if (failSecond && payload['path'].toString().endsWith('b.jpg')) {
        throw const AppFailure('第二张暂不可用');
      }
      final file = File(
        p.join(root, 'photo-versions', p.basename(payload['path'] as String)),
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes([1, 2, 3]);
      return {'path': file.path};
    }
    throw StateError('Unexpected $operation');
  }
}

void main() {
  late Directory directory;
  late _PresetCore core;
  late AppState state;
  late List<Json> rows;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('huevia-preset-b-');
    core = _PresetCore()..root = directory.path;
    state = AppState(core)
      ..photos = [
        for (final name in ['a.jpg', 'b.jpg'])
          Photo(p.join(directory.path, 'originals', name), name, {}),
      ];
    rows = state.photos
        .map((photo) => <String, dynamic>{'id': photo.path, 'name': photo.name})
        .toList();
  });
  tearDown(() async {
    state.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'Unified preset task has an isolated journal and requires a preset',
    () async {
      final normal = BatchExport(state, rows, phone: false);
      final current = BatchExport(
        state,
        rows,
        phone: false,
        currentEffects: true,
      );
      final preset = BatchExport(state, rows, phone: false, presetBatch: true);
      addTearDown(() {
        normal.dispose();
        current.dispose();
        preset.dispose();
      });
      expect({
        normal.journal.path,
        current.journal.path,
        preset.journal.path,
      }, hasLength(3));
      await expectLater(preset.run(), throwsA(isA<AppFailure>()));
      expect(preset.locked, isFalse);
      expect(core.exported, isEmpty);
    },
  );

  test('Online preset is prepared for every source; per-photo adjustments remain frozen across retry', () async {
    final batch = BatchExport(state, rows, phone: false, presetBatch: true);
    addTearDown(batch.dispose);
    final sha = 'a' * 64;
    final descriptor = <String, dynamic>{
      'id': 'remote',
      'sha256': sha,
      'name': '暖调胶片',
    };
    core.failSecond = true;
    await batch.run(presetId: sha, onlinePreset: descriptor, amount: 80);
    expect(
      core.prepared.map((v) => v['path']),
      state.photos.map((v) => v.path),
    );
    expect(
      core.exported.map((v) => (object(v['recipe'])['values'] as List).first),
      [2, 3],
    );
    expect(
      core.exported.every(
        (v) =>
            object(v['recipe'])['presetId'] == sha &&
            object(v['recipe'])['strength'] == 80,
      ),
      isTrue,
    );
    descriptor['name'] = 'later mutation';
    expect(batch.editorPreset!['name'], '暖调胶片');
    core.failSecond = false;
    await batch.run(presetId: 'b' * 64, amount: 5);
    expect(
      core.exported.where((v) => v['path'] == state.photos.first.path),
      hasLength(1),
    );
    expect(object(core.exported.last['recipe'])['presetId'], sha);
    expect(object(core.exported.last['recipe'])['strength'], 80);
    expect(batch.done, isTrue);
    expect(
      core.prepared,
      hasLength(2),
      reason: 'Frozen per-photo history resumes without preparing online again',
    );
  });

  test('Completed preset batch opens a fresh task and retains previous output bytes', () async {
    final first = BatchExport(state, rows, phone: false, presetBatch: true);
    await first.run(presetId: 'local', amount: 60);
    final outputs = first.items.map((v) => v.output!).toList();
    first.dispose();
    final next = BatchExport(state, rows, phone: false, presetBatch: true);
    addTearDown(next.dispose);
    expect(next.locked, isFalse);
    expect(next.preset, isNull);
    expect(next.items.every((item) => item.output == null), isTrue);
    expect(
      outputs.every((path) => File(path).readAsBytesSync().length == 3),
      isTrue,
    );
  });
}
