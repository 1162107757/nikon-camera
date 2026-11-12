import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/help.dart';
import 'package:huevia/theme.dart';
import 'package:huevia/app_stability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Diagnostic reports exclude payloads, credentials, device addresses and unexpected native fields', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      AppStability.channel,
      (_) async => jsonEncode({
        'platform': 'android',
        'sdk': 31,
        'lastJavaCrash': 'java.lang.IllegalStateException: secret-crash-message private-crash-path\n\tat cc.huevia.sharedapp.NativeMedia.render(NativeMedia.java:20)',
        'fingerprint': 'private-device-id',
      }),
    );
    messenger.setMockMethodCallHandler(HueviaCore.channel, (call) async {
      final operation = (call.arguments as Map)['operation'];
      if (operation == 'camera.diagnostics') {
        return jsonEncode({
          'connected': true,
          'totalHandles': 12,
          'observedObjects': 2,
          'host': 'secret-camera-address',
          'session': 'private-session',
          'trace': 'wall_ms=1 mono_ms=2 event=SHARED_PHOTO_PAGE_BEGIN\nsecret password\nwall_ms=2 mono_ms=3 event=PTP_REPLY op=0x1008 tx=4\n',
        });
      }
      if (operation == 'gallery.access') {
        return jsonEncode({'access': 'limited', 'assetId': 'private-asset'});
      }
      return '{}';
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(HueviaCore.channel, null),
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(AppStability.channel, null),
    );
    final core = HueviaCore();
    for (var i = 0; i < 130; i++) {
      await core.call('account.login', {
        'username': 'private-user',
        'password': 'secret-password',
      });
    }
    final snapshot = await diagnosticSnapshot(AppState(core));
    final encoded = jsonEncode(snapshot);
    for (final secret in [
      'secret-password',
      'private-user',
      'secret-camera-address',
      'private-session',
      'private-asset',
      'secret-crash-message',
      'private-crash-path',
      'private-device-id',
    ]) {
      expect(encoded.contains(secret), false);
    }
    expect((snapshot['operations'] as List).length, 128);
    expect(snapshot['camera']['trace'].length, 2);
    expect(snapshot['camera']['observedObjects'], 2);
    expect(snapshot['gallery']['access'], 'limited');
    expect(
      snapshot['appStability']['lastJavaCrash']['type'],
      'java.lang.IllegalStateException',
    );
  });
  testWidgets(
    'Help opens readable diagnostics and about opens a separate license page',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(HueviaCore.channel, (_) async => '{}');
      addTearDown(
        () => messenger.setMockMethodCallHandler(HueviaCore.channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: HelpPage(state: AppState(HueviaCore())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('导出诊断报告'), 300);
      await tester.tap(find.text('导出诊断报告'));
      await tester.pumpAndSettle();
      expect(find.text('诊断报告'), findsOneWidget);
      expect(find.text('导出 JSON'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: const AboutPage(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('开源许可'), 250);
      await tester.tap(find.text('开源许可'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
