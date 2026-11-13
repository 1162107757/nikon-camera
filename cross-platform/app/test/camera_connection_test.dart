import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera.dart';
import 'package:huevia/camera_connection.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';

class _CameraRequest {
  _CameraRequest(this.operation, this.payload, this.job);
  final String operation, job;
  final Json payload;
  final result = Completer<Json>();
}

class _ConnectionCore extends HueviaCore {
  final events = StreamController<dynamic>.broadcast(sync: true);
  final requests = <_CameraRequest>[];
  final cancelled = <String>[];
  Completer<void>? cancelGate;
  Json cameraStatus = {
    'connected': false,
    'session': '',
    'model': '',
    'mode': 'none',
    'inventoryReady': false,
  };
  @override
  Stream<dynamic> get operationProgress => events.stream;
  @override
  Future<void> cancel(String jobId) {
    cancelled.add(jobId);
    return cancelGate?.future ?? Future<void>.value();
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) {
    if (operation == 'camera.status') {
      return Future.value(Map<String, dynamic>.of(cameraStatus));
    }
    final request = _CameraRequest(operation, payload, jobId ?? '');
    requests.add(request);
    return request.result.future;
  }
}

void main() {
  testWidgets(
    'Camera handshake reports permission, confirmation, session and capabilities only for its own job',
    (tester) async {
      final core = _ConnectionCore();
      final request = CameraConnectionRequest(core);
      final future = request.run(
        'camera.connect',
        {},
        'mine',
        timeout: const Duration(seconds: 125),
      );
      core.events.add({'jobId': 'other', 'progress': .7});
      expect(request.phase, contains('Wi-Fi'));
      core.events.add({'jobId': 'mine', 'progress': .08});
      expect(request.phase, contains('本地网络授权'));
      core.events.add({'jobId': 'mine', 'progress': .1});
      expect(request.phase, contains('本地网络授权'));
      core.events.add({'jobId': 'mine', 'progress': .2});
      expect(request.phase, contains('机身确认'));
      core.events.add({'jobId': 'mine', 'progress': .4});
      expect(request.phase, contains('事件通道'));
      core.events.add({'jobId': 'mine', 'progress': .6});
      expect(request.phase, contains('相机信息与读取能力'));
      expect(request.busy, true);
      await tester.pump(const Duration(seconds: 3));
      expect(request.elapsedSeconds, 3);
      core.requests.single.result.complete({
        'connected': true,
        'session': 'real-reply',
      });
      await tester.pump();
      expect((await future)['session'], 'real-reply');
      expect(request.busy, false);
      request.dispose();
      await core.events.close();
    },
  );

  testWidgets(
    'Camera cancellation completes immediately even if native cancellation acknowledgement is blocked and rejects late results',
    (tester) async {
      final core = _ConnectionCore()..cancelGate = Completer<void>();
      final request = CameraConnectionRequest(core);
      final old = request.run(
        'camera.connect',
        {},
        'old',
        timeout: const Duration(seconds: 125),
      );
      final rejected = expectLater(old, throwsA(isA<AppFailure>()));
      request.cancel();
      await tester.pump();
      await rejected;
      expect(request.busy, false);
      expect(core.cancelled, ['old']);
      final next = request.run(
        'camera.connect',
        {},
        'new',
        timeout: const Duration(seconds: 125),
      );
      core.requests.first.result.complete({'session': 'stale'});
      await tester.pump();
      expect(request.busy, true);
      expect(request.jobId, 'new');
      core.requests.last.result.complete({'session': 'fresh'});
      await tester.pump();
      expect((await next)['session'], 'fresh');
      core.cancelGate!.complete();
      request.dispose();
      await core.events.close();
    },
  );

  testWidgets(
    'Camera overall deadline cancels the exact native job and identifies the stalled phase',
    (tester) async {
      final core = _ConnectionCore();
      final request = CameraConnectionRequest(core);
      final future = request.run(
        'camera.connect',
        {},
        'deadline',
        timeout: const Duration(seconds: 5),
      );
      final rejected = expectLater(
        future,
        throwsA(
          isA<AppFailure>().having((e) => e.message, 'phase', contains('机身确认')),
        ),
      );
      core.events.add({'jobId': 'deadline', 'progress': .2});
      await tester.pump(const Duration(seconds: 6));
      await rejected;
      expect(request.busy, false);
      expect(core.cancelled, ['deadline']);
      core.requests.single.result.complete({'session': 'late'});
      await tester.pump();
      expect(request.busy, false);
      request.dispose();
      await core.events.close();
    },
  );

  testWidgets(
    'USB discovery is bounded and disposal cancels an in-flight permission wait without late notifications',
    (tester) async {
      final core = _ConnectionCore();
      final request = CameraConnectionRequest(core);
      var notices = 0;
      request.addListener(() => notices++);
      final future = request.run(
        'camera.usb.devices',
        {},
        'usb-permission',
        timeout: const Duration(seconds: 50),
      );
      final rejected = expectLater(future, throwsA(isA<AppFailure>()));
      expect(request.phase, contains('访问授权'));
      request.dispose();
      final before = notices;
      await tester.pump();
      await rejected;
      core.events.add({'jobId': 'usb-permission', 'progress': .7});
      core.requests.single.result.complete({'items': []});
      await tester.pump(const Duration(seconds: 60));
      expect(notices, before);
      expect(core.cancelled, ['usb-permission']);
      await core.events.close();
    },
  );

  Future<({AppState state, Future<bool> result})> open(
    WidgetTester tester,
    _ConnectionCore core,
  ) async {
    final state = AppState(core)..cameraVisible.value = true;
    addTearDown(() async {
      state.dispose();
      await core.events.close();
    });
    late Future<bool> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  key: const Key('caller-connect'),
                  onPressed: () => result = connectCamera(context, state),
                  child: const Text('预设调用方连接'),
                ),
                TextButton(
                  key: const Key('explicit-camera-photos'),
                  onPressed: () {
                    // The explicit Sync caller, as in the real tab host, owns
                    // visibility before the photo page inspects its session.
                    state.cameraVisible.value = true;
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => CameraPage(state: state),
                      ),
                    );
                  },
                  child: const Text('同步 → 相机照片'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('caller-connect')));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, '连接相机');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    return (state: state, result: result);
  }

  testWidgets(
    'Camera UI exposes phase and cancel while connecting and never displays a late cancelled session',
    (tester) async {
      final core = _ConnectionCore();
      final opened = await open(tester, core);
      final connection = core.requests.single;
      core.events.add({'jobId': connection.job, 'progress': .2});
      await tester.pump();
      expect(find.textContaining('机身确认连接'), findsOneWidget);
      await tester.tap(find.text('取消连接'));
      await tester.pumpAndSettle();
      expect(core.cancelled, contains(connection.job));
      connection.result.complete({
        'connected': true,
        'session': 'late',
        'model': '迟到相机',
      });
      await tester.pumpAndSettle();
      expect(find.text('迟到相机'), findsNothing);
      expect(core.requests.where((r) => r.operation == 'camera.page'), isEmpty);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(await opened.result, false);
      expect(core.cancelled, [connection.job]);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Connect-only returns success without reading photos; explicit Sync reads and cancels only its page job',
    (tester) async {
      final core = _ConnectionCore();
      final opened = await open(tester, core);
      final connection = core.requests.single;
      core.cameraStatus = {
        'connected': true,
        'session': 'camera',
        'model': 'Nikon fixture',
        'mode': 'photos',
        'photoConnected': true,
        'slotsConnected': false,
        'inventoryReady': false,
      };
      connection.result.complete(Map<String, dynamic>.of(core.cameraStatus));
      await tester.pumpAndSettle();
      expect(await opened.result, true);
      expect(find.byKey(const Key('caller-connect')), findsOneWidget);
      // A successful connection is handed back to the caller, with no implicit
      // inventory/page/preview request and no disposal cancel of the handshake.
      expect(core.requests, [connection]);
      expect(core.cancelled, isEmpty);
      await tester.tap(find.byKey(const Key('explicit-camera-photos')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(core.requests.last.operation, 'camera.page');
      expect(find.textContaining('读取相机照片目录与首屏'), findsOneWidget);
      expect(find.text('取消读取'), findsOneWidget);
      final page = core.requests.last;
      expect(page.operation, 'camera.page');
      expect(page.payload['session'], 'camera');
      await tester.ensureVisible(find.text('取消读取'));
      await tester.tap(find.text('取消读取'));
      // Retire the same native page future immediately. Do not ask
      // pumpAndSettle to wait while a mocked native IO or spinner stays pending.
      page.result.completeError(const AppFailure('已取消照片读取。'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(core.cancelled, [page.job]);
      expect(core.cancelled, isNot(contains(connection.job)));
      expect(find.textContaining('已读取 0 张'), findsNothing);
      final nativeStatus = await core.call('camera.status');
      expect(nativeStatus['connected'], true);
      expect(nativeStatus['session'], 'camera');
      expect(nativeStatus['mode'], 'photos');
      expect(core.requests.where((r) => r.operation == 'camera.connect'), [
        connection,
      ]);
      expect(
        core.requests.where((r) => r.operation == 'camera.disconnect'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(core.cancelled, [page.job]);
    },
  );
}
