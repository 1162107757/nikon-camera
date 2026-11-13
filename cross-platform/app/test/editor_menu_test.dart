import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/copy_adjustments.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/editor_details.dart';
import 'package:huevia/recipes.dart';
import 'package:huevia/retouch_workspace.dart';
import 'package:huevia/theme.dart';
import 'package:huevia/versions.dart';

import 'editor_test.dart' as fixtures;

class MenuCore extends fixtures.DraftCore {
  MenuCore(super.directory);
  Json draft = Recipe().data..['values'] = [0, 32, ...List.filled(15, 0)];
  String rawSha = 'raw-sha', versionSha = 'source-sha';
  int portraitPreviewSerial = 0;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    switch (operation) {
      case 'media.preview':
      case 'media.originalPreview':
      case 'media.reviewPreview':
      case 'media.rawPreview':
        calls.add((operation, payload));
        final path = '$root/previews/menu-${++portraitPreviewSerial}.png';
        File(path).writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
          ),
        );
        return {'path': path, 'width': 1, 'height': 1};
      case 'media.retouchDescribe':
        calls.add((operation, payload));
        return {
          'localData': payload['localData'] ?? '',
          'regionId': '',
          'patchCount': 0,
          'tones': [],
          'portrait': {
            'tonePerFace': false,
            'hasSkinMask': false,
            'faces': [],
            'skin': {'toneId': 0, 'toneRgb': 0, 'toneAmount': 0},
            'body': [
              {
                'left': .25,
                'top': .25,
                'right': .75,
                'bottom': .9,
                'amount': 0,
              },
              {'left': .3, 'top': .5, 'right': .7, 'bottom': .94, 'amount': 0},
              {
                'left': .23,
                'top': .48,
                'right': .77,
                'bottom': .9,
                'amount': 0,
              },
            ],
          },
        };
      case 'media.retouchAnalyze':
        calls.add((operation, payload));
        return {'regionId': '', 'selectionOverlay': null};
      case 'draft.load':
        calls.add((operation, payload));
        return {'sourceSha': 'source-sha', 'recipe': draft};
      case 'draft.save':
        calls.add((operation, payload));
        draft = object(jsonDecode(jsonEncode(payload['recipe'])));
        return {'sourceSha': 'source-sha', 'recipe': draft};
      case 'recipe.list':
        calls.add((operation, payload));
        return {
          'items': [
            {'id': 'saved', 'name': '个人秋色', 'summary': '已保存的调节'},
          ],
        };
      case 'version.list':
        calls.add((operation, payload));
        return {
          'items': [
            {
              'id': 'version',
              'name': '已保存成品',
              'createdAt': 1000,
              'width': 80,
              'height': 60,
              'sourceAvailable': true,
            },
          ],
        };
      case 'version.recipe':
        calls.add((operation, payload));
        return {'sourceSha': versionSha, 'recipe': Recipe().data};
      case 'source.inspect':
        calls.add((operation, payload));
        return {
          'format': 'NEF',
          'sourceSha': payload['path'].toString().endsWith('.nef')
              ? rawSha
              : 'source-sha',
        };
    }
    return super.call(operation, payload, jobId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late MenuCore core;
  late AppState state;
  late Photo photo;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('huevia-menu-');
    Directory('${directory.path}/previews').createSync();
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
    );
    for (final name in ['preview.png', 'raw.png']) {
      File('${directory.path}/previews/$name').writeAsBytesSync(png);
    }
    core = MenuCore(directory.path);
    photo = Photo('${directory.path}/source.jpg', '测试照片', {
      'rawSource': '${directory.path}/source.nef',
      'rawSourceSha': 'raw-sha',
    });
    state = AppState(core)
      ..session = {
        'user': {'id': 'alice'},
      }
      ..photos = [
        photo,
        Photo('${directory.path}/target.jpg', '目标照片', const {}),
      ];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('cc.huevia/events'),
          (_) async => null,
        );
  });
  tearDown(() async {
    state.dispose();
    for (var attempt = 0; ; attempt++) {
      try {
        await directory.delete(recursive: true);
        break;
      } on FileSystemException catch (error) {
        if (Platform.isWindows && error.osError?.errorCode == 32) {
          // Windows codecs can keep a mapped fixture until the tester exits.
          // The outer runner removes this exact owned directory after exit.
          debugPrint(
            'FIXTURE_CLEANUP_AFTER_PROCESS ${jsonEncode(directory.path)}',
          );
          break;
        }
        if (error.osError?.errorCode != 32 || attempt >= 150) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });
  Future<void> openEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.dark),
        home: EditorPage(state: state, photo: photo),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String action) async {
    await tester.tap(find.bySemanticsLabel('更多照片操作和重置'));
    await tester.pumpAndSettle();
    final target = find.descendant(
      of: find.byKey(const ValueKey('photo-actions-menu')),
      matching: find.text(action),
    );
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'All visible editor menu pages use the saved current draft and return to the editor',
    (tester) async {
      await openEditor(tester);
      await menu(tester, '照片配方');
      expect(find.byType(RecipesPage), findsOneWidget);
      expect(find.text('个人秋色'), findsOneWidget);
      expect(
        core.calls.indexWhere((c) => c.$1 == 'draft.save'),
        lessThan(core.calls.indexWhere((c) => c.$1 == 'recipe.list')),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await menu(tester, '复制调色');
      expect(find.text('目标照片'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await menu(tester, '照片版本');
      expect(find.byType(VersionsPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await menu(tester, '查看细节');
      expect(find.byType(EditorDetailsPage), findsOneWidget);
      await tester.tap(find.text('细节预览'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RAW 显影'));
      await tester.pumpAndSettle();
      expect(
        core.calls.lastWhere((c) => c.$1 == 'source.inspect').$2,
        containsPair('expectedSourceSha', 'raw-sha'),
      );
      expect(core.calls.where((c) => c.$1 == 'media.rawPreview'), isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
  testWidgets(
    'Restore original persists immediately and an old menu cannot run after account change',
    (tester) async {
      await openEditor(tester);
      await menu(tester, '还原原图');
      expect(core.draft['values'], everyElement(0));
      await tester.tap(find.bySemanticsLabel('更多照片操作和重置'));
      await tester.pumpAndSettle();
      state.session = {
        'user': {'id': 'bob'},
      };
      state.notifyListeners();
      final before = core.calls.length;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo-actions-menu')), findsNothing);
      await tester.pumpAndSettle();
      expect(
        core.calls.skip(before).where((c) => c.$1.startsWith('recipe.')),
        isEmpty,
      );
      expect(find.byType(RecipesPage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
  testWidgets(
    'Saved version from another source is rejected without changing the editor recipe',
    (tester) async {
      core.versionSha = 'different-source';
      await openEditor(tester);
      final before = jsonEncode(core.draft);
      await menu(tester, '照片版本');
      await tester.tap(find.byTooltip('版本操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复此配方'));
      await tester.pumpAndSettle();
      expect(find.textContaining('成品与当前原图不一致'), findsOneWidget);
      expect(find.byType(VersionsPage), findsOneWidget);
      expect(jsonEncode(core.draft), before);
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pumpAndSettle();
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
  testWidgets('Linked RAW with changed bytes is rejected before RAW preview', (
    tester,
  ) async {
    core.rawSha = 'different-raw';
    await openEditor(tester);
    await menu(tester, '查看细节');
    await tester.tap(find.text('细节预览'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('RAW 显影'));
    await tester.pumpAndSettle();
    expect(find.textContaining('原始 RAW 已改变'), findsOneWidget);
    expect(core.calls.where((c) => c.$1 == 'media.rawPreview'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }, timeout: const Timeout(Duration(seconds: 45)));
  testWidgets('Copy page stops at an account change before any mutation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.dark),
        home: CopyAdjustmentsPage(
          state: state,
          source: photo,
          recipe: Recipe().data,
          owner: 'alice',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('目标照片'));
    await tester.pumpAndSettle();
    state.session = {
      'user': {'id': 'bob'},
    };
    state.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('照片或账号已变化，请返回重新打开。'), findsOneWidget);
    expect(find.text('目标照片'), findsNothing);
    expect(core.calls.where((c) => c.$1 == 'photo.copy'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pumpAndSettle();
  }, timeout: const Timeout(Duration(seconds: 45)));
  testWidgets(
    'Portrait tab opens the shared workspace directly and returns without the two intermediate cards',
    (tester) async {
      await openEditor(tester);
      await tester.tap(find.text('人像'));
      await tester.pumpAndSettle();
      expect(find.byType(RetouchWorkspace), findsOneWidget);
      expect(find.text('人像精修'), findsNothing);
      expect(find.text('涂抹自动修补'), findsNothing);
      expect(find.text('修补'), findsOneWidget);
      await tester.tap(find.byTooltip('取消人像精修'));
      await tester.pumpAndSettle();
      expect(find.byType(RetouchWorkspace), findsNothing);
      expect(find.byType(EditorPage), findsOneWidget);
      expect(find.text('人像精修'), findsNothing);
      expect(find.text('涂抹自动修补'), findsNothing);
      await tester.tap(find.text('人像'));
      await tester.pumpAndSettle();
      expect(find.byType(RetouchWorkspace), findsOneWidget);
      await tester.tap(find.byTooltip('取消人像精修'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      imageCache.clear();
      imageCache.clearLiveImages();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
