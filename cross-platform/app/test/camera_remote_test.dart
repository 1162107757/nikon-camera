import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_remote.dart';
import 'package:huevia/camera_remote_preview.dart';
import 'package:huevia/domain.dart';

class RemoteCore extends HueviaCore {
  final calls = <({String operation, Json payload, String? job})>[];
  final cancelled = <String>[];
  bool capable = true, viewing = false, verified = false;
  Json action = {};
  Json? liveFrame;
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
        return liveFrame ?? {'ready': false};
      default:
        return remote();
    }
  }

  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
  }
}

class RemoteSettingsCore extends RemoteCore {
  final values = {
    0x500d: 125,
    0x5007: 280,
    0x500f: 400,
    0x5010: -333,
    0x5005: 2,
    0xd01e: 5500,
  };
  final allowed = {
    0x500d: [100, 125, 160, 200],
    0x5007: [200, 250, 280, 320],
    0x500f: [200, 320, 400, 500],
    0x5010: [-666, -333, 0, 333, 666],
    0x5005: [2, 4, 0x8010, 0x8012],
    0xd01e: [5400, 5500, 5600, 5700],
  };
  final writes = <(int, int)>[];

  @override
  Json remote() {
    final response = super.remote();
    return {
      ...response,
      'exposureControls': true,
      'parameters': [
        for (final row in response['parameters'] as List)
          if (!values.containsKey(row['code'])) row,
        for (final entry in values.entries)
          {'code': entry.key, 'value': entry.value},
      ],
    };
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'camera.remote.exposure.options') {
      final code = payload['code'] as int;
      if (code == 0xd01e) expect(values[0x5005], 0x8012);
      return {'value': values[code], 'choices': allowed[code]};
    }
    if (operation == 'camera.remote.exposure.set') {
      expect(payload['session'], 'photos-one');
      expect(payload['remoteId'], 'remote-one');
      final code = payload['code'] as int;
      final value = payload['value'] as int;
      expect(allowed[code], contains(value));
      writes.add((code, value));
      values[code] = value;
      return remote();
    }
    return super.call(operation, payload, jobId);
  }
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> waitForRemoteFrame(
  WidgetTester tester, {
  bool Function(RawImage image)? matches,
}) async {
  final image = find.byKey(const Key('remote-frame-image'));
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (image.evaluate().isNotEmpty &&
        (matches == null || matches(tester.widget<RawImage>(image)))) {
      return;
    }
  }
  fail('No decoded remote frame matched');
}

void main() {
  testWidgets(
    'The moving ruler keeps its center fixed, cancels cleanly and commits one final value',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final core = RemoteSettingsCore()
        ..values[0x5007] = 300
        ..allowed[0x5007] = [280, 300, 320];
      final app = AppState(core);
      await tester.pumpWidget(MaterialApp(home: CameraRemotePage(state: app)));
      await frames(tester);
      final shutter = find.byKey(const Key('remote-shutter'));
      final position = tester.getCenter(shutter);
      final preview = find.byType(CameraRemotePreview);
      final viewfinder = tester.getRect(preview);
      expect(viewfinder.size, const Size(390, 844));
      expect(tester.widget<CameraRemotePreview>(preview).fit, BoxFit.contain);
      expect(
        tester.widget<CameraRemotePreview>(preview).grid,
        RemoteGrid.thirds,
      );
      expect(tester.widget<CameraRemotePreview>(preview).histogram, isTrue);
      final grid = tester.getRect(find.byTooltip('切换构图网格'));
      final chart = tester.getRect(find.byTooltip('显示或收起直方图'));
      expect(chart.top - grid.bottom, greaterThanOrEqualTo(5));
      const rulerKey = Key('remote-setting-ruler');
      final ruler = find.byKey(rulerKey);
      for (final code in [0x500d, 0x5007, 0x500f, 0x5010]) {
        await tester.tap(find.byKey(ValueKey('remote-exposure-$code')));
        await frames(tester);
        expect(find.byKey(rulerKey), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.getCenter(shutter), position);
        expect(tester.getRect(preview), viewfinder);
        if (code == 0x5007) {
          expect(find.text('最大光圈 F2.8'), findsOneWidget);
          await tester.tap(find.byKey(const Key('remote-maximum-aperture')));
          await frames(tester);
          expect(core.writes.single, (0x5007, 280));
          core.writes.clear();
        }
      }
      expect(find.byTooltip('曝光补偿加一档'), findsNothing);
      expect(find.byTooltip('曝光补偿减一档'), findsNothing);
      final marker = find.byKey(const Key('remote-ruler-marker'));
      final center = tester.getCenter(marker);
      final motion =
          tester
                  .widget<AnimatedBuilder>(
                    find.byKey(const Key('remote-ruler-motion')),
                  )
                  .listenable
              as Animation<double>;
      final startingIndex = motion.value;
      final canceled = await tester.startGesture(tester.getCenter(ruler));
      await canceled.moveBy(const Offset(-23, 0));
      await canceled.moveBy(const Offset(15, 0));
      await tester.pump();
      expect(motion.value, greaterThan(startingIndex));
      expect(motion.value, lessThan(startingIndex + .5));
      expect(tester.getCenter(marker), center);
      expect(core.writes, isEmpty);
      await canceled.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(motion.value, startingIndex);
      expect(core.writes, isEmpty);

      final handle = await tester.startGesture(tester.getCenter(ruler));
      await handle.moveBy(const Offset(-27, 0));
      await tester.pump();
      expect(motion.value, closeTo(startingIndex + .9, .05));
      expect(tester.getCenter(marker), center);
      expect(core.writes, isEmpty);
      await handle.up();
      await frames(tester);
      expect(core.writes, [(0x5010, 0)]);
      await tester.pump(const Duration(milliseconds: 220));
      expect(motion.value, startingIndex + 1);

      await tester.tap(find.byKey(const ValueKey('remote-exposure-20485')));
      await frames(tester);
      await tester.tap(find.text('晴天'));
      await frames(tester);
      expect(core.writes.last, (0x5005, 4));
      await tester.tap(find.text('色温'));
      await frames(tester);
      expect(core.writes.last, (0x5005, 0x8012));
      await tester.tapAt(tester.getCenter(ruler) + const Offset(30, 0));
      await frames(tester);
      expect(core.writes.last, (0xd01e, 5600));
      expect(find.text('5600 K'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

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
      expect(
        remoteFrameRect(const Size(300, 400), {
          'width': 600,
          'height': 400,
        }, fit: BoxFit.cover),
        const Rect.fromLTWH(-150, 0, 600, 400),
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
    'Remote direction switching preserves the 16-cell grid and the camera aspect',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final orientationCalls = <List<String>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientationCalls.add(List<String>.from(call.arguments as List));
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final core = RemoteCore()
        ..liveFrame = {
          'ready': true,
          'path': File(
            '../../docs/design-review/remote-capture-20261024/assets/live-view.png',
          ).absolute.path,
          // The actual image is 1448 × 1086. A wrong ratio must not stretch it.
          'width': 1920,
          'height': 1080,
          'pointFocus': true,
          'sequence': 1,
        };
      final app = AppState(core);
      await tester.pumpWidget(MaterialApp(home: CameraRemotePage(state: app)));
      await frames(tester);
      await tester.pump(const Duration(milliseconds: 380));
      await waitForRemoteFrame(tester);

      final picture = find.byKey(const Key('remote-frame-image'));
      final rotation = find.byKey(const Key('remote-rotate'));
      final grid = find.byKey(const Key('remote-grid'));
      final shutter = find.byKey(const Key('remote-shutter'));
      final firstParameter = find.byKey(
        const ValueKey('remote-exposure-20493'),
      );
      final portrait = tester.getRect(picture);
      expect(portrait.width, closeTo(390, .01));
      expect(portrait.width / portrait.height, closeTo(4 / 3, .003));
      expect(portrait.bottom, lessThan(tester.getTopLeft(firstParameter).dy));
      expect(grid, paintsExactlyCountTimes(#drawLine, 4));
      await tester.tap(find.byTooltip('切换构图网格'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('remote-grid-option-quarters')),
      );
      await tester.pumpAndSettle();
      expect(grid, paintsExactlyCountTimes(#drawLine, 6));
      await tester.tapAt(portrait.center);
      await tester.pump();
      expect(
        core.calls.where((call) => call.operation == 'camera.remote.focus'),
        isEmpty,
      );

      await tester.tap(rotation);
      await tester.pump();
      expect(orientationCalls.single, [
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ]);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      final landscape = tester.getRect(picture);
      expect(landscape.width, closeTo(844, .01));
      expect(landscape.width / landscape.height, closeTo(4 / 3, .003));
      expect(tester.getCenter(shutter).dx, greaterThan(720));
      expect(grid, paintsExactlyCountTimes(#drawLine, 6));

      await tester.tap(find.byTooltip('拍摄设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('横屏完整画幅'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final full = tester.getRect(picture);
      expect(full.width / full.height, closeTo(4 / 3, .003));
      expect(full.bottom, lessThan(tester.getTopLeft(firstParameter).dy));
      await tester.tap(find.byTooltip('切换构图网格'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remote-grid-option-off')));
      await tester.pumpAndSettle();
      expect(grid, findsNothing);

      await tester.tap(rotation);
      await tester.pump();
      expect(orientationCalls.last, ['DeviceOrientation.portraitUp']);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump();
      expect(tester.getRect(picture), portrait);
      expect(grid, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(orientationCalls.last, isEmpty);
      app.dispose();
    },
  );

  testWidgets(
    'Grid and draggable measured-histogram overlay do not send false focus taps',
    (tester) async {
      final taps = <Offset>[];
      var measuredPixels = 0;
      final frame = ValueNotifier<Json>({
        'path': File(
          '../../app/src/main/assets/preset-showcase/portrait-smile.jpg',
        ).absolute.path,
        'width': 640,
        'height': 960,
        'sequence': 1,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 400,
                height: 400,
                child: ValueListenableBuilder<Json>(
                  valueListenable: frame,
                  builder: (context, value, child) => CameraRemotePreview(
                    frame: value,
                    viewing: true,
                    busy: false,
                    grid: RemoteGrid.thirds,
                    histogram: true,
                    onFocus: (x, y) => taps.add(Offset(x, y)),
                    onHistogram: (data) =>
                        measuredPixels = data?.pixelCount ?? 0,
                    onResume: null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await waitForRemoteFrame(tester);
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
      final presented = find.byKey(const Key('remote-frame-image'));
      final originalImage = tester.widget<RawImage>(presented).image;
      final originalRect = tester.getRect(presented);
      frame.value = {...frame.value, 'sequence': 2, 'rotation': 90};
      await tester.pump();
      expect(tester.widget<RawImage>(presented).image, same(originalImage));
      expect(tester.getRect(presented), originalRect);

      frame.value = {...frame.value, 'sequence': 3, 'rotation': 0};
      await tester.pump();
      expect(tester.widget<RawImage>(presented).image, same(originalImage));
      await waitForRemoteFrame(
        tester,
        matches: (image) => image.image != originalImage,
      );
      expect(tester.getRect(presented), originalRect);

      final upright = tester.widget<RawImage>(presented).image;
      frame.value = {...frame.value, 'sequence': 4, 'rotation': 90};
      await tester.pump();
      expect(tester.getRect(presented), originalRect);
      frame.value = {...frame.value, 'sequence': 5};
      await tester.pump();
      await waitForRemoteFrame(
        tester,
        matches: (image) => image.image != upright,
      );
      expect(tester.getRect(presented).width, closeTo(400, .01));
      await tester.pumpWidget(const SizedBox());
      frame.dispose();
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
      expect(find.text('正在等待相机保存照片'), findsOneWidget);
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
      core.action = {
        'pending': true,
        'phase': 'resultUnknown',
        'actionId': 'shot-one',
      };
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
      core.verified = true;
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 350));
      }
      await frames(tester);
      expect(find.text('已确认新照片'), findsOneWidget);
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
      expect(find.text('Nikon fixture'), findsOneWidget);
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
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Nikon fixture'),
        ),
        findsOneWidget,
      );
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
