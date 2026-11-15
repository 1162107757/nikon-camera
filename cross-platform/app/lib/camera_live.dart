import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'project_presets_model.dart';

class _LiveOperationFailure extends AppFailure {
  _LiveOperationFailure(this.operation, Object failure) : super('$failure');
  final String operation;
}

enum CameraLivePhase {
  idle,
  starting,
  watching,
  receiving,
  importing,
  processing,
  paused,
  waiting,
  blocked,
  stopping,
  stopped,
  failed,
}

enum CameraLiveFormat { jpeg, raw }

/// One foreground producer per application, independent of the visible tab.
/// Durable cursor/receipts belong to the shared core; this object never treats
/// a transport reply alone as a received project photo.
class CameraLive extends ChangeNotifier with WidgetsBindingObserver {
  CameraLive(
    this.state, {
    this.automatic = true,
    this.interval = const Duration(seconds: 3),
  }) {
    _stopRevision = state.connectionProtection.stopRevision;
    state.addListener(_accountChanged);
    state.connectionProtection.addListener(_protectionChanged);
    WidgetsBinding.instance.addObserver(this);
  }
  final AppState state;
  final bool automatic;
  final Duration interval;
  CameraLivePhase phase = CameraLivePhase.idle;
  bool active = false, _alive = true, _foreground = true, _working = false;
  bool _protectionPaused = false;
  bool _transportRetired = false;
  String _retiredSession = '';
  CameraLiveFormat _selectedFormat = CameraLiveFormat.jpeg;
  CameraLiveFormat _sessionFormat = CameraLiveFormat.jpeg;
  int _lastTransportLossGeneration = -1;
  int _stopRevision = 0;
  String owner = '', projectId = '', projectName = '', cameraId = '';
  String session = '', watchId = '', token = '', name = '';
  String? error, _job, _jobOperation;
  String? formatNotice, _latestPreviewPath;
  int received = 0, total = 0, completed = 0, failed = 0, queued = 0;
  double? renderProgress;
  int _generation = 0, _sequence = 0;
  Json snapshot = {};
  Photo? latestPhoto;
  Timer? _timer;
  StreamSubscription<dynamic>? _events;
  ProjectPresetsModel? _processor;
  Future<void>? _processingFuture;

  bool get working => _working;
  CameraLiveFormat get selectedFormat => _selectedFormat;
  bool get transportRetired => _transportRetired;
  String? get pendingCameraJob =>
      _jobOperation?.startsWith('camera.') == true ? _job : null;
  String? get latestPreviewPath =>
      latestPhoto?.info['raw'] == true ? _latestPreviewPath : latestPhoto?.path;
  bool selectFormat(CameraLiveFormat format) {
    if (active || _working || phase == CameraLivePhase.stopping) return false;
    if (_selectedFormat == format) return true;
    _selectedFormat = format;
    formatNotice = null;
    _changed();
    return true;
  }

  bool get foreground => _foreground;
  bool get _canRun =>
      _foreground || state.connectionProtection.backgroundAllowed;
  bool get transportBusy =>
      active &&
      (phase == CameraLivePhase.starting ||
          phase == CameraLivePhase.receiving ||
          phase == CameraLivePhase.importing);
  String get currentOwner => state.session['user']?['id'] as String? ?? '';
  String get title => switch (phase) {
    CameraLivePhase.idle => '边拍边传',
    CameraLivePhase.starting => '正在准备边拍边传',
    CameraLivePhase.watching =>
      '等待相机新${_sessionFormat == CameraLiveFormat.raw ? ' RAW（NEF）' : ' JPEG'}照片',
    CameraLivePhase.receiving => '正在接收新照片',
    CameraLivePhase.importing => '正在保存新照片',
    CameraLivePhase.processing => '正在套用项目预设',
    CameraLivePhase.paused => '已暂停发现新照片',
    CameraLivePhase.waiting => '等待相机重新连接',
    CameraLivePhase.blocked => '边拍边传需要确认',
    CameraLivePhase.stopping => '正在停止边拍边传',
    CameraLivePhase.stopped => '边拍边传已停止',
    CameraLivePhase.failed => '边拍边传未开始',
  };
  void _changed() {
    if (_alive) notifyListeners();
  }

  bool _current(int generation) =>
      _alive &&
      active &&
      _generation == generation &&
      owner == currentOwner &&
      state.session['logoutPending'] != true;
  void _check(int generation) {
    if (!_current(generation)) throw const AppFailure('拍摄任务已停止或账号已改变。');
    if (!_canRun) throw const AppFailure('后台接收已暂停，返回应用后可继续。');
  }

  Json get _lease => {
    'owner': owner,
    'projectId': projectId,
    'cameraId': cameraId,
    'session': session,
    'watchId': watchId,
    'token': token,
    'format': _sessionFormat.name,
  };
  Future<Json> _call(String operation, Json payload, int generation) async {
    _check(generation);
    final job = 'camera-live-$generation-${_sequence++}';
    _job = job;
    _jobOperation = operation;
    try {
      final value = await state.core.call(operation, payload, job);
      if (!_current(generation)) {
        await _discardLateStart(operation, payload, value, generation);
      }
      _check(generation);
      return value;
    } catch (failure) {
      if (failure is _LiveOperationFailure) rethrow;
      throw _LiveOperationFailure(operation, failure);
    } finally {
      if (_job == job) {
        _job = null;
        _jobOperation = null;
      }
    }
  }

  Future<void> _discardLateStart(
    String operation,
    Json payload,
    Json value,
    int generation,
  ) async {
    // A transport boundary must never send a delayed stop into a new session.
    if (generation <= _lastTransportLossGeneration) return;
    try {
      if (operation == 'project.live.start' && value['token'] is String) {
        await state.core.call('project.live.stop', {
          ...payload,
          'token': value['token'],
          'session': value['session'],
          'watchId': value['watchId'],
        });
      } else if (operation == 'camera.live.start' &&
          value['watchId'] is String) {
        await state.core.call('camera.live.stop', {
          'session': value['session'],
          'watchId': value['watchId'],
        });
      }
    } catch (_) {
      /* An expired identity cannot stop a newer or other-owner run. */
    }
  }

  void _update(Json value) {
    snapshot = value;
    completed = (value['completedCount'] as num? ?? 0).toInt();
    failed = (value['failedCount'] as num? ?? 0).toInt();
    queued = (value['queuedCount'] as num? ?? 0).toInt();
    _changed();
  }

  Future<Json> available(String selected) async {
    final expectedOwner = currentOwner;
    final status = await state.core.call('camera.status');
    if (expectedOwner != currentOwner ||
        state.session['logoutPending'] == true) {
      throw const AppFailure('账号已改变，请重新打开拍摄项目。');
    }
    final id = status['cameraId'];
    if (status['connected'] != true || id is! String || id.isEmpty) {
      throw const AppFailure('请先连接相机，再开启边拍边传。');
    }
    if (status['supportsLive'] != true) {
      throw const AppFailure('当前相机尚未提供已验证的边拍边传能力。');
    }
    _validateStatus(status, format: selectedFormat);
    final value = await state.core.call('project.live.state', {
      'owner': expectedOwner,
      'projectId': selected,
      'cameraId': id,
    });
    if (expectedOwner != currentOwner) {
      throw const AppFailure('账号已改变，请重新打开拍摄项目。');
    }
    return value;
  }

  Future<void> start(
    String selected,
    String label, {
    bool resume = false,
  }) async {
    if (!_alive || active || _working || phase == CameraLivePhase.stopping) {
      return;
    }
    if (state.cameraDownloadsActive) {
      throw const AppFailure('请先暂停下载队列，再开启边拍边传。');
    }
    if (state.cameraManualTransferActive) {
      throw const AppFailure('请先停止手动接收，再开启边拍边传。');
    }
    owner = currentOwner;
    _sessionFormat = _selectedFormat;
    final previousProcessing = _processingFuture;
    _stopRevision = state.connectionProtection.stopRevision;
    projectId = selected;
    projectName = label;
    cameraId = session = watchId = token = name = '';
    error = null;
    formatNotice = null;
    _latestPreviewPath = null;
    _transportRetired = false;
    _retiredSession = '';
    _protectionPaused = false;
    received = total = completed = failed = queued = 0;
    latestPhoto = null;
    active = true;
    _working = true;
    phase = CameraLivePhase.starting;
    final generation = ++_generation;
    _events = state.core.operationProgress.listen(_progress, onError: (_) {});
    _changed();
    try {
      try {
        await previousProcessing;
      } catch (_) {
        // A retired processor's failure is already retained by its project task.
      }
      _check(generation);
      await state.connectionProtection.setActive('live', true);
      final status = await _call('camera.status', {}, generation);
      _validateStatus(status);
      cameraId = status['cameraId'] as String;
      final persisted = await _call('project.live.state', {
        'owner': owner,
        'projectId': projectId,
        'cameraId': cameraId,
      }, generation);
      if (persisted['active'] == true && !resume) {
        throw const AppFailure('此项目有未结束的收片记录，请选择继续上次拍摄，或先结束旧记录。');
      }
      if (resume && persisted['active'] != true) {
        throw const AppFailure('没有可继续的拍摄记录，请重新开始。');
      }
      if (resume && (persisted['format'] ?? 'jpeg') != _sessionFormat.name) {
        throw AppFailure(
          '上次拍摄接收${persisted['format'] == 'raw' ? ' RAW（NEF）' : ' JPEG'}，请选择相同格式后继续，或先结束旧任务。',
        );
      }
      await _attach(status, persisted, generation, resume: resume);
      _processor = ProjectPresetsModel(state)..selected = projectId;
      _processor!.addListener(_processingChanged);
      phase = _canRun ? CameraLivePhase.watching : CameraLivePhase.paused;
    } catch (failure) {
      if (_generation != generation) return;
      if (_current(generation)) {
        error = '$failure';
        active = false;
        phase = CameraLivePhase.failed;
      }
      await _events?.cancel();
      _events = null;
      await state.connectionProtection.setActive('live', false);
      if (watchId.isNotEmpty) {
        try {
          await state.core.call('camera.live.stop', {
            'session': session,
            'watchId': watchId,
          });
        } catch (_) {
          /* Already disconnected. */
        }
      }
    } finally {
      if (_generation == generation) {
        _working = false;
        _changed();
        _schedule();
      }
    }
  }

  void _validateStatus(Json status, {CameraLiveFormat? format}) {
    if (status['connected'] != true) throw const AppFailure('请先连接相机，再开启边拍边传。');
    if (status['supportsLive'] != true ||
        status['cameraId'] is! String ||
        status['session'] is! String) {
      throw const AppFailure('当前相机尚未提供已验证的边拍边传能力。');
    }
    final formats = status['liveFormats'];
    if ((format ?? _sessionFormat) == CameraLiveFormat.raw &&
        (formats is! List || !formats.contains('raw'))) {
      throw const AppFailure('当前相机连接尚未提供受支持的 RAW（NEF）边拍边传，请选择 JPEG。');
    }
  }

  Future<void> _attach(
    Json status,
    Json persisted,
    int generation, {
    required bool resume,
  }) async {
    final nextSession = status['session'] as String;
    session = nextSession;
    final discovery = await _call('camera.live.start', {
      'session': nextSession,
      'cameraId': cameraId,
      'format': _sessionFormat.name,
      if (resume) 'cursor': persisted['cursor'],
    }, generation);
    session = nextSession;
    watchId = discovery['watchId'] as String;
    if (watchId.isEmpty ||
        discovery['session'] != session ||
        discovery['cameraId'] != cameraId ||
        (discovery['format'] ?? 'jpeg') != _sessionFormat.name) {
      throw const AppFailure('相机未确认本次接收格式或会话，未开始边拍边传。');
    }
    final value = await _call('project.live.start', {
      'owner': owner,
      'projectId': projectId,
      'cameraId': cameraId,
      'session': session,
      'watchId': watchId,
      'trustedCamera': status['trustedCamera'] == true,
      'mode': resume ? 'resume' : 'fresh',
      'format': _sessionFormat.name,
      'cursor': discovery['cursor'],
    }, generation);
    token = value['token'] as String;
    if (token.isEmpty ||
        value['session'] != session ||
        value['watchId'] != watchId ||
        value['cameraId'] != cameraId ||
        (value['format'] ?? 'jpeg') != _sessionFormat.name) {
      throw const AppFailure('拍摄项目未确认本次接收格式或收片任务。');
    }
    _update(value);
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (automatic &&
        active &&
        _alive &&
        _canRun &&
        phase != CameraLivePhase.blocked &&
        !_working) {
      _timer = Timer(interval, () => unawaited(pollOnce()));
    }
  }

  Future<void> pollOnce() async {
    if (!active ||
        !_alive ||
        _working ||
        !_canRun ||
        phase == CameraLivePhase.blocked) {
      return;
    }
    _working = true;
    final generation = _generation;
    try {
      final status = await _call('camera.status', {}, generation);
      if (status['connected'] != true) {
        connectionLost(expectedSession: session);
        return;
      }
      if (status['cameraId'] != cameraId) {
        connectionLost(
          expectedSession: session,
          reason: '当前相机已改变，请重新连接并明确选择继续或重新开始拍摄。',
        );
        return;
      }
      if (status['session'] != session) {
        connectionLost(
          expectedSession: session,
          reason: '相机会话已改变，请重新连接后明确继续上次拍摄。',
        );
        return;
      }
      final found = await _call('camera.live.poll', {
        'session': session,
        'watchId': watchId,
        'limit': 12,
        'format': _sessionFormat.name,
      }, generation);
      final unsupportedRaw =
          _sessionFormat == CameraLiveFormat.raw &&
          (found['unsupportedRawCount'] as num? ?? 0) > 0 &&
          (found['items'] as List? ?? const []).isEmpty;
      if ((found['otherFormatCount'] as num? ?? 0) > 0 &&
          (found['items'] as List? ?? const []).isEmpty) {
        formatNotice = _sessionFormat == CameraLiveFormat.raw
            ? '已发现新的 JPEG，尚未收到 RAW（NEF）。请确认相机拍摄格式为 RAW 或 RAW+JPEG。'
            : '已发现新的 RAW，本次仅接收 JPEG。请确认相机拍摄格式包含 JPEG。';
      } else if ((found['items'] as List? ?? const []).isNotEmpty) {
        formatNotice = null;
      }
      _update(
        await _call('project.live.observe', {..._lease, ...found}, generation),
      );
      if (unsupportedRaw) {
        phase = CameraLivePhase.blocked;
        error = '相机提供了当前不支持的 RAW 格式；本次 RAW 接收仅支持 NEF，请停止后改选 JPEG。';
        formatNotice = error;
        return;
      }
      for (final key in snapshot['acknowledged'] as List? ?? []) {
        await _call('camera.live.ack', {
          'session': session,
          'watchId': watchId,
          'objectKey': key,
        }, generation);
      }
      final authorized = (found['items'] as List? ?? [])
          .map(object)
          .map((item) => item['objectKey'])
          .toSet();
      final candidates = (snapshot['pending'] as List? ?? [])
          .map(object)
          .where(
            (item) =>
                item['status'] == 'waiting' &&
                authorized.contains(item['objectKey']),
          )
          .toList();
      for (final item in candidates) {
        _check(generation);
        if (!_canRun) break;
        await _receive(item, generation);
      }
      if (_canRun && _current(generation)) await _process(generation);
      if (_current(generation)) {
        phase = _canRun ? CameraLivePhase.watching : CameraLivePhase.paused;
      }
    } catch (failure) {
      if (_current(generation)) {
        error = '$failure';
        phase = _canRun ? CameraLivePhase.blocked : CameraLivePhase.paused;
        if (_canRun &&
            failure is _LiveOperationFailure &&
            failure.operation.startsWith('camera.')) {
          try {
            final status = await _call('camera.status', {}, generation);
            if (status['connected'] != true || status['session'] != session) {
              connectionLost(expectedSession: session);
            }
          } catch (_) {
            /* Retain the stopped retry state if status is unknown. */
          }
        }
      }
    } finally {
      final recover = _protectionPaused && _current(generation) && _canRun;
      if (recover) {
        _protectionPaused = false;
        error = null;
        phase = CameraLivePhase.watching;
      }
      if (_generation == generation) {
        _working = false;
        _changed();
        if (recover && automatic) {
          unawaited(pollOnce());
        } else {
          _schedule();
        }
      }
    }
  }

  Future<void> retry() async {
    if (!active || _working || phase != CameraLivePhase.blocked) return;
    error = null;
    phase = CameraLivePhase.watching;
    await pollOnce();
  }

  Future<void> _receive(Json item, int generation) async {
    final raw = _sessionFormat == CameraLiveFormat.raw;
    if ((item['raw'] == true) != raw) {
      throw const AppFailure('相机新照片格式与本次拍摄任务不符，未接收。');
    }
    name = item['name'] as String;
    total = item['bytes'] as int;
    received = 0;
    phase = CameraLivePhase.receiving;
    error = null;
    _changed();
    final receipt = await _call('camera.download', {
      'session': session,
      'watchId': watchId,
      'objectKey': item['objectKey'],
      'handle': item['handle'],
      'raw': raw,
      'format': _sessionFormat.name,
    }, generation);
    final path = receipt['path'], sha = receipt['sha256'];
    if (path is! String ||
        sha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        receipt['bytes'] != total ||
        receipt['name'] != name ||
        receipt['raw'] != raw ||
        receipt['session'] != session ||
        receipt['watchId'] != watchId ||
        receipt['cameraId'] != cameraId ||
        receipt['objectKey'] != item['objectKey'] ||
        !p.isWithin(p.join(state.core.root, 'originals'), path) ||
        p.basename(path) != '$sha.${raw ? 'nef' : 'jpg'}') {
      throw const AppFailure('新照片收据与当前拍摄任务不符。');
    }
    received = total;
    phase = CameraLivePhase.importing;
    _changed();
    final info = await _call('media.info', {'path': path}, generation);
    if (raw && info['raw'] != true || !raw && info['raw'] == true) {
      throw const AppFailure('已接收原片的格式检查与本次拍摄任务不符。');
    }
    _check(generation);
    final imported = await state.registerPhoto(path, name, info);
    _check(generation);
    _update(
      await _call('project.live.commit', {...receipt, ..._lease}, generation),
    );
    latestPhoto = imported;
    _latestPreviewPath = raw ? null : path;
    _changed();
    await _call('camera.live.ack', {
      'session': session,
      'watchId': watchId,
      'objectKey': item['objectKey'],
    }, generation);
    if (raw) {
      try {
        final preview = await _call('media.rawThumbnail', {
          'path': path,
          'owner': owner,
          'expectedSourceSha': sha,
        }, generation);
        final thumbnail = preview['path'];
        if (preview['sourceSha'] == sha &&
            thumbnail is String &&
            p.isWithin(p.join(state.core.root, 'raw-thumbnails'), thumbnail)) {
          _latestPreviewPath = thumbnail;
          _changed();
        }
      } catch (_) {
        // The committed RAW is valid even when an optional preview is unavailable.
      }
    }
  }

  bool connectionLost({
    String? expectedSession,
    String reason = '相机已断开，请重新连接后继续上次拍摄。',
  }) {
    if ((!active && phase != CameraLivePhase.starting) ||
        expectedSession != null && expectedSession != session) {
      return false;
    }
    _lastTransportLossGeneration = _generation;
    _transportRetired = true;
    _retiredSession = session;
    active = false;
    ++_generation;
    _working = false;
    _protectionPaused = false;
    _timer?.cancel();
    _timer = null;
    _job = null;
    _jobOperation = null;
    token = '';
    phase = CameraLivePhase.blocked;
    error = reason;
    unawaited(_events?.cancel());
    _events = null;
    final processor = _processor;
    _processor = null;
    if (processor != null) {
      processor.removeListener(_processingChanged);
      processor.stopped = true;
      processor.job = null;
      final processing = _processingFuture;
      if (processing == null) {
        processor.dispose();
      } else {
        // Keep the old project lease alive through its own completion/failure
        // boundary, without canceling any camera transport or a newer job.
        unawaited(() async {
          try {
            await processing;
          } catch (_) {
            /* The original/task journal retains this stopped attempt. */
          }
          processor.job = null;
          processor.dispose();
        }());
      }
    }
    // Retain the durable journal for explicit resume. No old camera job is
    // canceled, stopped or closed after a different transport/session appears.
    unawaited(
      state.connectionProtection
          .setActive('live', false)
          .catchError((Object _) {}),
    );
    _changed();
    return true;
  }

  bool connectionRestored({required String session}) {
    if (!_alive ||
        !_transportRetired ||
        active ||
        owner != currentOwner ||
        state.session['logoutPending'] == true ||
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(session) ||
        session == _retiredSession) {
      return false;
    }
    // A verified new transport only unlocks explicit Start/Resume. Keep any old
    // processing boundary and its working lock; start() already waits for it.
    _transportRetired = false;
    _retiredSession = '';
    error = null;
    phase = CameraLivePhase.stopped;
    _changed();
    return true;
  }

  Future<void> _process(int generation) async {
    final processor = _processor;
    if (processor == null || queued <= 0) return;
    phase = CameraLivePhase.processing;
    renderProgress = null;
    _changed();
    final processing = processor.process();
    _processingFuture = processing;
    try {
      await processing;
    } finally {
      if (_processingFuture == processing) _processingFuture = null;
    }
    _check(generation);
    if (processor.error != null) error = processor.error;
    _update(
      await _call('project.live.state', {
        'owner': owner,
        'projectId': projectId,
        'cameraId': cameraId,
      }, generation),
    );
  }

  void _processingChanged() {
    if (!active) return;
    renderProgress = _processor?.progress;
    _changed();
  }

  void _progress(dynamic event) {
    if (!active ||
        phase != CameraLivePhase.receiving ||
        event is! Map ||
        event['jobId'] != _job) {
      return;
    }
    final progress = event['progress'];
    if (progress is! num ||
        !progress.isFinite ||
        progress < 0 ||
        progress > 1) {
      return;
    }
    final bytes = (total * progress).round();
    if (bytes >= received) {
      received = bytes;
      _changed();
    }
  }

  void _accountChanged() {
    if (owner == currentOwner && state.session['logoutPending'] != true) {
      return;
    }
    latestPhoto = null;
    _latestPreviewPath = null;
    if (!active) {
      _transportRetired = false;
      _retiredSession = '';
      error = formatNotice = null;
      name = '';
      received = total = completed = failed = queued = 0;
      renderProgress = null;
      snapshot = {};
      if (phase != CameraLivePhase.stopping) {
        // This is a local privacy boundary, not authority to stop an old camera
        // or to adopt the new owner's durable producer.
        _lastTransportLossGeneration = _generation;
        ++_generation;
        _working = false;
        _protectionPaused = false;
        _timer?.cancel();
        _timer = null;
        _job = null;
        _jobOperation = null;
        owner = projectId = projectName = cameraId = '';
        session = watchId = token = '';
        phase = CameraLivePhase.stopped;
      }
      _changed();
      return;
    }
    unawaited(stop());
    error = '账号已改变，边拍边传已停止。';
    _changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    _foreground = state == AppLifecycleState.resumed;
    _protectionChanged();
  }

  void _protectionChanged() {
    if (!_alive) return;
    final revision = state.connectionProtection.stopRevision;
    if (revision > _stopRevision) {
      _stopRevision = revision;
      if (active) {
        error = '已从系统通知停止边拍边传。';
        unawaited(stop());
      }
      return;
    }
    if (!_canRun) {
      if (active) _protectionPaused = true;
      _timer?.cancel();
      _timer = null;
      final job = _job;
      if (active && job != null) {
        unawaited(state.core.cancel(job).catchError((Object _) {}));
      }
      if (active) unawaited(_processor?.stop());
      if (active && !_working) phase = CameraLivePhase.paused;
    } else if (active && !_working && phase == CameraLivePhase.paused) {
      _protectionPaused = false;
      phase = CameraLivePhase.watching;
      if (automatic) unawaited(pollOnce());
    }
    _changed();
  }

  Future<void> stop() async {
    if (!active && phase != CameraLivePhase.starting) return;
    final lease = Map<String, dynamic>.of(_lease), job = _job;
    active = false;
    _protectionPaused = false;
    ++_generation;
    _working = false;
    _timer?.cancel();
    _timer = null;
    phase = CameraLivePhase.stopping;
    _changed();
    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (failure) {
        error = '已停止发现新照片，部分停止记录尚未确认：$failure';
      }
    }

    if (job != null) await attempt(() => state.core.cancel(job));
    await attempt(() async {
      await _processor?.stop();
    });
    await attempt(() async {
      await _processingFuture;
    });
    if ((lease['token'] as String).isNotEmpty) {
      await attempt(() async {
        await state.core.call('project.live.stop', lease);
      });
    }
    try {
      if ((lease['watchId'] as String).isNotEmpty) {
        await state.core.call('camera.live.stop', {
          'session': lease['session'],
          'watchId': lease['watchId'],
        });
      }
    } catch (_) {
      /* The camera may already be disconnected. */
    }
    await _events?.cancel();
    _events = null;
    _processor?.removeListener(_processingChanged);
    _processor?.dispose();
    _processor = null;
    await state.connectionProtection.setActive('live', false);
    phase = CameraLivePhase.stopped;
    _changed();
  }

  @override
  void dispose() {
    _alive = false;
    state.removeListener(_accountChanged);
    state.connectionProtection.removeListener(_protectionChanged);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(stop());
    super.dispose();
  }
}
