import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:huevia/camera_live.dart';
import 'package:huevia/camera_live_card.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/main.dart';
import 'package:huevia/theme.dart';
import 'package:path/path.dart' as p;

import 'camera_live_test.dart' as fixtures;

class LivePanelCore226 extends fixtures.LiveCore {
  final operations = <String>[];
  final recordPhotos = <Json>[];
  @override
  Json status() => {
    ...super.status(),
    'liveFormats': ['jpeg', 'raw'],
  };
  @override
  Json project() => {
    ...super.project(),
    'presetId': '',
    'photos': recordPhotos,
    'tasks': [],
  };
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    operations.add(operation);
    switch (operation) {
      case 'photo.stars':
        return {'keys': []};
      case 'gallery.access':
        return {'access': 'none'};
      case 'camera.page':
        return {'items': [], 'hasMore': false, 'nextOffset': 0};
      case 'online.page':
      case 'online.search':
        return {'items': [], 'categories': [], 'page': 1, 'hasMore': false};
      case 'community.activity':
        return {'items': [], 'unread': 0};
    }
    if (operation.startsWith('project.') ||
        operation.startsWith('camera.live.') ||
        operation == 'camera.status' ||
        operation == 'camera.download' ||
        operation == 'media.info' ||
        operation == 'media.export') {
      return super.call(operation, payload, jobId);
    }
    return {};
  }
}

Future<void> until(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  for (var i = 0; i < 80 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue, reason: reason);
  await tester.pump();
}

Future<(LivePanelCore226, fixtures.LiveState, Directory)> fixture() async {
  final directory = Directory.systemTemp.createTempSync('huevia-live-ui-226-');
  Directory('${directory.path}/originals').createSync();
  final core = LivePanelCore226()
    ..root = directory.path
    ..usePreset = false;
  final state = fixtures.LiveState(core)..ready = true;
  return (core, state, directory);
}

Future<void> close(
  WidgetTester tester,
  fixtures.LiveState state,
  LivePanelCore226 core,
  Directory directory,
) async {
  await state.controller.stop();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  tester.binding.imageCache.clear();
  tester.binding.imageCache.clearLiveImages();
  state.dispose();
  await core.events.close();
  expect(
    p.isWithin(Directory.systemTemp.absolute.path, directory.absolute.path),
    isTrue,
  );
  expect(p.basename(directory.path).startsWith('huevia-live-ui-226-'), isTrue);
  await tester.runAsync(() async {
    for (var i = 0; ; i++) {
      try {
        await directory.delete(recursive: true);
        break;
      } on FileSystemException {
        if (i == 20) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });
}

Widget panel(fixtures.LiveState state, {Future<bool> Function()? onConnect}) =>
    MaterialApp(
      theme: hueviaTheme(Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: CameraLiveCard(
            state: state,
            projectId: 'project-one',
            projectName: '人像拍摄',
            hasPreset: false,
            onConnect: onConnect,
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'A central start keeps the same preview bounds and freezes the mutually exclusive format',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (core, state, directory) = await fixture();
      addTearDown(() => close(tester, state, core, directory));
      await tester.pumpWidget(panel(state));
      await tester.pumpAndSettle();
      final selector = find.byKey(const Key('live-transfer-format'));
      expect(
        tester.widget<SegmentedButton<CameraLiveFormat>>(selector).selected,
        {CameraLiveFormat.jpeg},
      );
      final frame = find.byKey(const Key('live-transfer-preview'));
      final action = find.byKey(const Key('live-transfer-action'));
      expect(
        (tester.getRect(frame).center - tester.getRect(action).center).distance,
        lessThan(.5),
      );
      await tester.tap(find.text('RAW 原片'));
      await tester.pump();
      expect(
        tester.widget<SegmentedButton<CameraLiveFormat>>(selector).selected,
        {CameraLiveFormat.raw},
      );
      final before = tester.getRect(frame);
      await tester.tap(action);
      await until(
        tester,
        () => find
            .widgetWithText(FilledButton, '开始拍摄')
            .hitTestable()
            .evaluate()
            .isNotEmpty,
        'The RAW confirmation must be ready for an explicit start',
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.textContaining('新拍摄的 RAW 原片'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('开始拍摄'));
      await until(
        tester,
        () =>
            state.controller.phase == CameraLivePhase.watching &&
            find
                .widgetWithText(FilledButton, '停止边拍边传')
                .hitTestable()
                .evaluate()
                .isNotEmpty,
        'Explicit RAW start must reach the actual controller',
      );
      expect(core.lastStart['format'], 'raw');
      expect(tester.getRect(frame), before);
      expect(
        tester
            .widget<SegmentedButton<CameraLiveFormat>>(selector)
            .onSelectionChanged,
        isNull,
      );
      await tester.tap(find.text('JPEG'), warnIfMissed: false);
      await tester.pump();
      expect(state.controller.selectedFormat, CameraLiveFormat.raw);
      expect(tester.getRect(action).top, greaterThanOrEqualTo(before.bottom));
      await tester.tap(find.text('停止边拍边传'));
      await until(
        tester,
        () =>
            !state.controller.active &&
            !state.controller.working &&
            state.controller.phase == CameraLivePhase.stopped,
        'Stop must release format selection',
      );
      expect(
        tester
            .widget<SegmentedButton<CameraLiveFormat>>(selector)
            .onSelectionChanged,
        isNotNull,
      );
      expect(tester.getRect(frame), before);
      expect(
        (tester.getRect(frame).center - tester.getRect(action).center).distance,
        lessThan(.5),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A committed photograph keeps the preview frame and never carries a large action over its pixels',
    (tester) async {
      final (core, state, directory) = await fixture();
      addTearDown(() => close(tester, state, core, directory));
      File('../../app/src/main/assets/preset-showcase/portrait-smile.jpg')
          .copySync('${directory.path}/originals/${fixtures.sha(2)}.jpg');
      await tester.pumpWidget(panel(state));
      await tester.pumpAndSettle();
      final frame = find.byKey(const Key('live-transfer-preview'));
      final before = tester.getRect(frame);
      await tester.tap(find.byKey(const Key('live-transfer-action')));
      await until(
        tester,
        () => find
            .widgetWithText(FilledButton, '开始拍摄')
            .hitTestable()
            .evaluate()
            .isNotEmpty,
        'The JPEG confirmation must be ready for an explicit start',
      );
      await tester.tap(find.text('开始拍摄'));
      await until(
        tester,
        () =>
            state.controller.phase == CameraLivePhase.watching &&
            find
                .widgetWithText(FilledButton, '停止边拍边传')
                .hitTestable()
                .evaluate()
                .isNotEmpty,
        'JPEG capture must start',
      );
      core.visible = [fixtures.shot(2)];
      await tester.runAsync(() => state.controller.pollOnce());
      await until(
        tester,
        () => find
            .descendant(of: frame, matching: find.byType(RawImage))
            .evaluate()
            .any(
              (element) => (element.renderObject as RenderImage).image != null,
            ),
        'Committed ordinary photo must really decode',
      );
      expect(tester.getRect(frame), before);
      expect(
        find.descendant(of: frame, matching: find.byType(FilledButton)),
        findsNothing,
      );
      expect(
        tester.getRect(find.byKey(const Key('live-transfer-action'))).top,
        greaterThanOrEqualTo(before.bottom),
      );
      await tester.tap(find.text('停止边拍边传'));
      await until(
        tester,
        () =>
            !state.controller.active &&
            !state.controller.working &&
            state.controller.phase == CameraLivePhase.stopped,
        'Stop must complete',
      );
      expect(tester.getRect(frame), before);
      expect(
        find.descendant(of: frame, matching: find.byType(FilledButton)),
        findsNothing,
      );
      expect(
        find.descendant(of: frame, matching: find.byType(RawImage)),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byKey(const Key('live-transfer-action'))).top,
        greaterThanOrEqualTo(before.bottom),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'The central action and external stop remain usable at 320 wide with double text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final (core, state, directory) = await fixture();
      addTearDown(() => close(tester, state, core, directory));
      await tester.pumpWidget(panel(state));
      await tester.pumpAndSettle();
      final frame = find.byKey(const Key('live-transfer-preview'));
      final button = find.byKey(const Key('live-transfer-action'));
      expect(
        (tester.getRect(frame).center - tester.getRect(button).center).distance,
        lessThan(.5),
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(
        () => state.controller.start('project-one', '人像拍摄'),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('停止边拍边传'));
      await tester.pumpAndSettle();
      expect(find.text('停止边拍边传').hitTestable(), findsOneWidget);
      expect(
        tester.getRect(button).top,
        greaterThanOrEqualTo(tester.getRect(frame).bottom),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final hasPhoto in [false, true]) {
    testWidgets(
      'A retired live transport reconnects once without hiding its retained photo: $hasPhoto',
      (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final (core, state, directory) = await fixture();
        addTearDown(() => close(tester, state, core, directory));
        File('../../app/src/main/assets/preset-showcase/portrait-smile.jpg')
            .copySync('${directory.path}/originals/${fixtures.sha(2)}.jpg');
        var connects = 0;
        await tester.pumpWidget(
          panel(
            state,
            onConnect: () async {
              connects++;
              return false;
            },
          ),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => state.controller.start('project-one', '人像拍摄'),
        );
        if (hasPhoto) {
          core.visible = [fixtures.shot(2)];
          await tester.runAsync(() => state.controller.pollOnce());
        }
        await tester.pumpAndSettle();
        final frame = find.byKey(const Key('live-transfer-preview'));
        final before = tester.getRect(frame);
        core.connected = false;
        await tester.runAsync(() => state.controller.pollOnce());
        await tester.pumpAndSettle();
        expect(state.controller.transportRetired, isTrue);
        expect(state.controller.active, isFalse);
        expect(
          core.persistentActive,
          isTrue,
          reason: 'Disconnect must retain the resumable journal',
        );
        expect(tester.getRect(frame), before);
        expect(find.text('连接相机'), findsOneWidget);
        final action = find.byKey(const Key('live-transfer-action'));
        if (hasPhoto) {
          expect(state.controller.latestPhoto, isNotNull);
          expect(
            find.descendant(of: frame, matching: find.byType(FilledButton)),
            findsNothing,
          );
          expect(
            tester.getRect(action).top,
            greaterThanOrEqualTo(before.bottom),
          );
        } else {
          expect(
            (tester.getRect(action).center - before.center).distance,
            lessThan(.5),
          );
        }
        await tester.tap(find.text('连接相机'));
        await tester.pump();
        expect(connects, 1);
        expect(
          state.controller.active,
          isFalse,
          reason:
              'Opening connection does not silently resume a stale transport',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Live records use the root shell overlay and the last row is clickable where the tabs used to cover it',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (core, state, directory) = await fixture();
      addTearDown(() => close(tester, state, core, directory));
      for (var i = 0; i < 24; i++) {
        final path = '${directory.path}/originals/${fixtures.sha(100 + i)}.png';
        File(path).writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
          ),
        );
        core.recordPhotos.add({
          'path': path,
          'name': 'RECORD_$i.PNG',
          'raw': false,
          'width': 1,
          'height': 1,
        });
      }
      await tester.pumpWidget(HueviaApp(state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.text('同步').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('边拍边传'));
      await until(
        tester,
        () => find
            .byKey(const Key('live-transfer-records'))
            .evaluate()
            .isNotEmpty,
        'Real Sync project view must load',
      );
      await tester.ensureVisible(
        find.byKey(const Key('live-transfer-records')),
      );
      await tester.pumpAndSettle();
      final router = GoRouter.of(tester.element(find.byType(CameraLivePanel)));
      final nav = find.ancestor(
        of: find.text('设置').last,
        matching: find.byType(HueGlass),
      );
      final navRect = tester.getRect(nav);
      await tester.runAsync(() => state.controller.start('project-one', '拍摄'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('live-transfer-records')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('live-transfer-records-sheet')),
        findsOneWidget,
      );
      expect(find.text('设置').hitTestable(), findsNothing);
      final recordList = find.byKey(const Key('live-transfer-records-list'));
      final recordScrollable = find.descendant(
        of: recordList,
        matching: find.byType(Scrollable),
      );
      expect(recordScrollable, findsOneWidget);
      final recordPosition = tester
          .state<ScrollableState>(recordScrollable)
          .position;
      // Keep the pointer inside the sheet for each gesture. A single enormous
      // drag can finish outside the surface without reaching the list's tail.
      for (
        var scroll = 0;
        scroll < 20 && recordPosition.extentAfter > .5;
        scroll++
      ) {
        await tester.drag(recordList, const Offset(0, -280));
        await tester.pumpAndSettle();
      }
      expect(recordPosition.extentAfter, lessThanOrEqualTo(.5));
      final last = find.byKey(const ValueKey('live-record-photo-23'));
      expect(last.hitTestable(), findsOneWidget);
      expect(
        tester.getRect(last).center.dy,
        inInclusiveRange(navRect.top, navRect.bottom),
        reason: 'The regression must actually exercise the former tabbar-covered area',
      );
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('RECORD_23.PNG'),
        ),
        findsOneWidget,
      );
      expect(router.routeInformationProvider.value.uri.path, '/camera');
      expect(state.controller.active, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('live-transfer-records-sheet')),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('live-transfer-records-sheet')),
        findsNothing,
      );
      expect(router.routeInformationProvider.value.uri.path, '/camera');
      expect(state.controller.active, isTrue);
      expect(core.operations, isNot(contains('camera.disconnect')));
      expect(core.operations, isNot(contains('camera.live.stop')));
      expect(tester.takeException(), isNull);
    },
  );
}
