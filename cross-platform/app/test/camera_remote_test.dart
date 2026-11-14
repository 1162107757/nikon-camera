import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_remote.dart';
import 'package:huevia/camera_remote_preview.dart';
import 'package:huevia/domain.dart';

class RemoteCore extends HueviaCore {
  final calls = <({String operation, Json payload, String? job})>[];
  final cancelled = <String>[];
  bool capable = true, viewing = false, verified = false;
  Json action = {};
  Completer<Json>? opening, capturing, viewingChange;
  Json remote() => {
    'session': 'photos-one',
    'remoteId': 'remote-one',
    'connected': true,
    'model': 'Nikon fixture',
    'liveView': capable,
    'capture': capable,
    'autoFocus': capable,
    'pointFocus': capable,
    'viewing': viewing,
    'action': action,
    'parameters': [
      {'code': 0x5001, 'value': 72},
      {'code': 0x500d, 'value': 125},
      {'code': 0x5007, 'value': 280},
      {'code': 0x500f, 'value': 400},
      {'code': 0x5010, 'value': -300},
      {'code': 0x500e, 'value': 1},
    ],
  };
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation: operation, payload: Map.of(payload), job: jobId));
    switch (operation) {
      case 'camera.status':
        return {'connected': true, 'session': 'photos-one'};
      case 'camera.remote.open':
        return opening == null ? remote() : opening!.future;
      case 'camera.remote.close':
        return {'closed': true};
      case 'camera.remote.view':
        viewing = payload['enabled'] == true;
        return viewingChange == null ? remote() : viewingChange!.future;
      case 'camera.remote.capture':
        if (capturing != null) return capturing!.future;
        action = {
          'pending': true,
          'phase': 'acknowledged',
          'actionId': 'shot-one',
        };
        return remote();
      case 'camera.remote.check':
        if (verified) {
          action = {
            'pending': false,
            'phase': 'verified',
            'actionId': 'shot-one',
            'photos': [
              {'handle': 17, 'name': 'DSC_0017.JPG', 'raw': false},
            ],
          };
        }
        return remote();
      case 'camera.remote.acknowledge':
        action = {...action, 'pending': false};
        return remote();
      case 'camera.remote.frame':
        return {'ready': false};
      default:
        return remote();
    }
  }

  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
  }
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  test(
    'Remote geometry respects letterboxing and camera-reported rotation',
    () {
      expect(
        remoteFrameRect(const Size(400, 400), {'width': 400, 'height': 300}),
        const Rect.fromLTWH(0, 50, 400, 300),
      );
      expect(
        remoteFrameRect(const Size(400, 400), {
          'width': 400,
          'height': 300,
          'rotation': 90,
        }),
        const Rect.fromLTWH(50, 0, 300, 400),
      );
      expect(
        remoteFrameRect(const Size(400, 400), {'width': 0, 'height': 300}),
        Rect.zero,
      );
    },
  );
  test('Only a frame received within three seconds is marked live', () {
    final now = DateTime.utc(2026, 11, 14);
    expect(remoteFrameIsFresh(null, now), false);
    expect(
      remoteFrameIsFresh(now.subtract(const Duration(seconds: 3)), now),
      true,
    );
    expect(
      remoteFrameIsFresh(now.subtract(const Duration(milliseconds: 3001)), now),
      false,
    );
  });
  testWidgets(
    'Grid and draggable measured-histogram overlay do not send false focus taps',
    (tester) async {
      final taps = <Offset>[];
      var measuredPixels = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                height: 400,
                child: CameraRemotePreview(
                  frame: {
                    'path': File(
                      '../../app/src/main/assets/preset-showcase/portrait-smile.jpg',
                    ).absolute.path,
                    'width': 640,
                    'height': 960,
                    'sequence': 1,
                  },
                  viewing: true,
                  busy: false,
                  grid: true,
                  histogram: true,
                  onFocus: (x, y) => taps.add(Offset(x, y)),
                  onHistogram: (data) => measuredPixels = data?.pixelCount ?? 0,
                  onResume: null,
                ),
              ),
            ),
          ),
        ),
      );
      final origin = tester.getTopLeft(
        find.byKey(const Key('remote-frame-focus')),
      );
      await tester.tapAt(origin + const Offset(10, 200));
      expect(taps, isEmpty);
      await tester.tapAt(origin + const Offset(200, 200));
      expect(taps, hasLength(1));
      expect(taps.single.dx, closeTo(.5, 1e-9));
      expect(taps.single.dy, closeTo(.5, 1e-9));
      await tester.drag(
        find.byKey(const Key('remote-histogram')),
        const Offset(40, -60),
      );
      await tester.pump();
      expect(taps, hasLength(1));
      expect(find.byKey(const Key('remote-grid')), findsOneWidget);
      for (var i = 0; i < 40 && measuredPixels == 0; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('remote-histogram')));
      }
      expect(measuredPixels, greaterThan(0));
      expect(taps, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );

  Future<AppState> mount(
    WidgetTester tester,
    RemoteCore core, {
    VoidCallback? closed,
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
              closed?.call();
            },
          ),
        ),
      ),
    );
    await frames(tester);
    return state;
  }

  testWidgets(
    'Embedded remote reads real capabilities and closes only its lease',
    (tester) async {
      final core = RemoteCore()..capable = false;
      var closed = false;
      await mount(tester, core, closed: () => closed = true);
      expect(find.textContaining('Nikon fixture'), findsOneWidget);
      expect(find.text('72%'), findsOneWidget);
      expect(find.text('F2.8'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('remote-shutter')))
            .onPressed,
        isNull,
      );
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.view'),
        isEmpty,
      );
      await tester.tap(find.byKey(const Key('remote-close')));
      await frames(tester);
      expect(closed, true);
      final close = core.calls
          .where((c) => c.operation == 'camera.remote.close')
          .single;
      expect(close.payload, {
        'session': 'photos-one',
        'remoteId': 'remote-one',
      });
      expect(
        core.calls.where((c) => c.operation == 'camera.disconnect'),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'One shutter request stays blocked until its uncertain result is checked',
    (tester) async {
      final core = RemoteCore();
      await mount(tester, core);
      await tester.tap(find.byKey(const Key('remote-shutter')));
      await frames(tester);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture').length,
        1,
      );
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.check').length,
        1,
      );
      expect(find.text('拍摄结果待核对'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('remote-shutter')))
            .onPressed,
        isNull,
      );
      expect(
        core.calls.where(
          (c) =>
              c.operation == 'camera.page' || c.operation == 'camera.download',
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Lifecycle pauses only remote view and resumes only by explicit control',
    (tester) async {
      final core = RemoteCore();
      await mount(tester, core);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await frames(tester);
      expect(
        core.calls
            .where((c) => c.operation == 'camera.remote.view')
            .map((c) => c.payload['enabled']),
        [true, false],
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await frames(tester);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.view').length,
        2,
      );
      await tester.tap(find.text('恢复取景'));
      await frames(tester);
      expect(
        core.calls
            .where((c) => c.operation == 'camera.remote.view')
            .last
            .payload['enabled'],
        true,
      );
      expect(
        core.calls.where((c) => c.operation == 'camera.disconnect'),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Late remote open after account change closes exactly the old returned lease',
    (tester) async {
      final core = RemoteCore()..opening = Completer<Json>();
      final state = await mount(tester, core);
      state.session = {
        'user': {'id': 'other'},
      };
      state.notifyListeners();
      await frames(tester);
      core.opening!.complete(core.remote());
      await frames(tester);
      expect(find.text('账号已改变，请关闭后重新打开遥控拍摄。'), findsOneWidget);
      expect(
        core.calls
            .where((c) => c.operation == 'camera.remote.close')
            .single
            .payload,
        {'session': 'photos-one', 'remoteId': 'remote-one'},
      );
      expect(core.cancelled, isEmpty);
      expect(
        core.calls.where((c) => c.operation == 'camera.disconnect'),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Shutter timeout cancels its job and never automatically resends capture',
    (tester) async {
      final core = RemoteCore()..capturing = Completer<Json>();
      await mount(tester, core);
      await tester.tap(find.byKey(const Key('remote-shutter')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 76));
      await frames(tester);
      expect(core.cancelled, hasLength(1));
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture').length,
        1,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('remote-shutter')))
            .onPressed,
        isNull,
      );
      core.capturing!.complete(core.remote());
      await frames(tester);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture').length,
        1,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Closing view settings before its delayed reply does not update a disposed sheet',
    (tester) async {
      final core = RemoteCore();
      await mount(tester, core);
      core.viewingChange = Completer<Json>();
      await tester.tap(find.byTooltip('拍摄设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('实时取景'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.view').length,
        2,
      );
      expect(find.text('拍摄设置'), findsNothing);
      core.viewingChange!.complete(core.remote());
      await frames(tester);
      expect(find.byType(CameraRemotePage), findsOneWidget);
      expect(find.text('遥控拍照'), findsOneWidget);
      expect(
        core.calls
            .where((c) => c.operation == 'camera.remote.view')
            .last
            .payload['enabled'],
        false,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Account change masks the currently open remote parameter sheet without popping the host',
    (tester) async {
      final core = RemoteCore();
      final state = await mount(tester, core);
      await tester.tap(find.byTooltip('查看机身参数'));
      await tester.pumpAndSettle();
      expect(find.text('机身当前参数'), findsOneWidget);
      expect(find.text('Nikon fixture'), findsOneWidget);
      state.session = {
        'user': {'id': 'other'},
      };
      state.notifyListeners();
      await frames(tester);
      expect(find.text('机身当前参数'), findsNothing);
      expect(find.text('Nikon fixture'), findsNothing);
      expect(find.byType(CameraRemotePage), findsOneWidget);
      expect(find.text('遥控拍照'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'View-off remote refreshes parameters while foreground, including inactive overlays, without frames',
    (tester) async {
      final core = RemoteCore()
        ..capable = false
        ..action = {'pending': true, 'actionId': 'unconfirmed'};
      await mount(tester, core);
      Future<void> ticks(int count) async {
        for (var i = 0; i < count; i++) {
          await tester.pump(const Duration(milliseconds: 350));
          await tester.pump();
        }
      }

      await ticks(8);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.status'),
        hasLength(1),
      );
      expect(
        core.calls
            .where((c) => c.operation == 'camera.remote.status')
            .single
            .payload,
        {'session': 'photos-one', 'remoteId': 'remote-one'},
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await ticks(8);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.status'),
        hasLength(2),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await ticks(16);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.status'),
        hasLength(2),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await ticks(8);
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.status'),
        hasLength(3),
      );
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.frame'),
        isEmpty,
      );
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.capture'),
        isEmpty,
      );
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.check'),
        isEmpty,
      );
      expect(
        core.calls.where((c) => c.operation == 'camera.disconnect'),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Leaving pending remote open makes its later deadline harmless to the parent session',
    (tester) async {
      final core = RemoteCore()..opening = Completer<Json>();
      await mount(tester, core);
      final opening = core.calls.singleWhere(
        (c) => c.operation == 'camera.remote.open',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 21));
      expect(core.cancelled, isEmpty);
      core.opening!.complete(core.remote());
      await frames(tester);
      final closes = core.calls.where(
        (c) => c.operation == 'camera.remote.close',
      );
      expect(closes, hasLength(1));
      expect(closes.single.payload, {
        'session': 'photos-one',
        'remoteId': 'remote-one',
      });
      expect(core.cancelled, isNot(contains(opening.job)));
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.view'),
        isEmpty,
      );
      expect(
        core.calls.where((c) => c.operation == 'camera.disconnect'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Visible remote open still times out, cancels only its active job and releases a late lease',
    (tester) async {
      final core = RemoteCore()..opening = Completer<Json>();
      await mount(tester, core);
      final opening = core.calls.singleWhere(
        (c) => c.operation == 'camera.remote.open',
      );
      await tester.pump(const Duration(seconds: 21));
      await frames(tester);
      expect(core.cancelled, [opening.job]);
      expect(find.text('相机响应超时，请核对连接后重试。'), findsOneWidget);
      core.opening!.complete(core.remote());
      await frames(tester);
      expect(
        core.calls
            .where((c) => c.operation == 'camera.remote.close')
            .single
            .payload,
        {'session': 'photos-one', 'remoteId': 'remote-one'},
      );
      expect(
        core.calls.where((c) => c.operation == 'camera.remote.view'),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
