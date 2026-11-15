import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'theme.dart';

enum CameraTransferPhase {
  idle,
  preparing,
  receiving,
  validating,
  importing,
  done,
  failed,
  stopping,
  stopped,
  invalid,
}

class CameraTransfer extends ChangeNotifier {
  CameraTransfer(this.state) {
    state.addListener(_accountChanged);
  }
  final AppState state;
  CameraTransferPhase phase = CameraTransferPhase.idle;
  Json? photo;
  Photo? importedPhoto;
  String? error, job;
  int received = 0, total = 0;
  bool busy = false, _alive = true, _stopped = false, _invalid = false;
  String _owner = '';
  int _sequence = 0;
  int _generation = 0;
  StreamSubscription<dynamic>? _events;
  Completer<void>? _runCompletion, _stopCompletion;
  int _stoppingRunEpoch = -1;
  Set<String> _stopCancelledJobs = {};

  bool get visible => phase != CameraTransferPhase.idle;
  bool get done => phase == CameraTransferPhase.done;
  bool get canStop =>
      busy && !_stopped && !_invalid && phase != CameraTransferPhase.importing;
  double? get fraction => total > 0 ? received / total : null;
  String get title => switch (phase) {
    CameraTransferPhase.idle => '',
    CameraTransferPhase.preparing => '正在准备下载',
    CameraTransferPhase.receiving => '正在接收原文件',
    CameraTransferPhase.validating => '正在校验原文件',
    CameraTransferPhase.importing => '正在保存到应用相册',
    CameraTransferPhase.done => '下载完成',
    CameraTransferPhase.failed => '下载失败',
    CameraTransferPhase.stopping => '正在停止下载',
    CameraTransferPhase.stopped => '已停止下载',
    CameraTransferPhase.invalid => '账号已变化',
  };
  void _changed() {
    if (_alive) notifyListeners();
  }

  String get _currentOwner => state.session['user']?['id'] as String? ?? '';
  void _check(int epoch) {
    if (!_alive || _stopped || epoch != _generation) {
      throw const AppFailure('下载已停止。');
    }
    if (_invalid ||
        _currentOwner != _owner ||
        state.session['logoutPending'] == true) {
      throw const AppFailure('账号已变化，请重新读取照片。');
    }
  }

  void _accountChanged() {
    if (!busy ||
        (_currentOwner == _owner && state.session['logoutPending'] != true)) {
      return;
    }
    _invalid = true;
    photo = null;
    importedPhoto = null;
    received = total = 0;
    phase = CameraTransferPhase.invalid;
    error = '请返回后重新读取照片。';
    unawaited(stop(preserveConnection: false));
    _changed();
  }

  void _progress(dynamic event, int epoch) {
    if (!_alive ||
        epoch != _generation ||
        !busy ||
        _stopped ||
        _invalid ||
        event is! Map ||
        event['jobId'] != job) {
      return;
    }
    final value = event['progress'];
    if (value is! num || !value.isFinite || value < 0 || value > 1) return;
    // Native download checks its data-start byte count against this metadata
    // before publishing fractions. Both platforms send actual receive progress.
    final bytes = (total * value).round();
    if (bytes < received) return;
    received = bytes;
    phase = value >= 1
        ? CameraTransferPhase.validating
        : CameraTransferPhase.receiving;
    _changed();
  }

  Future<void> start(String session, Json item, {required bool raw}) async {
    if (busy || !_alive) return;
    if (state.cameraLiveActive || state.cameraDownloadsActive) {
      phase = CameraTransferPhase.failed;
      error = '请先停止边拍边传或暂停下载队列，再手动下载照片。';
      _changed();
      return;
    }
    final size = item['bytes'];
    if (session.isEmpty ||
        size is! int ||
        size < 4 ||
        size > 512 * 1024 * 1024) {
      phase = CameraTransferPhase.failed;
      error = '照片记录已失效，请刷新相机列表后重试。';
      photo = null;
      _changed();
      return;
    }
    if (!state.claimCameraTransfer(
      session: session,
      onStop: () async {
        // An already verified photo can finish its local publication. A
        // reconnect only cancels this download while it still owns camera I/O.
        if (canStop || busy && _stopCompletion != null) {
          await stop(preserveConnection: false);
        }
      },
    )) {
      phase = CameraTransferPhase.failed;
      error = '另一项相机传输正在进行，请先结束当前传输。';
      _changed();
      return;
    }
    photo = Map<String, dynamic>.of(item);
    importedPhoto = null;
    _owner = _currentOwner;
    _stopped = _invalid = false;
    received = 0;
    total = size;
    error = null;
    busy = true;
    final epoch = ++_generation;
    final completed = Completer<void>();
    _runCompletion = completed;
    _stopCompletion = null;
    _stopCancelledJobs = {};
    phase = CameraTransferPhase.preparing;
    final identity =
        'camera-download-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    job = identity;
    final runEvents = state.core.operationProgress.listen(
      (event) => _progress(event, epoch),
      onError: (_) {},
    );
    _events = runEvents;
    _changed();
    try {
      _check(epoch);
      final Json result;
      try {
        result = await state.core.call('camera.download', {
          'session': session,
          'handle': item['handle'],
          'raw': raw,
        }, identity);
      } finally {
        if (job == identity) job = null;
      }
      _check(epoch);
      final path = result['path'],
          sha = result['sha256'],
          name = result['name'];
      if (path is! String ||
          sha is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
          name is! String ||
          result['bytes'] != size ||
          result['raw'] != raw ||
          state.core.root.isEmpty ||
          !p.isWithin(p.join(state.core.root, 'originals'), path) ||
          p.basename(path) != '$sha.${raw ? 'nef' : 'jpg'}') {
        throw const AppFailure('接收的原文件记录无效，请重新读取照片。');
      }
      received = total;
      phase = CameraTransferPhase.importing;
      _changed();
      final info = await state.core.call('media.info', {'path': path});
      _check(epoch);
      if (result['downloadCameraId'] is String &&
          RegExp(r'^[0-9a-f]{64}$')
              .hasMatch(result['downloadCameraId'] as String) &&
          result['descriptor'] is String &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(result['descriptor'] as String) &&
          result['storage'] is num) {
        info['cameraSource'] = {
          'cameraId': result['downloadCameraId'],
          'descriptor': result['descriptor'],
          'storage': result['storage'],
          'trusted': result['downloadTrusted'] == true,
        };
      }
      final saved = await state.registerPhoto(path, name, info);
      _check(epoch);
      importedPhoto = saved;
      phase = CameraTransferPhase.done;
    } catch (failure) {
      if (_generation == epoch) {
        if (_invalid) {
          phase = CameraTransferPhase.invalid;
        } else if (_stopped) {
          phase = CameraTransferPhase.stopped;
        } else {
          phase = CameraTransferPhase.failed;
          error = '$failure';
        }
      }
    } finally {
      await runEvents.cancel();
      if (_generation == epoch) {
        if (identical(_events, runEvents)) _events = null;
        job = null;
        busy = false;
        state.releaseCameraTransfer();
        if (_generation == epoch) _changed();
      }
      if (identical(_runCompletion, completed)) _runCompletion = null;
      if (!completed.isCompleted) completed.complete();
    }
    final stopping = _stopCompletion;
    if (stopping != null && _stoppingRunEpoch == epoch) {
      await stopping.future;
    }
  }

  Future<void> _cancelStoppingJob(
    int epoch,
    Completer<void> completion, {
    required bool preserveConnection,
  }) async {
    if (preserveConnection ||
        _generation != epoch ||
        !identical(_stopCompletion, completion)) {
      return;
    }
    final identity = job;
    if (identity == null || !_stopCancelledJobs.add(identity)) return;
    try {
      await state.core.cancel(identity);
    } catch (_) {
      if (_alive &&
          !_invalid &&
          _generation == epoch &&
          identical(_stopCompletion, completion) &&
          _currentOwner == _owner) {
        error = '停止请求未确认，正在等待当前任务结果。';
        _changed();
      }
    }
  }

  Future<void> stop({bool preserveConnection = true}) async {
    final existing = _stopCompletion;
    if (existing != null) {
      if (!preserveConnection) {
        await _cancelStoppingJob(
          _generation,
          existing,
          preserveConnection: false,
        );
      }
      await existing.future;
      return;
    }
    if (!busy) return;
    final pending = _runCompletion;
    final stoppedEvents = _events;
    _stoppingRunEpoch = _generation;
    final epoch = ++_generation;
    final completion = Completer<void>();
    _stopCompletion = completion;
    _stopCancelledJobs = {};
    _stopped = true;
    if (!_invalid) phase = CameraTransferPhase.stopping;
    _changed();
    bool currentStop() =>
        _generation == epoch && identical(_stopCompletion, completion);
    try {
      await _cancelStoppingJob(
        epoch,
        completion,
        preserveConnection: preserveConnection,
      );
      if (!currentStop()) return;
      try {
        await pending?.future;
      } catch (_) {
        // The retired run owns any failure and its received original file.
      }
      if (!currentStop()) return;
      if (identical(_events, stoppedEvents)) _events = null;
      job = null;
      busy = false;
      phase = _invalid
          ? CameraTransferPhase.invalid
          : CameraTransferPhase.stopped;
      state.releaseCameraTransfer();
      if (currentStop()) _changed();
    } finally {
      if (!completion.isCompleted) completion.complete();
      if (identical(_stopCompletion, completion)) _stopCompletion = null;
    }
  }

  @override
  void dispose() {
    state.removeListener(_accountChanged);
    _alive = false;
    unawaited(stop());
    unawaited(_events?.cancel());
    super.dispose();
  }
}

String cameraByteCount(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1024 * 1024
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

class CameraTransferCard extends StatelessWidget {
  const CameraTransferCard({super.key, required this.transfer});
  final CameraTransfer transfer;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: transfer,
    builder: (context, _) {
      if (!transfer.visible) return const SizedBox.shrink();
      final p = HuePalette.of(context);
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                transfer.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (transfer.photo != null) ...[
                const SizedBox(height: 6),
                Text(
                  transfer.photo!['name'] as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: transfer.phase == CameraTransferPhase.preparing
                      ? null
                      : transfer.fraction,
                ),
                const SizedBox(height: 8),
                Text(
                  '${cameraByteCount(transfer.received)} / ${cameraByteCount(transfer.total)} · ${((transfer.fraction ?? 0) * 100).floor()}%',
                  style: TextStyle(color: p.secondary),
                ),
              ],
              if (transfer.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  transfer.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (transfer.done)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('已保存到应用相册'),
                ),
              if (transfer.canStop)
                TextButton(onPressed: transfer.stop, child: const Text('停止下载')),
            ],
          ),
        ),
      );
    },
  );
}
