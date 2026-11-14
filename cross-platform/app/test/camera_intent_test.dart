import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera.dart';
import 'package:huevia/camera_slots.dart';
import 'package:huevia/camera_remote.dart';
import 'package:huevia/camera_live.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/legacy_preset_details.dart';
import 'package:huevia/theme.dart';

class IntentCameraCore extends HueviaCore {
  final calls = <(String, Json, String?)>[];
  final cancelled = <String>[];
  bool connected = false;
  String mode = 'photos';
  String photoSession = 'album-session';
  int disconnectsApplied = 0;
  Completer<Json>? connection;
  Json? connectionResult;
  Object? connectionError;
  int pickCount = 0;

  @override
  Stream<dynamic> get operationProgress => const Stream<dynamic>.empty();

  @override
  Future<void> cancel(String jobId) async => cancelled.add(jobId);

  @override
  Future<Json?> pickFile({required bool preset}) async {
    pickCount++;
    return null;
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, Map.of(payload), jobId));
    switch (operation) {
      case 'camera.status':
        return {
          'connected': connected,
          'session': connected
              ? mode == 'slots'
                    ? 'slot-session'
                    : photoSession
              : '',
          'model': connected ? 'Nikon Z6II' : '',
          'mode': connected ? mode : 'none',
          'inventoryReady': false,
        };
      case 'camera.connect':
        if (connectionError != null) throw connectionError!;
        final result = connection != null
            ? await connection!.future
            : connectionResult ?? success;
        connected = result['connected'] == true;
        if (connected) photoSession = result['session'] as String;
        return result;
      case 'camera.slots.open':
        return {
          'session': 'slot-session',
          'model': 'Nikon Z6II',
          'canWrite': true,
          'canDelete': false,
          'action': {'pending': false},
          'items': [
            {
              'target': 201,
              'label': 'C1',
              'name': '',
              'empty': true,
              'sha256': 'a' * 64,
            },
          ],
        };
      case 'camera.slots.close':
        mode = 'photos';
        return {'closed': true};
      case 'camera.disconnect':
        final activeSession = mode == 'slots' ? 'slot-session' : photoSession;
        if (payload['session'] != activeSession) {
          return {
            'connected': connected,
            'session': connected ? activeSession : '',
            'model': connected ? 'Nikon Z6II' : '',
            'mode': connected ? mode : 'none',
            'disconnected': false,
            'stale': true,
          };
        }
        disconnectsApplied++;
        connected = false;
        return {
          'connected': false,
          'session': '',
          'model': '',
          'mode': 'none',
          'disconnected': true,
          'stale': false,
        };
      case 'camera.page':
        return {'items': [], 'nextOffset': 0, 'hasMore': false};
      case 'library.export':
        return {'path': '/private/selected-preset.ncp'};
      case 'camera.slots.prepare':
        return {
          'confirmationId': 'prepared',
          'targetLabel': 'C1',
          'beforeName': '',
          'overwrite': false,
          'name': '已选配方',
          'explanation': '待用户确认',
        };
      case 'library.inspect':
        return {};
      case 'media.showcase':
        throw const AppFailure('No showcase in this connection fixture');
      default:
        return {};
    }
  }

  static Json get success => {
    'connected': true,
    'session': 'album-session',
    'model': 'Nikon Z6II',
  };
  List<(String, Json, String?)> get photoCalls => calls
      .where(
        (c) => [
          'camera.page',
          'camera.thumbnail',
          'camera.preview',
          'photo.list',
        ].contains(c.$1),
      )
      .toList();
}

class HeldStopLive extends CameraLive {
  HeldStopLive(super.state) : super(automatic: false);
  final stopped = Completer<void>();
  @override
  Future<void> stop() {
    active = false;
    return stopped.future;
  }
}

class HeldStopState extends AppState {
  HeldStopState(super.core) {
    live = HeldStopLive(this)..active = true;
  }
  late final HeldStopLive live;
  @override
  CameraLive get cameraLive => live;
  @override
  bool get cameraLiveActive => live.active;
  @override
  void dispose() {
    if (!live.stopped.isCompleted) live.stopped.complete();
    live.dispose();
    super.dispose();
  }
}

class LateToolCore extends IntentCameraCore {
  LateToolCore(this.tool);
  final String tool;
  final opened = Completer<Json>();
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) {
    if (operation == 'camera.$tool.open') {
      calls.add((operation, Map.of(payload), jobId));
      return opened.future;
    }
    return super.call(operation, payload, jobId);
  }
}

const selectedPreset = Preset({
  'id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'displayName': '已选配方',
  'fileFormat': 'NCP',
});

Future<void> showImport(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.light),
      home: LegacyPresetDetails(
        state: state,
        preset: selectedPreset,
        onShare: () {},
        onCategory: () {},
        onRemove: () {},
        onDownload: () {},
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, '导入相机'));
  await tester.pumpAndSettle();
}

Future<void> tapConnect(WidgetTester tester) async {
  final button = find.byKey(const Key('camera-connect'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

void main() {
  testWidgets(
    'A delayed old stop cannot disconnect a replacement camera session',
    (tester) async {
      final core = IntentCameraCore()..connected = true;
      final state = HeldStopState(core)..cameraVisible.value = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: CameraPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('断开相机'));
      await tester.pump();
      expect(core.calls.where((c) => c.$1 == 'camera.disconnect'), isEmpty);
      core.connectionResult = {
        ...IntentCameraCore.success,
        'session': 'replacement-session',
      };
      await core.call('camera.connect', {}, 'replacement-job');
      state.live.stopped.complete();
      await tester.pumpAndSettle();
      expect(core.calls.singleWhere((c) => c.$1 == 'camera.disconnect').$2, {
        'session': 'album-session',
      });
      expect(core.disconnectsApplied, 0);
      expect(core.connected, isTrue);
      expect(find.text('未连接'), findsNothing);
      expect(find.textContaining('Nikon Z6II · 已连接'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'Leaving while an explicit disconnect waits for stop sends no later disconnect or setState',
    (tester) async {
      final core = IntentCameraCore()..connected = true;
      final state = HeldStopState(core)..cameraVisible.value = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: CameraPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('断开相机'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      state.live.stopped.complete();
      await tester.pumpAndSettle();
      expect(core.calls.where((c) => c.$1 == 'camera.disconnect'), isEmpty);
      expect(core.connected, isTrue);
      expect(tester.takeException(), isNull);
      state.dispose();
    },
  );

  testWidgets(
    'Repeated explicit disconnect activations remain one session-owned operation',
    (tester) async {
      final core = IntentCameraCore()..connected = true;
      final state = HeldStopState(core)..cameraVisible.value = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: CameraPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      final callback = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '断开相机',
            ),
          )
          .onPressed!;
      callback();
      callback();
      state.live.stopped.complete();
      await tester.pumpAndSettle();
      expect(
        core.calls.where((c) => c.$1 == 'camera.disconnect'),
        hasLength(1),
      );
      expect(core.disconnectsApplied, 1);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets('Explicit disconnect captures the active slots token', (
    tester,
  ) async {
    final core = IntentCameraCore()
      ..connected = true
      ..mode = 'slots';
    final state = AppState(core)..cameraVisible.value = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.light),
        home: CameraPage(state: state),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('断开相机'));
    await tester.pumpAndSettle();
    expect(core.calls.singleWhere((c) => c.$1 == 'camera.disconnect').$2, {
      'session': 'slot-session',
    });
    expect(core.disconnectsApplied, 1);
    expect(find.text('未连接'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets(
    'Explicit photo-page disconnect remains available without cancelling a completed connection job',
    (tester) async {
      final core = IntentCameraCore()..connected = true;
      final state = AppState(core)..cameraVisible.value = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: CameraPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('断开相机'));
      await tester.pumpAndSettle();
      expect(
        core.calls.where((c) => c.$1 == 'camera.disconnect'),
        hasLength(1),
      );
      expect(core.cancelled, isEmpty);
      expect(find.text('未连接'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  for (final tool in ['slots', 'remote']) {
    testWidgets(
      'Leaving before $tool opens releases only its late-owned lease and starts no preview',
      (tester) async {
        final core = LateToolCore(tool)..connected = true;
        final state = AppState(core);
        await tester.pumpWidget(
          MaterialApp(
            home: tool == 'slots'
                ? CameraSlotsPage(state: state)
                : CameraRemotePage(state: state),
          ),
        );
        await tester.pump();
        expect(
          core.calls.where((c) => c.$1 == 'camera.$tool.open'),
          hasLength(1),
        );
        await tester.pumpWidget(const SizedBox());
        core.opened.complete({
          'session': 'owned-$tool',
          'remoteId': 'owned-remote-id',
          'liveView': true,
        });
        await tester.pumpAndSettle();
        final closes = core.calls.where((c) => c.$1 == 'camera.$tool.close');
        expect(closes, hasLength(1));
        expect(closes.single.$2['session'], 'owned-$tool');
        expect(core.calls.where((c) => c.$1 == 'camera.remote.view'), isEmpty);
        expect(core.cancelled, isEmpty);
        state.dispose();
      },
    );
  }

  testWidgets(
    'Healthy slots mode is connected without loading photos or reporting zero photos',
    (tester) async {
      final core = IntentCameraCore()
        ..connected = true
        ..mode = 'slots';
      final state = AppState(core)..cameraVisible.value = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: CameraPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      expect(core.photoCalls, isEmpty);
      expect(find.textContaining('相机预设槽位正在使用连接'), findsOneWidget);
      expect(find.textContaining('已读取 0 张'), findsNothing);
      expect(find.textContaining('Nikon Z6II · 已连接'), findsOneWidget);
      await tester.tap(find.byTooltip('相机工具'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('相机预设槽位'));
      await tester.pumpAndSettle();
      expect(core.photoCalls, isEmpty);
      expect(core.cancelled, isEmpty);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(core.calls.where((c) => c.$1 == 'camera.page'), hasLength(1));
      expect(core.cancelled, isEmpty);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'Preset import connects then returns directly to the selected preset slots without browsing',
    (tester) async {
      final core = IntentCameraCore();
      final state = AppState(core);
      await showImport(tester, state);
      expect(find.byType(CameraPage), findsOneWidget);
      await tapConnect(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CameraPage), findsNothing);
      expect(find.byType(CameraSlotsPage), findsOneWidget);
      expect(find.text('已选配方'), findsOneWidget);
      expect(
        core.calls.where((c) => c.$1 == 'camera.slots.open'),
        hasLength(1),
      );
      expect(core.calls.where((c) => c.$1 == 'camera.slots.prepare'), isEmpty);
      expect(core.photoCalls, isEmpty);
      expect(core.cancelled, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(
        core.cancelled,
        isEmpty,
        reason: 'Completed connect job must not be cancelled after slots own the connection',
      );
      state.dispose();
    },
  );

  testWidgets(
    'Already connected preset import skips connection and keeps the selected source',
    (tester) async {
      final core = IntentCameraCore()..connected = true;
      final state = AppState(core);
      await showImport(tester, state);
      expect(core.calls.where((c) => c.$1 == 'camera.connect'), isEmpty);
      expect(find.byType(CameraSlotsPage), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('camera-slot-import')));
      await tester.pumpAndSettle();
      expect(find.text('确认写入此槽位'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        core.calls.singleWhere((c) => c.$1 == 'library.export').$2['id'],
        selectedPreset.id,
      );
      expect(
        core.calls
            .singleWhere((c) => c.$1 == 'camera.slots.prepare')
            .$2['path'],
        '/private/selected-preset.ncp',
      );
      expect(core.calls.where((c) => c.$1 == 'camera.slots.execute'), isEmpty);
      expect(core.pickCount, 0);
      expect(core.photoCalls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  for (final mode in ['failure', 'not-connected']) {
    testWidgets('A $mode result cannot continue preset import to slots', (
      tester,
    ) async {
      final core = IntentCameraCore();
      if (mode == 'failure') {
        core.connectionError = const AppFailure('连接被拒绝');
      } else {
        core.connectionResult = {
          'connected': false,
          'session': '',
          'model': '',
        };
      }
      final state = AppState(core);
      await showImport(tester, state);
      await tapConnect(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CameraPage), findsOneWidget);
      expect(core.calls.where((c) => c.$1 == 'camera.slots.open'), isEmpty);
      expect(core.photoCalls, isEmpty);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LegacyPresetDetails), findsOneWidget);
      expect(find.byType(CameraSlotsPage), findsNothing);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    });
  }

  testWidgets(
    'Cancel and leaving discard a late connection result and cancel only its pending job once',
    (tester) async {
      final core = IntentCameraCore()..connection = Completer<Json>();
      final state = AppState(core);
      await showImport(tester, state);
      await tapConnect(tester);
      await tester.tap(find.text('取消连接'));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(core.cancelled, hasLength(1));
      core.connection!.complete(IntentCameraCore.success);
      await tester.pumpAndSettle();
      expect(core.calls.where((c) => c.$1 == 'camera.slots.open'), isEmpty);
      expect(core.photoCalls, isEmpty);
      expect(find.byType(LegacyPresetDetails), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'An owner change during connection cannot import the old preset for a new account',
    (tester) async {
      final core = IntentCameraCore()..connection = Completer<Json>();
      final state = AppState(core)
        ..session = {
          'user': {'id': 'old-owner'},
        };
      await showImport(tester, state);
      await tapConnect(tester);
      state.session = {
        'user': {'id': 'new-owner'},
      };
      core.connection!.complete(IntentCameraCore.success);
      await tester.pumpAndSettle();
      expect(core.calls.where((c) => c.$1 == 'camera.slots.open'), isEmpty);
      expect(core.calls.where((c) => c.$1 == 'library.export'), isEmpty);
      expect(core.cancelled, isEmpty);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'Hidden sync never reads photos; explicitly entering camera photos does',
    (tester) async {
      final core = IntentCameraCore()..connected = true;
      final state = AppState(core);
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: CameraPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      expect(core.photoCalls, isEmpty);
      state.cameraVisible.value = true;
      await tester.pumpAndSettle();
      expect(core.calls.where((c) => c.$1 == 'camera.page'), hasLength(1));
      await tester.tap(find.text('已下载'));
      await tester.pumpAndSettle();
      expect(core.calls.where((c) => c.$1 == 'camera.page'), hasLength(1));
      expect(core.cancelled, isEmpty);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
