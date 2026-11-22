import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/photo_collage.dart';
import 'package:huevia/theme.dart';

class CollageExportCore extends HueviaCore {
  CollageExportCore(Directory directory) {
    root = directory.path;
  }
  int previews = 0, fullRenders = 0, exports = 0, publications = 0;
  final operations = <String>[];
  @override
  Future<Json> gallerySavePermission() async => {'granted': true};
  @override
  Future<String> importFile(XFile file, {required bool preset}) async {
    final bytes = await File(file.path).readAsBytes();
    final target = File('$root/originals/${sha256.convert(bytes)}.png');
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes);
    return target.path;
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'draft.load') {
      return {'sourceSha': 'a' * 64, 'recipe': Recipe().data};
    }
    if (operation == 'media.reviewPreview' ||
        operation == 'media.detailRender') {
      final full = operation == 'media.detailRender';
      if (full) fullRenders++;
      final file = File(
        '$root/previews/${full ? 'full-$fullRenders' : 'review-${++previews}'}.png',
      );
      await file.parent.create(recursive: true);
      await File(payload['path'] as String).copy(file.path);
      return {
        'path': file.path,
        'width': 10,
        'height': 10,
        'sourceSha': 'a' * 64,
        'temporary': true,
        'fullResolution': full,
      };
    }
    if (operation == 'media.info') return {'width': 10, 'height': 10};
    if (operation == 'version.list') return {'items': <Json>[]};
    if (operation == 'export.describe') {
      return {
        'sourceSha': sha256
            .convert(await File(payload['path'] as String).readAsBytes())
            .toString(),
        'qualities': List.generate(
          4,
          (_) => {'size': 'original', 'quality': 95},
        ),
      };
    }
    if (operation == 'media.export') {
      final hash = sha256
          .convert(await File(payload['path'] as String).readAsBytes())
          .toString();
      if (payload['expectedSourceSha'] != hash) {
        throw const AppFailure('原图与打开导出设置时不同，请重新打开照片。');
      }
      exports++;
      return {'id': 'c' * 64};
    }
    if (operation == 'gallery.publish') {
      publications++;
      operations.add(payload['operationId'] as String);
      if (publications == 1) throw const AppFailure('相册暂时不可用，请重试');
      return {'published': true, 'uri': 'content://test/collage237'};
    }
    throw AppFailure(operation);
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  await tester.pump();
  for (var i = 0; i < 400 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
  await tester.pump();
  expect(
    ready(),
    isTrue,
    reason: tester
        .widgetList<Text>(find.byType(Text))
        .map((v) => v.data)
        .join(' | '),
  );
}

void main() {
  testWidgets(
    'download generates a separate photo and retries publication without re-export or duplicate operation',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'huevia-collage237-export-',
      );
      final core = CollageExportCore(directory), state = AppState(core);
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
      );
      final original = File('${directory.path}/originals/${'a' * 64}.png');
      original.parent.createSync();
      original.writeAsBytesSync(bytes);
      state.photos = [
        Photo(original.path, 'original.png', {'width': 10, 'height': 10}),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: PhotoCollagePage(
            state: state,
            rows: [
              {'id': original.path},
              {'id': original.path},
            ],
          ),
        ),
      );
      await _until(
        tester,
        () =>
            tester
                .widget<IconButton>(find.byKey(const Key('download-collage')))
                .onPressed !=
            null,
      );
      await tester.tap(find.byKey(const Key('download-collage')));
      await _until(
        tester,
        () =>
            core.publications == 1 &&
            tester
                    .widget<IconButton>(
                      find.byKey(const Key('download-collage')),
                    )
                    .onPressed !=
                null,
      );
      expect(core.fullRenders, 2);
      expect(core.exports, 1);
      expect(state.photos, hasLength(2));
      await tester.tap(find.byKey(const Key('download-collage')));
      await _until(
        tester,
        () =>
            core.publications == 2 &&
            tester
                    .widget<IconButton>(
                      find.byKey(const Key('download-collage')),
                    )
                    .onPressed !=
                null,
      );
      expect(core.fullRenders, 2);
      expect(core.exports, 1);
      expect(core.operations[0], core.operations[1]);
      expect(find.text('拼图已保存到手机相册'), findsOneWidget);
      expect(original.readAsBytesSync(), bytes);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        try {
          await directory.delete(recursive: true);
        } on FileSystemException catch (error) {
          if (!Platform.isWindows || error.osError?.errorCode != 32) rethrow;
        }
      });
    },
  );
}
