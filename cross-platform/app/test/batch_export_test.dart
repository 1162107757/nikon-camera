import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/album_batch.dart';
import 'package:huevia/batch_export.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';
import 'package:path/path.dart' as p;

class BatchReferenceCore extends HueviaCore {
  Json? developed;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'media.rawDevelop') developed = payload;
    throw const AppFailure('Stop after inspecting the native RAW request');
  }
}

class BatchCore extends HueviaCore {
  final calls = <String>[];
  final recipes = <Json>[];
  bool failSecond = false;
  int secondExposure = 3;
  Future<void> Function()? afterFirst;
  @override
  Future<void> cancel(String jobId) async {}
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    final path = payload['path'] as String;
    calls.add('$operation:$path');
    if (operation == 'draft.load') {
      final recipe = Recipe();
      recipe.setValue(0, path.endsWith('a.jpg') ? 2 : secondExposure);
      return {'recipe': recipe.data};
    }
    if (operation == 'media.export') {
      recipes.add(object(payload['recipe']));
      if (path.endsWith('a.jpg')) await afterFirst?.call();
      if (path.endsWith('b.jpg') && failSecond) {
        throw const AppFailure('测试编码失败');
      }
      return {'path': '/private/versions/${path.split('/').last}'};
    }
    throw AppFailure(operation);
  }
}

void main() {
  (AppState, BatchCore, List<Json>) setup() {
    final core = BatchCore();
    final directory = Directory.systemTemp.createTempSync('huevia-batch-');
    core.root = directory.path;
    addTearDown(() => directory.delete(recursive: true));
    final state = AppState(core)
      ..photos = [
        const Photo('/private/originals/a.jpg', '第一张.jpg', {}),
        const Photo('/private/originals/b.jpg', '第二张.jpg', {}),
      ];
    return (
      state,
      core,
      state.photos
          .map(
            (photo) => <String, dynamic>{
              'id': photo.path,
              'name': photo.name,
              'date': 0,
            },
          )
          .toList(),
    );
  }

  test('Batch freezes every recipe before export and retains per-photo adjustments', () async {
    final (state, core, rows) = setup();
    core.afterFirst = () async => core.secondExposure = 12;
    final batch = BatchExport(state, rows, phone: false);
    addTearDown(batch.dispose);
    await batch.run(presetId: 'preset', amount: 42);
    expect(
      core.calls.take(2).every((call) => call.startsWith('draft.load')),
      isTrue,
    );
    expect(core.recipes.map((recipe) => (recipe['values'] as List).first), [
      2,
      3,
    ]);
    expect(
      core.recipes.every(
        (recipe) => recipe['presetId'] == 'preset' && recipe['strength'] == 42,
      ),
      isTrue,
    );
    expect(batch.completed, 2);
  });
  test('Batch retries failures without repeating completed outputs or changing frozen settings', () async {
    final (state, core, rows) = setup();
    core.failSecond = true;
    final batch = BatchExport(state, rows, phone: false);
    addTearDown(batch.dispose);
    await batch.run();
    expect(batch.completed, 1);
    expect(batch.failed, 1);
    core.failSecond = false;
    core.secondExposure = 20;
    await batch.run(presetId: 'must-not-replace', exportSize: 'share');
    expect(batch.completed, 2);
    expect(batch.failed, 0);
    expect(
      core.calls
          .where((call) => call == 'media.export:/private/originals/a.jpg')
          .length,
      1,
    );
    expect((core.recipes.last['values'] as List).first, 3);
    expect(core.recipes.last['presetId'], '');
    expect(batch.size, 'full');
  });
  test(
    'Cancellation keeps completed outputs and resumes only remaining photos',
    () async {
      final (state, core, rows) = setup();
      final batch = BatchExport(state, rows, phone: false);
      addTearDown(batch.dispose);
      core.afterFirst = batch.cancel;
      await batch.run();
      expect(batch.completed, 1);
      expect(batch.stopped, isTrue);
      expect(core.recipes.length, 1);
      core.afterFirst = null;
      await batch.run();
      expect(batch.completed, 2);
      expect(core.recipes.length, 2);
    },
  );
  test(
    'Changing account prevents remaining exports and all later retries',
    () async {
      final (state, core, rows) = setup();
      final batch = BatchExport(state, rows, phone: false);
      addTearDown(batch.dispose);
      core.afterFirst = () async {
        state.session = {
          'user': {'id': 'other'},
        };
        state.notifyListeners();
      };
      await batch.run();
      expect(batch.accountInvalid, isTrue);
      expect(core.recipes.length, 1);
      await batch.run();
      expect(core.recipes.length, 1);
    },
  );
  test('Batch refuses duplicate sources and an unbounded selection', () {
    final (state, _, rows) = setup();
    expect(
      () => BatchExport(state, [rows.first, rows.first], phone: false),
      throwsA(isA<AppFailure>()),
    );
    expect(
      () => BatchExport(
        state,
        List.generate(101, (i) => {'id': '$i'}),
        phone: false,
      ),
      throwsA(isA<AppFailure>()),
    );
  });
  test('Batch RAW preparation carries the persisted JPEG reference into the current private root', () async {
    final core = BatchReferenceCore()..root = '/new';
    final state = AppState(core)
      ..photos = [
        Photo('/new/originals/source.nef', 'SOURCE.NEF', {
          'raw': true,
          'rawJpegReference': {
            'relativePath': 'originals/reference.jpg',
            'name': 'PAIR.JPG',
            'sha256': 'a' * 64,
            'sourceSha': 'b' * 64,
          },
        }),
      ];
    final batch = BatchExport(state, [
      {'id': state.photos.first.path},
    ], phone: false);
    await expectLater(
      batch.prepare(batch.items.first),
      throwsA(isA<AppFailure>()),
    );
    expect(
      core.developed?['reference']['path'],
      p.normalize('/new/originals/reference.jpg'),
    );
    expect(core.developed?['reference']['sha256'], 'a' * 64);
    expect(core.developed?['reference']['sourceSha'], 'b' * 64);
    expect(core.developed?['settings']['colorMode'], 'CAMERA_JPEG');
    batch.dispose();
    state.dispose();
  });
  for (final viewport in const [
    (Size(375, 812), 1.0),
    (Size(375, 812), 2.0),
    (Size(812, 375), 2.0),
  ]) {
    testWidgets(
      'Album selection groups photos and opens a full-page batch with fixed actions at $viewport',
      (tester) async {
        final (state, _, rows) = setup();
        tester.view.physicalSize = viewport.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(viewport.$2)),
              child: child!,
            ),
            home: AlbumSelectionPage(state: state, rows: rows, phone: false),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '批量编辑'))
              .onPressed,
          isNull,
        );
        await tester.tap(find.byTooltip('日期未知，共 2 张，选择整组'));
        await tester.pumpAndSettle();
        expect(find.text('已选 2 张'), findsOneWidget);
        await tester.tap(find.text('批量编辑'));
        await tester.pumpAndSettle();
        expect(find.text('开始批量导出'), findsOneWidget);
        await tester.tap(find.text('开始批量导出'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('已保存 2/2 张'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('已保存 2/2 张'), findsOneWidget);
        expect(find.text('分享已完成的 2 张'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
