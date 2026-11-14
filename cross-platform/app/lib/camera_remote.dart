import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'camera_remote_preview.dart';
import 'camera_transfer.dart';
import 'domain.dart';
import 'editor_histogram.dart';

const _background = Color(0xff121313);
const _text = Color(0xfff6f1eb);
const _secondary = Color(0xffbeb9b2);
const _accent = Color(0xfff3b493);

class CameraRemotePage extends StatefulWidget {
  const CameraRemotePage({
    super.key,
    required this.state,
    this.embedded = false,
    this.onClose,
  });
  final AppState state;
  final bool embedded;
  final Future<void> Function()? onClose;
  @override
  State<CameraRemotePage> createState() => _CameraRemotePageState();
}

class _CameraRemotePageState extends State<CameraRemotePage>
    with WidgetsBindingObserver {
  Json data = {}, frame = {};
  String? error, job, operationInFlight, busyLabel;
  Completer<void>? pollCompletion;
  bool busy = false, leaving = false, foreground = true;
  bool grid = false, histogram = true, transferAfterCapture = false;
  bool uncertain = false;
  Timer? timer;
  DateTime? frameReceivedAt;
  int ticks = 0, sequence = 0;
  late final String owner;
  late final CameraTransfer transfer;
  final ValueNotifier<int> updates = ValueNotifier<int>(0);
  String importedAction = '';
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
  List<Json> get photos =>
      (action['photos'] as List? ?? []).map(object).toList();
  bool get pending => action['pending'] == true || uncertain;

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
      data = await call('camera.remote.open', {'session': status['session']});
      importedAction = action['actionId'] as String? ?? '';
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
    }
  }

  bool get conflictingWork =>
      widget.state.cameraLiveActive ||
      widget.state.cameraDownloadsActive ||
      widget.state.cameraManualTransferActive;
  String get statusText =>
      error ??
      (busy
          ? busyLabel ?? '正在处理相机操作'
          : pending
          ? '拍摄结果待核对'
          : action['phase'] == 'verified'
          ? '已确认新照片'
          : '相机就绪');

  Future<void> run(
    Future<void> Function() operation, {
    String label = '正在处理相机操作',
    bool allowBackground = false,
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
    });
    try {
      if (waiting != null) await waiting;
      if (!current) return;
      if (waiting != null && error != null) return;
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
      data = await call(operation, {...scope, ...payload});
      if (operation == 'camera.remote.check' ||
          operation == 'camera.remote.acknowledge') {
        uncertain = false;
      }
      await importVerifiedIfEnabled();
    },
    label: switch (operation) {
      'camera.remote.focus' => '正在对焦',
      'camera.remote.check' => '正在核对拍摄结果',
      'camera.remote.acknowledge' => '正在确认拍摄结果',
      'camera.remote.view' => payload['enabled'] == true ? '正在开启取景' : '正在暂停取景',
      _ => '正在处理相机操作',
    },
    allowBackground:
        operation == 'camera.remote.view' && payload['enabled'] == false,
  );

  Future<void> capture() => run(() async {
    if (pending) throw const AppFailure('上次拍摄结果待核对，未发送快门。');
    if (data['connected'] != true || data['capture'] != true) {
      throw const AppFailure('相机当前不可拍摄，请核对机身状态。');
    }
    uncertain = true;
    data = await call('camera.remote.capture', scope);
    uncertain = false;
    if (action['pending'] == true) {
      data = await call('camera.remote.check', scope);
    }
    await importVerifiedIfEnabled();
  }, label: '正在拍摄');

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

  Future<void> poll() async {
    if (!current ||
        !foreground ||
        busy ||
        pollCompletion != null ||
        data['remoteId'] is! String ||
        error != null ||
        conflictingWork) {
      return;
    }
    final refresh = ++ticks % 8 == 0;
    if (!refresh && data['viewing'] != true) return;
    final completion = Completer<void>();
    pollCompletion = completion;
    var changed = false;
    try {
      if (refresh) {
        final next = await call('camera.remote.status', scope);
        if (jsonEncode(next) != jsonEncode(data)) {
          data = next;
          changed = true;
        }
        if (!foreground || data['viewing'] != true) return;
        if (action['pending'] == true) {
          final checked = await call('camera.remote.check', scope);
          if (jsonEncode(checked) != jsonEncode(data)) {
            data = checked;
            changed = true;
          }
        }
        await importVerifiedIfEnabled();
      }
      if (!foreground || data['viewing'] != true) return;
      final next = await call('camera.remote.frame', scope);
      if (next['ready'] == true) {
        await FileImage(File(next['path'] as String)).evict();
        if (current && foreground) {
          frame = next;
          frameReceivedAt = DateTime.now();
          changed = true;
        }
      }
    } catch (failure) {
      if (current) {
        error = '$failure';
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

  Future<void> closeLease(Json lease, Future<void>? waiting) async {
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

  Future<void> acknowledge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('已在相机核对拍摄结果？'),
        content: const Text('请先查看相机中的最近照片。确认后可再次按快门；应用不会自动重拍上次操作。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('返回核对'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('已核对'),
          ),
        ],
      ),
    );
    if (confirmed == true && current) {
      await request('camera.remote.acknowledge', {
        'confirmedOnCamera': true,
        'actionId': action['actionId'],
      });
    }
  }

  @override
  void dispose() {
    final lease = !leaving && data['remoteId'] != null
        ? Map<String, dynamic>.of(scope)
        : null;
    final waiting = pollCompletion?.future;
    leaving = true;
    timer?.cancel();
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
    if (n == null) return '—';
    return switch (code) {
      0x5001 => n >= 0 && n <= 100 ? '$n%' : '—',
      0x5007 => 'F${(n / 100).toStringAsFixed(1)}',
      0x500d =>
        n >= 0xfffffffe
            ? 'Bulb / Time'
            : n > 0 && n < 10000
            ? '1/${(10000 / n).round()}'
            : '${n / 10000}s',
      0x500f => '$n',
      0x5010 => '${(n / 1000).toStringAsFixed(1)} EV',
      0x500e => const {1: 'M', 2: 'P', 3: 'A', 4: 'S'}[n] ?? '$n',
      0x5013 => n == 1 ? '单张' : '请在机身切为单张',
      0x500a => const {1: '手动', 2: '自动', 3: '自动微距'}[n] ?? '$n',
      _ => '$n',
    };
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
      const Text(
        '参数只读，请在相机上调整。未提供的项目显示 —。',
        style: TextStyle(color: _secondary),
      ),
      detail('机型', data['model'] as String? ?? '—'),
      for (final row in const [
        (0x500e, '拍摄模式'),
        (0x500d, '快门'),
        (0x5007, '光圈'),
        (0x500f, 'ISO'),
        (0x5010, '曝光补偿'),
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
        onChanged: busy || data['liveView'] != true
            ? null
            : (on) {
                Navigator.pop(context);
                unawaited(request('camera.remote.view', {'enabled': on}));
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
  Future<void> showHistogram(EditorHistogramData? measured) =>
      sheet('取景直方图', (change) {
        return [
          const Text(
            '根据当前相机取景帧统计，非 RAW 原始数据。',
            style: TextStyle(color: _secondary),
          ),
          const SizedBox(height: 12),
          for (final rgb in [false, true]) ...[
            Text(rgb ? 'RGB · 共用纵轴' : '亮度'),
            const SizedBox(height: 8),
            SizedBox(
              height: 100,
              child: CustomPaint(
                painter: EditorHistogramPainter(data: measured, rgb: rgb),
              ),
            ),
            const SizedBox(height: 16),
          ],
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
      if (error != null)
        Text(error!, style: const TextStyle(color: Color(0xffffb4a7))),
      TextButton(
        onPressed: busy
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

  Widget tools() => Row(
    children: [
      Expanded(
        child: Text(
          '${value(0x500e)}  ${value(0x500a)} · ${value(0x5013)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
      ),
      IconButton(
        tooltip: '拍摄设置',
        onPressed: settings,
        icon: const Icon(Icons.tune),
      ),
      IconButton(
        tooltip: '显示或收起直方图',
        isSelected: histogram,
        onPressed: () => setState(() => histogram = !histogram),
        icon: const Icon(Icons.bar_chart),
      ),
      IconButton(
        tooltip: '切换构图网格',
        isSelected: grid,
        onPressed: () => setState(() => grid = !grid),
        icon: const Icon(Icons.grid_3x3),
      ),
    ],
  );
  Widget preview() => CameraRemotePreview(
    frame: frame,
    busy: busy,
    viewing: data['viewing'] == true,
    foreground: foreground,
    fresh: remoteFrameIsFresh(frameReceivedAt, DateTime.now()),
    grid: grid,
    histogram: histogram,
    onFocus:
        error == null &&
            data['pointFocus'] == true &&
            frame['pointFocus'] == true
        ? (x, y) => unawaited(request('camera.remote.focus', {'x': x, 'y': y}))
        : null,
    onHistogram: (histogram) => unawaited(showHistogram(histogram)),
    onResume: data['liveView'] == true
        ? () => unawaited(request('camera.remote.view', {'enabled': true}))
        : null,
  );
  Widget controls() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            for (final row in const [
              (0x500d, '快门'),
              (0x5007, '光圈'),
              (0x500f, 'ISO'),
              (0x5010, '曝光补偿'),
            ])
              Expanded(
                child: Column(
                  children: [
                    Text(
                      value(row.$1),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      row.$2,
                      style: const TextStyle(fontSize: 11, color: _secondary),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      const Divider(height: 1),
      InkWell(
        onTap: pending
            ? reviewResult
            : () => sheet(
                '拍摄状态',
                (_) => [
                  Text(
                    error ??
                        (action['phase'] == 'verified'
                            ? '已从相机库存确认新照片。'
                            : '准备就绪，请在机身调整参数。'),
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
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 12,
                    color: error != null || pending
                        ? const Color(0xffffb4a7)
                        : _secondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: _secondary),
            ],
          ),
        ),
      ),
      if (transfer.visible)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              Text(transfer.title, style: const TextStyle(fontSize: 12)),
              if (transfer.busy)
                LinearProgressIndicator(value: transfer.fraction),
              if (transfer.error != null)
                Text(
                  transfer.error!,
                  style: const TextStyle(color: Color(0xffffb4a7)),
                ),
            ],
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: TextButton(
                onPressed: photos.isNotEmpty || pending ? recent : null,
                child: const Column(
                  children: [
                    Icon(Icons.photo_outlined),
                    SizedBox(height: 4),
                    Text('最近拍摄', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
            Semantics(
              button: true,
              label: '拍照',
              enabled:
                  !busy && error == null && !pending && data['capture'] == true,
              child: SizedBox(
                width: 84,
                height: 84,
                child: IconButton(
                  key: const Key('remote-shutter'),
                  tooltip: '拍照',
                  onPressed:
                      busy ||
                          error != null ||
                          pending ||
                          data['capture'] != true ||
                          data['connected'] != true
                      ? null
                      : capture,
                  style: IconButton.styleFrom(
                    backgroundColor: _accent,
                    disabledBackgroundColor: _accent.withValues(alpha: .3),
                    foregroundColor: const Color(0xff352016),
                    shape: const CircleBorder(
                      side: BorderSide(color: _accent, width: 2),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt_outlined, size: 34),
                ),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: busy || error != null || data['autoFocus'] != true
                    ? null
                    : () => request('camera.remote.focus'),
                child: const Column(
                  children: [
                    Icon(Icons.center_focus_strong),
                    SizedBox(height: 4),
                    Text('对焦', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final theme = ThemeData.dark(useMaterial3: true).copyWith(
      scaffoldBackgroundColor: _background,
      colorScheme: const ColorScheme.dark(
        primary: _accent,
        onPrimary: Color(0xff352016),
        surface: _background,
        onSurface: _text,
      ),
    );
    final content = Theme(
      data: theme,
      child: ColoredBox(
        color: _background,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    key: const Key('remote-close'),
                    tooltip: '返回同步',
                    onPressed: busy ? null : finish,
                    icon: Icon(
                      widget.embedded ? Icons.close : Icons.arrow_back,
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      '遥控拍摄',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '查看机身参数',
                    onPressed: parameters,
                    icon: const Icon(Icons.info_outline),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${data['connected'] == true ? '•  ' : ''}${data['model'] ?? '正在读取相机能力'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: _secondary),
                      ),
                    ),
                    const Icon(Icons.battery_std, size: 16, color: _secondary),
                    const SizedBox(width: 4),
                    Text(
                      value(0x5001),
                      style: const TextStyle(fontSize: 11, color: _secondary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final landscape =
                        box.maxWidth >= 700 && box.maxHeight >= 240;
                    final stage = Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: tools(),
                        ),
                        Expanded(child: preview()),
                      ],
                    );
                    if (landscape) {
                      return Row(
                        children: [
                          Expanded(child: stage),
                          SizedBox(
                            width: 240,
                            child: SingleChildScrollView(child: controls()),
                          ),
                        ],
                      );
                    }
                    return ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        SizedBox(
                          height: (box.maxWidth * 2 / 3 + 48)
                              .clamp(220, 480)
                              .toDouble(),
                          child: stage,
                        ),
                        controls(),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return PopScope(
      canPop: !busy,
      child: widget.embedded
          ? content
          : Scaffold(
              backgroundColor: _background,
              body: SafeArea(child: content),
            ),
    );
  }
}
