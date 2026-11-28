import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';

import 'camera_intent_test.dart' as intent;

class _TransportCore extends intent.IntentCameraCore {
  int permissions = 0;
  Completer<Json>? discovery;
  bool denied = false;
  bool closeOnFailedConnection = false;
  List<Json> devices = [
    {'id': 'z6-two', 'name': 'Nikon Z 6II', 'permission': false},
    {'id': 'z-f', 'name': 'Nikon Z f', 'permission': true},
  ];

  @override
  Future<void> requestUsbPermission(String id) async {
    permissions++;
    if (denied) throw const AppFailure('未获得 USB 访问权限');
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'camera.usb.devices') {
      calls.add((operation, Map.of(payload), jobId));
      return discovery == null ? {'items': devices} : discovery!.future;
    }
    if (operation == 'camera.connect') {
      if (connectionError == null) {
        transport = payload['transport'] as String? ?? 'wifi';
      } else if (closeOnFailedConnection) {
        connected = false;
      }
    }
    final result = await super.call(operation, payload, jobId);
    if (operation == 'camera.status' || operation == 'camera.connect') {
      return {...result, 'transport': transport};
    }
    return result;
  }
}

Future<void> _open(
  WidgetTester tester,
  _TransportCore core, {
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  final state = AppState(core);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    state.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => connectCamera(context, state),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final closes in [true, false]) {
    testWidgets(
      'Replacement failure refreshes actual native connection; old session closed=$closes',
      (tester) async {
        final core = _TransportCore()
          ..connected = true
          ..transport = 'usb'
          ..closeOnFailedConnection = closes
          ..connectionError = const AppFailure('连接等待已超时');
        await _open(tester, core);
        await tester.tap(find.text('Wi-Fi 无线'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('camera-connect')));
        await tester.pumpAndSettle();
        expect(core.calls.where((c) => c.$1 == 'camera.connect'), hasLength(1));
        expect(core.calls.last.$1, 'camera.status');
        await tester.tap(find.text('USB 有线'));
        await tester.pumpAndSettle();
        expect(find.text('返回继续操作'), closes ? findsNothing : findsOneWidget);
        expect(core.disconnectsApplied, 0);
        expect(core.calls.where((c) => c.$1 == 'camera.page'), isEmpty);
      },
    );
  }

  testWidgets(
    'Every new connection starts on Wi-Fi without USB scanning; mode switches preserve selected USB device without granting permission',
    (tester) async {
      final core = _TransportCore();
      await _open(tester, core);
      expect(find.text('Wi-Fi 无线'), findsOneWidget);
      expect(find.text('USB 有线'), findsOneWidget);
      expect(core.calls.where((c) => c.$1 == 'camera.usb.devices'), isEmpty);
      await tester.tap(find.text('USB 有线'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('usb-device-z-f')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nikon Z f'));
      await tester.pumpAndSettle();
      expect(core.permissions, 0);
      expect(core.calls.where((c) => c.$1 == 'camera.connect'), isEmpty);
      await tester.ensureVisible(find.text('Wi-Fi 无线'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wi-Fi 无线'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('USB 有线'));
      await tester.pumpAndSettle();
      expect(
        core.calls.where((c) => c.$1 == 'camera.usb.devices'),
        hasLength(1),
      );
      await tester.tap(find.byKey(const Key('camera-usb-connect')));
      await tester.pumpAndSettle();
      final connect = core.calls.singleWhere((c) => c.$1 == 'camera.connect');
      expect(connect.$2['transport'], 'usb');
      expect(connect.$2['deviceId'], 'z-f');
      expect(core.permissions, 1);
      expect(find.text('open'), findsOneWidget);
      expect(core.calls.where((c) => c.$1 == 'camera.page'), isEmpty);
      expect(core.cancelled, isEmpty);
    },
  );

  testWidgets(
    'USB permission denial remains on the selected transport and can retry explicitly',
    (tester) async {
      final core = _TransportCore()..denied = true;
      await _open(tester, core);
      await tester.tap(find.text('USB 有线'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('camera-usb-connect')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('未获得 USB 访问权限'));
      expect(find.text('未获得 USB 访问权限'), findsOneWidget);
      expect(core.calls.where((c) => c.$1 == 'camera.connect'), isEmpty);
      core.denied = false;
      await tester.tap(find.byKey(const Key('camera-usb-connect')));
      await tester.pumpAndSettle();
      expect(core.permissions, 2);
      expect(core.calls.where((c) => c.$1 == 'camera.connect'), hasLength(1));
    },
  );

  testWidgets(
    'An occupied Nikon USB session can be recovered explicitly on the same device',
    (tester) async {
      final core = _TransportCore()
        ..platform = 'android'
        ..connectionError = const AppFailure(
          '相机仍保留着 USB 会话',
          details: {'recoverUsbSession': true},
        );
      await _open(tester, core);
      await tester.tap(find.text('USB 有线'));
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('camera-usb-connect'));
      await tester.tap(button);
      await tester.pumpAndSettle();
      final first = core.calls.singleWhere((c) => c.$1 == 'camera.connect');
      expect(first.$2['deviceId'], 'z6-two');
      expect(first.$2.containsKey('recoverUsbSession'), isFalse);
      expect(find.text('已检测到 · 等待授权'), findsNothing);
      expect(find.text('恢复 USB 会话'), findsOneWidget);

      core.connectionError = null;
      await tester.tap(button);
      await tester.pumpAndSettle();
      final retry = core.calls.where((c) => c.$1 == 'camera.connect').toList();
      expect(retry, hasLength(2));
      expect(retry.last.$2['deviceId'], first.$2['deviceId']);
      expect(retry.last.$2['recoverUsbSession'], true);
      expect(retry.last.$2['requireDisconnected'], true);
      expect(find.text('open'), findsOneWidget);
    },
  );

  testWidgets(
    'USB discovery cancellation owns only discovery and leaves an existing Wi-Fi session intact',
    (tester) async {
      final core = _TransportCore()..connected = true;
      await _open(tester, core);
      core.discovery = Completer<Json>();
      await tester.tap(find.text('USB 有线'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final discovery = core.calls.singleWhere(
        (c) => c.$1 == 'camera.usb.devices',
      );
      await tester.tap(find.byKey(const Key('camera-usb-connect')));
      await tester.pumpAndSettle();
      expect(core.cancelled, [discovery.$3]);
      expect(core.disconnectsApplied, 0);
      expect(
        core.calls.where(
          (c) => c.$1 == 'camera.connect' || c.$1 == 'camera.disconnect',
        ),
        isEmpty,
      );
      await tester.tap(find.text('Wi-Fi 无线'));
      await tester.pumpAndSettle();
      expect(find.text('返回继续操作'), findsOneWidget);
      core.discovery!.complete({'items': core.devices});
      await tester.pumpAndSettle();
      expect(core.disconnectsApplied, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'An existing USB session is identified as USB and returning does not reconnect as Wi-Fi',
    (tester) async {
      final core = _TransportCore()
        ..connected = true
        ..transport = 'usb';
      await _open(tester, core);
      expect(find.text('返回继续操作'), findsOneWidget);
      expect(find.byKey(const Key('camera-reconnect')), findsNothing);
      expect(core.calls.where((c) => c.$1 == 'camera.usb.devices'), isEmpty);
      await tester.tap(find.text('返回继续操作'));
      await tester.pumpAndSettle();
      expect(
        core.calls.where(
          (c) => c.$1 == 'camera.connect' || c.$1 == 'camera.disconnect',
        ),
        isEmpty,
      );
      expect(core.cancelled, isEmpty);
    },
  );

  testWidgets(
    'Approved transport layout keeps fixed actions accessible on a narrow screen with large text and dark mode',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final core = _TransportCore();
      await _open(tester, core, scale: 1.8, brightness: Brightness.dark);
      expect(
        tester.getRect(find.byKey(const Key('camera-connect'))).bottom,
        lessThan(700),
      );
      await tester.tap(find.text('USB 有线'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const Key('camera-usb-connect'))).bottom,
        lessThan(700),
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('usb-device-z6-two')),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
