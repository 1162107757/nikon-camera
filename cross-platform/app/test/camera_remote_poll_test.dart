import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_remote.dart';
import 'package:huevia/domain.dart';

import 'camera_remote_test.dart' as fixtures;

class PollCore extends fixtures.RemoteCore {
  Completer<Json>? frameGate, statusGate;
  int activeCommands = 0, maximumCommands = 0;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    activeCommands++;
    if (activeCommands > maximumCommands) maximumCommands = activeCommands;
    try {
      final normal = await super.call(operation, payload, jobId);
      if (operation == 'camera.remote.frame' && frameGate != null) {
        final gate = frameGate!;
        frameGate = null;
        return await gate.future;
      }
      if (operation == 'camera.remote.status' && statusGate != null) {
        final gate = statusGate!;
        statusGate = null;
        return await gate.future;
      }
      return normal;
    } finally {
      activeCommands--;
    }
  }
}

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump();
  }
}

Future<void> tick(WidgetTester tester, [int count = 1]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 350));
    await flush(tester);
  }
}

Future<AppState> mount(
  WidgetTester tester,
  PollCore core, {
  VoidCallback? onClose,
}) async {
  final state = AppState(core)
    ..session = {
      'user': {'id': 'u'},
    };
  addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CameraRemotePage(
          state: state,
          embedded: true,
          onClose: () async {
            onClose?.call();
          },
        ),
      ),
    ),
  );
  await flush(tester);
  return state;
}

Finder get shutter => find.byKey(const Key('remote-shutter'));
void expectQuietReady(WidgetTester tester) {
  expect(tester.widget<IconButton>(shutter).onPressed, isNotNull);
  expect(find.text('相机就绪'), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);
}

void main() {
  testWidgets(
    '350ms held frame poll keeps ready stable and queues one shutter without parallel commands',
    (tester) async {
      final gate = Completer<Json>(), shot = Completer<Json>();
      final core = PollCore()
        ..frameGate = gate
        ..capturing = shot;
      await mount(tester, core);
      expectQuietReady(tester);
      await tick(tester);
      expectQuietReady(tester);
      await tick(tester, 2);
      expectQuietReady(tester);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.frame'),
        hasLength(1),
      );
      await tester.ensureVisible(shutter);
      await tester.tap(shutter);
      await flush(tester);
      expect(find.text('等待相机完成当前读取'), findsOneWidget);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture'),
        isEmpty,
      );
      expect(tester.widget<IconButton>(shutter).onPressed, isNull);
      await tester.tap(shutter);
      await flush(tester);
      gate.complete({'ready': false});
      await flush(tester);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture'),
        hasLength(1),
      );
      expect(find.text('正在拍摄'), findsOneWidget);
      core.action = {
        'pending': true,
        'actionId': 'one',
        'phase': 'acknowledged',
      };
      shot.complete(core.remote());
      await flush(tester);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture'),
        hasLength(1),
      );
      expect(find.text('拍摄结果待核对'), findsOneWidget);
      expect(tester.widget<IconButton>(shutter).onPressed, isNull);
      expect(core.maximumCommands, 1);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );
  testWidgets(
    '2.8s held status poll never flashes busy and rechecks capture capability before queued shutter',
    (tester) async {
      final gate = Completer<Json>();
      final core = PollCore()..statusGate = gate;
      await mount(tester, core);
      for (var i = 0; i < 8; i++) {
        await tick(tester);
        expectQuietReady(tester);
      }
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.status'),
        hasLength(1),
      );
      await tester.ensureVisible(shutter);
      await tester.tap(shutter);
      await flush(tester);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture'),
        isEmpty,
      );
      gate.complete({...core.remote(), 'capture': false});
      await flush(tester);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture'),
        isEmpty,
      );
      expect(find.text('相机当前不可拍摄，请核对机身状态。'), findsOneWidget);
      expect(tester.widget<IconButton>(shutter).onPressed, isNull);
      expect(core.maximumCommands, 1);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );
  testWidgets(
    'A newly pending status prevents a queued shutter from replaying an uncertain exposure',
    (tester) async {
      final gate = Completer<Json>();
      final core = PollCore()..statusGate = gate;
      await mount(tester, core);
      await tick(tester, 8);
      await tester.ensureVisible(shutter);
      await tester.tap(shutter);
      await flush(tester);
      core.action = {
        'pending': true,
        'actionId': 'previous',
        'phase': 'resultUnknown',
      };
      gate.complete(core.remote());
      await flush(tester);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture'),
        isEmpty,
      );
      expect(find.text('上次拍摄结果待核对，未发送快门。'), findsOneWidget);
      expect(tester.widget<IconButton>(shutter).onPressed, isNull);
      expect(core.maximumCommands, 1);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );
  testWidgets(
    'A real poll error remains visible and aborts the queued shutter rather than dropping or repeating it',
    (tester) async {
      final gate = Completer<Json>();
      final core = PollCore()..frameGate = gate;
      await mount(tester, core);
      await tick(tester);
      await tester.ensureVisible(shutter);
      await tester.tap(shutter);
      await flush(tester);
      gate.completeError(const AppFailure('取景读取失败'));
      await flush(tester);
      expect(find.text('取景读取失败'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.widget<IconButton>(shutter).onPressed, isNull);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture'),
        isEmpty,
      );
      expect(core.maximumCommands, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );
  for (final departure in ['finish', 'owner']) {
    testWidgets(
      '$departure during held silent status closes only the original lease and sends no late actors',
      (tester) async {
        final gate = Completer<Json>();
        final core = PollCore()..statusGate = gate;
        var closed = false;
        final state = await mount(tester, core, onClose: () => closed = true);
        await tick(tester, 8);
        expectQuietReady(tester);
        if (departure == 'finish') {
          await tester.tap(find.byKey(const Key('remote-close')));
        } else {
          state.session = {
            'user': {'id': 'other'},
          };
          state.notifyListeners();
        }
        await flush(tester);
        expect(
          core.calls.where((c) => c.operation == 'camera.remote.close'),
          isEmpty,
        );
        expect(core.cancelled, isEmpty);
        final frames = core.calls
            .where((c) => c.operation == 'camera.remote.frame')
            .length;
        gate.complete({
          ...core.remote(),
          'action': {'pending': true, 'actionId': 'late'},
        });
        await flush(tester);
        expect(
          core.calls
              .where((c) => c.operation == 'camera.remote.close')
              .single
              .payload,
          {'session': 'photos-one', 'remoteId': 'remote-one'},
        );
        expect(
          core.calls.where((c) => c.operation == 'camera.remote.frame'),
          hasLength(frames),
        );
        expect(
          core.calls.where((c) => c.operation == 'camera.remote.check'),
          isEmpty,
        );
        expect(
          core.calls.where((c) => c.operation == 'camera.remote.capture'),
          isEmpty,
        );
        expect(closed, departure == 'finish');
        expect(core.maximumCommands, 1);
        await tester.pumpWidget(const SizedBox());
        await flush(tester);
      },
    );
  }
}
