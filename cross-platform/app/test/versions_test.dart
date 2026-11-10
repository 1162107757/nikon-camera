import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';
import 'package:huevia/versions.dart';

class VersionsCore extends HueviaCore {
  VersionsCore(String directory) {
    root = directory;
  }
  final List<(String, Json)> calls = [];
  @override
  Future<void> cancel(String jobId) async {}
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    final version = {
      'id': 'version-1',
      'name': '保存时的秋色 · 70%',
      'path': '$root/photo-versions/frozen.jpg',
      'sourcePath': '$root/originals/source.png',
      'sourceAvailable': true,
      'createdAt': 1794300000000,
      'width': 4000,
      'height': 3000,
    };
    if (operation == 'version.list') {
      return {
        'items': [version],
      };
    }
    if (operation == 'version.open') return version;
    if (operation == 'media.originalPreview') {
      return {'path': '$root/previews/frozen.png'};
    }
    if (operation == 'version.recipe') {
      return {
        'recipe': {
          'schema': 1,
          'presetId': 'deleted-preset',
          'strength': 70,
          'values': List.filled(17, 0),
        },
      };
    }
    throw AppFailure(operation);
  }
}

void main() {
  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets(
      'Saved version viewing is bounded and readonly; restore and delete stay explicit at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final directory = Directory.systemTemp.createTempSync(
          'huevia-versions-',
        );
        Directory('${directory.path}/previews').createSync();
        final preview = File('${directory.path}/previews/frozen.png');
        preview.writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
          ),
        );
        addTearDown(() async {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          await tester.runAsync(() => directory.delete(recursive: true));
        });
        final core = VersionsCore(directory.path);
        Json? restored;
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    restored = await Navigator.push<Json>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VersionsPage(
                          core: core,
                          owner: 'alice',
                          path: '${directory.path}/originals/source.png',
                        ),
                      ),
                    );
                  },
                  child: const Text('查看版本'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('查看版本'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('保存时的秋色 · 70%'));
        await tester.pumpAndSettle();
        expect(find.text('已保存成品'), findsOneWidget);
        final request = core.calls.singleWhere(
          (call) => call.$1 == 'media.originalPreview',
        );
        expect(
          request.$2['path'],
          '${directory.path}/photo-versions/frozen.jpg',
        );
        expect(request.$2['owner'], 'alice');
        expect(core.calls.any((call) => call.$1.startsWith('draft.')), false);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('版本操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除成品'));
        await tester.pumpAndSettle();
        expect(find.text('删除这个成品版本？'), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(core.calls.any((call) => call.$1 == 'version.delete'), false);
        await tester.tap(find.byTooltip('版本操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('恢复此配方'));
        await tester.pumpAndSettle();
        expect(restored?['presetId'], 'deleted-preset');
        expect(restored?['strength'], 70);
        expect(core.calls.last.$2['owner'], 'alice');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
