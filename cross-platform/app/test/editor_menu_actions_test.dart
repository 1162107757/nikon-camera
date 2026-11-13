import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/theme.dart';

import 'editor_menu_test.dart' as fixture;

class ActionsCore extends fixture.MenuCore {
  ActionsCore(super.directory) {
    final names = ['BRIGHTNESS', 'EXPOSURE', 'CONTRAST', 'VIBRANCE'];
    schema = {
      'parameters': List.generate(
        17,
        (i) => {
          'index': i,
          'name': i < names.length ? names[i] : 'VALUE$i',
          'label': '参数$i',
          'min': -100,
          'max': 100,
          'help': '说明',
        },
      ),
    };
    draft = Recipe().data
      ..addAll({
        'presetId': 'old-look',
        'localData': 'existing-portrait-regions-patches',
        'geometry': {'turns': 1},
        'border': {'template': 3},
        'curves': {
          'master': [0, 0, 1, 1],
        },
      });
    draft['values'] = [70, 32, 80, 90, ...List.filled(13, 0)];
  }
  Completer<Json>? cleanup;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'media.cleanupAnalyze') {
      calls.add((operation, payload));
      return cleanup?.future ?? {'cleanupData': 'actual-cleanup'};
    }
    if (operation == 'media.retouchAnalyze') {
      calls.add((operation, payload));
      return {'localData': 'existing-portrait-regions-patches+real-mask'};
    }
    if (operation == 'media.retouchChange') {
      calls.add((operation, payload));
      return {
        'localData': 'existing-portrait-regions-patches+real-mask+natural',
      };
    }
    if (operation == 'photo.star') {
      calls.add((operation, payload));
      return {
        'keys': payload['starred'] == true
            ? [Photo(payload['path'] as String, '', const {}).starKey]
            : [],
      };
    }
    return super.call(operation, payload, jobId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ActionsCore core;
  late AppState state;
  late Photo photo;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('huevia-actions-');
    Directory('${directory.path}/previews').createSync();
    Directory('${directory.path}/originals').createSync();
    File('${directory.path}/previews/preview.png').writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
      ),
    );
    core = ActionsCore(directory.path);
    photo = Photo('${directory.path}/originals/source.jpg', '照片', const {});
    state = AppState(core)
      ..session = {
        'user': {'id': 'alice'},
      };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('cc.huevia/events'),
          (_) async => null,
        );
  });
  tearDown(() async {
    state.dispose();
    imageCache.clear();
    imageCache.clearLiveImages();
    for (var i = 0; i < 100; i++) {
      try {
        await directory.delete(recursive: true);
        break;
      } on FileSystemException catch (error) {
        if (Platform.isWindows && error.osError?.errorCode == 32) {
          debugPrint(
            'FIXTURE_CLEANUP_AFTER_PROCESS ${jsonEncode(directory.path)}',
          );
          break;
        }
        if (i >= 99) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.dark),
        home: EditorPage(state: state, photo: photo),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> action(WidgetTester tester, String name) async {
    await tester.tap(find.bySemanticsLabel('更多照片操作和重置'));
    await tester.pumpAndSettle();
    final target = find.descendant(
      of: find.byKey(const ValueKey('photo-actions-menu')),
      matching: find.text(name),
    );
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    imageCache.clear();
    imageCache.clearLiveImages();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pump();
  }

  testWidgets(
    'Opening and closing readonly details does not resave a draft or rerender a fresh main preview',
    (tester) async {
      await open(tester);
      final start = core.calls.length;
      await action(tester, '查看细节');
      await tester.tap(find.byTooltip('返回照片编辑'));
      await tester.pumpAndSettle();
      final after = core.calls.skip(start);
      expect(
        after.where(
          (c) =>
              c.$1 == 'draft.save' ||
              c.$1 == 'media.preview' ||
              c.$1 == 'media.export' ||
              c.$1.startsWith('version.'),
        ),
        isEmpty,
      );
      await close(tester);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'Favourite toggles the real original and reset colour preserves filter portrait regions geometry and border',
    (tester) async {
      await open(tester);
      await action(tester, '收藏照片');
      expect(state.starredPhotos, contains(photo.starKey));
      expect(
        core.calls.singleWhere((c) => c.$1 == 'photo.star').$2,
        containsPair('owner', 'alice'),
      );
      await action(tester, '取消收藏');
      expect(state.starredPhotos, isEmpty);
      await action(tester, '重置调色');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      final next = object(
        core.calls.lastWhere((c) => c.$1 == 'media.preview').$2['recipe'],
      );
      expect(next['values'], everyElement(0));
      expect(next.containsKey('curves'), isFalse);
      expect(next['presetId'], 'old-look');
      expect(next['localData'], 'existing-portrait-regions-patches');
      expect(next['geometry'], {'turns': 1});
      expect(next['border'], {'template': 3});
      await close(tester);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
  testWidgets(
    'Portrait quick optimization commits one complete analysis and preserves existing full local data',
    (tester) async {
      await open(tester);
      await action(tester, '快速优化');
      await tester.tap(find.bySemanticsLabel('快速优化，人像'));
      await tester.pumpAndSettle();
      expect(core.draft['presetId'], 'old-look');
      expect(core.draft['geometry'], {'turns': 1});
      expect(core.draft['border'], {'template': 3});
      expect(
        core.draft['localData'],
        'existing-portrait-regions-patches+real-mask+natural',
      );
      expect(core.draft['cleanup'], {'amount': 20, 'haze': 25, 'noise': 65});
      final analyzed = core.calls
          .singleWhere((c) => c.$1 == 'media.retouchAnalyze')
          .$2;
      expect(analyzed['localData'], 'existing-portrait-regions-patches');
      expect(analyzed['expectedSourceSha'], 'source-sha');
      expect(
        core.calls
            .singleWhere((c) => c.$1 == 'media.retouchChange')
            .$2['value'],
        {'NATURAL': 45},
      );
      expect(
        core.calls.where(
          (c) => c.$1 == 'media.export' || c.$1.startsWith('gallery.'),
        ),
        isEmpty,
      );
      await close(tester);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
  testWidgets(
    'Cancelling held quick analysis rejects late success without saving or changing staged recipe',
    (tester) async {
      await open(tester);
      await action(tester, '快速优化');
      core.cleanup = Completer<Json>();
      final before = jsonEncode(core.draft), start = core.calls.length;
      await tester.tap(find.bySemanticsLabel('快速优化，自然'));
      await tester.pump();
      await tester.pump();
      expect(find.text('取消分析'), findsOneWidget);
      await tester.tap(find.text('取消分析'));
      await tester.pump();
      core.cleanup!.complete({'cleanupData': 'late-success'});
      await tester.pumpAndSettle();
      expect(jsonEncode(core.draft), before);
      expect(
        core.calls.skip(start).where((c) => c.$1 == 'draft.save'),
        isEmpty,
      );
      expect(core.calls.where((c) => c.$1 == 'media.retouchChange'), isEmpty);
      await close(tester);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
