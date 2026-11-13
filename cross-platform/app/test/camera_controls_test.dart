import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_remote.dart';
import 'package:huevia/camera_slots.dart';
import 'package:huevia/domain.dart';

class ControlsCore extends HueviaCore {
  final calls = <String>[];
  bool pending = false, connected = true, capture = true;
  Json remote() => {
    'session': 'album',
    'remoteId': 'remote',
    'model': 'Nikon test',
    'connected': true,
    'liveView': false,
    'autoFocus': true,
    'pointFocus': false,
    'viewing': false,
    'capture': capture,
    'parameters': [
      {'code': 0x500f, 'value': 400, 'writable': false},
    ],
    'action': {'pending': pending, 'actionId': 'shutter-one'},
  };
  Json slots() => {
    'session': 'slots',
    'model': 'Nikon test',
    'canWrite': true,
    'canDelete': true,
    'consumed': false,
    'action': {'pending': false},
    'items': [
      {
        'target': 201,
        'label': 'C1',
        'name': 'SOURCE',
        'empty': false,
        'sha256': 'a' * 64,
      },
      {
        'target': 202,
        'label': 'C2',
        'name': '',
        'empty': true,
        'sha256': 'b' * 64,
      },
    ],
  };
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add(operation);
    switch (operation) {
      case 'camera.status':
        return {'connected': connected, 'session': 'album'};
      case 'camera.remote.open':
      case 'camera.remote.status':
        return remote();
      case 'camera.remote.capture':
        pending = true;
        return remote();
      case 'camera.remote.check':
        pending = false;
        return remote();
      case 'camera.remote.focus':
        return remote();
      case 'camera.remote.close':
        return {'closed': true};
      case 'camera.slots.open':
      case 'camera.slots.refresh':
        return slots();
      case 'camera.slots.prepare':
        return {
          'confirmationId': 'confirm',
          'targetLabel': 'C1',
          'beforeName': 'SOURCE',
          'overwrite': true,
          'name': '',
          'explanation': '',
        };
      case 'camera.slots.execute':
        return {
          ...slots(),
          'consumed': true,
          'action': {'pending': false, 'phase': 'verified'},
        };
      case 'camera.slots.close':
        return {'closed': true};
      default:
        throw StateError('Unexpected camera request: $operation');
    }
  }
}

void main() {
  testWidgets(
    'remote shutter remains blocked until the pending result is read',
    (tester) async {
      final core = ControlsCore();
      await tester.pumpWidget(
        MaterialApp(home: CameraRemotePage(state: AppState(core))),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('ISO 400'), 200);
      expect(find.text('ISO 400'), findsOneWidget);
      final shutter = find.widgetWithText(FilledButton, '拍摄一张并保存到相机');
      await tester.ensureVisible(shutter);
      await tester.tap(shutter);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('拍摄一张并保存到相机'), 200);
      expect(
        core.calls.where((call) => call == 'camera.remote.capture'),
        hasLength(1),
      );
      expect(tester.widget<FilledButton>(shutter).onPressed, isNull);
      final check = find.text('读取拍摄结果');
      await tester.ensureVisible(check);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(
        core.calls.where((call) => call == 'camera.remote.capture'),
        hasLength(1),
      );
      expect(tester.widget<FilledButton>(shutter).onPressed, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'remote capabilities disable shutter and disconnected entry recovers',
    (tester) async {
      final core = ControlsCore()..capture = false;
      await tester.pumpWidget(
        MaterialApp(home: CameraRemotePage(state: AppState(core))),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('拍摄一张并保存到相机'), 200);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '拍摄一张并保存到相机'),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      final disconnected = ControlsCore()..connected = false;
      await tester.pumpWidget(
        MaterialApp(home: CameraRemotePage(state: AppState(disconnected))),
      );
      await tester.pumpAndSettle();
      expect(find.text('请先连接尼康相机，再打开遥控拍摄。'), findsOneWidget);
      expect(disconnected.calls, ['camera.status']);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'slot deletion requires the final target confirmation and cancellation sends nothing',
    (tester) async {
      final core = ControlsCore();
      await tester.pumpWidget(
        MaterialApp(home: CameraSlotsPage(state: AppState(core))),
      );
      await tester.pumpAndSettle();
      expect(find.text('C1 · SOURCE'), findsOneWidget);
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除此槽位'));
      await tester.pumpAndSettle();
      expect(find.text('删除 C1？'), findsOneWidget);
      expect(core.calls.contains('camera.slots.execute'), isFalse);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(core.calls.contains('camera.slots.execute'), isFalse);
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除此槽位'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认删除此槽位'));
      await tester.pumpAndSettle();
      expect(
        core.calls.where((call) => call == 'camera.slots.execute'),
        hasLength(1),
      );
      expect(find.text('已精确读回核对，目标及其他槽位符合预期。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
