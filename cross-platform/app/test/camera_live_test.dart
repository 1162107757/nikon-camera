import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:huevia/camera_live.dart';
import 'package:huevia/camera_live_card.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';

const camera =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
String sha(int handle) => handle.toRadixString(16).padLeft(64, '0');
Json shot(int handle) => {
  'handle': handle,
  'storage': 1,
  'objectKey': sha(handle),
  'name': 'DSC_$handle.JPG',
  'bytes': 4096,
  'width': 100,
  'height': 80,
  'raw': false,
};

class LiveCore extends HueviaCore {
  LiveCore() {
    root = p.join(Directory.systemTemp.path, 'huevia-live-controller');
  }
  final events = StreamController<dynamic>.broadcast(sync: true);
  final calls = <String>[];
  final pending = <String, Json>{}, completed = <String, Json>{};
  final tasks = <Json>[];
  List<Json> visible = [];
  bool connected = true, trusted = true, persistentActive = false;
  bool cancelFails = false, downloadFails = false;
  bool usePreset = true;
  String session = 'session-one', activeWatch = '', activeToken = '';
  String? corruptReceipt;
  int exports = 0, downloads = 0;
  Completer<void>? downloadGate;
  Completer<void>? watchGate, projectGate;
  Json lastStart = {};
  Json cursor = {
    'baseline': [
      {'storage': 1, 'handle': 1},
    ],
    'initializedStorages': [1],
  };
  @override
  Stream<dynamic> get operationProgress => events.stream;
  Json status() => {
    'connected': connected,
    'cameraId': camera,
    'session': session,
    'trustedCamera': trusted,
    'supportsLive': true,
  };
  Json liveState() => {
    'exists': persistentActive || completed.isNotEmpty,
    'active': persistentActive,
    'cameraId': camera,
    'trustedCamera': trusted,
    'session': session,
    'watchId': activeWatch,
    'token': activeToken,
    'cursor': cursor,
    'pending': pending.values.toList(),
    'completedCount': completed.length,
    'failedCount': 0,
    'queuedCount': tasks.where((task) => task['status'] == 'queued').length,
  };
  Json project() => {
    'id': 'project-one',
    'name': '拍摄',
    'presetId': 'preset',
    'presetName': '项目预设',
    'photos': [
      for (final row in completed.values)
        {'path': row['path'], 'name': row['name']},
    ],
    'tasks': tasks,
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
        return status();
      case 'camera.live.start':
        activeWatch = 'watch-$session';
        lastStart = payload;
        await watchGate?.future;
        return {...status(), 'watchId': activeWatch, 'cursor': cursor};
      case 'project.live.state':
        return liveState();
      case 'project.live.start':
        persistentActive = true;
        activeToken = 'token-$session';
        await projectGate?.future;
        return liveState();
      case 'camera.live.poll':
        return {
          'session': session,
          'watchId': activeWatch,
          'items': List<Json>.of(visible),
          'baselineUpdates': [],
          'baselineRemoved': [],
          'initializedStorages': [1],
          'unavailable': [],
        };
      case 'project.live.observe':
        final ack = <String>[];
        for (final raw in payload['items'] as List) {
          final row = object(raw), key = row['objectKey'] as String;
          if (completed.containsKey(key)) {
            ack.add(key);
            continue;
          }
          pending.putIfAbsent(
            key,
            () => {...row, 'status': 'waiting', 'applyPreset': usePreset},
          );
        }
        return {...liveState(), 'acknowledged': ack};
      case 'camera.download':
        downloads++;
        if (downloadFails) throw const AppFailure('JPEG validation failed');
        final row = pending[payload['objectKey']]!;
        events.add({'jobId': jobId, 'progress': 0.5});
        await downloadGate?.future;
        return {
          ...row,
          'path': p.join(root, 'originals', '${row['objectKey']}.jpg'),
          'sha256': row['objectKey'],
          'raw': false,
          'cameraId': camera,
          'session': session,
          'watchId': corruptReceipt ?? activeWatch,
        };
      case 'media.info':
        return {'width': 100, 'height': 80, 'raw': false};
      case 'project.live.commit':
        final key = payload['objectKey'] as String;
        final applyPreset = pending[key]?['applyPreset'] == true;
        completed.putIfAbsent(key, () => Map<String, dynamic>.of(payload));
        pending.remove(key);
        if (applyPreset && !tasks.any((task) => task['key'] == key)) {
          tasks.add({
            'key': key,
            'status': 'queued',
            'name': payload['name'],
            'presetName': '项目预设',
            'path': payload['path'],
            'sha': payload['sha256'],
          });
        }
        return {
          ...liveState(),
          'acknowledged': [key],
        };
      case 'camera.live.ack':
        visible.removeWhere((row) => row['objectKey'] == payload['objectKey']);
        return {'acknowledged': true};
      case 'project.list':
        return {
          'items': [
            {'id': 'project-one', 'name': '拍摄'},
          ],
        };
      case 'project.open':
        return project();
      case 'project.begin':
        final task = tasks.firstWhere((task) => task['key'] == payload['key']);
        return {
          'lease': 'render-lease',
          'path': task['path'],
          'sourceSha': task['sha'],
          'recipe': {'schema': 1, 'presetId': 'preset'},
        };
      case 'media.export':
        exports++;
        return {'id': 'version-$exports'};
      case 'project.finish':
        tasks.firstWhere((task) => task['key'] == payload['key'])['status'] =
            'saved';
        return project();
      case 'project.fail':
        return project();
      case 'project.live.stop':
        persistentActive = false;
        return liveState();
      case 'camera.live.stop':
        if (activeWatch == payload['watchId']) activeWatch = '';
        return {'stopped': true};
      default:
        throw StateError('Unexpected $operation');
    }
  }

  @override
  Future<void> cancel(String jobId) async {
    calls.add('cancel');
    if (cancelFails) throw const AppFailure('Cancellation response lost');
  }
}

class LiveState extends AppState {
  LiveState(LiveCore super.core) {
    session = {
      'user': {'id': 'owner'},
    };
    controller = CameraLive(this, automatic: false);
  }
  late final CameraLive controller;
  final registered = <String>[];
  @override
  CameraLive get cameraLive => controller;
  @override
  bool get cameraLiveActive => controller.active;
  @override
  Future<Photo> registerPhoto(String path, String name, Json info) async {
    if (!registered.contains(path)) registered.add(path);
    return Photo(path, name, info);
  }

  void changeOwner() {
    session = {
      'user': {'id': 'other'},
    };
    notifyListeners();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Foreground camera live', () {
    late LiveCore core;
    late LiveState state;
    setUp(() {
      core = LiveCore();
      state = LiveState(core);
    });
    tearDown(() async {
      await state.controller.stop();
      state.dispose();
      await core.events.close();
    });
    test('Arming ignores existing inventory; repeated new shots save and process once', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      await live.pollOnce();
      expect(core.downloads, 0);
      expect(core.exports, 0);
      core.visible = [shot(2), shot(2), shot(3)];
      await live.pollOnce();
      await live.pollOnce();
      expect(core.downloads, 2);
      expect(core.exports, 2);
      expect(state.registered, hasLength(2));
      expect(live.completed, 2);
      expect(live.queued, 0);
      expect(live.phase, CameraLivePhase.watching);
      expect(core.tasks.every((task) => task['status'] == 'saved'), true);
    });
    test('Disconnect waits; matching trusted reconnect restores old cursor before new reception', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      core.visible = [shot(2)];
      await live.pollOnce();
      core.connected = false;
      await live.pollOnce();
      expect(live.phase, CameraLivePhase.waiting);
      core.connected = true;
      core.session = 'session-two';
      core.visible = [shot(2), shot(3)];
      await live.pollOnce();
      expect(core.lastStart['cursor'], core.cursor);
      expect(core.downloads, 2);
      expect(core.exports, 2);
      expect(live.session, 'session-two');
      expect(live.completed, 2);
    });
    test('Untrusted reconnect is blocked instead of merging another camera session', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      core.session = 'session-two';
      core.trusted = false;
      await live.pollOnce();
      expect(live.phase, CameraLivePhase.blocked);
      expect(core.downloads, 0);
      expect(
        core.calls.where((call) => call == 'project.live.start'),
        hasLength(1),
      );
    });
    test('Explicit stop discards a late download reply without committing to the stopped project', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      core.visible = [shot(2)];
      core.downloadGate = Completer<void>();
      final running = live.pollOnce();
      while (core.downloads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await live.stop();
      core.downloadGate!.complete();
      await running;
      expect(core.calls, contains('cancel'));
      expect(state.registered, isEmpty);
      expect(core.completed, isEmpty);
      expect(core.calls, isNot(contains('camera.disconnect')));
      expect(live.phase, CameraLivePhase.stopped);
    });
    test('Owner changes invalidate in-flight work before registration or project commit', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      core.visible = [shot(2)];
      core.downloadGate = Completer<void>();
      final running = live.pollOnce();
      while (core.downloads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      state.changeOwner();
      core.downloadGate!.complete();
      await running;
      await Future<void>.delayed(Duration.zero);
      expect(live.active, false);
      expect(state.registered, isEmpty);
      expect(core.completed, isEmpty);
    });
    test('Background pauses discovery; foreground reconciliation receives missed notifications', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      live.didChangeAppLifecycleState(AppLifecycleState.paused);
      core.visible = [shot(2)];
      final count = core.calls.length;
      await live.pollOnce();
      expect(core.calls, hasLength(count));
      expect(live.phase, CameraLivePhase.paused);
      live.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await live.pollOnce();
      expect(live.completed, 1);
      expect(core.exports, 1);
    });
    test('Receipt from an old watch never enters the album and blocks automatic retry', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      core.visible = [shot(2)];
      core.corruptReceipt = 'old-watch';
      await live.pollOnce();
      expect(live.phase, CameraLivePhase.blocked);
      expect(state.registered, isEmpty);
      expect(core.completed, isEmpty);
      await live.pollOnce();
      expect(core.downloads, 1);
    });
    test('An existing durable producer requires explicit resume', () async {
      core.persistentActive = true;
      final live = state.controller;
      await live.start('project-one', '拍摄');
      expect(live.active, false);
      expect(core.calls, isNot(contains('camera.live.start')));
      await live.start('project-one', '拍摄', resume: true);
      expect(live.active, true);
      expect(core.lastStart['cursor'], core.cursor);
    });
    test(
      'Stopping during watch creation compensates its late native success',
      () async {
        core.watchGate = Completer<void>();
        final starting = state.controller.start('project-one', '拍摄');
        while (core.activeWatch.isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }
        await state.controller.stop();
        core.watchGate!.complete();
        await starting;
        expect(core.activeWatch, isEmpty);
        expect(core.persistentActive, false);
        expect(state.controller.active, false);
      },
    );
    test('Stopping during durable start compensates its late token and active journal', () async {
      core.projectGate = Completer<void>();
      final starting = state.controller.start('project-one', '拍摄');
      while (!core.persistentActive) {
        await Future<void>.delayed(Duration.zero);
      }
      await state.controller.stop();
      core.projectGate!.complete();
      await starting;
      expect(core.persistentActive, false);
      expect(state.controller.active, false);
      expect(state.registered, isEmpty);
    });
    test('A lost cancel response still retires the durable producer', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      core.visible = [shot(2)];
      core.downloadGate = Completer<void>();
      core.cancelFails = true;
      final running = live.pollOnce();
      while (core.downloads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await live.stop();
      core.downloadGate!.complete();
      await running;
      expect(core.persistentActive, false);
      expect(state.registered, isEmpty);
      expect(core.calls, contains('project.live.stop'));
    });
    test('A connected camera verification error pauses instead of redownloading forever', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      core.visible = [shot(2)];
      core.downloadFails = true;
      await live.pollOnce();
      await live.pollOnce();
      expect(live.phase, CameraLivePhase.blocked);
      expect(core.downloads, 1);
      core.downloadFails = false;
      await live.retry();
      expect(live.completed, 1);
      expect(core.exports, 1);
    });
    test('No default preset receives originals; later defaults only affect new candidates', () async {
      final live = state.controller;
      core.usePreset = false;
      await live.start('project-one', '拍摄');
      core.visible = [shot(2)];
      core.downloadGate = Completer<void>();
      final receiving = live.pollOnce();
      while (core.downloads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      core.usePreset = true;
      core.downloadGate!.complete();
      await receiving;
      expect(live.completed, 1);
      expect(core.exports, 0);
      expect(state.registered, hasLength(1));
      core.downloadGate = null;
      core.visible = [shot(3)];
      await live.pollOnce();
      expect(live.completed, 2);
      expect(core.exports, 1);
      expect(state.registered, hasLength(2));
    });
    testWidgets('Starting without a default preset remains available', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: Scaffold(
            body: CameraLiveCard(
              state: state,
              projectId: 'project-one',
              projectName: '拍摄',
              hasPreset: false,
            ),
          ),
        ),
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '开始边拍边传'),
      );
      expect(button.onPressed, isNotNull);
      expect(find.text('未启用自动套用，接收的原图会保留。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets(
      'Disconnected live capture offers reconnection without discarding its journal',
      (tester) async {
        final live = state.controller;
        await live.start('project-one', '拍摄');
        core.connected = false;
        await live.pollOnce();
        var opened = false;
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.light),
            home: Scaffold(
              body: CameraLiveCard(
                state: state,
                projectId: 'project-one',
                projectName: '拍摄',
                hasPreset: true,
                onConnect: () async {
                  opened = true;
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('连接相机'));
        await tester.pump();
        expect(opened, true);
        expect(live.active, true);
        expect(core.persistentActive, true);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
    testWidgets(
      'Live reception card fits a narrow screen with large text and exposes stop',
      (tester) async {
        final live = state.controller;
        await live.start('project-one', '很长的拍摄项目名称');
        live.phase = CameraLivePhase.receiving;
        live.name = 'DSC_连续拍摄长文件名.JPG';
        live.total = 4096;
        live.received = 2048;
        await tester.binding.setSurfaceSize(const Size(320, 568));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.light),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
                child: SingleChildScrollView(
                  child: CameraLiveCard(
                    state: state,
                    projectId: 'project-one',
                    projectName: '拍摄',
                    hasPreset: true,
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.text('2.0 KB / 4.0 KB'), findsOneWidget);
        expect(find.text('停止边拍边传'), findsOneWidget);
        expect(tester.getSize(find.byType(Card)).width, 320);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  });
}
