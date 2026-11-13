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
      return Future.value({'connected': false, 'session': '', 'model': ''});
    }
    final request = _CameraRequest(operation, payload, jobId ?? '');
    requests.add(request);
    return request.result.future;
  }
}

void main() {
  testWidgets(
    'Camera connection reports actual permission, confirmation, session and inventory phases for only its job',
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
      core.events.add({'jobId': 'mine', 'progress': .7});
      expect(request.phase, contains('存储卡照片目录'));
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

  Future<void> open(WidgetTester tester, _ConnectionCore core) async {
    final state = AppState(core);
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.light),
        home: CameraPage(state: state, configuration: true),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, '连接相机');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  testWidgets(
    'Camera UI exposes phase and cancel while connecting and never displays a late cancelled session',
    (tester) async {
      final core = _ConnectionCore();
      await open(tester, core);
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
      await tester.pumpWidget(const SizedBox());
      await core.events.close();
    },
  );

  testWidgets(
    'Successful handshake changes the UI from connecting to bounded first-page reading with its own cancel',
    (tester) async {
      final core = _ConnectionCore();
      await open(tester, core);
      core.requests.single.result.complete({
        'connected': true,
        'session': 'camera',
        'model': 'Nikon fixture',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('读取相机照片目录与首屏'), findsOneWidget);
      expect(find.text('取消读取'), findsOneWidget);
      final page = core.requests.last;
      expect(page.operation, 'camera.page');
      await tester.tap(find.text('取消读取'));
      await tester.pumpAndSettle();
      expect(core.cancelled, contains(page.job));
      page.result.complete({'items': [], 'nextOffset': 0, 'hasMore': false});
      await tester.pumpAndSettle();
      expect(find.text('已连接 · 原文件按字节接收'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await core.events.close();
    },
  );
}
