import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'camera_remote_preview.dart';
import 'camera_remote_settings.dart';
import 'camera_transfer.dart';
import 'domain.dart';
import 'editor_histogram.dart';

const _background = Color(0xff202925);
const _text = Color(0xfff6f1eb);
const _secondary = Color(0xffc7cec2);
const _accent = Color(0xffd6ecbb);
const _shutter = Color(0xfffaf8ec);
const _overlay = Color(0xbe131d18);
const _overlayBorder = Color(0x40eff7ef);

class CameraRemotePage extends StatefulWidget {
  const CameraRemotePage({
    super.key,
    required this.state,
    this.embedded = false,
    this.onClose,
    this.onClosing,
  });
  final AppState state;
  final bool embedded;
  final Future<void> Function()? onClose;
  final ValueChanged<Future<void>>? onClosing;
  @override
  State<CameraRemotePage> createState() => _CameraRemotePageState();
}

class _CameraRemotePageState extends State<CameraRemotePage>
    with WidgetsBindingObserver {
  Json data = {}, frame = {};
  String? error, job, operationInFlight, busyLabel;
  String? captureNotice, previousCaptureId, pendingAtOpenId;
  String? operationNotice;
  int? adjusting;
  bool temperatureTab = false;
  final settingChoices = <int, List<int>>{};
  Completer<void>? pollCompletion;
  bool busy = false, leaving = false, foreground = true;
  RemoteGrid grid = RemoteGrid.thirds;
  bool histogram = true, histogramRgb = false;
  bool showFullLandscapeFrame = false, transferAfterCapture = false;
  bool orientationOverride = false;
  bool uncertain = false;
  Timer? timer, captureWatch;
  DateTime? frameReceivedAt;
  int ticks = 0, sequence = 0, captureTicks = 0;
  int captureCheckFailures = 0;
  late final String owner;
  late final CameraTransfer transfer;
  final ValueNotifier<int> updates = ValueNotifier<int>(0);
  String importedAction = '', transport = '';
  HueviaCore get core => widget.state.core;
  String get currentOwner =>
      widget.state.session['user']?['id'] as String? ?? '';
  bool get current =>
      mounted &&
      !leaving &&
      currentOwner == owner &&
      widget.state.session['logoutPending'] != true;
  Json get scope => {'session': data['session'], 'remoteId': data['remoteId']};
  Json get action => data['action'] is Map ? object(data['action']) : {};
  List<Json> get photos => action['phase'] == 'verified'
      ? (action['photos'] as List? ?? []).map(object).toList()
      : [];
  bool get pending => action['pending'] == true || uncertain;
  bool get previousShotPending =>
      pendingAtOpenId != null &&
      action['pending'] == true &&
      action['actionId'] == pendingAtOpenId;
  bool get blocksPreview => pending && !previousShotPending;
  bool get offersContinuation =>
      action['pending'] == true &&
      action['actionId'] is String &&
      (previousShotPending || captureWatch == null);
  bool get captureAvailable =>
      !busy && data['connected'] == true && data['capture'] == true;
  bool get canShoot => captureAvailable && error == null && !pending;
  bool get canContinue => captureAvailable && offersContinuation;

  @override
  void initState() {
    super.initState();
    owner = currentOwner;
    transfer = CameraTransfer(widget.state)..addListener(transferChanged);
    widget.state.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(open());
  }

  void transferChanged() {
    if (mounted) {
      setState(() {});
      updates.value++;
    }
  }

  void accountChanged() {
    if (currentOwner == owner &&
        widget.state.session['logoutPending'] != true) {
      return;
    }
    timer?.cancel();
    stopCaptureWatch();
    final lease = Map<String, dynamic>.of(scope);
    final waiting = pollCompletion?.future;
    leaving = true;
    if (job != null &&
        operationInFlight != 'camera.remote.open' &&
        pollCompletion == null) {
      unawaited(core.cancel(job!).catchError((Object _) {}));
    }
    if (data['remoteId'] != null) {
      unawaited(closeLease(lease, waiting));
    }
    if (mounted) {
      setState(() {
        data = {};
        frame = {};
        busy = false;
        error = '账号已改变，请关闭后重新打开遥控拍摄。';
      });
    }
  }

  Future<Json> call(String operation, [Json payload = const {}]) async {
    if (!current) throw const AppFailure('遥控页面已关闭或账号已改变。');
    final id = 'remote-${DateTime.now().microsecondsSinceEpoch}-${sequence++}';
    job = id;
    operationInFlight = operation;
    var expired = false;
    try {
      final result = await core
          .call(operation, payload, id)
          .then((value) {
            if ((expired || !current) && operation == 'camera.remote.open') {
              unawaited(
                core
                    .call('camera.remote.close', {
                      'session': value['session'],
                      'remoteId': value['remoteId'],
                    })
                    .catchError((_) => <String, dynamic>{}),
              );
            }
            return value;
          })
          .timeout(
            Duration(
              seconds:
                  operation == 'camera.remote.capture' ||
                      operation == 'camera.page'
                  ? 75
                  : 20,
            ),
            onTimeout: () {
              expired = true;
              if (current && job == id && operationInFlight == operation) {
                unawaited(core.cancel(id).catchError((Object _) {}));
              }
              throw AppFailure(
                operation == 'camera.remote.capture'
                    ? '快门响应超时，请核对相机中的拍摄结果；不会自动重拍。'
                    : '相机响应超时，请核对连接后重试。',
              );
            },
          );
      if (!current) throw const AppFailure('遥控页面已关闭或账号已改变。');
      return result;
    } finally {
      if (job == id) {
        job = null;
        operationInFlight = null;
      }
    }
  }

  Future<void> open() async {
    await run(() async {
      final status = await call('camera.status');
      if (status['connected'] != true || status['session'] is! String) {
        throw const AppFailure('请先连接尼康相机，再打开遥控拍摄。');
      }
      transport = status['transport'] as String? ?? '';
      data = await call('camera.remote.open', {'session': status['session']});
      importedAction = action['actionId'] as String? ?? '';
      pendingAtOpenId = action['pending'] == true
          ? action['actionId'] as String?
          : null;
      if (data['liveView'] == true && foreground) {
        data = await call('camera.remote.view', {...scope, 'enabled': true});
      }
    }, label: '正在连接遥控');
    if (current) {
      timer?.cancel();
      timer = Timer.periodic(const Duration(milliseconds: 350), (_) {
        if (current &&
            frame.isNotEmpty &&
            !remoteFrameIsFresh(frameReceivedAt, DateTime.now())) {
          setState(() {});
        }
        unawaited(poll());
      });
      startCaptureWatch();
    }
  }

  bool get conflictingWork =>
      widget.state.cameraLiveActive ||
      widget.state.cameraDownloadsActive ||
      widget.state.cameraManualTransferActive;
  String get statusText => busy
      ? busyLabel ?? '正在处理相机操作'
      : previousShotPending
      ? '上次拍摄未核对'
      : captureWatch != null
      ? action['phase'] == 'waitingForJpeg'
            ? 'RAW 已保存，正在等待配套 JPEG'
            : '正在等待相机保存照片'
      : error ??
            captureNotice ??
            operationNotice ??
            (pending
                ? '拍摄结果待核对'
                : action['phase'] == 'verified'
                ? '已确认新照片'
                : '相机就绪');

  Future<void> run(
    Future<void> Function() operation, {
    String label = '正在处理相机操作',
    bool allowBackground = false,
    bool allowAfterReadError = false,
  }) async {
    if (busy || !current) return;
    if (conflictingWork) {
      setState(() => error = '请先停止边拍边传和相机接收任务，再使用遥控拍摄。');
      return;
    }
    final waiting = pollCompletion?.future;
    final expectedLease = Map<String, dynamic>.of(scope);
    setState(() {
      busy = true;
      busyLabel = waiting == null ? label : '等待相机完成当前读取';
      error = null;
      captureNotice = null;
      operationNotice = null;
    });
    try {
      if (waiting != null) await waiting;
      if (!current) return;
      if (waiting != null && error != null && !allowAfterReadError) return;
      if (!foreground && !allowBackground) {
        throw const AppFailure('应用已进入后台，本次操作未发送。');
      }
      if (waiting != null &&
          (expectedLease['session'] != data['session'] ||
              expectedLease['remoteId'] != data['remoteId'])) {
        throw const AppFailure('遥控会话已变化，请核对当前相机后重试。');
      }
      if (conflictingWork) throw const AppFailure('其他相机任务已开始，本次操作未发送。');
      if (busyLabel != label) setState(() => busyLabel = label);
      await operation();
    } catch (failure) {
      if (current) error = '$failure';
    } finally {
      if (current) {
        setState(() {
          busy = false;
          busyLabel = null;
        });
        updates.value++;
        if (!foreground && data['viewing'] == true) pauseForLifecycle();
      }
    }
  }

  Future<void> request(String operation, [Json payload = const {}]) => run(
    () async {
      final next = await call(operation, {...scope, ...payload});
      operationNotice = next['notice'] as String?;
      data = {...next}..remove('notice');
      if (operation == 'camera.remote.check' ||
          operation == 'camera.remote.acknowledge') {
        uncertain = false;
        error = null;
        reconcileCaptureWatch();
        if (operation == 'camera.remote.check') startCaptureWatch();
      }
      await importVerifiedIfEnabled();
    },
    label: switch (operation) {
      'camera.remote.focus' => '正在对焦',
      'camera.remote.exposure.set' => '正在调整曝光',
      'camera.remote.check' => '正在核对拍摄结果',
      'camera.remote.acknowledge' =>
        payload['continueWithoutConfirming'] == true ? '正在恢复拍摄' : '正在确认拍摄结果',
      'camera.remote.view' => payload['enabled'] == true ? '正在开启取景' : '正在暂停取景',
      _ => '正在处理相机操作',
    },
    allowBackground:
        operation == 'camera.remote.view' && payload['enabled'] == false,
    allowAfterReadError: operation == 'camera.remote.acknowledge',
  );

  Future<void> capture() async {
    var attempted = false;
    await run(() async {
      if (pending) throw const AppFailure('上次拍摄结果待核对，未发送快门。');
      if (data['connected'] != true || data['capture'] != true) {
        throw const AppFailure('相机当前不可拍摄，请核对机身状态。');
      }
      attempted = true;
      previousCaptureId = action['actionId'] as String?;
      uncertain = true;
      final next = await call('camera.remote.capture', scope);
      captureNotice = next['notice'] as String?;
      data = {...next}..remove('notice');
      uncertain = false;
    }, label: '正在拍摄');
    if (attempted && startCaptureWatch()) await poll(checkNow: true);
  }

  bool get canWatchCapture =>
      pending &&
      data['connected'] == true &&
      data['capture'] == true &&
      action['canCheck'] != false &&
      action['phase'] != 'multipleExposures';

  // The journal is authoritative after a lost response. A check can confirm a
  // recorded shot or show that the request ended before sending the shutter.
  bool startCaptureWatch() {
    if (!current || !canWatchCapture || captureWatch != null) return false;
    captureTicks = 0;
    captureCheckFailures = 0;
    captureWatch = Timer(const Duration(seconds: 60), () {
      stopCaptureWatch();
      if (current) {
        setState(() {});
        updates.value++;
      }
    });
    setState(() {});
    updates.value++;
    return true;
  }

  void stopCaptureWatch() {
    captureWatch?.cancel();
    captureWatch = null;
  }

  void reconcileCaptureWatch() {
    if (!canWatchCapture) stopCaptureWatch();
  }

  Future<void> importVerifiedIfEnabled() async {
    final id = action['actionId'] as String? ?? '';
    if (!transferAfterCapture ||
        action['phase'] != 'verified' ||
        id.isEmpty ||
        importedAction == id) {
      return;
    }
    final jpeg = photos.where((p) => p['raw'] == false).firstOrNull;
    if (jpeg == null) return;
    importedAction = id;
    try {
      await importPhoto(jpeg);
    } catch (_) {
      importedAction = '';
      rethrow;
    }
  }

  Future<void> poll({bool checkNow = false}) async {
    final watchingCapture = captureWatch != null;
    if (!current ||
        !foreground ||
        busy ||
        pollCompletion != null ||
        data['remoteId'] is! String ||
        (error != null && !watchingCapture) ||
        conflictingWork) {
      return;
    }
    final checkingCapture =
        watchingCapture && (checkNow || ++captureTicks % 3 == 0);
    final refresh = !watchingCapture && ++ticks % 8 == 0;
    if (!checkingCapture &&
        !refresh &&
        (blocksPreview || data['viewing'] != true)) {
      return;
    }
    final completion = Completer<void>();
    pollCompletion = completion;
    var changed = false;
    try {
      if (checkingCapture || refresh) {
        final next = await call(
          checkingCapture ? 'camera.remote.check' : 'camera.remote.status',
          scope,
        );
        if (jsonEncode(next) != jsonEncode(data)) {
          data = next;
          changed = true;
        }
        if (checkingCapture) {
          if (uncertain) {
            changed = true;
            if (action['pending'] != true &&
                (action['phase'] != 'verified' ||
                    action['actionId'] == previousCaptureId)) {
              // A successful journal read found no new shot to finish.
              // Show the failed attempt without locking out the next shot.
              captureNotice = error;
              error = null;
            }
          }
          uncertain = false;
          captureCheckFailures = 0;
          if (error != null &&
              (action['pending'] == true || action['phase'] == 'verified')) {
            error = null;
            changed = true;
          }
          reconcileCaptureWatch();
          if (foreground && action['pending'] != true) {
            await importVerifiedIfEnabled();
          }
          return;
        }
      }
      if (busy || !foreground || blocksPreview || data['viewing'] != true) {
        return;
      }
      final next = await call('camera.remote.frame', scope);
      if (next['ready'] == true) {
        if (current && foreground) {
          frame = next;
          frameReceivedAt = DateTime.now();
          changed = true;
        }
      }
    } catch (failure) {
      if (current) {
        // A transient read failure is not a second shutter attempt. Bound the
        // retries and keep the existing manual confirmation route available.
        if (checkingCapture &&
            captureWatch != null &&
            ++captureCheckFailures < 3) {
          return;
        }
        if (checkingCapture) stopCaptureWatch();
        if (checkingCapture && previousShotPending) {
          captureNotice = '$failure';
        } else {
          error = '$failure';
        }
        changed = true;
      }
    } finally {
      if (identical(pollCompletion, completion)) pollCompletion = null;
      if (current && changed) {
        setState(() {});
        updates.value++;
      }
      completion.complete();
      if (current && !foreground && !busy && data['viewing'] == true) {
        pauseForLifecycle();
      }
    }
  }

  Future<void> closeLease(Json lease, Future<void>? waiting) {
    final released = releaseLease(lease, waiting);
    widget.onClosing?.call(released);
    return released;
  }

  Future<void> releaseLease(Json lease, Future<void>? waiting) async {
    if (waiting != null) await waiting;
    try {
      await core.call('camera.remote.close', lease);
    } catch (_) {
      /* A stale lease never closes a replacement reservation. */
    }
  }

  /// The existing photo reader owns metadata and validates the original receipt.
  /// Release only this remote lease before reading, then reopen the same session.
  Future<void> importPhoto(Json photo) async {
    if (photo['raw'] != false) throw const AppFailure('RAW 请返回相机照片接收原文件。');
    final session = data['session'], resume = data['viewing'] == true;
    await call('camera.remote.close', scope);
    data = {...data, 'remoteId': null, 'viewing': false};
    try {
      Json? item;
      var offset = 0;
      while (item == null && offset < 20000) {
        final page = await call('camera.page', {
          'session': session,
          'offset': offset,
          'limit': 24,
          'raw': false,
          'refresh': offset == 0,
        });
        item = (page['items'] as List)
            .map(object)
            .where(
              (row) =>
                  row['handle'] == photo['handle'] &&
                  row['name'] == photo['name'],
            )
            .firstOrNull;
        if (item != null || page['hasMore'] != true) break;
        final next = page['nextOffset'];
        if (next is! int || next <= offset) {
          throw const AppFailure('相机照片目录已变化。');
        }
        offset = next;
      }
      if (item == null) throw const AppFailure('未找到该拍摄原文件，请返回相机照片核对。');
      await transfer.start(session as String, item, raw: false);
      if (!current) return;
      if (!transfer.done) throw AppFailure(transfer.error ?? '原文件尚未传入 App。');
    } finally {
      if (current) {
        data = await call('camera.remote.open', {'session': session});
        if (resume && foreground && data['liveView'] == true) {
          data = await call('camera.remote.view', {...scope, 'enabled': true});
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    foreground = state == AppLifecycleState.resumed;
    if (!foreground && data['viewing'] == true && !busy) pauseForLifecycle();
    if (mounted) setState(() {});
  }

  void pauseForLifecycle() {
    data = {...data, 'viewing': false};
    unawaited(request('camera.remote.view', {'enabled': false}));
  }

  Future<void> finish() async {
    if (busy || (leaving && data.isNotEmpty)) return;
    final lease = Map<String, dynamic>.of(scope);
    final waiting = pollCompletion?.future;
    setState(() => leaving = true);
    timer?.cancel();
    stopCaptureWatch();
    try {
      if (data['remoteId'] != null) {
        await closeLease(lease, waiting);
      }
    } catch (_) {
      /* Closing never reconnects or disconnects another session. */
    }
    if (!mounted) return;
    if (widget.onClose != null) {
      await widget.onClose!();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> acknowledge({bool continueWithoutConfirming = false}) async {
    final actionId = action['actionId'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(continueWithoutConfirming ? '继续新的拍摄？' : '已在相机核对拍摄结果？'),
        content: Text(
          continueWithoutConfirming
              ? '上次结果会标记为未确认。返回后，按下快门才会拍下一张。'
              : '请先查看相机中的最近照片。确认后可再次按快门。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('返回核对'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(continueWithoutConfirming ? '继续拍摄' : '已核对'),
          ),
        ],
      ),
    );
    if (confirmed == true &&
        current &&
        pending &&
        actionId == action['actionId']) {
      await request('camera.remote.acknowledge', {
        if (continueWithoutConfirming)
          'continueWithoutConfirming': true
        else
          'confirmedOnCamera': true,
        'actionId': actionId,
      });
    }
  }

  @override
  void dispose() {
    if (orientationOverride) {
      unawaited(
        SystemChrome.setPreferredOrientations(const [])
            .catchError((Object _) {}),
      );
    }
    final lease = !leaving && data['remoteId'] != null
        ? Map<String, dynamic>.of(scope)
        : null;
    final waiting = pollCompletion?.future;
    leaving = true;
    timer?.cancel();
    stopCaptureWatch();
    widget.state.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    transfer.removeListener(transferChanged);
    transfer.dispose();
    updates.dispose();
    if (job != null &&
        operationInFlight != 'camera.remote.open' &&
        pollCompletion == null) {
      unawaited(core.cancel(job!).catchError((Object _) {}));
    }
    if (lease != null) {
      unawaited(closeLease(lease, waiting));
    }
    super.dispose();
  }

  int? reading(int code) {
    for (final value in (data['parameters'] as List? ?? [])) {
      final row = object(value);
      if (row['code'] == code && row['value'] is num) {
        return (row['value'] as num).toInt();
      }
    }
    return null;
  }

  String value(int code) {
    final n = reading(code);
    return n == null ? '—' : formatValue(code, n);
  }

  String formatValue(int code, int n) {
    return switch (code) {
      0x5001 => n >= 0 && n <= 100 ? '$n%' : '—',
      0x5007 => n == 0 || n == 65535 ? '—' : 'F${(n / 100).toStringAsFixed(1)}',
      0x500d =>
        n >= 0xfffffffe
            ? 'Bulb / Time'
            : n > 0 && n < 10000
            ? '1/${(10000 / n).round()}'
            : '${n / 10000}s',
      0x500f => n == 65535 ? '自动' : '$n',
      0x5010 => '${n > 0 ? '+' : ''}${(n / 1000).toStringAsFixed(1)} EV',
      remoteWhiteBalance =>
        n == remoteTemperatureMode && reading(remoteTemperature) != null
            ? '${reading(remoteTemperature)} K'
            : remoteWhiteBalanceLabels[n] ?? '—',
      remoteTemperature => '$n K',
      0x500e => const {1: 'M', 2: 'P', 3: 'A', 4: 'S'}[n] ?? '$n',
      0x5013 => n == 1 ? '单张' : '请在机身切为单张',
      0x500a =>
        const {
              1: 'MF',
              2: 'AF',
              3: '自动微距',
              0x8010: 'AF-S',
              0x8011: 'AF-C',
              0x8012: 'AF-A',
              0x8013: 'AF-F',
            }[n] ??
            '—',
      _ => '$n',
    };
  }

  bool canEditExposure(int code) =>
      data['exposureControls'] == true &&
      data['connected'] == true &&
      foreground &&
      !busy &&
      !pending &&
      error == null &&
      reading(code) != null;

  Future<void> editExposure(int code, String label) async {
    if (!canEditExposure(code)) return;
    if (adjusting == code) {
      closeAdjustment();
      return;
    }
    setState(() {
      adjusting = code;
      temperatureTab = false;
      settingChoices.clear();
    });
    await run(() async {
      await loadSetting(code);
      if (code == remoteWhiteBalance &&
          reading(remoteWhiteBalance) == remoteTemperatureMode &&
          foreground &&
          !pending) {
        temperatureTab = true;
        await loadSetting(remoteTemperature);
      }
    }, label: '正在读取$label档位');
  }

  void closeAdjustment() {
    setState(() {
      adjusting = null;
      temperatureTab = false;
      settingChoices.clear();
    });
  }

  Future<void> loadSetting(int code) async {
    final reply = await call('camera.remote.exposure.options', {
      ...scope,
      'code': code,
    });
    final choices = (reply['choices'] as List? ?? const [])
        .whereType<int>()
        .where((value) => code != 0x5007 || (value > 0 && value < 65535))
        .toSet();
    settingChoices[code] = code == remoteWhiteBalance
        ? remoteWhiteBalanceLabels.keys.where(choices.contains).toList()
        : (choices.toList()..sort());
    if (reply['value'] case final int actual) {
      data = {
        ...data,
        'parameters': [
          for (final parameter in (data['parameters'] as List? ?? const []))
            if (parameter is Map && parameter['code'] != code) parameter,
          {'code': code, 'value': actual},
        ],
      };
    }
    operationNotice = settingChoices[code]!.isEmpty
        ? reply['notice'] as String? ?? '当前机身模式下不可调节。'
        : null;
  }

  Future<void> writeSetting(int code, int selected) async {
    if (!foreground || pending) return;
    final next = await call('camera.remote.exposure.set', {
      ...scope,
      'code': code,
      'value': selected,
    });
    operationNotice = next['notice'] as String?;
    data = {...next}..remove('notice');
  }

  Future<void> selectSetting(int code, int selected) async {
    if (!canEditExposure(adjusting ?? -1) ||
        !(settingChoices[code]?.contains(selected) ?? false) ||
        selected == reading(code)) {
      return;
    }
    final label = remoteSettingTitles[code] ?? '色温';
    await run(() => writeSetting(code, selected), label: '正在调整$label');
  }

  Future<void> switchWhiteBalance(bool temperature) async {
    if (!canEditExposure(remoteWhiteBalance) || temperature == temperatureTab) {
      return;
    }
    setState(() {
      temperatureTab = temperature;
      settingChoices.remove(remoteTemperature);
    });
    if (!temperature) return;
    await run(() async {
      if (reading(remoteWhiteBalance) != remoteTemperatureMode) {
        await writeSetting(remoteWhiteBalance, remoteTemperatureMode);
      }
      if (reading(remoteWhiteBalance) == remoteTemperatureMode &&
          foreground &&
          !pending) {
        await loadSetting(remoteTemperature);
      }
    }, label: '正在读取色温档位');
  }

  Future<void> sheet(
    String title,
    List<Widget> Function(StateSetter change) children,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: _background,
    builder: (context) => Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          surface: _background,
          onSurface: _text,
        ),
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([widget.state, updates]),
        builder: (context, _) {
          if (currentOwner != owner ||
              widget.state.session['logoutPending'] == true) {
            return const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('账号已改变，请关闭后重新打开遥控拍摄。'),
              ),
            );
          }
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .85,
              ),
              child: StatefulBuilder(
                builder: (context, change) => ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ...children(change),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  Widget detail(String label, String text) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Text(text),
  );
  Future<void> parameters() => sheet(
    '机身当前参数',
    (_) => [
      Text(
        data['exposureControls'] == true
            ? '点底部的参数查看当前机身允许的档位。'
            : '当前连接只提供参数读取，请在机身上调整。',
        style: const TextStyle(color: _secondary),
      ),
      detail('机型', data['model'] as String? ?? '—'),
      for (final row in const [
        (0x500e, '拍摄模式'),
        (0x500d, '快门'),
        (0x5007, '光圈'),
        (0x500f, 'ISO'),
        (0x5010, '曝光补偿'),
        (remoteWhiteBalance, '白平衡'),
        (0x500a, '对焦模式'),
        (0x5013, '释放模式'),
      ])
        detail(row.$2, value(row.$1)),
    ],
  );
  Future<void> settings() => sheet(
    '拍摄设置',
    (change) => [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('实时取景'),
        subtitle: Text(data['liveView'] == true ? '仅控制当前遥控取景' : '相机未提供此能力'),
        value: data['viewing'] == true,
        onChanged: busy || pending || data['liveView'] != true
            ? null
            : (on) {
                Navigator.pop(context);
                unawaited(request('camera.remote.view', {'enabled': on}));
              },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('横屏完整画幅'),
        subtitle: const Text('打开后，横屏取景也会保留画面的完整边缘。'),
        value: showFullLandscapeFrame,
        onChanged: (on) {
          setState(() => showFullLandscapeFrame = on);
          change(() {});
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('拍摄后传入 App'),
        subtitle: const Text('只接收已核对的新 JPEG，原文件保留在相机'),
        value: transferAfterCapture,
        onChanged: busy
            ? null
            : (on) {
                setState(() => transferAfterCapture = on);
                change(() {});
              },
      ),
      const Text(
        '返回同步会结束取景，保留相机连接。参数在机身调整。',
        style: TextStyle(color: _secondary),
      ),
    ],
  );
  Future<void> showHistogram(EditorHistogramData? measured) => sheet('取景直方图', (
    change,
  ) {
    return [
      SegmentedButton<bool>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: false, label: Text('亮度')),
          ButtonSegment(value: true, label: Text('RGB')),
        ],
        selected: {histogramRgb},
        onSelectionChanged: (selected) {
          setState(() => histogramRgb = selected.single);
          change(() {});
        },
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 120,
        child: CustomPaint(
          painter: EditorHistogramPainter(data: measured, rgb: histogramRgb),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        histogramRgb ? '整张取景帧 · RGB 共用纵轴' : '整张取景帧的亮度分布',
        style: const TextStyle(color: _secondary, fontSize: 12),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('显示在取景页'),
        value: histogram,
        onChanged: (on) {
          setState(() => histogram = on);
          change(() {});
        },
      ),
    ];
  });
  Future<void> recent() => sheet(
    '最近拍摄',
    (_) => [
      if (photos.isEmpty)
        const Text('尚无已核对的新照片。', style: TextStyle(color: _secondary)),
      for (final photo in photos)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            photo['raw'] == true ? Icons.raw_on : Icons.photo_outlined,
          ),
          title: Text(photo['name'] as String? ?? '—'),
          subtitle: Text(
            photo['raw'] == true ? 'RAW · 返回同步接收原文件' : 'JPEG · 已保存到相机',
          ),
          trailing: photo['raw'] == false
              ? TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          Navigator.pop(context);
                          unawaited(run(() => importPhoto(photo)));
                        },
                  child: const Text('传入 App'),
                )
              : null,
        ),
      if (transfer.importedPhoto != null) ...[
        const SizedBox(height: 12),
        Image.file(
          File(transfer.importedPhoto!.path),
          height: 180,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Text('原图已传入应用相册。'),
        ),
        Text('已传入 App · ${transfer.importedPhoto!.name}'),
      ],
      if (pending)
        TextButton(
          onPressed: busy
              ? null
              : () {
                  Navigator.pop(context);
                  unawaited(reviewResult());
                },
          child: const Text('核对拍摄结果'),
        ),
    ],
  );
  Future<void> reviewResult() => sheet(
    '核对拍摄结果',
    (_) => [
      const Text('快门结果尚未核对。为避免重复拍摄，不会自动重发。请查看相机中的最近照片。'),
      if (action['canCheck'] == false)
        const Text('此记录暂不能读取，请在拍摄时使用的相机上查看最近照片。'),
      if (error != null)
        Text(error!, style: const TextStyle(color: Color(0xffffb4a7))),
      if (captureNotice != null)
        Text(captureNotice!, style: const TextStyle(color: Color(0xffffb4a7))),
      TextButton(
        onPressed: busy || action['canCheck'] == false
            ? null
            : () {
                Navigator.pop(context);
                unawaited(request('camera.remote.check'));
              },
        child: const Text('查看相机最近照片'),
      ),
      TextButton(
        onPressed: busy
            ? null
            : () {
                Navigator.pop(context);
                unawaited(acknowledge());
              },
        child: const Text('已核对相机，恢复拍摄'),
      ),
    ],
  );

  Future<void> switchOrientation(bool landscape) async {
    orientationOverride = true;
    try {
      await SystemChrome.setPreferredOrientations(
        landscape
            ? const [DeviceOrientation.portraitUp]
            : const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ],
      );
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('当前设备暂无法切换屏幕方向。')));
    }
  }

  Widget header(bool landscape) {
    final connected = data['connected'] == true;
    final link = switch (transport) {
      'usb' => 'USB',
      'wifi' => 'Wi-Fi',
      _ => '相机',
    };
    final battery = value(0x5001);
    return Row(
      children: [
        SizedBox(
          width: landscape ? 100 : 54,
          child: Align(
            alignment: Alignment.centerLeft,
            child: viewfinderSurface(
              radius: 24,
              child: IconButton(
                key: const Key('remote-close'),
                tooltip: '返回同步',
                onPressed: busy ? null : finish,
                icon: Icon(widget.embedded ? Icons.close : Icons.arrow_back),
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Tooltip(
                message: '查看机身参数',
                child: viewfinderSurface(
                  radius: 28,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: parameters,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 144,
                        minHeight: 46,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 5,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    data['model'] as String? ?? '遥控拍照',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 3),
                                const Icon(Icons.keyboard_arrow_down, size: 12),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 6,
                                  color: connected ? _accent : _secondary,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    connected
                                        ? '$link 已连接'
                                        : busy
                                        ? '读取相机中'
                                        : '相机未连接',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                                if (battery != '—') ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.battery_std, size: 12),
                                  Text(
                                    battery,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 5,
          children: [
            viewfinderSurface(
              radius: 24,
              child: Tooltip(
                message: landscape ? '切换到竖屏' : '切换到横屏',
                child: InkWell(
                  key: const Key('remote-rotate'),
                  onTap: () => switchOrientation(landscape),
                  child: SizedBox.square(
                    dimension: 48,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        RotatedBox(
                          quarterTurns: landscape ? 0 : 1,
                          child: const Icon(
                            Icons.stay_current_portrait,
                            size: 17,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          landscape ? '竖屏' : '横屏',
                          style: const TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            viewfinderSurface(
              radius: 24,
              child: IconButton(
                tooltip: '拍摄设置',
                onPressed: settings,
                icon: const Icon(Icons.tune, size: 21),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget viewfinderSurface({required double radius, required Widget child}) =>
      Material(
        color: _overlay,
        textStyle: const TextStyle(color: _text, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: _overlayBorder),
        ),
        clipBehavior: Clip.hardEdge,
        child: child,
      );

  Widget toolFace(
    IconData icon,
    String label, {
    bool selected = false,
    bool enabled = true,
  }) => Ink(
    decoration: BoxDecoration(
      color: selected ? const Color(0x28d6ecbb) : null,
      borderRadius: BorderRadius.circular(13),
    ),
    child: SizedBox(
      width: 46,
      height: 44,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 17,
            color: !enabled
                ? _secondary.withValues(alpha: .6)
                : selected
                ? _accent
                : _text,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              color: selected ? _accent : _secondary,
            ),
          ),
        ],
      ),
    ),
  );

  Widget viewfinderTool(
    IconData icon,
    String label,
    String tooltip,
    VoidCallback? action, {
    bool selected = false,
  }) => Tooltip(
    message: tooltip,
    child: Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: action,
        child: toolFace(
          icon,
          label,
          selected: selected,
          enabled: action != null,
        ),
      ),
    ),
  );

  Widget gridTool(bool horizontal) => PopupMenuButton<RemoteGrid>(
    tooltip: '切换构图网格',
    position: PopupMenuPosition.under,
    offset: horizontal ? const Offset(0, 2) : const Offset(-116, -44),
    initialValue: grid,
    color: const Color(0xff202b25),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    onSelected: (choice) => setState(() => grid = choice),
    itemBuilder: (_) => [
      for (final choice in RemoteGrid.values)
        PopupMenuItem(
          key: ValueKey('remote-grid-option-${choice.name}'),
          value: choice,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Text(choice.label),
              if (choice == grid)
                const Icon(Icons.check, size: 16, color: _accent),
            ],
          ),
        ),
    ],
    child: toolFace(
      switch (grid) {
        RemoteGrid.thirds => Icons.grid_3x3,
        RemoteGrid.quarters => Icons.grid_4x4,
        RemoteGrid.off => Icons.grid_off,
      },
      grid == RemoteGrid.off ? '网格' : grid.label,
      selected: grid != RemoteGrid.off,
    ),
  );

  Widget tools(bool horizontal) {
    final viewing = data['viewing'] == true;
    return viewfinderSurface(
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Flex(
          direction: horizontal ? Axis.horizontal : Axis.vertical,
          mainAxisSize: MainAxisSize.min,
          spacing: 5,
          children: [
            gridTool(horizontal),
            viewfinderTool(
              Icons.bar_chart,
              '直方图',
              '显示或收起直方图',
              () => setState(() => histogram = !histogram),
              selected: histogram,
            ),
            viewfinderTool(
              viewing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              viewing ? '暂停' : '恢复',
              viewing ? '暂停取景' : '恢复实时取景',
              busy || !foreground || blocksPreview || data['liveView'] != true
                  ? null
                  : () => request('camera.remote.view', {'enabled': !viewing}),
            ),
          ],
        ),
      ),
    );
  }

  Widget shootingMode() {
    final mode = value(0x500e);
    final focus = value(0x500a);
    if (mode == '—' && focus == '—') return const SizedBox.shrink();
    return viewfinderSurface(
      radius: 22,
      child: InkWell(
        onTap: parameters,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, maxWidth: 128),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Align(
              widthFactor: 1,
              heightFactor: 1,
              child: Text(
                [if (mode != '—') mode, if (focus != '—') focus].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget preview(
    bool landscape,
    EdgeInsets frameInsets,
    EdgeInsets histogramInsets,
  ) {
    final fresh = remoteFrameIsFresh(frameReceivedAt, DateTime.now());
    final viewing = data['viewing'] == true && foreground && fresh;
    return CameraRemotePreview(
      frame: frame,
      busy: busy,
      available: data.isEmpty || data['liveView'] == true,
      viewing: data['viewing'] == true,
      foreground: foreground,
      fresh: fresh,
      fit: landscape && !showFullLandscapeFrame ? BoxFit.cover : BoxFit.contain,
      frameInsets: frameInsets,
      grid: grid,
      histogram: histogram,
      histogramRgb: histogramRgb,
      histogramInsets: histogramInsets,
      onFocus:
          error == null &&
              !pending &&
              viewing &&
              data['pointFocus'] == true &&
              frame['pointFocus'] == true
          ? (x, y) =>
                unawaited(request('camera.remote.focus', {'x': x, 'y': y}))
          : null,
      onHistogram: (measured) => unawaited(showHistogram(measured)),
      onResume: !blocksPreview && data['liveView'] == true
          ? () => unawaited(request('camera.remote.view', {'enabled': true}))
          : null,
    );
  }

  Widget exposureControl(int code, String label) {
    final editable = canEditExposure(code);
    final selected = adjusting == code;
    final mode = reading(0x500e);
    final automatic =
        code == 0x5007 && (mode == 2 || mode == 4) ||
        code == 0x500d && (mode == 2 || mode == 3);
    final corner = BorderRadius.circular(14);
    return Semantics(
      selected: selected,
      child: Ink(
        decoration: BoxDecoration(
          color: selected ? const Color(0x30d6ecbb) : null,
          border: selected ? Border.all(color: const Color(0x80d6ecbb)) : null,
          borderRadius: corner,
        ),
        child: InkWell(
          key: ValueKey('remote-exposure-$code'),
          onTap: editable ? () => editExposure(code, label) : null,
          borderRadius: corner,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    automatic ? '$label 自动' : label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: _secondary),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 22,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        value(code),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: selected ? _accent : _text,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget settingPanel(int code) {
    final whiteBalance = code == remoteWhiteBalance;
    final property = whiteBalance && temperatureTab ? remoteTemperature : code;
    final available = settingChoices[property] ?? const <int>[];
    final presets = whiteBalance && !temperatureTab;
    final choices = presets
        ? available.where((value) => value != remoteTemperatureMode).toList()
        : available;
    final editable =
        canEditExposure(code) &&
        (property != remoteTemperature ||
            reading(remoteWhiteBalance) == remoteTemperatureMode);
    final balanceModes = settingChoices[remoteWhiteBalance] ?? const <int>[];
    final canSelectTemperature =
        balanceModes.contains(remoteTemperatureMode) ||
        reading(remoteWhiteBalance) == remoteTemperatureMode;
    final onChanged = editable
        ? (int value) => selectSetting(property, value)
        : null;
    final title = remoteSettingTitles[code]!;
    final maximumAperture = code == 0x5007 && choices.isNotEmpty
        ? choices.first
        : null;
    Widget card(Widget child, {Widget? readout}) => CameraRemoteSettingCard(
      title: title,
      readout: readout,
      onClose: busy ? null : closeAdjustment,
      tabs: whiteBalance
          ? SegmentedButton<bool>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(fontSize: 11),
                visualDensity: VisualDensity.compact,
              ),
              segments: [
                const ButtonSegment(value: false, label: Text('预设')),
                ButtonSegment(
                  value: true,
                  enabled: canSelectTemperature || temperatureTab,
                  label: const Text('色温'),
                ),
              ],
              selected: {temperatureTab},
              onSelectionChanged: canEditExposure(code)
                  ? (value) => switchWhiteBalance(value.single)
                  : null,
            )
          : null,
      action: maximumAperture == null
          ? null
          : TextButton(
              key: const Key('remote-maximum-aperture'),
              onPressed: onChanged == null
                  ? null
                  : () => onChanged(maximumAperture),
              child: Text(
                '最大光圈 ${formatValue(code, maximumAperture)}',
                style: const TextStyle(fontSize: 11),
              ),
            ),
      child: child,
    );
    if (choices.isEmpty) {
      return card(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Text(
            busy ? busyLabel ?? '正在读取档位' : operationNotice ?? '当前机身模式下不可调节。',
            style: const TextStyle(fontSize: 12, color: _secondary),
          ),
        ),
      );
    }
    return presets
        ? card(
            CameraRemoteWhiteBalancePresets(
              presets: choices,
              selected: reading(code),
              onChanged: onChanged,
            ),
          )
        : CameraRemoteRuler(
            key: ValueKey(property),
            title: property == remoteTemperature ? '色温' : title,
            temperature: property == remoteTemperature,
            values: choices,
            actual: reading(property),
            formatValue: (value) => formatValue(property, value),
            onChanged: onChanged,
            buildCard: card,
          );
  }

  Widget captureStatus({bool compact = false}) {
    final warning =
        error != null ||
        captureNotice != null ||
        operationNotice != null ||
        transfer.error != null ||
        pending;
    final transferStatus = transfer.error ?? transfer.title;
    final showTransfer =
        transfer.visible &&
        !pending &&
        !busy &&
        captureWatch == null &&
        error == null &&
        captureNotice == null &&
        operationNotice == null;
    final text = showTransfer ? transferStatus : statusText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 2,
          child: transfer.busy
              ? LinearProgressIndicator(value: transfer.fraction, minHeight: 2)
              : null,
        ),
        InkWell(
          onTap: pending
              ? reviewResult
              : () => sheet(
                  '拍摄状态',
                  (_) => [
                    Text(
                      transfer.error ??
                          error ??
                          captureNotice ??
                          operationNotice ??
                          (transfer.visible
                              ? transferStatus
                              : action['phase'] == 'verified'
                              ? '已从相机库存确认新照片。'
                              : transferAfterCapture
                              ? '拍摄后的新 JPEG 会传入 App，原文件保留在相机。'
                              : '照片保存在相机。'),
                    ),
                    if (error != null && data.isEmpty)
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          unawaited(open());
                        },
                        child: const Text('重试遥控连接'),
                      ),
                  ],
                ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 32 : 46),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  if (busy)
                    const SizedBox.square(
                      dimension: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.circle,
                      size: 6,
                      color: warning ? const Color(0xffffc29f) : _accent,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: warning ? const Color(0xffffc29f) : _secondary,
                      ),
                    ),
                  ),
                  if (offersContinuation)
                    TextButton(
                      key: const Key('remote-continue'),
                      onPressed: canContinue
                          ? () => acknowledge(continueWithoutConfirming: true)
                          : null,
                      child: const Text('继续拍摄'),
                    )
                  else
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: _secondary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget captureActions({bool landscape = false}) {
    final path = transfer.importedPhoto?.path;
    final shutterEnabled = canShoot || canContinue;
    final recentButton = TextButton(
      onPressed: recent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (path == null)
            const Icon(Icons.photo_outlined, size: 23)
          else
            ClipOval(
              child: Image.file(
                File(path),
                width: 30,
                height: 30,
                fit: BoxFit.cover,
                cacheWidth: 90,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.photo_outlined, size: 23),
              ),
            ),
          const SizedBox(height: 4),
          const Text('最近拍摄', style: TextStyle(fontSize: 10)),
        ],
      ),
    );
    final shutterButton = SizedBox.square(
      dimension: landscape ? 62 : 68,
      child: IconButton(
        key: const Key('remote-shutter'),
        tooltip: canContinue ? '继续拍摄' : '拍照',
        onPressed: canShoot
            ? capture
            : canContinue
            ? () => acknowledge(continueWithoutConfirming: true)
            : null,
        style: IconButton.styleFrom(
          padding: const EdgeInsets.all(6),
          shape: const CircleBorder(),
          side: BorderSide(
            color: _shutter.withValues(alpha: shutterEnabled ? .86 : .38),
          ),
        ),
        icon: Container(
          width: landscape ? 49 : 54,
          height: landscape ? 49 : 54,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _shutter.withValues(alpha: shutterEnabled ? 1 : .31),
          ),
          child: canContinue
              ? const Icon(Icons.priority_high, color: _background, size: 19)
              : null,
        ),
      ),
    );
    final focusButton = TextButton(
      onPressed: busy || error != null || pending || data['autoFocus'] != true
          ? null
          : () => request('camera.remote.focus'),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.center_focus_strong, size: 23),
          SizedBox(height: 4),
          Text('对焦', style: TextStyle(fontSize: 10)),
        ],
      ),
    );
    return Padding(
      padding: landscape
          ? const EdgeInsets.symmetric(vertical: 6)
          : const EdgeInsets.fromLTRB(9, 6, 9, 2),
      child: landscape
          ? Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [recentButton, shutterButton, focusButton],
            )
          : Row(
              children: [
                Expanded(child: recentButton),
                shutterButton,
                Expanded(child: focusButton),
              ],
            ),
    );
  }

  Widget exposureBar() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 3),
    child: Row(
      children: [
        for (final entry in remoteSettingTitles.entries)
          Expanded(child: exposureControl(entry.key, entry.value)),
      ],
    ),
  );

  Widget portraitControls() => viewfinderSurface(
    radius: 23,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        exposureBar(),
        const Divider(
          color: _overlayBorder,
          height: 1,
          indent: 12,
          endIndent: 12,
        ),
        captureActions(),
        captureStatus(),
      ],
    ),
  );

  Widget viewfinder() => LayoutBuilder(
    builder: (context, box) {
      final safe = MediaQuery.paddingOf(context);
      final width = box.maxWidth - safe.horizontal;
      final height = box.maxHeight - safe.vertical;
      final landscape = width > height;
      final compact = height < 540;
      final toolbarBelowHeader = landscape && width < 740;
      const railWidth = 78.0;
      const railMargin = railWidth + 24.0;
      final dockWidth = (width - railMargin - 12).clamp(1.0, 550.0);
      final dockLeft = ((width - dockWidth) / 2).clamp(
        12.0,
        (width - railMargin - dockWidth).clamp(12.0, double.infinity),
      );
      final frameInsets =
          safe +
          (landscape
              ? const EdgeInsets.fromLTRB(12, 65, railMargin, 112)
              : EdgeInsets.only(
                  top: compact ? 128 : (height * .28).clamp(220.0, 248.0),
                  bottom: 200,
                ));
      final histogramInsets = EdgeInsets.fromLTRB(
        safe.left + 13,
        safe.top + 76,
        safe.right + (landscape ? railMargin : 70),
        safe.bottom + (landscape ? 116 : 194),
      );
      final horizontalTools = landscape || compact;
      return Stack(
        fit: StackFit.expand,
        children: [
          preview(landscape, frameInsets, histogramInsets),
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: landscape ? 62 : 0,
                  left: landscape ? dockLeft : 12,
                  width: landscape ? dockWidth : null,
                  right: landscape ? null : 12,
                  bottom: landscape ? 8 : 12,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (adjusting case final code?)
                        Flexible(
                          child: SingleChildScrollView(
                            reverse: true,
                            child: settingPanel(code),
                          ),
                        ),
                      if (landscape) ...[
                        viewfinderSurface(radius: 16, child: exposureBar()),
                        const SizedBox(height: 4),
                        viewfinderSurface(
                          radius: 8,
                          child: captureStatus(compact: true),
                        ),
                      ] else
                        portraitControls(),
                    ],
                  ),
                ),
                if (landscape)
                  Positioned(
                    top: 62,
                    bottom: 8,
                    right: 12,
                    width: railWidth,
                    child: Align(
                      child: SingleChildScrollView(
                        child: viewfinderSurface(
                          radius: 23,
                          child: SizedBox(
                            width: railWidth,
                            child: captureActions(landscape: true),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: landscape ? 120 : 12,
                  top: landscape ? (toolbarBelowHeader ? 65 : 7) : 76,
                  child: tools(horizontalTools),
                ),
                Positioned(
                  left: 13,
                  top: histogram ? 154 : 76,
                  child: shootingMode(),
                ),
                Positioned(
                  top: 7,
                  left: 12,
                  right: 12,
                  child: header(landscape),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: _background,
      colorScheme: const ColorScheme.dark(
        primary: _accent,
        onPrimary: Color(0xff263621),
        surface: _background,
        onSurface: _text,
      ),
    );
    final content = Theme(
      data: theme,
      child: Material(
        color: _background,
        textStyle: theme.textTheme.bodyMedium!.copyWith(color: _text),
        child: viewfinder(),
      ),
    );
    return PopScope(
      canPop: !busy,
      child: widget.embedded
          ? content
          : AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.light.copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarContrastEnforced: false,
              ),
              child: Scaffold(backgroundColor: _background, body: content),
            ),
    );
  }
}
