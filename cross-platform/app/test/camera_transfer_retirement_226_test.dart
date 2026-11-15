import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_downloads.dart';
import 'package:huevia/camera_transfer.dart';
import 'package:huevia/connection_protection.dart';
import 'package:huevia/domain.dart';
import 'package:path/path.dart' as p;

import 'camera_transfer_test.dart' as manual;

Json clone(Json data) => object(jsonDecode(jsonEncode(data)));

class RetirementCore226 extends HueviaCore {
  RetirementCore226(Directory directory) {
    root = directory.path;
    for (final id in ['old', 'new']) {
      final bytes = id == 'old'
          ? [255, 216, 1, 2, 3, 4, 255, 217]
          : [255, 216, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 255, 217];
      final digest = sha256.convert(bytes).toString();
      final file = File(p.join(root, 'originals', '$digest.jpg'));
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      receipts[id] = {
        'path': file.path,
        'sha256': digest,
        'bytes': bytes.length,
        'raw': false,
        'name': '$id.JPG',
      };
      journals[id] = {
        'id': id,
        'owner': 'owner',
        'cameraId': 'same-camera',
        'session': '$id-session',
        'trusted': true,
        'target': {'kind': 'app'},
        'phase': 'paused',
        'items': [
          {'id': '$id-completed', 'name': 'kept-$id.JPG', 'phase': 'completed'},
          {
            'id': '$id-pending',
            'name': '$id.JPG',
            'phase': 'waiting',
            'handle': id == 'old' ? 2 : 3,
            'storage': 1,
            'descriptor': (id == 'old' ? 'a' : 'b') * 64,
            'bytes': bytes.length,
            'raw': false,
          },
        ],
      };
      downloads[id] = Completer<Json>();
    }
  }
  final calls = <(String, Json, String?)>[];
  final cancelled = <String>[];
  final progress = StreamController<dynamic>.broadcast(sync: true);
  final journals = <String, Json>{}, receipts = <String, Json>{};
  final downloads = <String, Completer<Json>>{};
  final heldLists = <Completer<Json>>[];
  Completer<Json>? nextList;
  Json? visibleList;
  String sessionName = 'old-session';
  @override
  Stream<dynamic> get operationProgress => progress.stream;
  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
  }

  Json row(String id) => (journals[id]!['items'] as List).last as Json;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, clone(payload), jobId));
    final id = payload['id'] as String?;
    if (operation.startsWith('downloads.') &&
        id != null &&
        payload['owner'] != journals[id]!['owner']) {
      throw const AppFailure('Queue owner mismatch');
    }
    switch (operation) {
      case 'downloads.list':
        final gate = nextList;
        nextList = null;
        if (gate != null) {
          heldLists.add(gate);
          return gate.future;
        }
        return visibleList == null
            ? {
                'items': journals.values
                    .where((row) => row['owner'] == payload['owner'])
                    .map(clone)
                    .toList(),
                'issues': [],
              }
            : clone(visibleList!);
      case 'downloads.get':
        return clone(journals[id]!);
      case 'downloads.resume':
        journals[id]!['phase'] = 'active';
        return clone(journals[id]!);
      case 'downloads.item':
        row(id!)['phase'] = payload['phase'];
        return clone(journals[id]!);
      case 'downloads.pause':
        journals[id]!['phase'] = 'paused';
        return clone(journals[id]!);
      case 'downloads.finish':
        journals[id]!['phase'] = 'done';
        return clone(journals[id]!);
      case 'camera.status':
        return {
          'connected': true,
          'session': sessionName,
          'downloadCameraId': 'same-camera',
          'downloadTrusted': true,
        };
      case 'camera.resolve':
        return {
          'match': {'handle': payload['handle']},
          'hasMore': false,
        };
      case 'camera.download':
        final queue = payload['queueId'] as String;
        if (payload['owner'] != journals[queue]!['owner']) {
          throw const AppFailure('Receive owner mismatch');
        }
        final value = await downloads[queue]!.future;
        row(queue)['receipt'] = clone(value);
        row(queue)['phase'] = 'received';
        return clone(value);
      case 'media.info':
        return {'width': 10, 'height': 8, 'raw': false};
      default:
        throw AppFailure('Unexpected retirement fixture operation: $operation');
    }
  }
}

class RetirementProtection226 extends CameraConnectionProtection {
  RetirementProtection226(super.core);
  @override
  bool get native => false;
}

class RetirementState226 extends AppState {
  RetirementState226(super.core) {
    session = {
      'user': {'id': 'owner'},
    };
    protection = RetirementProtection226(core);
  }
  late final RetirementProtection226 protection;
  final registered = <String>[];
  @override
  CameraConnectionProtection get connectionProtection => protection;
  @override
  Future<Photo> registerPhoto(String path, String name, Json info) async {
    registered.add(path);
    return Photo(path, name, info);
  }

  void changeOwner(String value) {
    session = {
      'user': {'id': value},
    };
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
    protection.dispose();
  }
}

Future<void> untilRetired226(bool Function() ready, String reason) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(ready(), isTrue, reason: reason);
}

class RetirementFixture226 {
  RetirementFixture226() {
    directory = Directory.systemTemp.createTempSync(
      'huevia-transfer-retirement-226-',
    );
    core = RetirementCore226(directory);
    state = RetirementState226(core);
    queue = state.cameraDownloads;
  }
  late Directory directory;
  late RetirementCore226 core;
  late RetirementState226 state;
  late CameraDownloads queue;
  final pending = <Future<void>>[];
  Future<void> run(String id) {
    final future = queue.resume(id);
    pending.add(future);
    return future;
  }

  Future<void> dispose() async {
    for (final entry in core.downloads.entries) {
      if (!entry.value.isCompleted) {
        entry.value.complete(core.receipts[entry.key]!);
      }
    }
    for (final gate in core.heldLists) {
      if (!gate.isCompleted) gate.complete({'items': [], 'issues': []});
    }
    await Future.wait(pending);
    await queue.stop();
    state.dispose();
    await core.progress.close();
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, directory.absolute.path),
      isTrue,
    );
    expect(
      p.basename(directory.path).startsWith('huevia-transfer-retirement-226-'),
      isTrue,
    );
    await directory.delete(recursive: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final oldFails in [false, true]) {
    test(
      'Retiring held download preserves the new generation after old RPC ${oldFails ? 'fails' : 'succeeds'}',
      () async {
        final f = RetirementFixture226();
        addTearDown(f.dispose);
        final oldRun = f.run('old');
        await untilRetired226(
          () => f.core.calls.any(
            (c) => c.$1 == 'camera.download' && c.$2['queueId'] == 'old',
          ),
          'Old camera RPC must actually be held',
        );
        final oldJob = f.queue.job!, oldEvents = f.queue.events;
        final before = clone(f.queue.current!);
        expect(f.queue.activeSession, 'old-session');
        expect(
          f.queue.connectionLost(expectedSession: 'unrelated-session'),
          isFalse,
        );
        expect(f.queue.current, before);
        expect(f.queue.busy, isTrue);
        expect(f.queue.connectionLost(expectedSession: 'old-session'), isTrue);
        expect(f.queue.busy, isFalse);
        expect(f.queue.phase, 'paused');
        expect(
          f.queue.current,
          before,
          reason: 'Retirement must retain every durable row',
        );
        expect(f.queue.done, 1);
        expect(f.queue.events, isNull);
        expect(f.core.cancelled, isEmpty);
        expect(
          f.core.journals['old']!['phase'],
          'active',
          reason: 'Retirement must not pause or rewrite native journal',
        );
        f.core.sessionName = 'new-session';
        final newRun = f.run('new');
        await untilRetired226(
          () => f.core.calls.any(
            (c) => c.$1 == 'camera.download' && c.$2['queueId'] == 'new',
          ),
          'New run must obtain its own camera lease',
        );
        final newJob = f.queue.job!,
            newEvents = f.queue.events,
            generation = f.queue.generation;
        expect(newJob, isNot(oldJob));
        expect(identical(newEvents, oldEvents), isFalse);
        expect(f.queue.activeSession, 'new-session');
        expect(f.queue.connectionLost(expectedSession: 'old-session'), isFalse);
        expect(f.queue.generation, generation);
        expect(f.state.protection.actors, contains('downloads'));
        f.core.progress.add({'jobId': oldJob, 'progress': .9});
        expect(f.queue.received, 0);
        f.core.progress.add({'jobId': newJob, 'progress': .25});
        final received = f.queue.received;
        expect(received, greaterThan(0));
        if (oldFails) {
          f.core.downloads['old']!.completeError(
            const AppFailure('Old socket ended late'),
          );
        } else {
          f.core.downloads['old']!.complete(f.core.receipts['old']!);
        }
        await oldRun;
        expect(f.queue.busy, isTrue);
        expect(f.queue.phase, 'receiving');
        expect(f.queue.job, newJob);
        expect(identical(f.queue.events, newEvents), isTrue);
        expect(f.queue.current!['id'], 'new');
        expect(f.queue.done, 1);
        expect(f.queue.received, received);
        expect(f.state.protection.actors, contains('downloads'));
        f.core.progress.add({'jobId': newJob, 'progress': .5});
        expect(
          f.queue.received,
          (f.queue.total * .5).round(),
          reason:
              'New progress subscription must still deliver after old finally',
        );
        expect(f.core.cancelled, isEmpty);
        expect(
          f.core.calls.any(
            (c) => c.$1 == 'downloads.pause' && c.$2['id'] == 'old',
          ),
          isFalse,
        );
        expect(
          f.core.calls.any(
            (c) => [
              'camera.close',
              'camera.disconnect',
              'camera.live.stop',
            ].contains(c.$1),
          ),
          isFalse,
        );
        expect(f.state.registered, isEmpty);
        f.core.downloads['new']!.complete(f.core.receipts['new']!);
        await newRun;
        expect(f.queue.phase, 'done');
        expect(f.queue.done, 2);
        expect(f.state.registered, [f.core.receipts['new']!['path']]);
        expect(
          (f.core.journals['old']!['items'] as List).first['phase'],
          'completed',
        );
      },
    );
  }

  test('A held restore from the retired generation cannot overwrite a fresh queue list', () async {
    final f = RetirementFixture226();
    addTearDown(f.dispose);
    final oldList = Completer<Json>();
    f.core.nextList = oldList;
    final restoring = f.queue.restore();
    f.pending.add(restoring);
    await untilRetired226(
      () => f.core.heldLists.isNotEmpty,
      'Old list RPC must be pending',
    );
    f.core.sessionName = 'new-session';
    final running = f.run('new');
    await untilRetired226(
      () => f.queue.phase == 'receiving' && f.queue.job != null,
      'New generation must be receiving',
    );
    f.core.visibleList = {
      'items': [
        {'id': 'fresh-cache'},
      ],
      'issues': [],
    };
    await f.queue.restore();
    expect(f.queue.queues.single['id'], 'fresh-cache');
    final job = f.queue.job;
    oldList.complete({
      'items': [
        {'id': 'stale-cache'},
      ],
      'issues': [
        {'reason': 'stale'},
      ],
    });
    await restoring;
    expect(f.queue.queues.single['id'], 'fresh-cache');
    expect(f.queue.issues, isEmpty);
    expect(f.queue.current!['id'], 'new');
    expect(f.queue.job, job);
    expect(f.queue.busy, isTrue);
    f.core.downloads['new']!.complete(f.core.receipts['new']!);
    await running;
  });

  test('Owner change retires held camera work and lets the next owner start without stale cleanup', () async {
    final f = RetirementFixture226();
    addTearDown(f.dispose);
    f.core.journals['new']!['owner'] = 'other';
    await f.queue.restore();
    expect(f.queue.queues.map((row) => row['id']), ['old']);
    final oldRun = f.run('old');
    await untilRetired226(
      () => f.core.calls.any(
        (c) => c.$1 == 'camera.download' && c.$2['queueId'] == 'old',
      ),
      'Old owner camera RPC must be pending',
    );
    final oldJob = f.queue.job!;
    f.state.changeOwner('other');
    expect(
      f.queue.busy,
      isFalse,
      reason:
          'Retiring generation must release the old exclusive flag immediately',
    );
    expect(f.queue.current, isNull);
    expect(f.queue.queues, isEmpty);
    expect(f.queue.issues, isEmpty);
    expect(f.state.cameraDownloadsActive, isFalse);
    expect(f.state.protection.actors, isNot(contains('downloads')));
    expect(f.core.cancelled, [oldJob]);
    f.core.sessionName = 'new-session';
    final newRun = f.run('new');
    await untilRetired226(
      () => f.core.calls.any(
        (c) => c.$1 == 'camera.download' && c.$2['queueId'] == 'new',
      ),
      'New account must be able to acquire its own run',
    );
    final newJob = f.queue.job!, newEvents = f.queue.events;
    expect(f.queue.current!['owner'], 'other');
    expect(f.queue.busy, isTrue);
    f.core.downloads['old']!.complete(f.core.receipts['old']!);
    await oldRun;
    expect(f.queue.current!['id'], 'new');
    expect(f.queue.current!['owner'], 'other');
    expect(f.queue.busy, isTrue);
    expect(f.queue.job, newJob);
    expect(identical(f.queue.events, newEvents), isTrue);
    expect(f.state.protection.actors, contains('downloads'));
    f.core.progress.add({'jobId': newJob, 'progress': .5});
    expect(f.queue.received, (f.queue.total * .5).round());
    expect(f.core.cancelled, [
      oldJob,
    ], reason: 'Only the captured old-account job may be canceled');
    expect(
      f.core.calls.any((c) => c.$1 == 'downloads.pause' && c.$2['id'] == 'old'),
      isFalse,
    );
    expect(f.state.registered, isEmpty);
    f.core.downloads['new']!.complete(f.core.receipts['new']!);
    await newRun;
    expect(f.queue.phase, 'done');
    expect(f.queue.done, 2);
    expect(f.state.registered, [f.core.receipts['new']!['path']]);
    expect(
      f.core.calls
          .where((c) => c.$1.startsWith('downloads.') && c.$2['id'] == 'new')
          .every((c) => c.$2['owner'] == 'other'),
      isTrue,
    );
  });

  test('Manual stop owns its captured session and lease and cannot stop a replacement transfer', () async {
    final core = manual.TransferCore();
    final state = AppState(core);
    final oldGate = Completer<void>();
    Future<void>? pendingStop;
    addTearDown(() async {
      if (!oldGate.isCompleted) oldGate.complete();
      state.releaseCameraTransfer();
      if (pendingStop != null) await pendingStop;
      state.dispose();
      await core.events.close();
    });
    var oldStops = 0, newStops = 0, oldFinished = false;
    expect(
      state.claimCameraTransfer(
        session: 'old-session',
        onStop: () async {
          oldStops++;
          await oldGate.future;
        },
      ),
      isTrue,
    );
    await state.stopCameraManualTransfer(expectedSession: 'wrong-session');
    expect(oldStops, 0);
    final oldStop = state
        .stopCameraManualTransfer(expectedSession: 'old-session')
        .then<void>((_) {
          oldFinished = true;
        });
    pendingStop = oldStop;
    await untilRetired226(
      () => oldStops == 1,
      'Old stop callback must be entered',
    );
    expect(state.cameraManualTransferActive, isTrue);
    state.releaseCameraTransfer();
    expect(
      state.claimCameraTransfer(
        session: 'new-session',
        onStop: () async {
          newStops++;
          state.releaseCameraTransfer();
        },
      ),
      isTrue,
    );
    await state.stopCameraManualTransfer(expectedSession: 'old-session');
    expect(newStops, 0);
    expect(oldFinished, isFalse);
    oldGate.complete();
    await oldStop;
    expect(state.cameraManualTransferActive, isTrue);
    expect(newStops, 0);
    await state.stopCameraManualTransfer(expectedSession: 'new-session');
    expect(newStops, 1);
    expect(state.cameraManualTransferActive, isFalse);
    expect(
      state.claimCameraTransfer(),
      isTrue,
      reason: 'Existing bool API remains compatible',
    );
    expect(state.claimCameraTransfer(), isFalse);
    expect(core.cancelled, isEmpty);
  });

  test('Reconnect waits for a real CameraTransfer catalog save without canceling local publication', () async {
    final core = manual.TransferCore();
    final state = manual.TransferState(core)..save = Completer<void>();
    final transfer = CameraTransfer(state);
    final receiving = transfer.start(
      'saving-session',
      manual.transferPhoto,
      raw: false,
    );
    addTearDown(() async {
      if (!core.response.isCompleted) core.response.complete(core.receipt());
      if (!core.info.isCompleted) core.info.complete({});
      if (!state.save!.isCompleted) state.save!.complete();
      await receiving;
      transfer.dispose();
      state.dispose();
      await core.events.close();
    });
    core.response.complete(core.receipt());
    core.info.complete({'width': 100, 'height': 80, 'raw': false});
    await untilRetired226(
      () => state.registrations == 1,
      'Local catalog publication must actually be held',
    );
    expect(transfer.phase, CameraTransferPhase.importing);
    expect(transfer.canStop, isFalse);
    var released = false;
    final stop = state
        .stopCameraManualTransfer(expectedSession: 'saving-session')
        .then<void>((_) {
          released = true;
        });
    await Future<void>.delayed(Duration.zero);
    expect(released, isFalse);
    expect(state.cameraManualTransferActive, isTrue);
    expect(state.claimCameraTransfer(session: 'new-session'), isFalse);
    expect(core.cancelled, isEmpty);
    expect(transfer.phase, CameraTransferPhase.importing);
    state.save!.complete();
    await receiving;
    await stop;
    expect(released, isTrue);
    expect(transfer.done, isTrue);
    expect(transfer.importedPhoto?.path, core.receipt()['path']);
    expect(state.registrations, 1);
    expect(state.cameraManualTransferActive, isFalse);
    expect(core.cancelled, isEmpty);
  });

  test('A matching manual receiving stop cancels only that live RPC and waits for its lease release', () async {
    final core = manual.TransferCore();
    final state = manual.TransferState(core);
    final transfer = CameraTransfer(state);
    final receiving = transfer.start(
      'receiving-session',
      manual.transferPhoto,
      raw: false,
    );
    addTearDown(() async {
      if (!core.response.isCompleted) core.response.complete(core.receipt());
      if (!core.info.isCompleted) core.info.complete({});
      await receiving;
      transfer.dispose();
      state.dispose();
      await core.events.close();
    });
    await state.stopCameraManualTransfer(expectedSession: 'previous-session');
    expect(core.cancelled, isEmpty);
    var released = false;
    final stop = state
        .stopCameraManualTransfer(expectedSession: 'receiving-session')
        .then<void>((_) {
          released = true;
        });
    await untilRetired226(
      () => core.cancelled.isNotEmpty,
      'Matching receiver must cancel its own live RPC',
    );
    expect(core.cancelled, [core.downloadJob]);
    expect(released, isFalse);
    expect(state.cameraManualTransferActive, isTrue);
    core.response.complete(core.receipt());
    await receiving;
    await stop;
    expect(state.registrations, 0);
    expect(transfer.phase, CameraTransferPhase.stopped);
    expect(state.cameraManualTransferActive, isFalse);
  });
}
