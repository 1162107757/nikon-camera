import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera.dart';
import 'package:huevia/camera_connection_view.dart';
import 'package:huevia/camera_live.dart';
import 'package:huevia/camera_live_card.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';

import 'camera_reconnect_226_test.dart' as reconnect;

class StartConnectionCore extends reconnect.ReconnectCore226 {
  bool supportsRaw = true;

  @override
  Json snapshot({String? session, bool? isConnected}) => {
    ...super.snapshot(session: session, isConnected: isConnected),
    'liveFormats': ['jpeg', if (supportsRaw) 'raw'],
  };
}

void portraitStartSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> closeStartConnection(
  WidgetTester tester,
  reconnect.ReconnectState226 state,
  StartConnectionCore core,
) async {
  final connection = core.connection;
  if (connection != null && !connection.isCompleted) {
    connection.complete(core.snapshot(isConnected: false));
  }
  for (final gate in [
    ...core.heldStatuses,
    ...core.statusGates,
    if (core.postConnectStatus != null) core.postConnectStatus!,
  ]) {
    if (!gate.isCompleted) gate.complete(core.snapshot());
  }
  for (final gate in core.heldPages) {
    if (!gate.isCompleted) gate.complete(reconnect.ReconnectCore226.emptyPage);
  }
  await state.live.stop();
  await reconnect.closeReconnect226(tester, state, core);
}

Future<void> mountStartCard(
  WidgetTester tester,
  reconnect.ReconnectState226 state,
) => tester.pumpWidget(
  MaterialApp(
    theme: hueviaTheme(Brightness.light),
    home: Builder(
      builder: (context) => Scaffold(
        body: SingleChildScrollView(
          child: CameraLiveCard(
            state: state,
            projectId: 'project-one',
            projectName: '人像拍摄',
            hasPreset: false,
            onConnect: () => connectCamera(context, state),
          ),
        ),
      ),
    ),
  ),
);

Finder get startAction => find.byKey(const Key('live-transfer-action'));
Finder get confirmStart => find.widgetWithText(FilledButton, '开始拍摄');

Future<void> waitForStartRoute(WidgetTester tester) => reconnect.untilReconnect(
  tester,
  () => find.byType(CameraConnectionView).evaluate().length == 1,
  'An invalid camera session must open the real connection route',
);

Future<void> waitForStartConfirmation(WidgetTester tester) =>
    reconnect.untilReconnect(
      tester,
      () =>
          find.byType(CameraConnectionView).evaluate().isEmpty &&
          confirmStart.hitTestable().evaluate().length == 1,
      'A successful connection must offer exactly one real start confirmation',
    );

void main() {
  for (final format in CameraLiveFormat.values) {
    testWidgets(
      'Live tab and disconnected Start connect before one ${format.name} confirmation without loading camera photos',
      (tester) async {
        portraitStartSize(tester);
        final core = StartConnectionCore();
        final state = reconnect.ReconnectState226(core);
        addTearDown(() => closeStartConnection(tester, state, core));
        await reconnect.mountCamera226(tester, state);
        await reconnect.untilReconnect(
          tester,
          () => find.text('未连接').evaluate().isNotEmpty,
          'The main Sync page must finish its disconnected snapshot',
        );

        // Selecting the tab itself connects but must not start a producer or
        // show a capture confirmation. Cancel leaves the actual Live panel.
        await reconnect.tapReconnectUi(tester, find.text('边拍边传').first);
        await waitForStartRoute(tester);
        expect(confirmStart, findsNothing);
        expect(core.operations('camera.connect'), isEmpty);
        expect(core.operations('camera.live.start'), isEmpty);
        await tester.binding.handlePopRoute();
        await reconnect.untilReconnect(
          tester,
          () =>
              find.byType(CameraConnectionView).evaluate().isEmpty &&
              startAction.evaluate().length == 1,
          'Canceling the tab connection must leave Live available to start',
        );
        if (format == CameraLiveFormat.raw) {
          await reconnect.tapReconnectUi(tester, find.text('RAW 原片'));
        }
        final selector = find.byKey(const Key('live-transfer-format'));
        expect(
          tester.widget<SegmentedButton<CameraLiveFormat>>(selector).selected,
          {format},
        );

        final nativeConnect = core.connection = Completer<Json>();
        Completer<Json>? parentStatus;
        if (format == CameraLiveFormat.raw) {
          parentStatus = core.postConnectStatus = Completer<Json>();
        }
        await reconnect.tapReconnectUi(tester, startAction);
        await waitForStartRoute(tester);
        expect(confirmStart, findsNothing);
        expect(core.operations('camera.live.start'), isEmpty);
        await reconnect.tapReconnectUi(
          tester,
          find.byKey(const Key('camera-connect')),
        );
        await reconnect.untilReconnect(
          tester,
          () => core.operations('camera.connect').length == 1,
          'Only the explicit connection button may begin native connection',
        );
        nativeConnect.complete(
          core.snapshot(session: 'start-${format.name}', isConnected: true),
        );
        await waitForStartConfirmation(tester);
        expect(find.byType(CameraConnectionView), findsNothing);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(core.operations('camera.live.start'), isEmpty);
        expect(core.operations('project.live.start'), isEmpty);
        expect(state.live.selectedFormat, format);
        expect(
          tester.widget<SegmentedButton<CameraLiveFormat>>(selector).selected,
          {format},
        );
        if (parentStatus != null) {
          expect(parentStatus.isCompleted, isFalse);
          expect(core.heldStatuses, contains(parentStatus));
        }
        await reconnect.tapReconnectUi(tester, confirmStart);
        await reconnect.untilReconnect(
          tester,
          () => state.live.phase == CameraLivePhase.watching,
          'The single accepted confirmation must start the original project',
        );
        expect(core.operations('camera.connect'), hasLength(1));
        expect(core.operations('camera.live.start'), hasLength(1));
        expect(core.operations('project.live.start'), hasLength(1));
        expect(core.liveBackend.lastStart['format'], format.name);
        expect(
          core.operations('project.live.start').single.$2['projectId'],
          'project-one',
        );
        expect(
          core.operations('project.live.start').single.$2['format'],
          format.name,
        );
        expect(state.live.projectId, 'project-one');
        expect(confirmStart, findsNothing);
        expect(core.photoCalls, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Canceling a disconnected Start ends its intent even if another session becomes available',
    (tester) async {
      portraitStartSize(tester);
      final core = StartConnectionCore();
      final state = reconnect.ReconnectState226(core);
      addTearDown(() => closeStartConnection(tester, state, core));
      await mountStartCard(tester, state);
      await reconnect.tapReconnectUi(tester, startAction);
      await waitForStartRoute(tester);
      core.connected = true;
      core.photoSession = 'independently-connected';
      await tester.binding.handlePopRoute();
      await reconnect.untilReconnect(
        tester,
        () =>
            find.byType(CameraConnectionView).evaluate().isEmpty &&
            startAction.evaluate().length == 1 &&
            tester.widget<FilledButton>(startAction).onPressed != null,
        'The canceled intent must release checking without starting anything',
      );
      expect(confirmStart, findsNothing);
      expect(state.live.active, isFalse);
      expect(core.operations('camera.connect'), isEmpty);
      expect(core.operations('camera.live.start'), isEmpty);
      expect(core.operations('project.live.start'), isEmpty);
      expect(core.photoCalls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A connected snapshot with an empty session still reconnects before it can start',
    (tester) async {
      portraitStartSize(tester);
      final core = StartConnectionCore()
        ..connected = true
        ..photoSession = '';
      final state = reconnect.ReconnectState226(core);
      addTearDown(() => closeStartConnection(tester, state, core));
      await mountStartCard(tester, state);
      final nativeConnect = core.connection = Completer<Json>();
      await reconnect.tapReconnectUi(tester, startAction);
      await waitForStartRoute(tester);
      expect(confirmStart, findsNothing);
      await reconnect.tapReconnectUi(
        tester,
        find.byKey(const Key('camera-connect')),
      );
      await reconnect.untilReconnect(
        tester,
        () => core.operations('camera.connect').length == 1,
        'A stale connected flag is insufficient without an actual session',
      );
      nativeConnect.complete(
        core.snapshot(session: 'complete-session', isConnected: true),
      );
      await waitForStartConfirmation(tester);
      await reconnect.tapReconnectUi(tester, confirmStart);
      await reconnect.untilReconnect(
        tester,
        () => state.live.phase == CameraLivePhase.watching,
        'The new complete session may start only after confirmation',
      );
      expect(state.live.session, 'complete-session');
      expect(core.operations('camera.live.start'), hasLength(1));
      expect(core.photoCalls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A to B to A account changes retire an awaiting Start connection intent',
    (tester) async {
      portraitStartSize(tester);
      final core = StartConnectionCore();
      final state = reconnect.ReconnectState226(core);
      addTearDown(() => closeStartConnection(tester, state, core));
      await mountStartCard(tester, state);
      final nativeConnect = core.connection = Completer<Json>();
      await reconnect.tapReconnectUi(tester, startAction);
      await waitForStartRoute(tester);
      await reconnect.tapReconnectUi(
        tester,
        find.byKey(const Key('camera-connect')),
      );
      await reconnect.untilReconnect(
        tester,
        () => core.operations('camera.connect').length == 1,
        'Native connection must actually be pending before the account changes',
      );
      state.session = {
        'user': {'id': 'other'},
      };
      state.notifyListeners();
      state.session = {
        'user': {'id': 'owner'},
      };
      state.notifyListeners();
      nativeConnect.complete(
        core.snapshot(
          session: 'connected-after-account-change',
          isConnected: true,
        ),
      );
      await reconnect.untilReconnect(
        tester,
        () =>
            find.byType(CameraConnectionView).evaluate().isEmpty &&
            startAction.evaluate().length == 1 &&
            tester.widget<FilledButton>(startAction).onPressed != null,
        'A late successful camera route must not resurrect the old account intent',
      );
      expect(core.connected, isTrue);
      expect(confirmStart, findsNothing);
      expect(state.live.active, isFalse);
      expect(core.operations('camera.live.start'), isEmpty);
      expect(core.operations('project.live.start'), isEmpty);
      expect(core.photoCalls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A valid session without RAW capability reports the format limitation without reconnecting',
    (tester) async {
      portraitStartSize(tester);
      final core = StartConnectionCore()
        ..connected = true
        ..supportsRaw = false;
      final state = reconnect.ReconnectState226(core);
      state.live.selectFormat(CameraLiveFormat.raw);
      addTearDown(() => closeStartConnection(tester, state, core));
      await mountStartCard(tester, state);
      await reconnect.tapReconnectUi(tester, startAction);
      await reconnect.untilReconnect(
        tester,
        () => find.textContaining('尚未提供受支持的 RAW').evaluate().isNotEmpty,
        'A capability failure must remain explicit rather than trigger a connection loop',
      );
      expect(find.byType(CameraConnectionView), findsNothing);
      expect(confirmStart, findsNothing);
      expect(state.live.selectedFormat, CameraLiveFormat.raw);
      expect(core.operations('camera.connect'), isEmpty);
      expect(core.operations('camera.live.start'), isEmpty);
      expect(core.operations('project.live.start'), isEmpty);
      expect(core.photoCalls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
