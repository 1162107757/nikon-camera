import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_downloads.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/main.dart';
import 'package:huevia/sync_tools_dock.dart';
import 'package:huevia/theme.dart';

import 'camera_test.dart' as fixtures;

class SyncCore extends fixtures.CameraCore {
  SyncCore(super.preview);
  final events = StreamController<dynamic>.broadcast();
  @override
  Stream<dynamic> get operationProgress => events.stream;
  final pages = <Json>[];
  final next = Completer<Json>();
  bool failNext = false;
  bool connected = true;
  String notice = '';
  int statusCalls = 0;
  bool showQueue = false;
  final queueGet = Completer<Json>();
  final cancelled = <String>[];

  Json batch(int first, int count, {bool more = true, int? offset}) => {
    'items': [
      for (var i = first; i < first + count; i++)
        {
          'handle': i,
          'name': 'DSC_$i.JPG',
          'bytes': 1024,
          'width': 100,
          'height': 100,
        },
    ],
    'nextOffset': offset ?? first + count - 1,
    'hasMore': more,
  };

  @override
  Future<void> cancel(String id) async => cancelled.add(id);

  @override
  Future<Json> call(String op, [Json payload = const {}, String? jobId]) async {
    if (op == 'camera.page') {
      pages.add(Map.of(payload));
      if (payload['offset'] == 0) return batch(1, 24);
      if (failNext) throw const AppFailure('后续目录读取失败');
      return next.future;
    }
    if (op == 'downloads.list') {
      return {
        'items': showQueue
            ? [
                {'id': 'owned-queue', 'done': 0, 'count': 1, 'phase': 'ready'},
              ]
            : [],
      };
    }
    if (op == 'downloads.get') return queueGet.future;
    if (op == 'gallery.access') return {'access': 'none'};
    if (op == 'photo.stars') return {'keys': []};
    if (op == 'camera.status') {
      statusCalls++;
      return {
        'connected': connected,
        'session': connected ? 'z6-fixture' : '',
        'model': connected ? 'Z 6_2' : '',
        'connectionNotice': notice,
        'mode': connected ? 'photos' : 'none',
        'inventoryReady': pages.isNotEmpty,
      };
    }
    if (op == 'camera.thumbnail') {
      return super.call(op, payload, jobId);
    }
    return {};
  }
}

class SyncTestState extends AppState {
  SyncTestState(super.core);
  void signIn(String id) {
    session = {
      'user': {'id': id},
    };
    notifyListeners();
  }
}

Future<SyncCore> syncCore() async {
  final base = await fixtures.fixture();
  final core = SyncCore(base.preview);
  addTearDown(core.events.close);
  return core;
}

void main() {
  testWidgets(
    'A late queue-history result never installs another account record into the floating window',
    (tester) async {
      final core = (await syncCore())..showQueue = true;
      final state = SyncTestState(core)..signIn('first-owner');
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: CameraDownloadsPage(state: state, embedded: true),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('0 / 1 张'));
      await tester.pump();
      core.showQueue = false;
      state.signIn('second-owner');
      await tester.pumpAndSettle();
      core.queueGet.complete({
        'id': 'owned-queue',
        'phase': 'done',
        'items': [
          {'name': 'from-first-account.jpg', 'phase': 'completed'},
        ],
      });
      await tester.pumpAndSettle();
      expect(state.cameraDownloads.current, isNull);
      expect(find.text('0 / 1 张'), findsNothing);
      expect(find.text('from-first-account.jpg'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'Background maintenance events do not resume previews and foreground rechecks the connection',
    (tester) async {
      final core = await syncCore();
      final state = AppState(core);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await fixtures.open(tester, state);
      final before = core.statusCalls;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      core.connected = false;
      core.notice = '相机 Wi-Fi 连接已断开，请重新连接后继续。';
      core.events.add({'kind': 'cameraConnectionChanged'});
      await tester.pumpAndSettle();
      expect(core.statusCalls, before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(core.statusCalls, before + 1);
      expect(find.text(core.notice), findsOneWidget);
      expect(core.pages, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'Idle connection loss updates the visible Sync page without retrying or reconnecting',
    (tester) async {
      final core = await syncCore();
      final state = AppState(core);
      await fixtures.open(tester, state);
      core.connected = false;
      core.notice = '相机 Wi-Fi 连接已断开，请重新连接后继续。';
      core.events.add({'kind': 'cameraConnectionChanged'});
      await tester.pumpAndSettle();
      expect(find.text('未连接'), findsOneWidget);
      expect(find.text(core.notice), findsOneWidget);
      expect(core.pages, hasLength(1));
      expect(core.calls.where((c) => c.$1 == 'camera.connect'), isEmpty);
      expect(core.cancelled, isEmpty);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'Camera photos load next page on scroll once and deduplicate handles',
    (tester) async {
      final core = await syncCore();
      final state = AppState(core);
      await fixtures.open(tester, state);
      expect(core.pages, hasLength(1));
      expect(find.text('读取更多照片'), findsNothing);
      final scroll = find.byKey(const PageStorageKey('sync-camera-photos'));
      await tester.drag(scroll, const Offset(0, -2400));
      await tester.pump();
      expect(core.pages, hasLength(2));
      expect(core.pages.last['offset'], 24);
      await tester.drag(scroll, const Offset(0, -400));
      await tester.pump();
      expect(core.pages, hasLength(2));
      core.next.complete(core.batch(24, 24, more: false, offset: 48));
      await fixtures.settleImages(tester);
      await tester.drag(scroll, const Offset(0, 1800));
      await fixtures.settleImages(tester);
      expect(find.text('47 张'), findsOneWidget);
      expect(core.pages, hasLength(2));
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'Failed next page preserves loaded photos and waits for explicit retry',
    (tester) async {
      final core = (await syncCore())..failNext = true;
      final state = AppState(core);
      await fixtures.open(tester, state);
      final scroll = find.byKey(const PageStorageKey('sync-camera-photos'));
      await tester.drag(scroll, const Offset(0, -1400));
      await fixtures.settleImages(tester);
      expect(core.pages, hasLength(2));
      await tester.drag(scroll, const Offset(0, -400));
      await fixtures.settleImages(tester);
      expect(core.pages, hasLength(2));
      expect(find.text('重试加载'), findsOneWidget);
      core.failNext = false;
      core.next.complete(core.batch(25, 12, more: false, offset: 36));
      await tester.ensureVisible(find.text('重试加载'));
      await tester.tap(find.text('重试加载'));
      await fixtures.settleImages(tester);
      expect(core.pages, hasLength(3));
      await tester.drag(scroll, const Offset(0, 2000));
      await fixtures.settleImages(tester);
      expect(find.text('36 张'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'Sync tool sheets close without replacing the grid or disconnecting the camera',
    (tester) async {
      final core = await syncCore();
      final state = AppState(core);
      await fixtures.open(tester, state);
      await tester.tap(find.byTooltip('相机工具'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下载队列'));
      await tester.pumpAndSettle();
      expect(find.byType(CameraDownloadsPage), findsOneWidget);
      await tester.tap(find.byTooltip('关闭下载队列'));
      await tester.pumpAndSettle();
      expect(find.text('24+ 张'), findsOneWidget);
      expect(core.pages, hasLength(1));
      expect(core.cancelled, isEmpty);
      expect(core.calls.where((c) => c.$1 == 'camera.disconnect'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'Camera tools appear only on Sync and stay local when tabs switch',
    (tester) async {
      final core = await syncCore();
      final state = AppState(core)..ready = true;
      await tester.pumpWidget(HueviaApp(state: state));
      await tester.pumpAndSettle();
      expect(find.byType(SyncToolsDock), findsNothing);
      await tester.tap(find.text('同步').last);
      await fixtures.settleImages(tester);
      expect(find.byType(SyncToolsDock), findsOneWidget);
      await tester.tap(find.byTooltip('相机工具'));
      await tester.pumpAndSettle();
      for (final tab in ['预设', '相册', '设置']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        expect(find.byType(SyncToolsDock), findsNothing);
      }
      expect(core.cancelled, isEmpty);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'Dock remains usable on small phones with large text and reduced motion',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.dark),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(375, 667),
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomRight,
                child: SyncToolsDock(
                  onDownloads: () {},
                  onRemote: () {},
                  onSlots: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('相机工具'));
      await tester.pumpAndSettle();
      expect(find.text('遥控拍照'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
