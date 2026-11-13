import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/batch_export.dart';
import 'package:huevia/domain.dart';
import 'package:path/path.dart' as p;

class PublicationCore extends HueviaCore {
  final exports = <String>[], operations = <String>[];
  bool failSecond = true;
  @override
  Future<Json> gallerySavePermission() async => {'granted': true};
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
    if (op == 'gallery.publish') {
      operations.add(payload['operationId'] as String);
      if (payload['id'] == 'b' * 64 && failSecond) {
        throw const AppFailure('系统授权改变');
      }
      return {'published': true, 'identifier': '${payload['id']}/L0/001'};
    }
    throw AppFailure(op);
  }
}

void main() {
  test(
    'a restarted batch preserves publication identity and completed receipts',
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
      await first.run(systemAlbum: true);
      expect(first.completed, 2);
      expect(first.published, 1);
      expect(first.done, false);
      final failedOperation = first.items[1].operation;
      first.dispose();
      core.failSecond = false;
      final resumed = BatchExport(state, rows, phone: false);
      addTearDown(resumed.dispose);
      expect(resumed.locked, true);
      expect(resumed.saveToGallery, true);
      expect(resumed.published, 1);
      await resumed.run();
      expect(resumed.done, true);
      expect(resumed.published, 2);
      expect(core.exports.length, 2); // Neither native JPEG is generated again.
      expect(core.operations, [
        first.items[0].operation,
        failedOperation,
        failedOperation,
      ]);
      final before = resumed.items.map((i) => i.operation).toSet();
      await resumed.newTask();
      expect(resumed.locked, false);
      expect(resumed.completed, 0);
      expect(resumed.items.any((i) => before.contains(i.operation)), false);
    },
  );
}
