import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera.dart';
import 'package:huevia/camera_slots.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';

import 'camera_intent_test.dart' show IntentCameraCore;

class _SyncCore extends IntentCameraCore {
  final events = StreamController<dynamic>.broadcast(sync: true);
  String? notice;
  Object? pageFailure;
  bool disconnectOnPageFailure = false;
  bool indexed = false;
  @override
  Stream<dynamic> get operationProgress => events.stream;
  int get pages => calls.where((call) => call.$1 == 'camera.page').length;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'camera.page') {
      calls.add((operation, Map.of(payload), jobId));
      if (pageFailure != null) {
        if (disconnectOnPageFailure) {
          connected = false;
          notice = '相机 Wi-Fi 连接已断开，请重新连接后继续。';
        }
        throw pageFailure!;
      }
      indexed = true;
      return {'items': [], 'nextOffset': 0, 'hasMore': false};
    }
    if (operation == 'camera.connect') indexed = false;
    final result = await super.call(operation, payload, jobId);
    if (operation == 'camera.slots.open') mode = 'slots';
    if (operation == 'camera.status') {
      return {
        ...result,
        'inventoryReady': connected && mode == 'photos' && indexed,
        'connectionNotice': ?notice,
      };
    }
    return result;
  }

  void changed() => events.add({'kind': 'cameraConnectionChanged'});
}

Future<AppState> _open(
  WidgetTester tester,
  _SyncCore core, {
  bool visible = true,
}) async {
  final state = AppState(core)..cameraVisible.value = visible;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    await core.events.close();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.light),
      home: CameraPage(state: state),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Future<void> _connect(WidgetTester tester) async {
  final button = find.byKey(const Key('camera-connect'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Visible Sync connects then reads once without a second browse action or empty-album reload loop',
    (tester) async {
      final core = _SyncCore();
      final state = await _open(tester, core);
      await tester.tap(find.widgetWithText(FilledButton, '连接相机'));
      await tester.pumpAndSettle();
      expect(core.pages, 0);
      await _connect(tester);
      expect(core.pages, 1);
      expect(
        core.calls.where((call) => call.$1 == 'camera.connect'),
        hasLength(1),
      );
      expect(
        core.calls.firstWhere((call) => call.$1 == 'camera.page').$2['session'],
        core.photoSession,
      );
      expect(find.text('浏览相机照片'), findsNothing);
      expect(find.text('相机已连接。需要浏览时，再读取照片。'), findsNothing);
      expect(find.text('Nikon Z6II · 已连接'), findsOneWidget);
      core.changed();
      await tester.pumpAndSettle();
      state.cameraVisible.value = false;
      await tester.pumpAndSettle();
      state.cameraVisible.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.text('已下载'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('相机照片'));
      await tester.pumpAndSettle();
      expect(core.pages, 1);
      expect(core.cancelled, isEmpty);
    },
  );

  testWidgets(
    'An already connected hidden Sync waits for foreground visibility then reads exactly once',
    (tester) async {
      final core = _SyncCore()..connected = true;
      final state = await _open(tester, core, visible: false);
      expect(core.pages, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      state.cameraVisible.value = true;
      await tester.pumpAndSettle();
      core.changed();
      await tester.pumpAndSettle();
      expect(core.pages, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(core.pages, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(core.pages, 1);
      expect(core.calls.where((call) => call.$1 == 'camera.connect'), isEmpty);
    },
  );

  testWidgets(
    'A current photo-read failure survives healthy status and retries only on the explicit retry action',
    (tester) async {
      final core = _SyncCore()
        ..connected = true
        ..pageFailure = const AppFailure('存储卡读取失败，请重试。');
      final state = await _open(tester, core);
      expect(core.pages, 1);
      expect(find.text('存储卡读取失败，请重试。'), findsOneWidget);
      expect(find.text('重试读取照片'), findsOneWidget);
      expect(find.text('浏览相机照片'), findsNothing);
      core.changed();
      await tester.pumpAndSettle();
      state.cameraVisible.value = false;
      state.cameraVisible.value = true;
      await tester.pumpAndSettle();
      expect(core.pages, 1);
      expect(find.text('存储卡读取失败，请重试。'), findsOneWidget);
      core.pageFailure = null;
      await tester.tap(find.text('重试读取照片'));
      await tester.pumpAndSettle();
      expect(core.pages, 2);
      expect(find.text('存储卡读取失败，请重试。'), findsNothing);
      expect(find.text('Nikon Z6II · 已连接'), findsOneWidget);
      expect(
        core.calls.where((call) => call.$1 == 'camera.disconnect'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'A real disconnected notice remains visible until a newer healthy status retires only that notice',
    (tester) async {
      const notice = '相机 Wi-Fi 连接已断开，请重新连接后继续。';
      final core = _SyncCore()..connected = true;
      await _open(tester, core);
      expect(core.pages, 1);
      core
        ..connected = false
        ..notice = notice;
      core.changed();
      await tester.pumpAndSettle();
      expect(find.text(notice), findsOneWidget);
      expect(find.text('未连接'), findsOneWidget);
      core.connected = true;
      // The healthy native channel is authoritative even if its last historical
      // notice is still included; this event is status-only, not an implicit IO.
      core.changed();
      await tester.pumpAndSettle();
      expect(find.text('Nikon Z6II · 已连接'), findsOneWidget);
      expect(find.text(notice), findsNothing);
      expect(core.pages, 1);
    },
  );

  testWidgets(
    'A fatal photo read refreshes closed native status before displaying a disconnected header',
    (tester) async {
      const notice = '相机 Wi-Fi 连接已断开，请重新连接后继续。';
      final core = _SyncCore()
        ..connected = true
        ..disconnectOnPageFailure = true
        ..pageFailure = const AppFailure(notice);
      await _open(tester, core);
      expect(core.pages, 1);
      expect(
        core.calls.where((call) => call.$1 == 'camera.status'),
        hasLength(2),
      );
      expect(find.text('未连接'), findsOneWidget);
      expect(find.text('Nikon Z6II · 已连接'), findsNothing);
      expect(find.text(notice), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '连接相机'), findsOneWidget);
      expect(find.text('浏览相机照片'), findsNothing);
      expect(core.calls.where((call) => call.$1 == 'camera.connect'), isEmpty);
      expect(core.cancelled, isEmpty);
    },
  );

  testWidgets(
    'Connecting for slots performs no photo IO while the child owns the channel and reads on return to Sync',
    (tester) async {
      final core = _SyncCore();
      await _open(tester, core);
      final dynamic page = tester.state(find.byType(CameraPage));
      unawaited(page.openConnectedTool(slots: true) as Future<void>);
      await tester.pumpAndSettle();
      await _connect(tester);
      expect(find.byType(CameraSlotsPage), findsOneWidget);
      expect(core.pages, 0);
      core.changed();
      await tester.pumpAndSettle();
      expect(core.pages, 0);
      Navigator.of(tester.element(find.byType(CameraSlotsPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(CameraSlotsPage), findsNothing);
      expect(core.pages, 1);
      expect(
        core.calls.firstWhere((call) => call.$1 == 'camera.page').$2['session'],
        core.photoSession,
      );
      expect(core.cancelled, isEmpty);
    },
  );
}
