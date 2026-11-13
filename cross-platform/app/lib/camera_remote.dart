import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'domain.dart';

class CameraRemotePage extends StatefulWidget {
  const CameraRemotePage({super.key, required this.state});
  final AppState state;
  @override
  State<CameraRemotePage> createState() => _CameraRemotePageState();
}

class _CameraRemotePageState extends State<CameraRemotePage>
    with WidgetsBindingObserver {
  Json data = {}, frame = {};
  String? error;
  bool busy = false, leaving = false, foreground = true;
  Timer? timer;
  int ticks = 0;
  HueviaCore get core => widget.state.core;
  Json get scope => {'session': data['session'], 'remoteId': data['remoteId']};
  Json get action => data['action'] is Map ? object(data['action']) : {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(open());
  }

  Future<void> open() async {
    await run(() async {
      final status = await core.call('camera.status');
      if (!mounted || leaving) return;
      if (status['connected'] != true) {
        throw const AppFailure('请先连接尼康相机，再打开遥控拍摄。');
      }
      final opened = await core.call('camera.remote.open', {
        'session': status['session'],
      });
      if (!mounted || leaving) {
        await core.call('camera.remote.close', {
          'session': opened['session'],
          'remoteId': opened['remoteId'],
        });
        return;
      }
      data = opened;
      if (data['liveView'] == true) {
        final viewed = await core.call('camera.remote.view', {
          ...scope,
          'enabled': true,
        });
        if (!mounted || leaving) return;
        data = viewed;
      }
    });
    if (mounted && !leaving) {
      timer = Timer.periodic(const Duration(milliseconds: 350), (_) => poll());
    }
  }

  Future<void> run(Future<void> Function() operation) async {
    if (busy || leaving) return;
    if (widget.state.cameraDownloadsActive ||
        widget.state.cameraManualTransferActive) {
      setState(() => error = '请先停止相机接收队列，再使用遥控拍摄。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
    } catch (failure) {
      if (mounted) error = '$failure';
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (!foreground && data['viewing'] == true) {
          pauseForLifecycle();
        }
      }
    }
  }

  Future<void> request(String operation, [Json payload = const {}]) =>
      run(() async {
        data = await core.call(operation, {...scope, ...payload});
      });

  Future<void> poll() async {
    if (!mounted ||
        !foreground ||
        busy ||
        leaving ||
        data['viewing'] != true ||
        error != null) {
      return;
    }
    await run(() async {
      if (++ticks % 8 == 0) {
        data = await core.call('camera.remote.status', scope);
      }
      final next = await core.call('camera.remote.frame', scope);
      if (next['ready'] == true) {
        await FileImage(File(next['path'] as String)).evict();
        frame = next;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) return;
    foreground = state == AppLifecycleState.resumed;
    if (state != AppLifecycleState.resumed && data['viewing'] == true) {
      if (!busy) pauseForLifecycle();
    }
  }

  void pauseForLifecycle() {
    data = {...data, 'viewing': false};
    unawaited(request('camera.remote.view', {'enabled': false}));
  }

  Future<void> finish() async {
    if (busy || leaving) return;
    leaving = true;
    timer?.cancel();
    try {
      if (data['remoteId'] != null) {
        await core.call('camera.remote.close', scope);
      }
    } catch (failure) {
      error = '$failure';
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> acknowledge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('已在相机核对拍摄结果？'),
        content: const Text('请先查看相机中的最近照片。确认后可再次按快门；应用不会自动重拍上次操作。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回核对'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('已核对'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await request('camera.remote.acknowledge', {
        'confirmedOnCamera': true,
        'actionId': action['actionId'],
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (!leaving && data['remoteId'] != null) {
      unawaited(
        core
            .call('camera.remote.close', scope)
            .catchError((_) => <String, dynamic>{}),
      );
    }
    super.dispose();
  }

  String parameter(Json row) {
    final value = (row['value'] as num).toInt();
    return switch (row['code']) {
      0x5001 => '电量 $value%',
      0x5007 => '光圈 F${(value / 100).toStringAsFixed(1)}',
      0x500d =>
        value >= 0xfffffffe
            ? '快门 Bulb / Time'
            : value < 10000 && value > 0
            ? '快门 1/${(10000 / value).round()}'
            : '快门 ${value / 10000}s',
      0x500f => 'ISO $value',
      0x5010 => '曝光 ${(value / 1000).toStringAsFixed(1)} EV',
      0x500e =>
        '曝光模式 ${const {1: 'M', 2: 'P', 3: 'A', 4: 'S'}[value] ?? value}',
      0x5013 => value == 1 ? '释放模式 单张' : '释放模式 请在相机切为单张',
      _ => '0x${(row['code'] as int).toRadixString(16).toUpperCase()}：$value',
    };
  }

  @override
  Widget build(BuildContext context) {
    final pending = action['pending'] == true;
    final rows = (data['parameters'] as List? ?? []).map(object).toList();
    final shotRows = (action['photos'] as List? ?? []).map(object);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(finish());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('遥控拍摄'),
          leading: IconButton(
            onPressed: busy ? null : finish,
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回相机照片',
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                data['model'] as String? ?? '正在读取相机能力',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ),
              if (data.isNotEmpty || busy)
                AspectRatio(
                  aspectRatio: frame['width'] is int && frame['height'] is int
                      ? (frame['rotation'] == 90 || frame['rotation'] == -90
                            ? (frame['height'] as int) / (frame['width'] as int)
                            : (frame['width'] as int) /
                                  (frame['height'] as int))
                      : 3 / 2,
                  child: ColoredBox(
                    color: Colors.black,
                    child: frame['path'] is String
                        ? LayoutBuilder(
                            builder: (context, box) => GestureDetector(
                              onTapDown:
                                  !busy &&
                                      frame['pointFocus'] == true &&
                                      data['viewing'] == true
                                  ? (tap) {
                                      unawaited(
                                        request('camera.remote.focus', {
                                          'x':
                                              tap.localPosition.dx /
                                              box.maxWidth,
                                          'y':
                                              tap.localPosition.dy /
                                              box.maxHeight,
                                        }),
                                      );
                                    }
                                  : null,
                              child: Center(
                                child: RotatedBox(
                                  quarterTurns:
                                      (frame['rotation'] as int? ?? 0) ~/ 90,
                                  child: Image.file(
                                    File(frame['path'] as String),
                                    key: ValueKey(frame['sequence']),
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                    cacheWidth: 1280,
                                    errorBuilder: (_, _, _) => const Text(
                                      '取景帧无法显示',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const Center(
                            child: Text(
                              '等待相机实时画面',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy || data['liveView'] != true
                        ? null
                        : () => request('camera.remote.view', {
                            'enabled': data['viewing'] != true,
                          }),
                    icon: Icon(
                      data['viewing'] == true ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(data['viewing'] == true ? '暂停取景' : '开始取景'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy || data['autoFocus'] != true
                        ? null
                        : () => request('camera.remote.focus'),
                    icon: const Icon(Icons.center_focus_strong),
                    label: const Text('自动对焦'),
                  ),
                ],
              ),
              if (frame['focusKnown'] == true)
                Text(frame['focused'] == true ? '相机报告已合焦' : '相机报告未合焦'),
              const SizedBox(height: 16),
              if (busy) const LinearProgressIndicator(),
              if (pending) ...[
                const Text(
                  '拍摄结果待核对',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const Text('相机可能已拍摄。先读取最近照片；应用不会自动重复快门。'),
                TextButton(
                  onPressed: busy ? null : () => request('camera.remote.check'),
                  child: const Text('读取拍摄结果'),
                ),
                TextButton(
                  onPressed: busy ? null : acknowledge,
                  child: const Text('我已在相机手动核对'),
                ),
              ] else if (action['phase'] == 'verified')
                const Text('已从相机库存确认新照片。返回相机照片可接收原文件。'),
              for (final photo in shotRows)
                Text(photo['name'] as String? ?? ''),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: busy || pending || data['capture'] != true
                    ? null
                    : () => request('camera.remote.capture'),
                icon: const Icon(Icons.camera),
                label: const Text('拍摄一张并保存到相机'),
              ),
              const SizedBox(height: 20),
              Text('机身当前参数', style: Theme.of(context).textTheme.titleMedium),
              const Text('以下参数读取自相机，请在机身调整。'),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text(parameter(row)),
                ),
              if (data.isEmpty && !busy)
                TextButton(onPressed: open, child: const Text('重新连接遥控')),
            ],
          ),
        ),
      ),
    );
  }
}
