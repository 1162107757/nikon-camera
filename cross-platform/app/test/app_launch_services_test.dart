import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/app_launch_services.dart';
import 'package:huevia/domain.dart';

void main() {
  test(
    'mandatory update is scheduled while anonymous usage is still pending',
    () async {
      final usage = Completer<void>();
      var prompts = 0;
      await coordinateLaunchChecks(
        usage: usage.future,
        update: Future<void>.value(),
        mandatory: () => true,
        notify: () => prompts++,
      );
      expect(prompts, 1);
      expect(usage.isCompleted, isFalse);
      usage.complete();
      await Future<void>.delayed(Duration.zero);
      expect(prompts, 1);
    },
  );
  test(
    'optional reminder waits for probability sync and tolerates usage failure',
    () async {
      final usage = Completer<void>();
      var prompts = 0;
      final ready = coordinateLaunchChecks(
        usage: usage.future,
        update: Future<void>.value(),
        mandatory: () => false,
        notify: () => prompts++,
      );
      await Future<void>.delayed(Duration.zero);
      expect(prompts, 0);
      usage.completeError(StateError('offline'));
      await ready;
      expect(prompts, 1);
    },
  );
  test(
    'same version can remind again next launch after an earlier dismissal',
    () {
      final first = LaunchUpdateGate(draw: .2);
      expect(first.eligible(mandatory: false, probability: .5), isTrue);
      first.shown = true;
      expect(first.eligible(mandatory: false, probability: .5), isFalse);
      expect(
        LaunchUpdateGate(draw: .2).eligible(mandatory: false, probability: .5),
        isTrue,
      );
    },
  );
  test('one draw per launch; probability boundaries and mandatory updates', () {
    final gate = LaunchUpdateGate(draw: .7);
    expect(gate.eligible(mandatory: false, probability: .5), isFalse);
    expect(gate.eligible(mandatory: false, probability: .5), isFalse);
    expect(gate.eligible(mandatory: false, probability: 0), isFalse);
    expect(gate.eligible(mandatory: false, probability: 1), isTrue);
    gate.shown = true;
    expect(gate.eligible(mandatory: true, probability: 0), isTrue);
  });
  testWidgets(
    'iOS update prompts and opens the IPA directly on the first tap',
    (tester) async {
      final state = AppState(HueviaCore());
      final navigator = GlobalKey<NavigatorState>();
      final download = Uri.parse(
        'https://huevia.cc/preset-library/ios/releases/dd87c30e-75e5-40a7-8eb4-e85cde60254e/file',
      );
      final service =
          AppLaunchServices(
              state: state,
              navigatorKey: navigator,
              canPrompt: () => true,
            )
            ..probability = 0
            ..available = {'versionName': '0.31.1', 'versionCode': 242}
            ..iosDownload = download;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final launches = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        launches.add(call);
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        service.dispose();
        state.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: const Scaffold(body: Text('首页')),
        ),
      );
      service.schedulePrompt();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 0.31.1 · 构建 242'), findsOneWidget);
      await tester.tap(find.text('下载 IPA'));
      await tester.pumpAndSettle();

      expect(launches, hasLength(1));
      expect(launches.single.method, 'launch');
      expect(launches.single.arguments['url'], '$download');
      expect(launches.single.arguments['useSafariVC'], false);
      expect(launches.single.arguments['useWebView'], false);
      expect(find.text('首页'), findsOneWidget);
      expect(navigator.currentState!.canPop(), false);
    },
  );
  test(
    'anonymous ID is a random UUID and has no account or hardware identifier',
    () {
      final ids = List.generate(100, (_) => newUsageId());
      expect(ids.toSet(), hasLength(100));
      for (final id in ids) {
        expect(
          id,
          matches(
            RegExp(
              r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
            ),
          ),
        );
      }
    },
  );
}
