import 'dart:async';

import 'package:flutter/foundation.dart';

import 'domain.dart';

/// One bounded, cancellable camera request. A cancelled generation can never
/// install a late method-channel result into the next attempt's UI.
class CameraConnectionRequest extends ChangeNotifier {
  CameraConnectionRequest(this.core);
  final HueviaCore core;
  bool busy = false;
  bool _disposed = false, _wired = false, _permissionWaiting = false;
  int elapsedSeconds = 0;
  String jobId = '', operation = '', phase = '';
  Completer<Json>? _pending;
  Timer? _elapsed, _deadline;
  StreamSubscription<dynamic>? _events;

  Future<Json> run(
    String operation,
    Json payload,
    String jobId, {
    required Duration timeout,
  }) {
    if (_disposed || busy) throw const AppFailure('请先完成或取消当前相机操作。');
    final pending = Completer<Json>();
    _pending = pending;
    this.operation = operation;
    this.jobId = jobId;
    _wired = payload['transport'] == 'usb';
    _permissionWaiting = false;
    elapsedSeconds = 0;
    busy = true;
    phase = operation == 'camera.connect'
        ? (_wired ? '等待外接相机访问授权' : '检查相机 Wi-Fi 与本地网络权限')
        : operation == 'camera.usb.devices'
        ? '检测外接相机与访问授权'
        : '读取相机照片目录与首屏';
    try {
      _events = core.operationProgress.listen(_progress, onError: (_) {});
    } catch (_) {
      // A missing optional event stream must not prevent the bounded request.
    }
    _elapsed = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_pending != pending) return;
      elapsedSeconds++;
      notifyListeners();
    });
    _deadline = Timer(timeout, () {
      if (_pending != pending) return;
      cancel(message: '$phase超时，已停止本次操作。请核对相机 Wi-Fi、访问权限和机身确认后重试。');
    });
    notifyListeners();
    unawaited(() async {
      try {
        final result = await core.call(operation, payload, jobId);
        if (_pending != pending) return;
        _release();
        pending.complete(result);
      } catch (error, stack) {
        if (_pending != pending) return;
        _release();
        pending.completeError(error, stack);
      }
    }());
    return pending.future;
  }

  void _progress(dynamic event) {
    if (!busy || event is! Map || event['jobId'] != jobId) return;
    final progress = event['progress'];
    if (progress is! num ||
        !progress.isFinite ||
        operation != 'camera.connect') {
      return;
    }
    final value = progress.toDouble();
    if ((value - .08).abs() < .0001) {
      _permissionWaiting = true;
      phase = '等待 iPhone 本地网络授权，请在系统弹窗中允许';
    } else {
      if (_permissionWaiting && value <= .1) return;
      _permissionWaiting = false;
      phase = value < .04
          ? '等待确认本地网络连接提示'
          : value < .15
          ? (_wired ? '等待外接相机访问授权' : '连接相机 Wi-Fi 通道')
          : value < .3
          ? '等待机身确认连接，请查看相机屏幕'
          : value < .55
          ? (_wired ? '打开外接相机会话并准备目录' : '建立事件通道并打开相机会话')
          : value < .7
          ? '检查相机信息与读取能力'
          : value < 1
          ? '读取存储卡照片目录'
          : '相机连接已建立';
    }
    notifyListeners();
  }

  void _release() {
    _pending = null;
    busy = false;
    jobId = '';
    _elapsed?.cancel();
    _deadline?.cancel();
    _elapsed = _deadline = null;
    final events = _events;
    _events = null;
    if (events != null) unawaited(events.cancel());
    if (!_disposed) notifyListeners();
  }

  void cancel({String message = '已取消相机连接与读取。'}) {
    final pending = _pending;
    if (pending == null) return;
    final job = jobId;
    _release();
    // Cancellation has its own native lane; never wait behind camera IO.
    unawaited(core.cancel(job).catchError((Object _) {}));
    pending.completeError(AppFailure(message));
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}
