import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/album_edit_status.dart';
import 'package:huevia/domain.dart';
import 'package:path/path.dart' as p;

class _StatusCore extends HueviaCore {
  bool edited = true;
  String identity = 'a' * 64;
  Completer<Json>? alice;
  final calls = <(String, Json)>[];
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    if (operation == 'draft.statuses') {
      if (payload['owner'] == 'alice' && alice != null) return alice!.future;
      return {
        'items': [
          for (final path in payload['paths'] as List)
            {
              'path': path,
              'sourceSha': 'a' * 64,
              'edited': edited && payload['owner'] == 'alice',
            },
        ],
      };
    }
    if (operation == 'gallery.identity') return {'sourceSha': identity};
    throw AppFailure(operation);
  }
}

void main() {
  (AppState, _StatusCore) setup() {
    final root = Directory.systemTemp.createTempSync('album-edit-status-');
    addTearDown(() => root.deleteSync(recursive: true));
    final core = _StatusCore()..root = root.path;
    return (
      AppState(core)
        ..session = {
          'user': {'id': 'alice'},
        }
        ..photos = [
          Photo(p.join(root.path, 'originals', 'a.jpg'), 'same.jpg', {}),
        ],
      core,
    );
  }

  test('Edited badge follows native current-owner status and disappears after resetting edits', () async {
    final (state, core) = setup();
    final status = AlbumEditStatus(state)..refresh();
    await status.ready;
    final rows = [
      {'id': state.photos.single.path},
    ];
    expect(status.editedIds(rows, phone: false), {state.photos.single.path});
    core.edited = false;
    core.editRevision.value++;
    await status.ready;
    expect(status.editedIds(rows, phone: false), isEmpty);
    status.dispose();
    state.dispose();
  });

  test('Phone legacy linkage requires the exact original digest and survives metadata reload', () async {
    final (state, core) = setup();
    final status = AlbumEditStatus(state)..refresh();
    await status.ready;
    final row = <String, dynamic>{
      'id': 'asset:one',
      'name': 'same.jpg',
      'bytes': 15,
      'modified': 123,
    };
    core.identity = 'b' * 64;
    await status.linkPhoneRows([row]);
    expect(status.editedIds([row], phone: true), isEmpty);
    expect(state.photos.single.info['gallerySources'], isNull);
    core.identity = 'a' * 64;
    final revised = {...row, 'modified': 124};
    await status.linkPhoneRows([revised]);
    await status.ready;
    expect(status.editedIds([revised], phone: true), {'asset:one'});
    expect(status.editedIds([row], phone: true), isEmpty);
    final photo = Photo.fromJson(state.photos.single.toJson());
    expect(state.phonePhotoMatches(photo, revised), isTrue);
    expect(core.calls.where((call) => call.$1 == 'gallery.import'), isEmpty);
    status.dispose();
    state.dispose();
  });

  test('Unrelated phone originals are not read to decorate an album', () async {
    final (state, core) = setup();
    final status = AlbumEditStatus(state)..refresh();
    await status.ready;
    await status.linkPhoneRows([
      {'id': 'unrelated', 'name': 'other.jpg'},
    ]);
    expect(core.calls.where((call) => call.$1.startsWith('gallery.')), isEmpty);
    status.dispose();
    state.dispose();
  });

  test('Late Alice statuses cannot appear for Bob', () async {
    final (state, core) = setup();
    core.alice = Completer<Json>();
    final status = AlbumEditStatus(state)..refresh();
    final previous = status.ready;
    state.acceptAuthenticatedSession({
      'verified': true,
      'user': {'id': 'bob'},
    });
    await status.ready;
    core.alice!.complete({
      'items': [
        {
          'path': state.photos.single.path,
          'sourceSha': 'a' * 64,
          'edited': true,
        },
      ],
    });
    await previous;
    expect(status.isEdited(state.photos.single), isFalse);
    status.dispose();
    state.dispose();
  });
}
