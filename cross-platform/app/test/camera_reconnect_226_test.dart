import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera.dart';
import 'package:huevia/camera_connection_view.dart';
import 'package:huevia/camera_live.dart';
import 'package:huevia/camera_photo_toolbar.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';

import 'camera_intent_test.dart' as intent;
import 'camera_live_test.dart' as live_fixture;

/// Uses real page routing, maintenance events and live-controller retirement.
/// The bridge gates model late RPC replies; they do not call private page APIs.
class ReconnectCore226 extends intent.IntentCameraCore {
  final events = StreamController<dynamic>.broadcast(sync: true);
  final liveBackend = live_fixture.LiveCore();
  final pageGates = Queue<Completer<Json>>();
  final statusGates = Queue<Completer<Json>>();
  final heldPages = <Completer<Json>>[];
  final heldStatuses = <Completer<Json>>[];
  Completer<Json>? postConnectStatus;

  @override
  Stream<dynamic> get operationProgress => events.stream;

  Json snapshot({String? session, bool? isConnected}) {
    final online = isConnected ?? connected;
    return {
      'connected': online,
      'session': online ? session ?? photoSession : '',
      'model': online ? 'Nikon Z6II' : '',
      'mode': online ? 'photos' : 'none',
      'inventoryReady': false,
      'cameraId': live_fixture.camera,
      'downloadCameraId': live_fixture.camera,
      'trustedCamera': true,
      'trustedDownloadCamera': true,
      'supportsLive': true,
      'liveFormats': ['jpeg', 'raw'],
      'liveRawFormat': 'NEF',
    };
  }

  static Json get emptyPage => {
    'items': <Json>[],
    'nextOffset': 0,
    'hasMore': false,
    'unavailableStorages': 0,
  };

  Completer<Json> holdPage() {
    final gate = Completer<Json>();
    pageGates.add(gate);
    heldPages.add(gate);
    return gate;
  }

  void maintenance() => events.add({
    'kind': 'cameraConnectionChanged',
    'connected': connected,
    'session': connected ? photoSession : '',
  });

  List<(String, Json, String?)> operations(String name) =>
      calls.where((call) => call.$1 == name).toList();

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'camera.connect') {
      final result = await super.call(operation, payload, jobId);
      final gate = postConnectStatus;
      if (gate != null) {
        postConnectStatus = null;
        statusGates.add(gate);
        heldStatuses.add(gate);
      }
      return result;
    }
    if (operation == 'camera.status' ||
        operation == 'camera.page' ||
        operation.startsWith('project.') ||
        operation.startsWith('camera.live.')) {
      calls.add((operation, Map<String, dynamic>.of(payload), jobId));
      if (operation == 'camera.status') {
        return statusGates.isEmpty
            ? snapshot()
            : await statusGates.removeFirst().future;
      }
      if (operation == 'camera.page') {
        return pageGates.isEmpty
            ? emptyPage
            : await pageGates.removeFirst().future;
      }
      liveBackend.connected = connected;
      liveBackend.session = photoSession;
      return liveBackend.call(operation, payload, jobId);
    }
    return super.call(operation, payload, jobId);
  }

  Future<void> close() async {
    if (connection != null && !connection!.isCompleted) {
      connection!.complete(snapshot(isConnected: false));
    }
    for (final gate in heldPages) {
      if (!gate.isCompleted) gate.complete(emptyPage);
    }
    for (final gate in heldStatuses) {
      if (!gate.isCompleted) gate.complete(snapshot());
    }
    await events.close();
    await liveBackend.events.close();
  }
}

class ReconnectState226 extends AppState {
  ReconnectState226(ReconnectCore226 super.core) {
    session = {
      'user': {'id': 'owner'},
    };
    live = CameraLive(this, automatic: false);
    cameraVisible.value = true;
  }
  late final CameraLive live;
  @override
  CameraLive get cameraLive => live;
  @override
  bool get cameraLiveActive => live.active;
  @override
  void dispose() {
    live.dispose();
    super.dispose();
  }
}

Future<void> untilReconnect(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  for (var attempt = 0; attempt < 80 && !ready(); attempt++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(ready(), isTrue, reason: reason);
  await tester.pump();
}

Future<void> tapReconnectUi(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  // jumpTo/ensureVisible changes the scroll offset before the next layout.
  // The tap must use the newly laid out position, not the old off-screen box.
  await tester.pump();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await tester.pump();
}

Future<void> mountCamera226(
  WidgetTester tester,
  ReconnectState226 state,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.light),
      home: CameraPage(state: state),
    ),
  );
  await tester.pump();
}

Future<void> closeReconnect226(
  WidgetTester tester,
  ReconnectState226 state,
  ReconnectCore226 core,
) async {
  await tester.pumpWidget(const SizedBox());
  state.dispose();
  await core.close();
  await tester.pump();
}

Future<void> openLiveTab226(WidgetTester tester) async {
  await tapReconnectUi(tester, find.text('边拍边传').first);
  await untilReconnect(
    tester,
    () => find.byKey(const Key('live-transfer-action')).evaluate().length == 1,
    'The real project tab must finish loading its live panel',
  );
}

void main() {
  testWidgets(
    'An explicit connection route keeps an existing snapshot and reconnects before returning',
    (tester) async {
      final core = ReconnectCore226()..connected = true;
      final state = ReconnectState226(core);
      final returned = ValueNotifier<bool?>(null);
      addTearDown(() async {
        await closeReconnect226(tester, state, core);
        returned.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  FilledButton(
                    key: const Key('explicit-connect-launcher'),
                    onPressed: () async {
                      returned.value = await connectCamera(context, state);
                    },
                    child: const Text('打开连接页'),
                  ),
                  ValueListenableBuilder<bool?>(
                    valueListenable: returned,
                    builder: (_, value, _) => Text('route-result:$value'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tapReconnectUi(
        tester,
        find.byKey(const Key('explicit-connect-launcher')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CameraConnectionView), findsOneWidget);
      expect(returned.value, isNull);
      expect(core.operations('camera.connect'), isEmpty);
      expect(find.byKey(const Key('camera-reconnect')), findsOneWidget);

      final connect = core.connection = Completer<Json>();
      await tapReconnectUi(tester, find.byKey(const Key('camera-reconnect')));
      await untilReconnect(
        tester,
        () => core.operations('camera.connect').length == 1,
        'The reconnect button must invoke the native connect operation',
      );
      final connectJob = core.operations('camera.connect').single.$3!;
      expect(returned.value, isNull);
      expect(find.byType(CameraConnectionView), findsOneWidget);
      connect.complete(core.snapshot(session: 'replacement-session'));
      await untilReconnect(
        tester,
        () => returned.value == true,
        'A successful new native session must automatically return',
      );
      await tester.pumpAndSettle();
      expect(find.byType(CameraConnectionView), findsNothing);
      expect(find.text('route-result:true'), findsOneWidget);
      expect(core.photoSession, 'replacement-session');
      expect(core.cancelled, isNot(contains(connectJob)));
      expect(core.operations('camera.page'), isEmpty);
      expect(core.operations('camera.disconnect'), isEmpty);
    },
  );

  testWidgets(
    'A real maintenance disconnect retires live capture and its CTA opens a successful connection',
    (tester) async {
      final core = ReconnectCore226()..connected = true;
      final state = ReconnectState226(core);
      addTearDown(() => closeReconnect226(tester, state, core));
      await state.live.start('project-one', '拍摄');
      expect(state.live.active, isTrue);
      await mountCamera226(tester, state);
      await openLiveTab226(tester);
      final statusCount = core.operations('camera.status').length;
      core.connected = false;
      core.maintenance();
      await untilReconnect(
        tester,
        () => !state.live.active && state.live.transportRetired,
        'Maintenance must inspect a disconnect even while live capture is exclusive',
      );
      expect(core.operations('camera.status').length, greaterThan(statusCount));
      expect(core.liveBackend.persistentActive, isTrue);
      expect(core.operations('camera.live.stop'), isEmpty);
      expect(core.operations('project.live.stop'), isEmpty);
      expect(core.operations('camera.page'), isEmpty);
      final action = find.byKey(const Key('live-transfer-action'));
      expect(
        find.descendant(of: action, matching: find.text('连接相机')),
        findsOneWidget,
      );
      final connect = core.connection = Completer<Json>();
      await tapReconnectUi(tester, action);
      await tester.pumpAndSettle();
      expect(find.byType(CameraConnectionView), findsOneWidget);
      await tapReconnectUi(tester, find.byKey(const Key('camera-connect')));
      await untilReconnect(
        tester,
        () => core.operations('camera.connect').length == 1,
        'Retirement must release the old live lease before reconnecting',
      );
      final connectJob = core.operations('camera.connect').single.$3!;
      connect.complete(
        core.snapshot(session: 'live-reconnected', isConnected: true),
      );
      await untilReconnect(
        tester,
        () => find.byType(CameraConnectionView).evaluate().isEmpty,
        'The live-tab connection route must return on native success',
      );
      await tester.pumpAndSettle();
      expect(state.live.active, isFalse);
      expect(state.live.transportRetired, isFalse);
      expect(core.operations('camera.live.start'), hasLength(1));
      expect(core.operations('camera.page'), isEmpty);
      expect(core.cancelled, isNot(contains(connectJob)));
      expect(find.text('Nikon Z6II · 已连接'), findsOneWidget);
    },
  );

  testWidgets(
    'Maintenance retires a held page and its late rows cannot replace a reconnected session',
    (tester) async {
      final core = ReconnectCore226()..connected = true;
      final oldPage = core.holdPage();
      final state = ReconnectState226(core);
      addTearDown(() => closeReconnect226(tester, state, core));
      await mountCamera226(tester, state);
      await untilReconnect(
        tester,
        () => core.operations('camera.page').length == 1,
        'Initial camera browsing must enter the held old-session read',
      );
      final oldJob = core.operations('camera.page').single.$3!;
      final statusCount = core.operations('camera.status').length;
      core.connected = false;
      core.maintenance();
      await untilReconnect(
        tester,
        () => find.widgetWithText(FilledButton, '连接相机').evaluate().length == 1,
        'The maintenance event must retire a busy old page and expose reconnect',
      );
      expect(core.operations('camera.status').length, greaterThan(statusCount));
      expect(core.cancelled.where((job) => job == oldJob), hasLength(1));
      final connect = core.connection = Completer<Json>();
      await tapReconnectUi(tester, find.widgetWithText(FilledButton, '连接相机'));
      await tester.pumpAndSettle();
      await tapReconnectUi(tester, find.byKey(const Key('camera-connect')));
      await untilReconnect(
        tester,
        () => core.operations('camera.connect').length == 1,
        'An old hung page must not keep the new native request busy',
      );
      final connectJob = core.operations('camera.connect').single.$3!;
      connect.complete(
        core.snapshot(session: 'new-photo-session', isConnected: true),
      );
      await untilReconnect(
        tester,
        () => core.operations('camera.page').length == 2,
        'Returning to camera photos must read the new session',
      );
      await untilReconnect(
        tester,
        () =>
            find.byType(CameraConnectionView).evaluate().isEmpty &&
            find.text('0 张').evaluate().length == 1 &&
            find.byKey(const Key('camera-raw-switch')).evaluate().length == 1 &&
            tester
                    .widget<Switch>(find.byKey(const Key('camera-raw-switch')))
                    .onChanged !=
                null,
        'The completed new-session page must be visible and browsing unlocked',
      );
      expect(
        core.operations('camera.page').last.$2['session'],
        'new-photo-session',
      );
      oldPage.complete({
        ...ReconnectCore226.emptyPage,
        'items': [live_fixture.shot(999)],
        'nextOffset': 1,
      });
      await tester.pumpAndSettle();
      expect(find.text('DSC_999.JPG'), findsNothing);
      expect(
        tester
            .widget<CameraPhotoToolbar>(find.byType(CameraPhotoToolbar))
            .count,
        0,
        reason: 'A late old row must not change the visible new-session count',
      );
      expect(find.text('0 张'), findsOneWidget);
      expect(core.photoSession, 'new-photo-session');
      expect(core.cancelled, isNot(contains(connectJob)));
      expect(core.cancelled.where((job) => job == oldJob), hasLength(1));
      expect(core.operations('camera.disconnect'), isEmpty);
      expect(
        tester
            .widget<Switch>(find.byKey(const Key('camera-raw-switch')))
            .onChanged,
        isNotNull,
      );
    },
  );

  testWidgets(
    'A returned live-tab connection releases the route lease before its held parent status',
    (tester) async {
      final core = ReconnectCore226()..connected = true;
      final state = ReconnectState226(core);
      addTearDown(() => closeReconnect226(tester, state, core));
      await state.live.start('project-one', '拍摄');
      await mountCamera226(tester, state);
      await openLiveTab226(tester);
      core.connected = false;
      core.maintenance();
      await untilReconnect(
        tester,
        () => state.live.transportRetired,
        'A real disconnect must expose the live-tab connection CTA',
      );
      await tapReconnectUi(
        tester,
        find.byKey(const Key('live-transfer-action')),
      );
      await tester.pumpAndSettle();
      final parentStatus = core.postConnectStatus = Completer<Json>();
      final connect = core.connection = Completer<Json>();
      await tapReconnectUi(tester, find.byKey(const Key('camera-connect')));
      await untilReconnect(
        tester,
        () => core.operations('camera.connect').length == 1,
        'Connect must start',
      );
      connect.complete(
        core.snapshot(session: 'live-new-session', isConnected: true),
      );
      await untilReconnect(
        tester,
        () =>
            core.heldStatuses.contains(parentStatus) &&
            core.statusGates.isEmpty,
        'The first route must close before the parent post-route status completes',
      );
      await tester.pumpAndSettle();
      expect(find.byType(CameraConnectionView), findsNothing);
      expect(parentStatus.isCompleted, isFalse);
      expect(core.operations('camera.page'), isEmpty);

      // This existing Sync tool uses openConnection(loadPhotos:false) while the
      // parent still has its disconnected snapshot. No direct callback calls.
      await tapReconnectUi(tester, find.byTooltip('相机工具'));
      await tapReconnectUi(tester, find.text('遥控拍照'));
      await tester.pumpAndSettle();
      expect(find.byType(CameraConnectionView), findsOneWidget);
      expect(find.byKey(const Key('camera-reconnect')), findsOneWidget);
      expect(parentStatus.isCompleted, isFalse);
      expect(core.operations('camera.connect'), hasLength(1));
      expect(core.operations('camera.page'), isEmpty);
      expect(core.cancelled, isEmpty);
    },
  );

  testWidgets(
    'Same-session maintenance preserves a held page epoch and releases browsing controls when it completes',
    (tester) async {
      final core = ReconnectCore226()..connected = true;
      final page = core.holdPage();
      final state = ReconnectState226(core);
      addTearDown(() => closeReconnect226(tester, state, core));
      await mountCamera226(tester, state);
      await untilReconnect(
        tester,
        () => core.operations('camera.page').length == 1,
        'The first page must start',
      );
      final rawSwitch = find.byKey(const Key('camera-raw-switch'));
      expect(tester.widget<Switch>(rawSwitch).onChanged, isNull);
      final statusCount = core.operations('camera.status').length;
      core.maintenance();
      await untilReconnect(
        tester,
        () => core.operations('camera.status').length == statusCount + 1,
        'Same-session maintenance must still inspect the native state during a read',
      );
      expect(tester.widget<Switch>(rawSwitch).onChanged, isNull);
      page.complete(ReconnectCore226.emptyPage);
      await untilReconnect(
        tester,
        () => tester.widget<Switch>(rawSwitch).onChanged != null,
        'Completing the same-session page must clear busy rather than latch it',
      );
      await tapReconnectUi(tester, rawSwitch);
      await untilReconnect(
        tester,
        () => core.operations('camera.page').length == 2,
        'An enabled filter must issue another real page read',
      );
      await tester.pumpAndSettle();
      expect(core.operations('camera.page').last.$2['raw'], isTrue);
      expect(
        core.operations('camera.page').last.$2['session'],
        'album-session',
      );
      expect(tester.widget<Switch>(rawSwitch).value, isTrue);
      expect(tester.widget<Switch>(rawSwitch).onChanged, isNotNull);
      expect(core.cancelled, isEmpty);
      expect(core.operations('camera.disconnect'), isEmpty);
      expect(find.text('Nikon Z6II · 已连接'), findsOneWidget);
    },
  );
}
