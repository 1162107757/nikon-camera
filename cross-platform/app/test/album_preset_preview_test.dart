import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/album_preset_preview.dart';
import 'package:huevia/batch_export.dart';
import 'package:huevia/domain.dart';
import 'package:path/path.dart' as p;

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAEklEQVR4nGMQWm3yHx9mGBkKAKq5fAFPbl0bAAAAAElFTkSuQmCC',
);

Preset _preset(String sha, {bool online = false}) => Preset({
  'id': online ? 'online-$sha' : sha,
  'sha256': sha,
  'displayName': '本地色彩',
  'name': '在线色彩',
  'fileFormat': 'NCP',
}, online: online);

class AlbumPresetPreviewTestCore extends HueviaCore {
  final calls = <({String operation, Json payload, String? job})>[];
  final cancelled = <String>[];
  final rendered = <String>[];
  Completer<void>? heldMain;
  bool failThumbnail = false, mismatchAfterRender = false;
  int active = 0, peak = 0, serial = 0, draftExposure = 7;
  late String importedPath;

  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
    // A native completion may race with cancellation; the model must reject it.
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((
      operation: operation,
      payload: object(jsonDecode(jsonEncode(payload))),
      job: jobId,
    ));
    active++;
    if (active > peak) peak = active;
    try {
      switch (operation) {
        case 'gallery.import':
          return {'path': importedPath, 'name': '手机照片.jpg'};
        case 'media.info':
          return {'width': 8, 'height': 8, 'raw': false};
        case 'draft.load':
          final recipe = Recipe()..setValue(0, draftExposure);
          recipe.data['localData'] = {'existing': 'portrait-and-patch'};
          return {'recipe': recipe.data};
        case 'source.inspect':
          return {
            'path': payload['path'],
            'sourceSha':
                mismatchAfterRender && payload.containsKey('expectedSourceSha')
                ? 'f' * 64
                : 'a' * 64,
          };
        case 'editor.prepare':
          return {'id': object(payload['preset'])['sha256']};
        case 'media.reviewPreview':
          if (payload['maxEdge'] == 160 && failThumbnail) {
            failThumbnail = false;
            throw const AppFailure('测试缩略图失败');
          }
          if (payload['maxEdge'] == 1280 && heldMain != null) {
            final held = heldMain!;
            heldMain = null;
            await held.future;
          }
          final file = File(p.join(root, 'previews', 'owned-${serial++}.png'));
          await file.parent.create(recursive: true);
          await file.writeAsBytes(_png, flush: true);
          rendered.add(file.path);
          return {'path': file.path, 'width': 8, 'height': 8};
        default:
          throw AppFailure('Unexpected $operation');
      }
    } finally {
      active--;
    }
  }
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(
    condition(),
    isTrue,
    reason: 'The bounded preview operation completed',
  );
}

Future<
  ({
    AppState state,
    AlbumPresetPreviewTestCore core,
    BatchExport batch,
    AlbumPresetPreview preview,
  })
>
_setup({bool phone = false, bool rawWorking = false, int count = 1}) async {
  final directory = Directory.systemTemp.createTempSync('huevia-album-preset-');
  final core = AlbumPresetPreviewTestCore()
    ..root = directory.resolveSymbolicLinksSync();
  final state = AppState(core)
    ..session = {
      'user': {'id': 'account-a'},
    };
  final photos = <Photo>[];
  for (var i = 0; i < count; i++) {
    final file = File(
      p.join(core.root, 'originals', '${i + 1}.${rawWorking ? 'nef' : 'jpg'}'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(_png);
    photos.add(
      Photo(file.path, '照片${i + 1}.jpg', {
        'width': 8,
        'height': 8,
        if (rawWorking) 'raw': true,
      }),
    );
  }
  core.importedPath = photos.first.path;
  if (!phone) state.photos = photos;
  if (rawWorking) {
    final file = File(p.join(core.root, 'originals', 'working.jpg'));
    await file.writeAsBytes(_png);
    state.photos = [
      ...state.photos,
      Photo(file.path, '显影.jpg', {
        'rawSource': photos.first.path,
        'raw': false,
      }),
    ];
  }
  final batch = BatchExport(state, [
    for (var i = 0; i < count; i++)
      {'id': phone ? 'phone-$i' : photos[i].path, 'name': photos[i].name},
  ], phone: phone);
  final preview = AlbumPresetPreview(state, batch, isCurrent: () => true);
  addTearDown(() async {
    await preview.stop();
    preview.dispose();
    batch.dispose();
    state.dispose();
    await directory.delete(recursive: true);
  });
  return (state: state, core: core, batch: batch, preview: preview);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Latest main preview takes priority over queued thumbnails with one native request', () async {
    final fixture = await _setup();
    final held = Completer<void>();
    fixture.core.heldMain = held;
    final first = fixture.preview.update(
      item: fixture.batch.items.first,
      preset: _preset('b' * 64),
      strength: 10,
    );
    await _until(
      () => fixture.core.calls.any((c) => c.operation == 'media.reviewPreview'),
    );
    final thumbnail = fixture.preview.thumbnail(_preset('c' * 64));
    final replaced = fixture.preview.update(
      item: fixture.batch.items.first,
      preset: _preset('b' * 64),
      strength: 20,
    );
    final latest = fixture.preview.update(
      item: fixture.batch.items.first,
      preset: _preset('b' * 64),
      strength: 30,
    );
    held.complete();
    await Future.wait([first, replaced, latest]);
    expect(await thumbnail, isNotNull);
    final renders = fixture.core.calls
        .where((c) => c.operation == 'media.reviewPreview')
        .toList();
    expect(renders.map((c) => c.payload['maxEdge']), [1280, 1280, 160]);
    expect(
      renders.take(2).map((c) => object(c.payload['recipe'])['strength']),
      [10, 30],
    );
    expect(
      renders
          .take(2)
          .every(
            (c) =>
                c.payload['snapshot'] == true &&
                c.payload['expectedSourceSha'] == 'a' * 64,
          ),
      isTrue,
    );
    expect(fixture.core.peak, 1);
    expect(fixture.preview.frame?.image.width, 8);
    expect(fixture.preview.frame?.sourceSha, 'a' * 64);
    expect(fixture.batch.items.first.recipe, isNull);
    expect(await File(fixture.core.rendered.first).exists(), isFalse);
    expect(
      fixture.core.calls.any(
        (c) => c.operation == 'draft.save' || c.operation == 'media.export',
      ),
      isFalse,
    );
  });

  test('Phone preparation is reused and preview recipes never freeze the later export', () async {
    final fixture = await _setup(phone: true);
    final item = fixture.batch.items.first;
    final online = _preset('b' * 64, online: true);
    await fixture.preview.update(item: item, preset: online, strength: 25);
    final thumbnail = await fixture.preview.thumbnail(online);
    expect(
      identical(await fixture.preview.thumbnail(online), thumbnail),
      isTrue,
    );
    await fixture.preview.update(item: item, preset: online, strength: 75);
    expect(
      fixture.core.calls.where((c) => c.operation == 'gallery.import'),
      hasLength(1),
    );
    expect(
      fixture.core.calls.where((c) => c.operation == 'draft.load'),
      hasLength(1),
    );
    expect(
      fixture.core.calls.where((c) => c.operation == 'editor.prepare'),
      hasLength(1),
    );
    expect(item.recipe, isNull);
    final photo = item.photo;
    await fixture.preview.stop();
    fixture.core.draftExposure = 19;
    await fixture.batch.prepare(item);
    expect(item.photo, same(photo));
    expect(item.recipe!['presetId'], '');
    expect((item.recipe!['values'] as List).first, 19);
    expect(object(item.recipe!['localData'])['existing'], 'portrait-and-patch');
    expect(
      fixture.core.calls.where((c) => c.operation == 'gallery.import'),
      hasLength(1),
    );
  });

  test('Account change retires a held result and stop waits for its owned-file cleanup', () async {
    final fixture = await _setup();
    final original = File(fixture.core.importedPath);
    final bytes = await original.readAsBytes();
    final held = Completer<void>();
    fixture.core.heldMain = held;
    final update = fixture.preview.update(item: fixture.batch.items.first);
    await _until(
      () => fixture.core.calls.any((c) => c.operation == 'media.reviewPreview'),
    );
    fixture.state.acceptAuthenticatedSession({
      'user': {'id': 'account-b'},
      'verified': true,
    });
    var settled = false;
    final stop = fixture.preview.stop().then((_) => settled = true);
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);
    expect(fixture.preview.frame, isNull);
    expect(fixture.core.cancelled.single, startsWith('album-preset-'));
    held.complete();
    await Future.wait([update, stop]);
    expect(settled, isTrue);
    expect(fixture.preview.frame, isNull);
    expect(await File(fixture.core.rendered.single).exists(), isFalse);
    expect(await original.readAsBytes(), bytes);
    final calls = fixture.core.calls.length;
    await fixture.preview.update(item: fixture.batch.items.first);
    expect(fixture.core.calls, hasLength(calls));
  });

  test('An existing RAW working photo is reused without developing or replacing the selected original', () async {
    final fixture = await _setup(rawWorking: true);
    final item = fixture.batch.items.single;
    final original = item.row['id'];
    await fixture.preview.update(item: item, preset: _preset('b' * 64));
    await fixture.preview.update(
      item: item,
      preset: _preset('c' * 64),
      strength: 40,
    );
    expect(item.row['id'], original);
    expect(item.photo!.path, endsWith('working.jpg'));
    expect(item.photo!.info['rawSource'], original);
    expect(
      fixture.core.calls.where((c) => c.operation == 'draft.load'),
      hasLength(1),
    );
    expect(
      fixture.core.calls.any((c) => c.operation == 'media.rawDevelop'),
      isFalse,
    );
    expect(
      fixture.core.calls
          .where((c) => c.operation == 'media.reviewPreview')
          .every((c) => c.payload['path'] == item.photo!.path),
      isTrue,
    );
    expect(item.recipe, isNull);
  });

  test('Thumbnail failure is retryable and a source mismatch never installs or leaks a main image', () async {
    final fixture = await _setup();
    await fixture.preview.update(item: fixture.batch.items.first);
    final accepted = fixture.preview.frame;
    fixture.core.failThumbnail = true;
    expect(await fixture.preview.thumbnail(_preset('c' * 64)), isNull);
    expect(await fixture.preview.thumbnail(_preset('c' * 64)), isNotNull);
    expect(fixture.preview.frame, same(accepted));
    fixture.core.mismatchAfterRender = true;
    await fixture.preview.update(
      item: fixture.batch.items.first,
      preset: _preset('b' * 64),
    );
    expect(fixture.preview.frame, same(accepted));
    expect(fixture.preview.error, contains('原图身份已变化'));
    expect(await File(fixture.core.rendered.last).exists(), isFalse);
    expect(fixture.batch.items.first.recipe, isNull);
    expect(fixture.core.peak, 1);
  });

  test('Online recipe preparation is repeated for each photo identity without a library import', () async {
    final fixture = await _setup(count: 2);
    final online = _preset('b' * 64, online: true);
    await fixture.preview.update(item: fixture.batch.items[0], preset: online);
    await fixture.preview.update(item: fixture.batch.items[1], preset: online);
    final prepared = fixture.core.calls
        .where((c) => c.operation == 'editor.prepare')
        .toList();
    expect(prepared, hasLength(2));
    expect(prepared.map((c) => c.payload['path']).toSet(), hasLength(2));
    expect(prepared.every((c) => c.payload['owner'] == 'account-a'), isTrue);
    expect(
      fixture.core.calls.any(
        (c) =>
            c.operation == 'online.download' || c.operation == 'library.import',
      ),
      isFalse,
    );
    expect(fixture.batch.items.every((item) => item.recipe == null), isTrue);
    expect(fixture.core.peak, 1);
  });
}
