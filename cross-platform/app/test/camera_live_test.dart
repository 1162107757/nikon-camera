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
Json shot(int handle, {bool raw = false}) => {
  'handle': handle,
  'storage': 1,
  'objectKey': sha(handle),
  'name': 'DSC_$handle.${raw ? 'NEF' : 'JPG'}',
  'bytes': 4096,
  'width': 100,
  'height': 80,
  'raw': raw,
};

class LiveCore extends HueviaCore {
  LiveCore() {
    root = p.join(Directory.systemTemp.path, 'huevia-live-controller');
  }
  final events = StreamController<dynamic>.broadcast(sync: true);
  final calls = <String>[];
  final requests = <(String, Json)>[];
  final jobs = <(String, String?)>[];
  final pending = <String, Json>{}, completed = <String, Json>{};
  final tasks = <Json>[];
  final otherSeen = <String>{};
  List<Json> visible = [];
  bool connected = true, trusted = true, persistentActive = false;
  bool cancelFails = false, downloadFails = false;
  bool usePreset = true;
  bool supportsRaw = true;
  bool thumbnailFails = false;
  String activeFormat = 'jpeg';
  String session = 'session-one', activeWatch = '', activeToken = '';
  String? corruptReceipt;
  int exports = 0, downloads = 0;
  Completer<void>? downloadGate;
  Completer<void>? exportGate;
  Completer<void>? watchGate, projectGate, mediaGate;
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
    'liveFormats': ['jpeg', if (supportsRaw) 'raw'],
  };
  Json liveState() => {
    'exists': persistentActive || completed.isNotEmpty,
    'active': persistentActive,
    'format': activeFormat,
    'cameraId': camera,
    'trustedCamera': trusted,
    'session': session,
    'watchId': activeWatch,
    'token': activeToken,
    'cursor': cursor,
    'pending': pending.values.toList(),
    'completedCount': completed.length,
    'failedCount': 0,
    'queuedCount': tasks
        .where(
          (task) =>
              task['status'] == 'queued' || task['status'] == 'processing',
        )
        .length,
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
    requests.add((operation, Map<String, dynamic>.of(payload)));
    jobs.add((operation, jobId));
    switch (operation) {
      case 'camera.status':
        return status();
      case 'camera.live.start':
        otherSeen.clear();
        activeFormat = payload['format'] as String? ?? 'jpeg';
        activeWatch = 'watch-$session';
        lastStart = payload;
        await watchGate?.future;
        return {
          ...status(),
          'format': activeFormat,
          'watchId': activeWatch,
          'cursor': {...cursor, 'format': activeFormat},
        };
      case 'project.live.state':
        return liveState();
      case 'project.live.start':
        activeFormat = payload['format'] as String? ?? 'jpeg';
        persistentActive = true;
        activeToken = 'token-$session';
        await projectGate?.future;
        return liveState();
      case 'camera.live.poll':
        final otherFormats = visible
            .where(
              (item) =>
                  (item['raw'] == true) != (activeFormat == 'raw') &&
                  otherSeen.add(item['objectKey'] as String),
            )
            .length;
        return {
          'session': session,
          'watchId': activeWatch,
          'format': activeFormat,
          'items': visible
              .where((item) => (item['raw'] == true) == (activeFormat == 'raw'))
              .toList(),
          'otherFormatCount': otherFormats,
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
          'path': p.join(
            root,
            'originals',
            '${row['objectKey']}.${row['raw'] == true ? 'nef' : 'jpg'}',
          ),
          'sha256': row['objectKey'],
          'raw': row['raw'] == true,
          'cameraId': camera,
          'session': session,
          'watchId': corruptReceipt ?? activeWatch,
        };
      case 'media.info':
        await mediaGate?.future;
        return {
          'width': 100,
          'height': 80,
          'raw': (payload['path'] as String).endsWith('.nef'),
        };
      case 'media.rawThumbnail':
        if (thumbnailFails) throw const AppFailure('RAW thumbnail unavailable');
        final hash = p.basenameWithoutExtension(payload['path'] as String);
        return {
          'path': p.join(root, 'raw-thumbnails', '$hash.jpg'),
          'sourceSha': hash,
        };
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
        task['status'] = 'processing';
        return {
          'lease': 'render-lease',
          'path': task['path'],
          'sourceSha': task['sha'],
          'recipe': {'schema': 1, 'presetId': 'preset'},
        };
      case 'media.export':
        exports++;
        await exportGate?.future;
        return {'id': 'version-$exports'};
      case 'project.finish':
        tasks.firstWhere((task) => task['key'] == payload['key'])['status'] =
            'saved';
        return project();
      case 'project.fail':
        tasks.firstWhere((task) => task['key'] == payload['key'])['status'] =
            'error';
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
    test('RAW selection freezes the run, ignores the JPEG companion and preserves a NEF preview source', () async {
      final live = state.controller;
      expect(live.selectedFormat, CameraLiveFormat.jpeg);
      expect(live.selectFormat(CameraLiveFormat.raw), true);
      await live.start('project-one', 'RAW 拍摄');
      expect(live.active, true);
      expect(live.selectFormat(CameraLiveFormat.jpeg), false);
      expect(core.lastStart['format'], 'raw');
      core.visible = [
        shot(2),
        {...shot(3, raw: true), 'name': 'DSC_2.NEF'},
      ];
      await live.pollOnce();
      await live.pollOnce();
      expect(core.downloads, 1);
      expect(core.exports, 1);
      expect(live.completed, 1);
      expect(state.registered.single, endsWith('${sha(3)}.nef'));
      expect(live.latestPhoto!.info['raw'], true);
      expect(
        live.latestPreviewPath,
        p.join(core.root, 'raw-thumbnails', '${sha(3)}.jpg'),
      );
      final download = core.requests
          .singleWhere((request) => request.$1 == 'camera.download')
          .$2;
      expect(download['raw'], true);
      expect(download['format'], 'raw');
      expect(
        core.calls.where((operation) => operation == 'camera.disconnect'),
        isEmpty,
      );
      await live.stop();
      expect(live.selectFormat(CameraLiveFormat.jpeg), true);
    });
    test(
      'JPEG remains the default and never receives a RAW companion',
      () async {
        final live = state.controller;
        await live.start('project-one', 'JPEG 拍摄');
        core.visible = [
          shot(2),
          {...shot(3, raw: true), 'name': 'DSC_2.NEF'},
        ];
        await live.pollOnce();
        expect(core.downloads, 1);
        expect(state.registered.single, endsWith('${sha(2)}.jpg'));
        expect(live.latestPreviewPath, live.latestPhoto!.path);
        expect(
          core.requests
              .singleWhere((request) => request.$1 == 'camera.download')
              .$2['raw'],
          false,
        );
        expect(
          core.calls.where((operation) => operation == 'media.rawThumbnail'),
          isEmpty,
        );
      },
    );
    test('Unavailable RAW capability and a different durable format are rejected before watching', () async {
      final live = state.controller;
      live.selectFormat(CameraLiveFormat.raw);
      core.supportsRaw = false;
      await expectLater(
        live.available('project-one'),
        throwsA(isA<AppFailure>()),
      );
      await live.start('project-one', 'RAW 拍摄');
      expect(live.active, false);
      expect(live.error, contains('NEF'));
      expect(
        core.calls.where((operation) => operation == 'camera.live.start'),
        isEmpty,
      );
      core.supportsRaw = true;
      core.persistentActive = true;
      core.activeFormat = 'jpeg';
      await live.start('project-one', 'RAW 拍摄', resume: true);
      expect(live.active, false);
      expect(live.error, contains('上次拍摄'));
      expect(core.persistentActive, true);
      expect(
        core.calls.where((operation) => operation == 'camera.live.start'),
        isEmpty,
      );
    });
    test('RAW waiting reports JPEG-only captures and an optional preview failure never loses the original', () async {
      final live = state.controller;
      live.selectFormat(CameraLiveFormat.raw);
      await live.start('project-one', 'RAW 拍摄');
      core.visible = [shot(2)];
      await live.pollOnce();
      expect(core.downloads, 0);
      expect(live.formatNotice, contains('尚未收到 RAW'));
      core.thumbnailFails = true;
      core.visible.add(shot(3, raw: true));
      await live.pollOnce();
      expect(live.completed, 1);
      expect(live.phase, CameraLivePhase.watching);
      expect(live.latestPhoto!.info['raw'], true);
      expect(live.latestPreviewPath, isNull);
      expect(state.registered.single, endsWith('.nef'));
      expect(live.formatNotice, isNull);
      core.visible = [shot(4)];
      await live.pollOnce();
      expect(live.formatNotice, contains('尚未收到 RAW'));
      expect(core.downloads, 1);
    });
    test(
      'Only the exact pending camera RPC is exposed for reconnect cleanup',
      () async {
        final live = state.controller;
        core.projectGate = Completer<void>();
        final starting = live.start('project-one', '拍摄');
        for (
          var i = 0;
          i < 20 && !core.calls.contains('project.live.start');
          i++
        ) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(core.jobs.last.$1, 'project.live.start');
        expect(core.jobs.last.$2, isNotNull);
        expect(live.pendingCameraJob, isNull);
        core.projectGate!.complete();
        await starting;
        expect(live.pendingCameraJob, isNull);

        core.visible = [shot(2)];
        core.downloadGate = Completer<void>();
        core.mediaGate = Completer<void>();
        final poll = live.pollOnce();
        for (var i = 0; i < 20 && core.downloads == 0; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(core.jobs.last.$1, 'camera.download');
        expect(core.jobs.last.$2, isNotNull);
        expect(live.pendingCameraJob, core.jobs.last.$2);
        core.downloadGate!.complete();
        for (var i = 0; i < 20 && !core.calls.contains('media.info'); i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(core.jobs.last.$1, 'media.info');
        expect(core.jobs.last.$2, isNotNull);
        expect(live.pendingCameraJob, isNull);
        final boundary = core.calls.length;
        expect(live.connectionLost(expectedSession: 'session-one'), true);
        expect(live.pendingCameraJob, isNull);
        core.mediaGate!.complete();
        await poll;
        expect(live.pendingCameraJob, isNull);
        expect(core.calls.skip(boundary), isEmpty);
        expect(state.registered, isEmpty);
      },
    );
    test('Transport loss retires only the old run and late work cannot stop a new session', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      core.visible = [shot(2)];
      core.downloadGate = Completer<void>();
      final oldPoll = live.pollOnce();
      while (core.downloads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final oldCameraJob = core.jobs.last.$2;
      expect(core.jobs.last.$1, 'camera.download');
      expect(oldCameraJob, isNotNull);
      expect(live.pendingCameraJob, oldCameraJob);
      expect(live.connectionLost(expectedSession: 'different-session'), false);
      expect(live.active, true);
      expect(live.pendingCameraJob, oldCameraJob);
      final boundary = core.calls.length;
      expect(live.connectionLost(expectedSession: 'session-one'), true);
      expect(live.pendingCameraJob, isNull);
      expect(live.active, false);
      expect(live.token, isEmpty);
      expect(live.phase, CameraLivePhase.blocked);
      expect(live.error, contains('重新连接'));
      expect(core.persistentActive, true);
      core.session = 'session-two';
      core.visible = [];
      await live.start('project-one', '拍摄', resume: true);
      final freshToken = live.token;
      core.downloadGate!.complete();
      await oldPoll;
      expect(live.active, true);
      expect(live.session, 'session-two');
      expect(live.token, freshToken);
      expect(live.phase, CameraLivePhase.watching);
      expect(state.registered, isEmpty);
      expect(
        core.calls
            .skip(boundary)
            .where(
              (operation) =>
                  operation == 'camera.live.stop' ||
                  operation == 'camera.disconnect' ||
                  operation == 'cancel' ||
                  operation.startsWith('cancel:'),
            ),
        isEmpty,
      );
    });
    test('Starting freezes format and a retired late watcher cannot clear a newer producer', () async {
      final live = state.controller;
      live.selectFormat(CameraLiveFormat.raw);
      final oldWatch = core.watchGate = Completer<void>();
      final starting = live.start('project-one', 'RAW 拍摄');
      for (
        var i = 0;
        i < 20 && !core.calls.contains('camera.live.start');
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(core.calls, contains('camera.live.start'));
      expect(live.phase, CameraLivePhase.starting);
      expect(live.session, 'session-one');
      expect(live.selectFormat(CameraLiveFormat.jpeg), false);
      expect(live.connectionLost(expectedSession: 'session-one'), true);
      expect(live.transportRetired, true);
      expect(live.selectFormat(CameraLiveFormat.jpeg), true);
      core.watchGate = null;
      core.session = 'session-two';
      await live.start('project-one', 'JPEG 拍摄');
      final token = live.token;
      oldWatch.complete();
      await starting;
      expect(live.active, true);
      expect(live.working, false);
      expect(live.transportRetired, false);
      expect(live.session, 'session-two');
      expect(live.token, token);
      expect(live.selectedFormat, CameraLiveFormat.jpeg);
      expect(
        core.calls.where(
          (operation) =>
              operation == 'camera.live.stop' || operation == 'cancel',
        ),
        isEmpty,
      );
    });
    test('A verified new connection unlocks explicit resume without attaching or changing the journal', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      core.visible = [shot(2)];
      await live.pollOnce();
      expect(live.connectionLost(expectedSession: 'session-one'), true);
      expect(live.connectionRestored(session: ''), false);
      expect(live.connectionRestored(session: ' '), false);
      expect(live.connectionRestored(session: 'session-one'), false);
      final calls = core.calls.length;
      var changes = 0;
      void changed() => changes++;
      live.addListener(changed);
      expect(live.connectionRestored(session: 'session-two'), true);
      live.removeListener(changed);
      expect(changes, 1);
      expect(core.calls.length, calls);
      expect(live.active, false);
      expect(live.transportRetired, false);
      expect(live.phase, CameraLivePhase.stopped);
      expect(live.error, isNull);
      expect(
        live.session,
        'session-one',
        reason: 'The controller has not attached to the new connection',
      );
      expect(core.persistentActive, true);
      expect(core.completed, hasLength(1));
      expect(state.registered, hasLength(1));
      expect(live.connectionRestored(session: 'session-three'), false);
      live.phase = CameraLivePhase.failed;
      live.error = '普通启动失败';
      expect(live.connectionRestored(session: 'session-four'), false);
      expect(live.phase, CameraLivePhase.failed);
      expect(live.error, '普通启动失败');
    });
    test('Restoring once during held old processing lets explicit resume finish after that boundary', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      final gate = core.exportGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      core.visible = [shot(2)];
      final oldPoll = live.pollOnce();
      for (var i = 0; i < 30 && core.exports == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(core.exports, 1);
      expect(core.tasks.single['status'], 'processing');
      expect(live.connectionLost(expectedSession: 'session-one'), true);
      core.session = 'session-two';
      final watches = core.calls
          .where((operation) => operation == 'camera.live.start')
          .length;
      expect(live.connectionRestored(session: 'session-two'), true);
      expect(gate.isCompleted, false);
      expect(live.transportRetired, false);
      expect(live.phase, CameraLivePhase.stopped);
      expect(live.active, false);
      expect(
        core.calls
            .where((operation) => operation == 'camera.live.start')
            .length,
        watches,
      );
      final resume = live.start('project-one', '拍摄', resume: true);
      await Future<void>.delayed(Duration.zero);
      expect(live.working, true);
      expect(live.phase, CameraLivePhase.starting);
      expect(
        core.calls
            .where((operation) => operation == 'camera.live.start')
            .length,
        watches,
        reason: 'Explicit resume must wait for the held old project lease',
      );
      gate.complete();
      await oldPoll;
      await resume;
      expect(
        live.transportRetired,
        false,
        reason: 'No second connected snapshot is required',
      );
      expect(live.active, true);
      expect(live.working, false);
      expect(live.phase, CameraLivePhase.watching);
      expect(live.session, 'session-two');
      expect(
        core.calls
            .where((operation) => operation == 'camera.live.start')
            .length,
        watches + 1,
      );
      expect(
        core.calls.where(
          (operation) =>
              operation == 'camera.live.stop' || operation == 'cancel',
        ),
        isEmpty,
      );
      expect(core.completed, hasLength(1));
      expect(state.registered, hasLength(1));
      expect(core.persistentActive, true);
    });
    test('Changing owner after transport retirement clears only the old local presentation', () async {
      final live = state.controller;
      await live.start('project-one', '旧账号拍摄');
      core.visible = [shot(2)];
      await live.pollOnce();
      final receipt = core.completed[sha(2)];
      final original = state.registered.single;
      expect(live.connectionLost(expectedSession: 'session-one'), true);
      expect(live.transportRetired, true);
      expect(live.latestPreviewPath, isNotNull);
      core.session = 'session-two';
      final boundary = core.calls.length;
      state.changeOwner();
      await Future<void>.delayed(Duration.zero);
      expect(live.active, false);
      expect(live.working, false);
      expect(live.transportRetired, false);
      expect(live.phase, CameraLivePhase.stopped);
      expect(live.error, isNull);
      expect(live.formatNotice, isNull);
      expect(live.latestPhoto, isNull);
      expect(live.latestPreviewPath, isNull);
      expect(live.snapshot, isEmpty);
      expect(live.name, isEmpty);
      expect(live.owner, isEmpty);
      expect(live.projectId, isEmpty);
      expect(live.projectName, isEmpty);
      expect(live.session, isEmpty);
      expect(live.watchId, isEmpty);
      expect(live.token, isEmpty);
      expect(live.completed, 0);
      expect(
        live.connectionRestored(session: 'session-two'),
        false,
        reason:
            'The new account has no retired producer to resume automatically',
      );
      expect(core.persistentActive, true);
      expect(core.completed[sha(2)], same(receipt));
      expect(receipt!['owner'], 'owner');
      expect(state.registered, contains(original));
      expect(
        core.calls
            .skip(boundary)
            .where(
              (operation) =>
                  operation.startsWith('camera.live.') ||
                  operation == 'camera.disconnect' ||
                  operation == 'cancel' ||
                  operation.startsWith('project.live.'),
            ),
        isEmpty,
      );
    });
    test('Transport retirement keeps the received original and closes only its own preset task boundary', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      final gate = core.exportGate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      core.visible = [shot(2)];
      final processing = live.pollOnce();
      for (var i = 0; i < 30 && core.exports == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(core.exports, 1);
      expect(core.tasks.single['status'], 'processing');
      final boundary = core.calls.length;
      expect(live.connectionLost(expectedSession: 'session-one'), true);
      core.session = 'session-two';
      gate.complete();
      await processing;
      expect(state.registered, hasLength(1));
      expect(core.completed, hasLength(1));
      expect(core.tasks.single['status'], 'error');
      expect(core.calls.skip(boundary), contains('project.fail'));
      expect(
        core.calls
            .skip(boundary)
            .where(
              (operation) =>
                  operation == 'camera.live.stop' ||
                  operation == 'camera.disconnect' ||
                  operation == 'cancel',
            ),
        isEmpty,
      );
      expect(live.active, false);
      expect(live.phase, CameraLivePhase.blocked);
      expect(core.persistentActive, true);
    });
    test('Disconnect retires the local producer; explicit trusted resume restores its cursor', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      core.visible = [shot(2)];
      await live.pollOnce();
      core.connected = false;
      await live.pollOnce();
      expect(live.phase, CameraLivePhase.blocked);
      expect(live.active, false);
      expect(core.persistentActive, true);
      core.connected = true;
      core.session = 'session-two';
      core.visible = [shot(2), shot(3)];
      await live.pollOnce();
      expect(core.downloads, 1);
      await live.start('project-one', '拍摄', resume: true);
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
    test('An inactive permission overlay preserves the active receive and never cancels its camera job', () async {
      final live = state.controller;
      await live.start('project-one', '拍摄');
      core.visible = [shot(2)];
      core.downloadGate = Completer<void>();
      final running = live.pollOnce();
      while (core.downloads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      live.didChangeAppLifecycleState(AppLifecycleState.inactive);
      expect(core.calls, isNot(contains('cancel')));
      expect(live.active, isTrue);
      core.downloadGate!.complete();
      await running;
      expect(live.completed, 1);
      expect(state.registered, hasLength(1));
      expect(core.calls, isNot(contains('camera.live.stop')));
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
        expect(live.active, false);
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
