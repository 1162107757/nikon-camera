import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/legacy_theme.dart';
import 'package:huevia/main.dart';

class PreferenceCore extends HueviaCore {
  Json stored = {'schema': 1};
  bool failNextWrite = false;
  @override
  Stream<dynamic> get galleryChanges => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'ui.preferences.get') {
      return object(jsonDecode(jsonEncode(stored)));
    }
    if (operation == 'ui.preferences.set') {
      if (failNextWrite) {
        failNextWrite = false;
        throw const AppFailure('Storage busy');
      }
      stored = {...stored, ...payload};
      return object(jsonDecode(jsonEncode(stored)));
    }
    if (operation == 'account.current') return {};
    if (operation == 'photo.stars') return {'keys': []};
    if (operation == 'gallery.access') return {'access': 'none'};
    if (operation == 'library.list') {
      return {
        'items': [
          {
            'id': 'local-ncp',
            'sha256': 'a' * 64,
            'displayName': '本地 NCP',
            'fileFormat': 'NCP',
          },
          {
            'id': 'local-np3',
            'sha256': 'b' * 64,
            'displayName': '本地 NP3',
            'fileFormat': 'NP3',
          },
        ],
      };
    }
    if (operation == 'online.page' || operation == 'online.search') {
      return {
        'items': [
          {
            'id': 'online',
            'sha256': 'c' * 64,
            'name': '在线 NCP',
            'fileFormat': 'NCP',
          },
        ],
        'page': 1,
        'hasMore': false,
        'categories': [],
        'available': true,
      };
    }
    throw AppFailure(operation);
  }
}

void main() {
  Future<(PreferenceCore, Directory)> setup() async {
    final directory = await Directory.systemTemp.createTemp(
      'huevia-view-preferences-',
    );
    addTearDown(() => directory.delete(recursive: true));
    return (PreferenceCore()..root = directory.path, directory);
  }

  testWidgets(
    'Independent source filters survive rebuilding the whole application state',
    (tester) async {
      final (core, _) = (await tester.runAsync(setup))!;
      var state = AppState(core);
      await tester.runAsync(state.initialize);
      await tester.pumpWidget(HueviaApp(state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('筛选预设'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('NP3'));
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(find.text('本地 NP3'), findsOneWidget);
      expect(find.text('本地 NCP'), findsNothing);
      await tester.tap(find.text('在线预设'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('筛选预设'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已下载'));
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      state = AppState(core);
      await tester.runAsync(state.initialize);
      await tester.pumpWidget(HueviaApp(state: state));
      await tester.pumpAndSettle();
      expect(find.text('在线 NCP'), findsNothing);
      expect(find.text('没有符合条件的预设'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(CapsuleSwitch),
          matching: find.text('我的预设'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('本地 NP3'), findsOneWidget);
      expect(find.text('本地 NCP'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Album sort and RAW filter survive rebuilding the application', (
    tester,
  ) async {
    final (core, directory) = (await tester.runAsync(setup))!;
    final photos = [
      Photo('${directory.path}/originals/a.nef', '原片.nef', {'raw': true}),
      Photo('${directory.path}/originals/b.jpg', '照片.jpg', {}),
    ];
    Future<void> show() async {
      final state = AppState(core);
      await tester.runAsync(state.initialize);
      state.photos = photos;
      await tester.pumpWidget(HueviaApp(state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.text('相册').last);
      await tester.pumpAndSettle();
    }

    await show();
    await tester.tap(find.byTooltip('排序，拍摄时间，新到旧'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加时间'));
    await tester.tap(find.text('旧到新'));
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('相册更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只看 RAW 照片'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await show();
    expect(find.byTooltip('排序，添加时间，旧到新'), findsOneWidget);
    expect(find.bySemanticsLabel('原片.nef'), findsOneWidget);
    expect(find.bySemanticsLabel('照片.jpg'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test(
    'A failed preference commit does not block subsequent partial updates',
    () async {
      final (core, _) = await setup();
      final state = AppState(core);
      core.failNextWrite = true;
      await expectLater(
        state.saveUiPreferences({'presetSource': 'online'}),
        throwsA(isA<AppFailure>()),
      );
      await state.saveUiPreferences({'presetSource': 'local'});
      await state.saveUiPreferences({
        'album': {
          'source': 'app',
          'filter': 'raw',
          'added': false,
          'oldest': false,
        },
      });
      expect(state.uiPreferences['presetSource'], 'local');
      expect(state.uiPreferences['album']['filter'], 'raw');
    },
  );
}
