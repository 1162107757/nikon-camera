import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_location.dart';
import 'package:huevia/theme.dart';
// The platform package supplies the in-memory implementation for this test.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets(
    'location is sent only after pairing and reports success after camera response',
    (tester) async {
      const method = MethodChannel('cc.huevia/camera-location');
      const event = MethodChannel('cc.huevia/camera-location/events');
      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final prior = SharedPreferencesAsyncPlatform.instance;
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      addTearDown(() => SharedPreferencesAsyncPlatform.instance = prior);
      messenger.setMockMethodCallHandler(event, (_) async => null);
      final ack = Completer<void>();
      final calls = <String>[];
      var scans = 0;
      Future<void> emit(String type, Uint8List bytes) =>
          messenger.handlePlatformMessage(
            event.name,
            codec.encodeSuccessEnvelope({'type': type, 'bytes': bytes}),
            (_) {},
          );
      messenger.setMockMethodCallHandler(method, (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'scan':
            scans++;
            return [
              {'id': scans == 1 ? 'first' : 'second', 'name': 'Z6 II'},
            ];
          case 'encrypt':
            // The separate wire test verifies real Blowfish known answers.
            return Uint8List(8);
          case 'connect':
            expect(call.arguments['id'], scans == 1 ? 'first' : 'second');
          case 'write':
            final type = call.arguments['type'];
            final value = call.arguments['bytes'] as Uint8List;
            if (type == 'pair' && value.first == 1) {
              await emit('pair', Uint8List(17)..[0] = 2);
            } else if (type == 'pair' && value.first == 3) {
              await emit(
                'pair',
                Uint8List(17)
                  ..[0] = 4
                  ..setAll(9, '12345678'.codeUnits),
              );
              await emit('ready', Uint8List.fromList([1, 0]));
            } else if (type == 'location') {
              expect(scans, 2);
              expect(value, hasLength(41));
              calls.add('location-write');
              await ack.future;
            }
          case 'locate':
            expect(calls, contains('pairClassic'));
            return {
              'latitude': 23.0,
              'longitude': 114.0,
              'altitude': 75.0,
              'accuracy': 20.0,
              'time': DateTime.now().millisecondsSinceEpoch,
            };
        }
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: const CameraLocationPage(),
        ),
      );
      expect(calls, isEmpty);
      await tester.tap(find.text('搜索蓝牙相机'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Z6 II'));
      await tester.pumpAndSettle();
      expect(calls.where((call) => call == 'pairClassic'), hasLength(1));
      expect(calls, contains('location-write'));
      expect(find.text('位置已发送给相机'), findsNothing);
      ack.complete();
      await tester.pumpAndSettle();
      expect(find.text('位置已发送给相机'), findsOneWidget);
      await tester.tap(find.text('停止同步'));
      await tester.pump(const Duration(seconds: 20));
      expect(calls.last, 'stop');
      expect(calls.where((call) => call == 'location-write'), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
