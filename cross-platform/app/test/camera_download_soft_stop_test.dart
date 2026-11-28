import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_downloads.dart';
import 'package:huevia/camera_transfer.dart';
import 'package:huevia/domain.dart';
import 'package:path/path.dart' as p;

import 'camera_transfer_retirement_226_test.dart' as retired;

// These real files and held bridge futures verify lifecycle/receipt ownership,
// not native JPEG decoding or physical Nikon transport behavior.
class SoftQueueCore extends retired.RetirementCore226 {
  SoftQueueCore(super.directory);
  String? heldOperation;
  Completer<Json>? cameraGate;
  Completer<void>? mediaGate, cancelAck;

  @override
  Future<Json> call(String op, [Json payload = const {}, String? jobId]) async {
    if (op == heldOperation && cameraGate != null) {
      calls.add((op, retired.clone(payload), jobId));
      return cameraGate!.future;
    }
    if (op == 'media.info' && mediaGate != null) {
      calls.add((op, retired.clone(payload), jobId));
      await mediaGate!.future;
      return {'width': 10, 'height': 8, 'raw': false};
    }
    return super.call(op, payload, jobId);
  }

  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
    if (calls.any((c) => c.$1 == 'media.info' && c.$3 == jobId) &&
        mediaGate?.isCompleted == false) {
      mediaGate!.complete();
    }
    await cancelAck?.future;
  }
}

class SoftQueueFixture {
  SoftQueueFixture() {
    directory = Directory.systemTemp.createTempSync('huevia-soft-stop-');
    core = SoftQueueCore(directory);
    state = retired.RetirementState226(core);
    queue = state.cameraDownloads;
  }
  late final Directory directory;
  late final SoftQueueCore core;
  late final retired.RetirementState226 state;
  late final CameraDownloads queue;
  final runs = <Future<void>>[];
  Future<void> run(String id) {
    final pending = queue.resume(id);
    runs.add(pending);
    return pending;
  }

  Future<void> close() async {
    if (core.cameraGate?.isCompleted == false) {
      core.cameraGate!.complete({
        'connected': true,
        'session': core.sessionName,
        'downloadCameraId': 'same-camera',
        'downloadTrusted': true,
        'match': {'handle': 2},
        'hasMore': false,
      });
    }
    if (core.mediaGate?.isCompleted == false) core.mediaGate!.complete();
    if (core.cancelAck?.isCompleted == false) core.cancelAck!.complete();
    for (final entry in core.downloads.entries) {
      if (!entry.value.isCompleted) {
        entry.value.complete(core.receipts[entry.key]!);
      }
    }
    await Future.wait(runs);
    await queue.stop();
    state.dispose();
    await core.progress.close();
    expect(
      p.isWithin(Directory.systemTemp.absolute.path, directory.absolute.path),
      isTrue,
    );
    expect(p.basename(directory.path).startsWith('huevia-soft-stop-'), isTrue);
    await directory.delete(recursive: true);
  }
}

class SoftManualCore extends HueviaCore {
  SoftManualCore(this.directory) {
    root = directory.path;
    final bytes = [255, 216, 1, 2, 3, 4, 255, 217];
    digest = sha256.convert(bytes).toString();
    file = File(p.join(root, 'originals', '$digest.jpg'));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
  }
  final Directory directory;
  late final File file;
  late final String digest;
  final events = StreamController<dynamic>.broadcast(sync: true);
  final calls = <(String, Json, String?)>[];
  final downloads = <Completer<Json>>[];
  final cancelled = <String>[];
  Completer<void>? cancelAck;
  Json get item => {
    'handle': 1,
    'name': 'SOURCE.JPG',
    'bytes': file.lengthSync(),
  };
  Json get receipt => {
    'path': file.path,
    'sha256': digest,
    'name': 'SOURCE.JPG',
    'bytes': file.lengthSync(),
    'raw': false,
  };
  @override
  Stream<dynamic> get operationProgress => events.stream;
  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    await cancelAck?.future;
  }

  @override
  Future<Json> call(String op, [Json payload = const {}, String? jobId]) async {
    calls.add((op, Map<String, dynamic>.of(payload), jobId));
    if (op == 'camera.download') {
      final gate = Completer<Json>();
      downloads.add(gate);
      return gate.future;
    }
    if (op == 'media.info') return {'width': 10, 'height': 8, 'raw': false};
    throw AppFailure('Unexpected manual soft-stop operation $op');
  }
}

class SoftManualState extends AppState {
  SoftManualState(super.core) {
    session = {
      'user': {'id': 'owner'},
    };
  }
  int registered = 0;
  @override
  Future<Photo> registerPhoto(String path, String name, Json info) async {
    registered++;
    return Photo(path, name, info);
  }
}

Future<void> untilSoftStop(bool Function() ready) => retired.untilRetired226(
  ready,
  'The real held bridge operation must be reached',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final operation in ['camera.status', 'camera.resolve']) {
    test(
      'Queue ${operation == 'camera.status' ? 'background' : 'ordinary'} stop drains held $operation without canceling the camera',
      () async {
        final f = SoftQueueFixture();
        addTearDown(f.close);
        f.core.heldOperation = operation;
        final gate = f.core.cameraGate = Completer<Json>();
        final run = f.run('old');
        await untilSoftStop(() => f.core.calls.any((c) => c.$1 == operation));
        final job = f.queue.job;
        if (operation == 'camera.status') {
          f.queue.didChangeAppLifecycleState(AppLifecycleState.paused);
        }
        final stop = f.queue.stop();
        final repeated = f.queue.stop();
        expect(f.queue.busy, isTrue);
        expect(f.queue.phase, 'stopping');
        expect(f.queue.pendingCameraJob, job);
        expect(f.state.cameraDownloadsActive, isTrue);
        expect(f.state.claimCameraTransfer(), isFalse);
        await f.queue.resume('new');
        expect(
          f.core.calls.any(
            (c) => c.$1 == 'downloads.get' && c.$2['id'] == 'new',
          ),
          isFalse,
        );
        expect(f.core.cancelled, isEmpty);
        gate.complete({
          'connected': true,
          'session': 'old-session',
          'downloadCameraId': 'same-camera',
          'downloadTrusted': true,
          'match': {'handle': 2},
          'hasMore': false,
        });
        await Future.wait([run, stop, repeated]);
        expect(f.queue.busy, isFalse);
        expect(f.queue.phase, 'paused');
        expect(f.core.cancelled, isEmpty);
        expect(f.core.calls.any((c) => c.$1 == 'camera.download'), isFalse);
        expect(f.state.registered, isEmpty);
        expect(f.queue.done, 1);
      },
    );
  }

  test('Queue soft stop retains a received original and resume imports its durable receipt without redownloading', () async {
    final f = SoftQueueFixture();
    addTearDown(f.close);
    final run = f.run('old');
    await untilSoftStop(
      () => f.queue.pendingCameraJob != null && f.queue.phase == 'receiving',
    );
    final original = File(f.core.receipts['old']!['path'] as String);
    final before = original.readAsBytesSync();
    final stop = f.queue.stop();
    expect(f.queue.busy, isTrue);
    expect(f.core.cancelled, isEmpty);
    f.core.downloads['old']!.complete(f.core.receipts['old']!);
    await Future.wait([run, stop]);
    expect(f.queue.phase, 'paused');
    expect(f.state.registered, isEmpty);
    expect(f.queue.done, 1);
    expect(f.core.row('old')['receipt'], isNotNull);
    expect(original.readAsBytesSync(), before);
    await f.run('old');
    expect(f.queue.phase, 'done');
    expect(f.queue.done, 2);
    expect(f.state.registered, [original.path]);
    expect(f.core.calls.where((c) => c.$1 == 'camera.download'), hasLength(1));
    expect(f.core.cancelled, isEmpty);
    expect(original.readAsBytesSync(), before);
  });

  test('Queue hard upgrade cancels only its held old job and a late cancel ACK cannot alter a new session', () async {
    final f = SoftQueueFixture();
    addTearDown(f.close);
    f.core.cancelAck = Completer<void>();
    final oldRun = f.run('old');
    await untilSoftStop(() => f.queue.phase == 'receiving');
    final oldJob = f.queue.job!;
    final soft = f.queue.stop();
    final hard = f.queue.stop(preserveConnection: false);
    final duplicate = f.queue.stop(preserveConnection: false);
    await untilSoftStop(() => f.core.cancelled.length == 1);
    expect(f.core.cancelled, [oldJob]);
    expect(f.queue.busy, isTrue);
    f.core.downloads['old']!.complete(f.core.receipts['old']!);
    await Future.wait([oldRun, soft, duplicate]);
    f.core.sessionName = 'new-session';
    final newer = f.run('new');
    await untilSoftStop(() => f.queue.phase == 'receiving');
    final newJob = f.queue.job, newEvents = f.queue.events;
    f.core.cancelAck!.completeError(
      const AppFailure('Old cancel ACK failed late'),
    );
    await hard;
    expect(f.queue.busy, isTrue);
    expect(f.queue.job, newJob);
    expect(identical(f.queue.events, newEvents), isTrue);
    expect(f.queue.error, isNull);
    expect(f.queue.current!['id'], 'new');
    expect(f.state.protection.actors, contains('downloads'));
    expect(f.core.cancelled, [oldJob]);
    f.core.downloads['new']!.complete(f.core.receipts['new']!);
    await newer;
    expect(f.state.registered, [f.core.receipts['new']!['path']]);
  });

  test('Account retirement during a queue soft stop cannot pause or clear the next owner run', () async {
    final f = SoftQueueFixture();
    addTearDown(f.close);
    f.core.journals['new']!['owner'] = 'other';
    final oldRun = f.run('old');
    await untilSoftStop(() => f.queue.phase == 'receiving');
    final oldJob = f.queue.job;
    final soft = f.queue.stop();
    f.state.changeOwner('other');
    expect(f.queue.busy, isFalse);
    expect(f.core.cancelled, [oldJob]);
    f.core.sessionName = 'new-session';
    final newer = f.run('new');
    await untilSoftStop(() => f.queue.phase == 'receiving');
    final newJob = f.queue.job, events = f.queue.events;
    f.core.downloads['old']!.complete(f.core.receipts['old']!);
    await Future.wait([oldRun, soft]);
    expect(f.queue.busy, isTrue);
    expect(f.queue.job, newJob);
    expect(identical(f.queue.events, events), isTrue);
    expect(f.queue.current!['owner'], 'other');
    expect(f.state.protection.actors, contains('downloads'));
    expect(
      f.core.calls.any((c) => c.$1 == 'downloads.pause' && c.$2['id'] == 'old'),
      isFalse,
    );
    f.core.downloads['new']!.complete(f.core.receipts['new']!);
    await newer;
    expect(f.state.registered, [f.core.receipts['new']!['path']]);
  });

  test('Queue local metadata work still cancels safely while its saved original is preserved', () async {
    final f = SoftQueueFixture();
    addTearDown(f.close);
    f.core.row('old')['receipt'] = f.core.receipts['old'];
    f.core.mediaGate = Completer<void>();
    final run = f.run('old');
    await untilSoftStop(() => f.core.calls.any((c) => c.$1 == 'media.info'));
    final localJob = f.queue.job;
    await f.queue.stop();
    await run;
    expect(f.core.cancelled, [localJob]);
    expect(f.core.calls.any((c) => c.$1.startsWith('camera.')), isFalse);
    expect(f.state.registered, isEmpty);
    expect(
      File(f.core.receipts['old']!['path'] as String).existsSync(),
      isTrue,
    );
    expect(f.queue.phase, 'paused');
  });

  for (final upgrade in [false, true]) {
    test(
      'Manual stop ${upgrade ? 'upgrades through the scoped reconnect lease and fences late ACKs' : 'drains without cancel or publication and preserves source bytes'}',
      () async {
        final directory = Directory.systemTemp.createTempSync(
          'huevia-soft-manual-',
        );
        final core = SoftManualCore(directory);
        final state = SoftManualState(core);
        final transfer = CameraTransfer(state);
        final runs = <Future<void>>[];
        addTearDown(() async {
          if (core.cancelAck?.isCompleted == false) core.cancelAck!.complete();
          for (final gate in core.downloads) {
            if (!gate.isCompleted) gate.complete(core.receipt);
          }
          await Future.wait(runs);
          await transfer.stop();
          transfer.dispose();
          state.dispose();
          await core.events.close();
          expect(
            p.isWithin(
              Directory.systemTemp.absolute.path,
              directory.absolute.path,
            ),
            isTrue,
          );
          expect(
            p.basename(directory.path).startsWith('huevia-soft-manual-'),
            isTrue,
          );
          await directory.delete(recursive: true);
        });
        if (upgrade) core.cancelAck = Completer<void>();
        final oldRun = transfer.start('old-session', core.item, raw: false);
        runs.add(oldRun);
        await untilSoftStop(() => core.downloads.length == 1);
        final oldJob = transfer.job;
        final before = core.file.readAsBytesSync();
        final soft = state.stopCameraManualTransfer(
          expectedSession: 'old-session',
          preserveConnection: true,
        );
        expect(transfer.busy, isTrue);
        expect(transfer.phase, CameraTransferPhase.stopping);
        expect(transfer.job, oldJob);
        expect(state.cameraManualTransferActive, isTrue);
        expect(state.claimCameraTransfer(), isFalse);
        expect(core.cancelled, isEmpty);
        Future<void>? hard;
        if (upgrade) {
          hard = state.stopCameraManualTransfer(expectedSession: 'old-session');
          await untilSoftStop(() => core.cancelled.isNotEmpty);
          expect(core.cancelled, [oldJob]);
        }
        core.downloads.first.complete(core.receipt);
        await Future.wait([oldRun, soft]);
        expect(transfer.busy, isFalse);
        expect(transfer.phase, CameraTransferPhase.stopped);
        expect(state.cameraManualTransferActive, isFalse);
        expect(state.registered, 0);
        expect(transfer.importedPhoto, isNull);
        expect(core.file.readAsBytesSync(), before);
        if (!upgrade) return;
        final next = transfer.start('new-session', core.item, raw: false);
        runs.add(next);
        await untilSoftStop(() => core.downloads.length == 2);
        final newJob = transfer.job;
        core.cancelAck!.completeError(
          const AppFailure('Late old manual cancel ACK'),
        );
        await hard;
        expect(transfer.busy, isTrue);
        expect(transfer.job, newJob);
        expect(transfer.error, isNull);
        expect(state.cameraManualTransferActive, isTrue);
        expect(core.cancelled, [oldJob]);
        core.events.add({'jobId': newJob, 'progress': .5});
        expect(transfer.received, core.file.lengthSync() ~/ 2);
        core.downloads.last.complete(core.receipt);
        await next;
        expect(transfer.phase, CameraTransferPhase.done);
        expect(state.registered, 1);
        expect(transfer.importedPhoto!.path, core.file.path);
        expect(core.file.readAsBytesSync(), before);
      },
    );
  }
}
