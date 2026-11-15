import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_transfer.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';

class TransferCore extends HueviaCore {
  TransferCore() {
    root = '/private';
  }
  final events = StreamController<dynamic>.broadcast(sync: true);
  final response = Completer<Json>();
  final info = Completer<Json>();
  String? downloadJob;
  int downloads = 0;
  final cancelled = <String>[];
  @override
  Stream<dynamic> get operationProgress => events.stream;
  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
  }

  @override
  Future<Json> call(String op, [Json payload = const {}, String? jobId]) {
    if (op == 'camera.download') {
      downloads++;
      downloadJob = jobId;
      return response.future;
    }
    if (op == 'media.info') return info.future;
    throw AppFailure(op);
  }

  void progress(num value, {String? job}) =>
      events.add({'jobId': job ?? downloadJob, 'progress': value});
  Json receipt() => {
    'path': '/private/originals/${'a' * 64}.jpg',
    'sha256': 'a' * 64,
    'name': 'ONE.JPG',
    'bytes': 8000,
    'raw': false,
  };
}

class TransferState extends AppState {
  TransferState(super.core);
  int registrations = 0;
  Completer<void>? save;
  @override
  Future<Photo> registerPhoto(String path, String name, Json info) async {
    registrations++;
    await save?.future;
    return Photo(path, name, info);
  }

  void changeOwner() {
    session = {
      'user': {'id': 'different'},
    };
    notifyListeners();
  }
}

const transferPhoto = {'handle': 1, 'name': 'ONE.JPG', 'bytes': 8000};
Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  test(
    'Real job progress waits for receipt, metadata and durable catalog save',
    () async {
      final core = TransferCore();
      final actual = TransferState(core)..save = Completer<void>();
      final transfer = CameraTransfer(actual);
      final pending = transfer.start('session', transferPhoto, raw: false);
      await transfer.start('session', transferPhoto, raw: false);
      expect(core.downloads, 1);
      expect(transfer.phase, CameraTransferPhase.preparing);
      core.progress(.25, job: 'other');
      expect(transfer.received, 0);
      core.progress(.25);
      expect(transfer.received, 2000);
      core.progress(.5);
      core.progress(.1);
      core.progress(double.nan);
      core.progress(2);
      expect(transfer.received, 4000);
      core.progress(1);
      expect(transfer.phase, CameraTransferPhase.validating);
      expect(actual.registrations, 0);
      core.response.complete(core.receipt());
      await tick();
      expect(transfer.phase, CameraTransferPhase.importing);
      core.info.complete({});
      await tick();
      expect(actual.registrations, 1);
      expect(transfer.done, false);
      actual.save!.complete();
      await pending;
      expect(transfer.done, true);
      expect(transfer.busy, false);
      transfer.dispose();
      actual.dispose();
      await core.events.close();
    },
  );
  for (final reason in ['cancel', 'owner', 'dispose']) {
    test('Late receive response is ignored after $reason', () async {
      final core = TransferCore();
      final transfer = CameraTransfer(TransferState(core));
      final pending = transfer.start('session', transferPhoto, raw: false);
      Future<void>? stopping;
      if (reason == 'cancel') {
        stopping = transfer.stop();
        expect(transfer.busy, isTrue);
        expect(core.cancelled, isEmpty);
      }
      if (reason == 'owner') (transfer.state as TransferState).changeOwner();
      if (reason == 'dispose') transfer.dispose();
      core.response.complete(core.receipt());
      await pending;
      await stopping;
      expect((transfer.state as TransferState).registrations, 0);
      expect(core.cancelled, hasLength(reason == 'owner' ? 1 : 0));
      expect(transfer.state.cameraManualTransferActive, isFalse);
      if (reason != 'dispose') transfer.dispose();
      transfer.state.dispose();
      await core.events.close();
    });
  }
  test('Invalid metadata and mismatched receipt show failure', () async {
    final core = TransferCore();
    final transfer = CameraTransfer(TransferState(core));
    await transfer.start('', transferPhoto, raw: false);
    expect(transfer.error, contains('刷新'));
    final pending = transfer.start('session', transferPhoto, raw: false);
    core.response.complete({...core.receipt(), 'bytes': 7999});
    await pending;
    expect(transfer.phase, CameraTransferPhase.failed);
    expect(transfer.error, contains('无效'));
    transfer.dispose();
    transfer.state.dispose();
    await core.events.close();
  });
  testWidgets(
    'Download card displays real byte count and stop action on small screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final core = TransferCore();
      final transfer = CameraTransfer(TransferState(core));
      debugPrint('M227 BEFORE START');
      final receiving = transfer.start('session', transferPhoto, raw: false);
      var receivingSettled = false;
      unawaited(
        receiving.then<void>(
          (_) => receivingSettled = true,
          onError: (Object _, StackTrace _) => receivingSettled = true,
        ),
      );
      Future<void> drainReceiving() async {
        for (var i = 0; i < 100 && !receivingSettled; i++) {
          // Stream cancellation can finish outside the widget fake clock.
          // Give both that zone and the frame/microtask queue a turn.
          debugPrint('M227 REAL BEFORE');
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          debugPrint('M227 PUMP BEFORE');
      await tester.pump();
      debugPrint('M227 PUMP AFTER');
        }
        expect(
          receivingSettled,
          isTrue,
          reason: 'The released camera response and soft stop must both drain.',
        );
        debugPrint('M227 AWAIT RECEIVING settled=$receivingSettled busy=${transfer.busy}');
        await receiving;
        debugPrint('M227 RECEIVING DONE');
      }

      core.progress(.5);
      addTearDown(() async {
        if (!core.response.isCompleted) core.response.complete(core.receipt());
        if (!core.info.isCompleted) core.info.complete({});
        try {
          await drainReceiving();
        } finally {
          transfer.dispose();
          transfer.state.dispose();
          debugPrint('M227 REAL BEFORE');
          await tester.runAsync(
            () => core.events.close().timeout(const Duration(seconds: 1)),
          );
        }
      });
      debugPrint('M227 BEFORE WIDGET');
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
                child: CameraTransferCard(transfer: transfer),
              ),
            ),
          ),
        ),
      );
      debugPrint('M227 PUMP BEFORE');
      await tester.pump();
      debugPrint('M227 PUMP AFTER');
      expect(find.textContaining('50%'), findsOneWidget);
      expect(find.textContaining('3.9 KB'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugPrint('M227 TAP BEFORE');
      await tester.tap(find.text('停止下载'));
      debugPrint('M227 TAP AFTER');
      debugPrint('M227 PUMP BEFORE');
      await tester.pump();
      debugPrint('M227 PUMP AFTER');
      expect(find.text('正在停止下载'), findsOneWidget);
      expect(transfer.busy, isTrue);
      expect(core.cancelled, isEmpty);
      debugPrint('M227 RESPONSE BEFORE');
      core.response.complete(core.receipt());
      debugPrint('M227 RESPONSE AFTER');
      await drainReceiving();
      expect(transfer.busy, isFalse);
      debugPrint('M227 BEFORE WIDGET');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
