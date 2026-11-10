import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:huevia/domain.dart';

class PhotoCore extends HueviaCore {
  PhotoCore(String directory) {
    root = directory;
  }
  int active = 0, maximum = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'library.list') return {'items': []};
    if (operation == 'account.current') return {};
    if (operation != 'media.info') throw AppFailure(operation);
    active++;
    if (active > maximum) maximum = active;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    active--;
    return {'width': 256, 'height': 192, 'raw': false};
  }
}

void main() {
  test('Photo index survives a changed application container path', () async {
    final directory = await Directory.systemTemp.createTemp(
      'huevia-photo-relocation-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final before = await Directory('${directory.path}/old-container').create();
    final original = await File('${directory.path}/source.jpg')
        .writeAsBytes([11, 22, 33]);
    final state = AppState(PhotoCore(before.path));
    final photo = await state.importPhoto(XFile(original.path));
    await state.updatePhoto(photo, {'rawSource': photo.path});
    final after = await before.rename('${directory.path}/new-container');
    final reopened = AppState(PhotoCore(after.path));
    await reopened.initialize();
    expect(reopened.failure, isNull);
    expect(reopened.photos, hasLength(1));
    expect(p.isWithin(after.path, reopened.photos.single.path), isTrue);
    expect(
      reopened.photos.single.info['rawSource'],
      reopened.photos.single.path,
    );
    expect(await File(reopened.photos.single.path).readAsBytes(), [11, 22, 33]);
  });
  test(
    'Concurrent imports commit a complete index and retain distinct originals',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'huevia-photo-commit-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final root = await Directory('${directory.path}/private').create(),
          core = PhotoCore('${directory.path}/private');
      final first = await File('${directory.path}/first.jpg')
          .writeAsBytes([1, 2, 3, 4]);
      final second = await File('${directory.path}/second.jpg')
          .writeAsBytes([4, 3, 2, 1]);
      final state = AppState(core);
      await Future.wait([
        state.importPhoto(XFile(first.path)),
        state.importPhoto(XFile(second.path)),
      ]);
      final saved = jsonDecode(
        await File('${root.path}/photos-index.json').readAsString(),
      ) as List;
      expect(saved.length, 2);
      expect(state.photos.length, 2);
      expect(core.maximum, 1);
      expect(state.photos.map((photo) => photo.path).toSet().length, 2);
      expect(await first.readAsBytes(), [1, 2, 3, 4]);
      expect(await second.readAsBytes(), [4, 3, 2, 1]);
    },
  );
  test(
    'Index write failure leaves the visible library intact and permits retry',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'huevia-photo-rollback-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final root = await Directory('${directory.path}/private').create();
      final blocker = await Directory('${root.path}/photos-index.json')
          .create();
      final source = await File('${directory.path}/source.jpg')
          .writeAsBytes([10, 20, 30]);
      final state = AppState(PhotoCore(root.path));
      await expectLater(
        state.importPhoto(XFile(source.path)),
        throwsA(isA<FileSystemException>()),
      );
      expect(state.photos, isEmpty);
      await blocker.delete();
      final photo = await state.importPhoto(XFile(source.path));
      expect(state.photos.single.path, photo.path);
      expect(await source.readAsBytes(), [10, 20, 30]);
      expect(
        Directory(root.path)
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.part')),
        isEmpty,
      );
      await expectLater(
        state.registerPhoto(source.path, 'outside.jpg', {}),
        throwsA(isA<AppFailure>()),
      );
    },
  );
}
