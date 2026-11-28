import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_remote.dart';
import 'package:huevia/camera_remote_preview.dart';
import 'package:huevia/domain.dart';

import 'camera_remote_test.dart' as fixtures;

class PollCore extends fixtures.RemoteCore {
  Completer<Json>? frameGate, statusGate;
  bool previewAvailable = true;
  int failedChecks = 0;
  int activeCommands = 0, maximumCommands = 0;
  @override
  Json remote() => {...super.remote(), 'liveView': previewAvailable};
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
      if (operation == 'camera.remote.check' && failedChecks > 0) {
        failedChecks--;
        throw const AppFailure('照片目录暂不可读');
      }
      return normal;
    } finally {
      activeCommands--;
    }
  }
}

class ExposureCore extends PollCore {
  final values = {0x500d: 50, 0x5007: 280, 0x500f: 6400};
  final choices = {
    0x500d: [50, 100],
    0x5007: [280, 400],
    0x500f: [3200, 6400],
  };

  @override
  Json remote() => {
    ...super.remote(),
    'exposureControls': true,
    'parameters': [
      {'code': 0x500a, 'value': 0x8011},
      for (final entry in values.entries)
        {'code': entry.key, 'value': entry.value},
    ],
  };

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    switch (operation) {
      case 'camera.remote.exposure.options':
      case 'camera.remote.exposure.set':
      case 'camera.remote.focus':
        calls.add((operation: operation, payload: Map.of(payload), job: jobId));
        if (operation == 'camera.remote.focus') {
          return {...remote(), 'notice': '相机暂忙，对焦未完成。'};
        }
        final code = payload['code'] as int;
        if (operation == 'camera.remote.exposure.options') {
          return {'value': values[code], 'choices': choices[code]};
        }
        values[code] = payload['value'] as int;
        return remote();
      default:
        return super.call(operation, payload, jobId);
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
    'DeviceBusy focus is recoverable and three camera exposure choices write the selected values',
    (tester) async {
      tester.view.physicalSize = const Size(360, 795);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final core = ExposureCore();
      await mount(tester, core);
      expect(find.textContaining('AF-C'), findsOneWidget);
      await tester.tap(find.text('对焦'));
      await flush(tester);
      expect(find.text('相机暂忙，对焦未完成。'), findsOneWidget);
      expect(tester.widget<IconButton>(shutter).onPressed, isNotNull);
      await tick(tester);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.frame'),
        isNotEmpty,
      );
      for (final (code, choice, number, direction) in [
        (0x5007, 'F4.0', 400, 1),
        (0x500f, '3200', 3200, -1),
        (0x500d, '1/100', 100, 1),
      ]) {
        final button = find.byKey(ValueKey('remote-exposure-$code'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        final ruler = find.byKey(const Key('remote-setting-ruler'));
        expect(ruler, findsOneWidget);
        await tester.ensureVisible(ruler);
        await tester.tapAt(
          tester.getCenter(ruler) + Offset(direction * 30.0, 0),
        );
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: button, matching: find.text(choice)),
          findsOneWidget,
        );
        final write = core.calls.lastWhere(
          (c) => c.operation == 'camera.remote.exposure.set',
        );
        expect(write.payload, {
          'session': 'photos-one',
          'remoteId': 'remote-one',
          'code': code,
          'value': number,
        });
      }
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.exposure.set'),
        hasLength(3),
      );
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture'),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );

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
      expect(find.text('正在等待相机保存照片'), findsOneWidget);
      expect(tester.widget<IconButton>(shutter).onPressed, isNull);
      expect(core.maximumCommands, 1);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );
  for (final viewing in [false, true]) {
    testWidgets('Delayed shutter result is checked with live view $viewing', (
      tester,
    ) async {
      final core = PollCore()..previewAvailable = viewing;
      await mount(tester, core);
      await tester.ensureVisible(shutter);
      await tester.tap(shutter);
      await flush(tester);
      final captureIndex = core.calls.indexWhere(
        (call) => call.operation == 'camera.remote.capture',
      );
      expect(captureIndex, greaterThanOrEqualTo(0));
      await tick(tester, 9);
      expect(find.text('正在等待相机保存照片'), findsOneWidget);
      expect(tester.widget<IconButton>(shutter).onPressed, isNull);
      final afterCapture = core.calls.skip(captureIndex + 1);
      expect(afterCapture.length, greaterThan(1));
      expect(
        afterCapture.every((call) => call.operation == 'camera.remote.check'),
        isTrue,
      );
      core.verified = true;
      await tick(tester, 3);
      expect(find.text('已确认新照片'), findsOneWidget);
      expect(tester.widget<IconButton>(shutter).onPressed, isNotNull);
      expect(
        core.calls.where((call) => call.operation == 'camera.remote.capture'),
        hasLength(1),
      );
      expect(core.maximumCommands, 1);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    });
  }
  testWidgets('Unseen result ends automatic checks and stays safe to review', (
    tester,
  ) async {
    final core = PollCore();
    await mount(tester, core);
    await tester.tap(shutter);
    await flush(tester);
    await tester.pump(const Duration(seconds: 61));
    await flush(tester);
    expect(find.text('拍摄结果待核对'), findsOneWidget);
    expect(find.byKey(const Key('remote-continue')), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('remote-close')))
          .onPressed,
      isNotNull,
    );
    final checkCount = core.calls
        .where((c) => c.operation == 'camera.remote.check')
        .length;
    await tick(tester, 9);
    expect(
      core.calls.where((c) => c.operation == 'camera.remote.check'),
      hasLength(checkCount),
    );
    expect(
      core.calls.where((c) => c.operation == 'camera.remote.capture'),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  });
  testWidgets(
    'An uncertain shutter reply verifies automatically despite a transient read failure',
    (tester) async {
      final capture = Completer<Json>();
      final core = PollCore()
        ..capturing = capture
        ..failedChecks = 1;
      await mount(tester, core);
      await tester.tap(shutter);
      await flush(tester);
      core.action = {
        'actionId': 'shot-one',
        'pending': true,
        'phase': 'resultUnknown',
      };
      capture.complete(core.remote());
      await flush(tester);
      expect(find.text('正在等待相机保存照片'), findsOneWidget);
      expect(tester.widget<IconButton>(shutter).onPressed, isNull);
      core.verified = true;
      await tick(tester, 3);
      expect(find.text('已确认新照片'), findsOneWidget);
      expect(tester.widget<IconButton>(shutter).onPressed, isNotNull);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.check'),
        hasLength(2),
      );
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture'),
        hasLength(1),
      );
      expect(core.maximumCommands, 1);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );

  testWidgets('Reopening resumes the pending shot from the same camera', (
    tester,
  ) async {
    final core = PollCore()
      ..action = {
        'actionId': 'shot-one',
        'pending': true,
        'phase': 'waitingForJpeg',
        'canCheck': true,
      };
    await mount(tester, core);
    expect(find.text('上次拍摄未核对'), findsOneWidget);
    core.verified = true;
    await tick(tester, 3);
    expect(find.text('已确认新照片'), findsOneWidget);
    expect(tester.widget<IconButton>(shutter).onPressed, isNotNull);
    expect(
      core.calls.where((c) => c.operation == 'camera.remote.capture'),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    await flush(tester);
  });

  testWidgets(
    'A stale entry opens live preview and allows an explicit fresh start without shooting',
    (tester) async {
      tester.view.physicalSize = const Size(360, 792);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final frame = Completer<Json>();
      final core = PollCore()
        ..frameGate = frame
        ..action = {
          'actionId': 'old-shot',
          'pending': true,
          'phase': 'resultUnknown',
          'canCheck': false,
        };
      await mount(tester, core);
      expect(find.text('上次拍摄未核对'), findsOneWidget);
      final title = tester.element(find.text('Nikon fixture'));
      expect(DefaultTextStyle.of(title).style.color, const Color(0xfff6f1eb));
      final resume = find.byKey(const Key('remote-continue'));
      expect(tester.widget<TextButton>(resume).onPressed, isNotNull);
      expect(tester.widget<IconButton>(shutter).onPressed, isNotNull);
      await tick(tester);
      expect(
        core.calls.where((call) => call.operation == 'camera.remote.frame'),
        hasLength(1),
      );
      frame.complete({
        'ready': true,
        'path': File('assets/legacy/huevia_launcher.png').absolute.path,
        'width': 640,
        'height': 480,
        'sequence': 1,
      });
      await flush(tester);
      final preview = tester.widget<CameraRemotePreview>(
        find.byType(CameraRemotePreview),
      );
      expect(preview.fresh, isTrue);
      await fixtures.waitForRemoteFrame(tester);
      expect(find.text('等待相机实时画面'), findsNothing);
      expect(
        core.calls.where((call) => call.operation == 'camera.remote.check'),
        isEmpty,
      );
      expect(
        core.calls.where((call) => call.operation == 'camera.remote.capture'),
        isEmpty,
      );

      await tester.tap(resume);
      await tester.pumpAndSettle();
      expect(find.text('继续新的拍摄？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '继续拍摄'));
      await tester.pumpAndSettle();
      final close = core.calls.singleWhere(
        (call) => call.operation == 'camera.remote.acknowledge',
      );
      expect(close.payload['actionId'], 'old-shot');
      expect(close.payload['continueWithoutConfirming'], isTrue);
      expect(close.payload.containsKey('confirmedOnCamera'), isFalse);
      expect(find.text('相机就绪'), findsOneWidget);
      expect(
        core.calls.where((call) => call.operation == 'camera.remote.capture'),
        isEmpty,
      );

      await tester.tap(shutter);
      await flush(tester);
      expect(
        core.calls.where((call) => call.operation == 'camera.remote.capture'),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );

  testWidgets(
    'A confirmed busy rejection leaves the shutter available with a readable notice',
    (tester) async {
      final reply = Completer<Json>();
      final core = PollCore()..capturing = reply;
      await mount(tester, core);
      await tester.tap(shutter);
      await flush(tester);
      const notice = '相机暂忙，机身未接受快门。请稍候再拍。';
      reply.complete({
        ...core.remote(),
        'notice': notice,
        'action': {'pending': false, 'phase': 'rejected'},
      });
      await flush(tester);
      expect(find.text(notice), findsOneWidget);
      expect(tester.widget<IconButton>(shutter).onPressed, isNotNull);
      expect(
        core.calls.where((call) => call.operation == 'camera.remote.check'),
        isEmpty,
      );
      expect(
        core.calls.where((call) => call.operation == 'camera.remote.capture'),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
    },
  );

  testWidgets(
    'A capture failure before the journal entry releases the shutter lock',
    (tester) async {
      final capture = Completer<Json>();
      final core = PollCore()..capturing = capture;
      await mount(tester, core);
      await tester.tap(shutter);
      await flush(tester);
      capture.completeError(const AppFailure('机身快门设置无效'));
      await flush(tester);
      expect(find.text('机身快门设置无效'), findsOneWidget);
      expect(tester.widget<IconButton>(shutter).onPressed, isNotNull);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.check'),
        hasLength(1),
      );
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture'),
        hasLength(1),
      );
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
      await tester.tap(shutter);
      await tester.pumpAndSettle();
      expect(find.text('继续新的拍摄？'), findsOneWidget);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture'),
        isEmpty,
      );
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
