import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/personal_sync.dart';
import 'package:huevia/theme.dart';

class RaceCore extends HueviaCore {
  final initialCamera = Completer<Json>();
  final List<(String, Json)> calls = [];
  final cancelled = <String>[];
  int cameraStatusRequests = 0;
  Json cameraStatus = {'connected': false, 'session': '', 'model': ''};
  @override
  Stream<dynamic> get operationProgress => const Stream<dynamic>.empty();
  @override
  Future<void> cancel(String id) async => cancelled.add(id);
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    switch (operation) {
      case 'camera.status':
        // Only the first status is held; later explicit photo routes inspect the
        // current native session rather than replaying that stale response.
        if (cameraStatusRequests++ == 0) return initialCamera.future;
        return Map<String, dynamic>.of(cameraStatus);
      case 'camera.connect':
        cameraStatus = {
          'connected': true,
          'session': 'new-session',
          'model': '已核对相机',
          'mode': 'photos',
          'photoConnected': true,
          'slotsConnected': false,
          'inventoryReady': false,
        };
        return Map<String, dynamic>.of(cameraStatus);
      case 'camera.page':
        return {'items': [], 'nextOffset': 0, 'hasMore': false};
      case 'personal.status':
        return {'consentNeeded': true, 'unclaimed': 2, 'conflicts': 0};
      case 'personal.consent':
      case 'personal.sync':
        return {'consentNeeded': false, 'unclaimed': 2, 'conflicts': 0};
      case 'library.list':
        return {'items': []};
      default:
        throw AppFailure(operation);
    }
  }
}

void main() {
  testWidgets(
    'Late old status cannot replace a connect-only session; only explicit Sync pages with the new session',
    (tester) async {
      final core = RaceCore();
      final actualState = AppState(core)..cameraVisible.value = true;
      addTearDown(actualState.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: CameraPage(state: actualState, configuration: true),
        ),
      );
      final connect = find.byKey(const Key('camera-connect'));
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await tester.pumpAndSettle();
      expect(find.text('已核对相机'), findsOneWidget);
      expect(find.text('相机已连接。返回上一页继续操作。'), findsOneWidget);
      expect(core.calls.where((call) => call.$1 == 'camera.page'), isEmpty);
      core.initialCamera.complete({
        'connected': false,
        'session': '',
        'model': '',
      });
      await tester.pumpAndSettle();
      expect(find.text('已核对相机'), findsOneWidget);
      expect(find.text('相机已连接。返回上一页继续操作。'), findsOneWidget);
      expect(core.calls.where((call) => call.$1 == 'camera.page'), isEmpty);
      // A later, explicitly opened photo route gets a fresh State/status read.
      // The configuration page must not read photos or cancel its completed job.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(core.cancelled, isEmpty);
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: CameraPage(state: actualState),
        ),
      );
      await tester.pumpAndSettle();
      // Explicitly entering Sync / camera photos is the user's browse action;
      // the connection configuration above must never trigger this request.
      expect(
        core.calls.lastWhere((call) => call.$1 == 'camera.page').$2['session'],
        'new-session',
      );
      expect(
        core.calls.where((call) => call.$1 == 'camera.connect'),
        hasLength(1),
      );
      expect(
        core.calls.where((call) => call.$1 == 'camera.page'),
        hasLength(1),
      );
      expect(find.text('已核对相机 · 已连接'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(core.cancelled, isEmpty);
    },
  );
  testWidgets(
    'Personal sync respects the explicit existing-preset choice and pins every request to the owner',
    (tester) async {
      const owner = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
      final core = RaceCore();
      final actualState = AppState(core)
        ..session = {
          'user': {'id': owner},
        };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('cc.huevia/events'),
            (_) async => null,
          );
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: PersonalSyncPage(state: actualState),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即同步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('仅同步账号预设'));
      await tester.pumpAndSettle();
      expect(
        core.calls
            .firstWhere((call) => call.$1 == 'personal.consent')
            .$2['includeExisting'],
        false,
      );
      for (final call in core.calls.where(
        (call) => call.$1.startsWith('personal.'),
      )) {
        expect(call.$2['owner'], owner);
      }
      expect(find.text('同步已完成。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('cc.huevia/events'),
            null,
          );
      actualState.dispose();
    },
  );
}
