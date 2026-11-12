import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/wired_camera.dart';

class WiredCore extends HueviaCore {
  List<Json> devices = [];
  bool denied = false;
  int permissions = 0;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    expect(operation, 'camera.usb.devices');
    return {'items': devices};
  }

  @override
  Future<void> requestUsbPermission(String id) async {
    permissions++;
    if (denied) throw const AppFailure('未获得 USB 访问权限');
  }
}

void main() {
  testWidgets(
    'USB discovery can refresh after attach, obtains permission and connects the selected device',
    (tester) async {
      final core = WiredCore();
      final selected = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WiredCameraPicker(
              core: core,
              enabled: true,
              onConnect: (id) async => selected.add(id),
            ),
          ),
        ),
      );
      await tester.tap(find.text('检测 USB 相机'));
      await tester.pumpAndSettle();
      expect(find.textContaining('尚未检测到相机'), findsOneWidget);
      core.devices = [
        {'id': 'usb-one', 'name': 'Nikon Z 6II'},
      ];
      await tester.tap(find.text('检测 USB 相机'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nikon Z 6II'));
      await tester.pumpAndSettle();
      expect(core.permissions, 1);
      expect(selected, ['usb-one']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'USB permission denial is visible and does not open a camera session',
    (tester) async {
      final core = WiredCore()
        ..denied = true
        ..devices = [
          {'id': 'usb-one', 'name': 'Nikon USB'},
        ];
      var connections = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WiredCameraPicker(
              core: core,
              enabled: true,
              onConnect: (_) async {
                connections++;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('检测 USB 相机'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nikon USB'));
      await tester.pumpAndSettle();
      expect(find.text('未获得 USB 访问权限'), findsOneWidget);
      expect(connections, 0);
    },
  );
}
