import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_remote.dart';
import 'package:huevia/camera_slots.dart';
import 'package:huevia/domain.dart';

class ControlsCore extends HueviaCore {
  final calls = <String>[];
  bool pending = false, connected = true, capture = true;
  int remoteChecks = 0;
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
        remoteChecks = 0;
        pending = true;
        return remote();
      case 'camera.remote.check':
        // Initial post-shutter inventory can precede camera file creation.
        pending = ++remoteChecks < 2;
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

class LifecycleRemoteCore extends ControlsCore {
  bool viewing = false;
  final viewChanges = <bool>[];
  @override
  Json remote() => {...super.remote(), 'liveView': true, 'viewing': viewing};
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'camera.remote.view') {
      calls.add(operation);
      viewing = payload['enabled'] == true;
      viewChanges.add(viewing);
      return remote();
    }
    if (operation == 'camera.remote.frame') {
      calls.add(operation);
      return {'ready': false};
    }
    return super.call(operation, payload, jobId);
  }
}

void main() {
  testWidgets(
    'remote view survives inactive overlays but still pauses for actual background',
    (tester) async {
      final core = LifecycleRemoteCore();
      final state = AppState(core);
      await tester.pumpWidget(
        MaterialApp(home: CameraRemotePage(state: state)),
      );
      await tester.pumpAndSettle();
      expect(core.viewChanges, [true]);
      final beforeInactive = core.calls
          .where((c) => c == 'camera.remote.frame')
          .length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 400));
      expect(core.viewChanges, [true]);
      final afterInactive = core.calls
          .where((c) => c == 'camera.remote.frame')
          .length;
      expect(afterInactive, greaterThan(beforeInactive));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(core.viewChanges, [true, false]);
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        core.calls.where((c) => c == 'camera.remote.frame'),
        hasLength(afterInactive),
      );
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      state.dispose();
    },
  );
  testWidgets(
    'remote shutter remains blocked until the pending result is read',
    (tester) async {
      final core = ControlsCore();
      await tester.pumpWidget(
        MaterialApp(home: CameraRemotePage(state: AppState(core))),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('400'), 200);
      expect(find.text('ISO'), findsOneWidget);
      expect(find.text('400'), findsOneWidget);
      final shutter = find.byKey(const Key('remote-shutter'));
      await tester.ensureVisible(shutter);
      await tester.tap(shutter);
      await tester.pumpAndSettle();
      expect(
        core.calls.where((call) => call == 'camera.remote.capture'),
        hasLength(1),
      );
      expect(
        core.calls.where((call) => call == 'camera.remote.check'),
        hasLength(1),
      );
      expect(tester.widget<IconButton>(shutter).onPressed, isNull);
      await tester.tap(find.text('拍摄结果待核对'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('查看相机最近照片'));
      await tester.pumpAndSettle();
      expect(
        core.calls.where((call) => call == 'camera.remote.capture'),
        hasLength(1),
      );
      expect(
        core.calls.where((call) => call == 'camera.remote.check'),
        hasLength(2),
      );
      expect(tester.widget<IconButton>(shutter).onPressed, isNotNull);
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
      await tester.scrollUntilVisible(
        find.byKey(const Key('remote-shutter')),
        200,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('remote-shutter')))
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
      expect(find.byKey(const ValueKey('camera-slot-201')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('camera-slot-delete')));
      await tester.pumpAndSettle();
      expect(find.text('删除 C1？'), findsOneWidget);
      expect(core.calls.contains('camera.slots.execute'), isFalse);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(core.calls.contains('camera.slots.execute'), isFalse);
      await tester.tap(find.byKey(const ValueKey('camera-slot-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认删除此槽位'));
      await tester.pumpAndSettle();
      expect(
        core.calls.where((call) => call == 'camera.slots.execute'),
        hasLength(1),
      );
      expect(find.text('已读回核对'), findsOneWidget);
      expect(find.text('已删除 C1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
