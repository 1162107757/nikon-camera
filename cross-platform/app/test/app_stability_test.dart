import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/app_stability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Android crash evidence retains type, code locations and OS memory reasons without private messages', () {
    final value = AppStability.redactSnapshot({
      'platform': 'android',
      'sdk': 31,
      'manufacturer': 'HONOR',
      'model': 'Magic',
      'fingerprint': 'private-build-id',
      'lastJavaCrash': 'recordedAtEpochMillis=1234\nthread=private-user\nheapMax=10000\nheapUsed=9000\njava.lang.OutOfMemoryError: secret-camera-address /private/photos/secret.NEF\n\tat cc.huevia.sharedapp.NativeMedia.render(NativeMedia.java:200)\nCaused by: java.io.IOException: secret-password\n\tat cc.huevia.album.PtpIpClient.read(PtpIpClient.java:90)',
      'processExitHistoryAvailable': true,
      'processExitHistory': [
        {
          'reason': 3,
          'status': 0,
          'timestamp': 123,
          'pssKb': 100,
          'rssKb': 200,
          'description': 'secret-user',
          'trace': 'secret-password',
          'traceBase64': 'private-photo-bytes',
          'processName': 'private-process',
        },
      ],
    });
    expect(value['available'], true);
    expect(value['lastJavaCrash']['type'], 'java.lang.OutOfMemoryError');
    expect(value['lastJavaCrash']['heapUsed'], 9000);
    expect(value['lastJavaCrash']['frames'], [
      'at cc.huevia.sharedapp.NativeMedia.render(NativeMedia.java:200)',
      'at cc.huevia.album.PtpIpClient.read(PtpIpClient.java:90)',
    ]);
    expect(value['processExitHistory'], [
      {'reason': 3, 'status': 0, 'timestamp': 123, 'pssKb': 100, 'rssKb': 200},
    ]);
    final encoded = jsonEncode(value);
    for (final secret in [
      'secret',
      'private',
      'fingerprint',
      'traceBase64',
      'description',
      'processName',
    ]) {
      expect(encoded.contains(secret), false);
    }
  });
  test('iOS exception and delivered MetricKit summaries exclude symbols, paths and exception reasons', () {
    final value = AppStability.redactSnapshot({
      'platform': 'ios',
      'uncaughtExceptionHandlerInstalled': true,
      'metricKitRegistered': true,
      'lastNativeException': {
        'recordedAtEpochMillis': 300,
        'type': 'NSInvalidArgumentException',
        'reason': 'private-user',
        'frames': [
          '-[HueviaMedia request:payload:task:]',
          '/private/container/secret.NEF',
          '0x12345 private-device-id',
        ],
      },
      'metricKitCrashes': [
        {
          'windowStartedAt': 100,
          'windowEndedAt': 200,
          'signal': 11,
          'exceptionType': 1,
          'terminationReason': 'secret',
          'callStackTree': {'binaryUUID': 'private-device-id'},
        },
      ],
      'metricKitExits': {
        'windowStartedAt': 100,
        'windowEndedAt': 200,
        'foregroundMemoryLimit': 1,
        'backgroundMemoryPressure': 2,
        'includesMultipleAppVersions': true,
        'latestAppVersion': '0.31.0-dev',
        'description': 'private-path',
      },
    });
    expect(value['lastNativeException']['frames'], [
      '-[HueviaMedia request:payload:task:]',
    ]);
    expect(value['metricKitCrashes'], [
      {
        'windowStartedAt': 100,
        'windowEndedAt': 200,
        'signal': 11,
        'exceptionType': 1,
      },
    ]);
    expect(value['metricKitDelivery'], 'system-managed');
    expect(value['metricKitExits']['foregroundMemoryLimit'], 1);
    expect(value['metricKitExits']['backgroundMemoryPressure'], 2);
    expect(value['metricKitExits']['countsForReportingWindow'], true);
    expect(jsonEncode(value).contains('private'), false);
    expect(jsonEncode(value).contains('secret'), false);
  });
  test('Dart records do not serialize exception messages or absolute file locations', () {
    final record = AppStability.flutterRecord(
      const FormatException('private-token secret.NEF'),
      StackTrace.fromString(
        '#0 Editor.render (package:huevia/editor.dart:42:9)\n#1 bad (/Users/private-user/secret.NEF:4:5)\n#2 helper (dart:async/zone.dart:20:7)',
      ),
      'framework',
    );
    expect(record['type'], 'FormatException');
    expect(record['kind'], 'framework');
    expect(record['frames'], [
      'Editor.render (package:huevia/editor.dart:42:9)',
      'helper (dart:async/zone.dart:20:7)',
    ]);
    expect(jsonEncode(record).contains('private'), false);
    expect(jsonEncode(record).contains('secret'), false);
  });
  test('Record count, stack count, numeric range and individual frames stay bounded', () {
    final native = {
      'platform': 'android',
      'lastJavaCrash':
          'heapMax=999999999999999999\n${'A' * 200}Error: private\n${'at test.Type.call(Call.java:9)\n' * 1000}${'private' * 20000}',
      'processExitHistory': List.generate(
        20,
        (_) => {'timestamp': -1, 'reason': 3, 'rssKb': 9007199254740992},
      ),
      'lastFlutterError': {
        'type': 'Error',
        'kind': 'anything',
        'frames': List.generate(
          100,
          (_) => 'call (package:huevia/editor.dart:1:2)',
        ),
      },
    };
    final value = AppStability.redactSnapshot(native);
    expect(value['lastJavaCrash']['frames'], hasLength(48));
    expect(value['lastJavaCrash']['type'], isNull);
    expect(value['lastJavaCrash']['heapMax'], isNull);
    expect(value['lastFlutterError']['frames'], hasLength(48));
    expect(value['processExitHistory'], List.generate(4, (_) => {'reason': 3}));
    expect(jsonEncode(value).length, lessThan(32768));
  });
  test('Native journal is best effort and unavailable collectors preserve safe diagnostics', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(
      () => messenger.setMockMethodCallHandler(AppStability.channel, null),
    );
    Map<dynamic, dynamic>? persisted;
    messenger.setMockMethodCallHandler(AppStability.channel, (call) async {
      if (call.method == 'recordFlutter') {
        persisted = Map<dynamic, dynamic>.from(call.arguments as Map);
        return null;
      }
      return jsonEncode({
        'platform': 'android',
        'lastFlutterError': persisted,
        'unexpected': 'secret',
      });
    });
    AppStability.record(
      StateError('private-payload'),
      StackTrace.fromString('#0 preview (package:huevia/editor.dart:1:2)'),
      'unhandled',
    );
    await Future<void>.delayed(Duration.zero);
    final value = await AppStability.snapshot();
    expect(value['lastFlutterError']['type'], 'StateError');
    expect(value['available'], true);
    expect(jsonEncode(persisted).contains('private'), false);
    expect(jsonEncode(value).contains('secret'), false);
    messenger.setMockMethodCallHandler(AppStability.channel, (_) async {
      throw MissingPluginException('Test collector unavailable');
    });
    final unavailable = await AppStability.snapshot();
    expect(unavailable['available'], false);
    expect(unavailable['lastFlutterError']['type'], 'StateError');
  });
  test('Installing capture twice keeps existing Flutter and platform error handlers in charge', () async {
    final framework = FlutterError.onError,
        asynchronous = PlatformDispatcher.instance.onError;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AppStability.channel, (_) async => null);
    var frameworkCalls = 0, asyncCalls = 0;
    FlutterError.onError = (_) {
      frameworkCalls++;
    };
    PlatformDispatcher.instance.onError = (_, _) {
      asyncCalls++;
      return false;
    };
    try {
      AppStability.install();
      AppStability.install();
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError('private'),
          stack: StackTrace.empty,
        ),
      );
      final handled = PlatformDispatcher.instance.onError!(
        StateError('private'),
        StackTrace.empty,
      );
      expect(frameworkCalls, 1);
      expect(asyncCalls, 1);
      expect(handled, false);
      await Future<void>.delayed(Duration.zero);
    } finally {
      FlutterError.onError = framework;
      PlatformDispatcher.instance.onError = asynchronous;
      messenger.setMockMethodCallHandler(AppStability.channel, null);
    }
  });
}
