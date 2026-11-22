import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/batch_export.dart';
import 'package:huevia/domain.dart';
import 'package:path/path.dart' as p;

class PublicationCore extends HueviaCore {
  final exports = <String>[], operations = <String>[];
  final targets = <String?>[];
  final albums = <String?>[];
  final orderedNames = <bool>[];
  bool failSecond = true;
  int permissionRequests = 0;
  @override
  Future<Json> gallerySavePermission() async {
    permissionRequests++;
    return {'granted': true};
  }

  @override
  Future<void> cancel(String jobId) async {}
  @override
  Future<Json> call(String op, [Json payload = const {}, String? job]) async {
    if (op == 'draft.load') return {'recipe': Recipe().data};
    if (op == 'media.export') {
      final path = payload['path'] as String;
      final id = path.endsWith('a.jpg') ? 'a' * 64 : 'b' * 64;
      final output = File(p.join(root, 'photo-versions', id, 'output.jpg'));
      await output.parent.create(recursive: true);
      await output.writeAsBytes([1, 2, 3]);
      exports.add(path);
      return {'id': id, 'path': output.path};
    }
    if (op == 'gallery.publish' || op == 'files.publishExport') {
      orderedNames.add(payload['orderedFilename'] == true);
      operations.add(payload['operationId'] as String);
      targets.add(payload['targetId'] as String?);
      albums.add(payload['albumPath'] as String?);
      if (payload['id'] == 'b' * 64 && failSecond) {
        throw const AppFailure('系统授权改变');
      }
      return {
        'published': true,
        'identifier': '${payload['id']}/L0/001',
        if (payload['albumPath'] != null) ...{
          'verified': true,
          'albumPath': payload['albumPath'],
        },
        if (op == 'files.publishExport') ...{
          'verified': true,
          'targetId': payload['targetId'],
          'filename':
              '${p.basenameWithoutExtension(payload['filename'] as String)}_001.jpg',
        },
      };
    }
    throw AppFailure(op);
  }
}

void main() {
  for (final (targetId, legacy, albumPath) in [
    (null, false, null),
    ('c' * 32, false, null),
    (null, true, null),
    (null, false, 'DCIM/假日/'),
  ]) {
    test(
      'a restarted ${albumPath != null
          ? 'selected phone album'
          : legacy
          ? 'legacy album'
          : targetId == null
          ? 'album'
          : 'folder'} batch preserves publication identity and completed receipts',
      () async {
        final folder = await Directory.systemTemp.createTemp(
          'huevia-batch-publish-',
        );
        addTearDown(() => folder.delete(recursive: true));
        final core = PublicationCore()..root = folder.path;
        final state = AppState(core);
        final originals = Directory(p.join(folder.path, 'originals'));
        await originals.create();
        for (final name in ['a.jpg', 'b.jpg']) {
          final file = File(p.join(originals.path, name));
          await file.writeAsBytes([1]);
          state.photos.add(Photo(file.path, name, {}));
        }
        final rows = state.photos
            .map((v) => <String, dynamic>{'id': v.path, 'name': v.name})
            .toList();
        final first = BatchExport(state, rows, phone: false);
        await first.run(
          systemAlbum: targetId == null,
          targetId: targetId,
          targetName: targetId == null ? null : '导出文件',
          albumPath: albumPath,
        );
        expect(first.completed, 2);
        expect(first.published, 1);
        expect(first.done, false);
        final failedOperation = first.items[1].operation;
        if (legacy) {
          final oldJournal = object(
            jsonDecode(await first.journal.readAsString()),
          );
          oldJournal.remove('orderedFilename');
          await first.journal.writeAsString(jsonEncode(oldJournal));
        }
        first.dispose();
        core.failSecond = false;
        final resumed = BatchExport(state, rows, phone: false);
        addTearDown(resumed.dispose);
        expect(resumed.locked, true);
        expect(resumed.saveToGallery, targetId == null);
        expect(resumed.targetId, targetId);
        expect(resumed.targetName, targetId == null ? null : '导出文件');
        expect(resumed.published, 1);
        await resumed.run();
        expect(resumed.done, true);
        expect(resumed.published, 2);
        expect(
          core.exports.length,
          2,
        ); // Neither native JPEG is generated again.
        expect(core.operations, [
          first.items[0].operation,
          failedOperation,
          failedOperation,
        ]);
        expect(core.targets, [targetId, targetId, targetId]);
        expect(core.albums, [albumPath, albumPath, albumPath]);
        expect(resumed.albumPath, albumPath);
        expect(core.orderedNames, [true, true, !legacy]);
        expect(core.permissionRequests, targetId == null ? 2 : 0);
        final before = resumed.items.map((i) => i.operation).toSet();
        await resumed.newTask();
        expect(resumed.locked, false);
        expect(resumed.completed, 0);
        expect(resumed.items.any((i) => before.contains(i.operation)), false);
      },
    );
  }
}
