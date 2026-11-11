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
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    switch (operation) {
      case 'camera.status':
        return initialCamera.future;
      case 'camera.connect':
        return {'connected': true, 'session': 'new-session', 'model': '已核对相机'};
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
    'An old camera status cannot replace a newly established session',
    (tester) async {
      final core = RaceCore();
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: CameraPage(state: AppState(core), configuration: true),
        ),
      );
      await tester.tap(find.text('连接相机'));
      await tester.pumpAndSettle();
      expect(find.text('已连接 · 原文件按字节接收'), findsOneWidget);
      core.initialCamera.complete({
        'connected': false,
        'session': '',
        'model': '',
      });
      await tester.pumpAndSettle();
      expect(find.text('已连接 · 原文件按字节接收'), findsOneWidget);
      expect(
        core.calls.lastWhere((call) => call.$1 == 'camera.page').$2['session'],
        'new-session',
      );
      expect(tester.takeException(), isNull);
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
