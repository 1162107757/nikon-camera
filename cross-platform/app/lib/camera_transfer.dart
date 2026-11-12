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
  String? error, job;
  int received = 0, total = 0;
  bool busy = false, _alive = true, _stopped = false, _invalid = false;
  String _owner = '';
  int _sequence = 0;
  StreamSubscription<dynamic>? _events;

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
  void _check() {
    if (!_alive || _stopped) throw const AppFailure('下载已停止。');
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
    received = total = 0;
    phase = CameraTransferPhase.invalid;
    error = '请返回后重新读取照片。';
    unawaited(stop());
    _changed();
  }

  void _progress(dynamic event) {
    if (!_alive ||
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
    photo = Map<String, dynamic>.of(item);
    _owner = _currentOwner;
    _stopped = _invalid = false;
    received = 0;
    total = size;
    error = null;
    busy = true;
    phase = CameraTransferPhase.preparing;
    final identity =
        'camera-download-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    job = identity;
    _events = state.core.operationProgress.listen(_progress, onError: (_) {});
    _changed();
    try {
      _check();
      final result = await state.core.call('camera.download', {
        'session': session,
        'handle': item['handle'],
        'raw': raw,
      }, identity);
      _check();
      job = null;
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
      _check();
      await state.registerPhoto(path, name, info);
      _check();
      phase = CameraTransferPhase.done;
    } catch (failure) {
      if (_invalid) {
        phase = CameraTransferPhase.invalid;
      } else if (_stopped) {
        phase = CameraTransferPhase.stopped;
      } else {
        phase = CameraTransferPhase.failed;
        error = '$failure';
      }
    } finally {
      await _events?.cancel();
      _events = null;
      job = null;
      busy = false;
      _changed();
    }
  }

  Future<void> stop() async {
    if (!busy || _stopped) return;
    _stopped = true;
    if (!_invalid) phase = CameraTransferPhase.stopping;
    _changed();
    final identity = job;
    if (identity != null) {
      try {
        await state.core.cancel(identity);
      } catch (_) {
        if (_alive && !_invalid) {
          error = '停止请求未确认，正在等待当前任务结果。';
          _changed();
        }
      }
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
