import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:huevia/camera_downloads.dart';
import 'package:huevia/connection_protection.dart';
import 'package:huevia/domain.dart';
import 'package:path/path.dart' as p;

import 'camera_live_test.dart' as live_fixture;

Json copy(Json value) => object(jsonDecode(jsonEncode(value)));

class DownloadCore extends HueviaCore {
  DownloadCore(this.file, this.sha) {
    root = file.parent.parent.path;
    queue = {
      'id': 'a' * 32,
      'owner': 'owner',
      'cameraId': 'camera-one',
      'session': 'session-one',
      'trusted': true,
      'target': {'kind': 'app'},
      'phase': 'paused',
      'items': [
        {
          'id': 'b' * 32,
          'handle': 1,
          'name': 'DSC_1.JPG',
          'bytes': file.lengthSync(),
          'raw': false,
          'storage': 1,
          'descriptor': 'd' * 64,
          'phase': 'received',
          'receipt': receipt,
        },
      ],
    };
  }
  final File file;
  final String sha;
  late Json queue;
  final calls = <(String, Json)>[];
  final progress = StreamController<dynamic>.broadcast(sync: true);
  Completer<void>? mediaGate, publishGate, listGate;
  bool persistReceipt = true, readAllowed = true;
  List<Json> issues = [];
  Json get receipt => {
    'path': file.path,
    'sha256': sha,
    'bytes': file.lengthSync(),
    'raw': false,
    'name': 'DSC_1.JPG',
  };
  Json get row => (queue['items'] as List).first as Json;
  @override
  Stream<dynamic> get operationProgress => progress.stream;
  @override
  Future<Json> gallerySavePermission() async {
    calls.add(('gallerySavePermission', {}));
    return {'granted': true};
  }

  @override
  Future<Json> galleryPermission() async {
    calls.add(('galleryPermission', {}));
    readAllowed = true;
    return {'access': 'full'};
  }

  @override
  Future<void> cancel(String jobId) async {
    calls.add(('cancel', {'jobId': jobId}));
    if (mediaGate?.isCompleted == false) mediaGate!.complete();
    if (publishGate?.isCompleted == false) publishGate!.complete();
  }

  @override
  Future<Json> call(String op, [Json payload = const {}, String? job]) async {
    calls.add((op, copy(payload)));
    switch (op) {
      case 'downloads.list':
        await listGate?.future;
        return {
          'items': [copy(queue)],
          'issues': issues,
        };
      case 'downloads.get':
        return copy(queue);
      case 'downloads.resume':
        queue['phase'] = 'active';
        return copy(queue);
      case 'downloads.pause':
        queue['phase'] = 'paused';
        return copy(queue);
      case 'camera.status':
        return {
          'connected': true,
          'downloadCameraId': 'camera-one',
          'downloadTrusted': true,
          'session': 'session-one',
        };
      case 'camera.resolve':
        return {
          'match': {'handle': 1},
          'hasMore': false,
        };
      case 'camera.download':
        if (persistReceipt) {
          row['receipt'] = receipt;
          row['phase'] = 'received';
        }
        return receipt;
      case 'media.info':
        await mediaGate?.future;
        return {'width': 10, 'height': 8, 'raw': false};
      case 'gallery.access':
        return {'access': readAllowed ? 'full' : 'none'};
      case 'gallery.publishOriginal':
      case 'files.publishOriginal':
        await publishGate?.future;
        return {
          'published': true,
          'verified': true,
          'owner': payload['owner'],
          'operationId': payload['operationId'],
          'sha256': sha,
          'bytes': file.lengthSync(),
          'targetKind': op.startsWith('files.') ? 'folder' : 'system',
          if (op.startsWith('files.')) 'targetId': payload['targetId'],
          if (op.startsWith('files.')) 'uri': 'content://documents/verified',
          if (op.startsWith('gallery.')) 'identifier': 'asset/L0/001',
        };
      case 'downloads.item':
        if (payload['phase'] == 'completed' &&
            object(queue['target'])['kind'] != 'app') {
          final publication = object(payload['publication']);
          if (publication['verified'] != true ||
              publication['owner'] != 'owner' ||
              publication['operationId'] != row['id'] ||
              publication['sha256'] != sha ||
              publication['bytes'] != file.lengthSync()) {
            throw const AppFailure('Native target readback rejected');
          }
          row['publication'] = publication;
        }
        row['phase'] = payload['phase'];
        return copy(queue);
      case 'downloads.finish':
        queue['phase'] = 'done';
        return copy(queue);
      default:
        throw AppFailure('Unexpected queue operation $op');
    }
  }
}

class LocalProtection extends CameraConnectionProtection {
  LocalProtection(super.core);
  @override
  bool get native => false;
}

class DownloadState extends AppState {
  DownloadState(DownloadCore super.core) {
    session = {
      'user': {'id': 'owner'},
    };
    protection = LocalProtection(core);
  }
  late final LocalProtection protection;
  final registered = <Json>[];
  @override
  CameraConnectionProtection get connectionProtection => protection;
  @override
  Future<Photo> registerPhoto(String path, String name, Json info) async {
    registered.add({'path': path, 'name': name, 'info': copy(info)});
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
    super.dispose();
    protection.dispose();
  }
}

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(ready(), true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<(DownloadCore, DownloadState, CameraDownloads)> fixture() async {
    final directory = await Directory.systemTemp.createTemp('huevia-queue-');
    final bytes = [255, 216, 1, 2, 3, 4, 255, 217],
        digest = sha256.convert(bytes).toString();
    final file = File(p.join(directory.path, 'originals', '$digest.jpg'));
    await file.parent.create();
    await file.writeAsBytes(bytes);
    final core = DownloadCore(file, digest);
    final state = DownloadState(core);
    final queue = state.cameraDownloads;
    addTearDown(() async {
      await queue.stop();
      state.dispose();
      await core.progress.close();
      await directory.delete(recursive: true);
    });
    return (core, state, queue);
  }

  test(
    'restored native byte receipt imports once without touching the camera',
    () async {
      final (core, state, queue) = await fixture();
      await queue.restore();
      await queue.resume('a' * 32);
      expect(queue.phase, 'done');
      expect(queue.done, 1);
      expect(state.registered, hasLength(1));
      expect(
        core.calls.any(
          (c) => [
            'camera.status',
            'camera.resolve',
            'camera.download',
          ].contains(c.$1),
        ),
        false,
      );
      final source = object(
        object(state.registered.single['info'])['cameraSource'],
      );
      expect(source['cameraId'], 'camera-one');
      expect(source['storage'], 1);
      expect(source['descriptor'], 'd' * 64);
      await queue.resume('a' * 32);
      expect(state.registered, hasLength(1));
      expect(await core.file.exists(), true);
    },
  );
  test('system target requests actual byte readback before completing a queue item', () async {
    final (core, state, queue) = await fixture();
    core.platform = 'ios';
    core.readAllowed = false;
    core.queue['target'] = {'kind': 'system'};
    await queue.resume('a' * 32);
    final publication = core.calls
        .singleWhere((c) => c.$1 == 'gallery.publishOriginal')
        .$2;
    expect(publication['verifyReadback'], true);
    expect(publication['expectedSourceSha'], core.sha);
    expect(publication['operationId'], 'b' * 32);
    expect(publication['owner'], 'owner');
    expect(core.calls.any((c) => c.$1 == 'galleryPermission'), true);
    expect(queue.done, 1);
    expect(state.registered, hasLength(1));
  });
  test('folder target preserves the selected capability and the same readback operation', () async {
    final (core, _, queue) = await fixture();
    core.queue['target'] = {'kind': 'folder', 'id': 'chosen-capability'};
    await queue.resume('a' * 32);
    final payload = core.calls
        .singleWhere((c) => c.$1 == 'files.publishOriginal')
        .$2;
    expect(payload['targetId'], 'chosen-capability');
    expect(payload['verifyReadback'], true);
    expect(payload['operationId'], 'b' * 32);
    expect(queue.done, 1);
  });
  test(
    'a transient download reply cannot replace a missing durable receipt',
    () async {
      final (core, state, queue) = await fixture();
      core.row.remove('receipt');
      core.row['phase'] = 'pending';
      core.persistReceipt = false;
      await queue.resume('a' * 32);
      expect(queue.phase, 'paused');
      expect(queue.done, 0);
      expect(state.registered, isEmpty);
      expect(core.calls.where((c) => c.$1 == 'camera.download'), hasLength(1));
      expect(queue.error, contains('收据尚未保存'));
    },
  );
  test('owner change during publication retains the original and prevents completion', () async {
    final (core, state, queue) = await fixture();
    core.queue['target'] = {'kind': 'system'};
    core.publishGate = Completer<void>();
    final running = queue.resume('a' * 32);
    await until(() => core.calls.any((c) => c.$1 == 'gallery.publishOriginal'));
    state.changeOwner();
    await running;
    expect(queue.current, isNull);
    expect(queue.queues, isEmpty);
    expect(await core.file.exists(), true);
    expect(
      core.calls.any(
        (c) => c.$1 == 'downloads.item' && c.$2['phase'] == 'completed',
      ),
      false,
    );
    expect(queue.busy, false);
  });
  test('background protection expiration pauses a receipt and foreground continuation does not redownload', () async {
    final (core, state, queue) = await fixture();
    state.protection.accept({
      'enabled': true,
      'available': true,
      'backgroundAllowed': true,
    });
    core.mediaGate = Completer<void>();
    final running = queue.resume('a' * 32);
    await until(() => core.calls.any((c) => c.$1 == 'media.info'));
    queue.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(queue.stopped, false);
    state.protection.accept({
      'enabled': true,
      'backgroundAllowed': false,
      'expired': true,
    });
    await running;
    expect(queue.stopped, true);
    expect(queue.phase, 'paused');
    expect(state.registered, isEmpty);
    expect(await core.file.exists(), true);
    core.mediaGate = null;
    queue.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await queue.resume('a' * 32);
    expect(queue.done, 1);
    expect(state.registered, hasLength(1));
    expect(core.calls.any((c) => c.$1 == 'camera.download'), false);
  });
  test('corrupt queue issues stay visible while other valid tasks remain resumable', () async {
    final (core, _, queue) = await fixture();
    core.issues = [
      {'id': 'bad-record', 'error': '校验失败'},
    ];
    await queue.restore();
    expect(queue.queues, hasLength(1));
    expect(queue.issues.single['id'], 'bad-record');
    await queue.resume('a' * 32);
    expect(queue.done, 1);
    expect(queue.issues, hasLength(1));
  });
  test('notification stop ends a foreground queue while a normal background switch does not', () async {
    final (core, state, queue) = await fixture();
    state.protection.accept({
      'enabled': true,
      'backgroundAllowed': true,
      'stopRevision': 4,
    });
    core.mediaGate = Completer<void>();
    final running = queue.resume('a' * 32);
    await until(() => core.calls.any((call) => call.$1 == 'media.info'));
    state.protection.accept({
      'enabled': false,
      'backgroundAllowed': false,
      'stopRevision': 4,
    });
    expect(queue.stopped, false);
    expect(queue.busy, true);
    state.protection.accept({
      'enabled': false,
      'backgroundAllowed': false,
      'stopRevision': 5,
    });
    await running;
    expect(queue.stopped, true);
    expect(queue.busy, false);
    expect(queue.phase, 'paused');
    expect(queue.error, contains('系统通知'));
    expect(state.registered, isEmpty);
    expect(await core.file.exists(), true);
    expect(core.calls.any((call) => call.$1 == 'cancel'), true);
  });
  test(
    'idle owner changes and late restore responses never expose an old queue',
    () async {
      final (core, state, queue) = await fixture();
      await queue.restore();
      expect(queue.queues, hasLength(1));
      core.listGate = Completer<void>();
      final restoring = queue.restore();
      state.changeOwner();
      core.listGate!.complete();
      await restoring;
      expect(queue.queues, isEmpty);
      expect(queue.current, isNull);
      expect(queue.issues, isEmpty);
    },
  );
  test(
    'live, queue and cross-page manual transfer reject competing admissions',
    () async {
      final core = live_fixture.LiveCore();
      final state = live_fixture.LiveState(core);
      final live = state.controller, queue = state.cameraDownloads;
      addTearDown(() async {
        queue.busy = false;
        await live.stop();
        state.dispose();
        await core.events.close();
      });
      expect(state.claimCameraTransfer(), true);
      await expectLater(
        queue.create(
          {'connected': true},
          [
            {'handle': 1},
          ],
          {'kind': 'app'},
        ),
        throwsA(isA<AppFailure>()),
      );
      await queue.resume('queue');
      expect(queue.busy, false);
      await expectLater(
        live.start('project-one', '拍摄'),
        throwsA(isA<AppFailure>()),
      );
      state.releaseCameraTransfer();
      queue.busy = true;
      await expectLater(
        live.start('project-one', '拍摄'),
        throwsA(isA<AppFailure>()),
      );
      expect(state.claimCameraTransfer(), false);
      queue.busy = false;
      await live.start('project-one', '拍摄');
      await expectLater(
        queue.create(
          {'connected': true},
          [
            {'handle': 1},
          ],
          {'kind': 'app'},
        ),
        throwsA(isA<AppFailure>()),
      );
      await queue.resume('queue');
      expect(queue.busy, false);
      expect(state.claimCameraTransfer(), false);
    },
  );
}
