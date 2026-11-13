import 'dart:async';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'widgets.dart';
import 'legacy_dialog.dart';
import 'theme.dart';
import 'help.dart';
import 'camera_previews.dart';
import 'camera_transfer.dart';
import 'wired_camera.dart';
import 'camera_grid.dart';
import 'camera_live.dart';
import 'photo_grid.dart';
import 'project_presets.dart';
import 'camera_remote.dart';
import 'camera_slots.dart';
import 'camera_downloads.dart';
import 'camera_connection.dart';

import 'package:go_router/go_router.dart';

Future<bool> connectCamera(BuildContext context, AppState state) async =>
    await hueRootPage<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => CameraPage(state: state, configuration: true),
      ),
    ) ==
    true;

class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    required this.state,
    this.configuration = false,
  });
  final AppState state;
  final bool configuration;
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final host = TextEditingController(text: '192.168.1.1'),
      port = TextEditingController(text: '15740');
  String protocol = 'nikon', session = '', model = '', job = '';
  String connectionMode = 'none';
  bool inventoryReady = false;
  bool busy = false, connected = false, hasMore = false;
  bool get raw => widget.state.cameraRaw;
  set raw(bool value) => widget.state.cameraRaw = value;
  late final CameraPreviews previews;
  late final CameraTransfer transfer;
  late final CameraConnectionRequest connectionRequest;
  final listScroll = ScrollController();
  int offset = 0, epoch = 0;
  String? error;
  String? warning;
  List<Json> items = [];
  int overviewTab = 0;
  bool settingsExpanded = false;
  CameraLivePhase? lastLivePhase;
  bool selecting = false;
  bool childOpen = false;
  final Set<int> selection = {};
  bool get exclusive =>
      widget.state.cameraLiveActive || widget.state.cameraDownloadsActive;
  bool get browsingPhotos =>
      !widget.configuration &&
      !childOpen &&
      widget.state.cameraVisible.value &&
      overviewTab == 0;
  bool get photosReady => connected && connectionMode == 'photos';

  void acceptCameraStatus(Json value) {
    connected = value['connected'] == true;
    session = value['session'] as String? ?? '';
    model = value['model'] as String? ?? '';
    connectionMode =
        value['mode'] as String? ?? (connected ? 'photos' : 'none');
    inventoryReady = value['inventoryReady'] == true;
  }

  Future<void> openCameraTool(Widget page) async {
    if (childOpen || busy || transfer.busy || exclusive) return;
    childOpen = true;
    previews.pause();
    try {
      await hueRootPage<void>(context, MaterialPageRoute(builder: (_) => page));
    } finally {
      childOpen = false;
      if (mounted) {
        if (!exclusive && browsingPhotos && photosReady) previews.resume();
        await status();
      }
    }
  }

  Future<List<Json>> morePhotos() async {
    if (!busy && !exclusive && hasMore) await page(next: true);
    return List<Json>.of(items);
  }

  void toggleSelection(Json item) {
    final handle = item['handle'];
    if (busy || exclusive || handle is! int) return;
    setState(() {
      if (!selection.remove(handle)) {
        if (selection.length < 100) selection.add(handle);
      }
    });
  }

  Future<void> receiveSelection() async {
    if (busy || transfer.busy || exclusive || selection.isEmpty) return;
    final expectedSession = session;
    final selected = items
        .where((item) => selection.contains(item['handle']))
        .map((item) => Map<String, dynamic>.of(item))
        .toList();
    try {
      final target = await chooseDownloadTarget(context, widget.state);
      if (!mounted || target == null) return;
      final status = await widget.state.core.call('camera.status');
      if (!mounted ||
          expectedSession != session ||
          status['session'] != expectedSession ||
          exclusive) {
        throw const AppFailure('相机会话已改变，请重新选择照片。');
      }
      await widget.state.cameraDownloads.create(status, selected, target);
      if (!mounted) return;
      setState(() {
        selecting = false;
        selection.clear();
      });
      unawaited(
        widget.state.cameraDownloads.resume(
          widget.state.cameraDownloads.current!['id'] as String,
        ),
      );
      await hueRootPage<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CameraDownloadsPage(state: widget.state),
        ),
      );
    } catch (failure) {
      if (mounted) report(context, failure);
    }
  }

  void downloadsChanged() {
    if (!mounted) return;
    if (exclusive) {
      previews.pause();
    } else if (browsingPhotos && photosReady) {
      previews.resume();
    }
    setState(() {});
  }

  Future<void> openConnection() async {
    if (childOpen || busy || transfer.busy || exclusive) return;
    childOpen = true;
    previews.pause();
    try {
      final connected = await connectCamera(context, widget.state);
      if (mounted && connected) {
        childOpen = false;
        await status();
      }
    } finally {
      childOpen = false;
      if (mounted && !exclusive && browsingPhotos && photosReady) {
        previews.resume();
      }
    }
  }

  Future<void> chooseProtocol() async {
    final selected = await hueChoice<String>(
      context: context,
      title: '选择相机类型',
      selected: protocol,
      choices: const [('nikon', '尼康'), ('fujifilm', '富士 X-T20')],
    );
    if (!mounted || selected == null || selected == protocol) return;
    setState(() {
      protocol = selected;
      host.text = protocol == 'nikon' ? '192.168.1.1' : '';
      port.text = protocol == 'nikon' ? '15740' : '55740';
      error = null;
    });
  }

  @override
  void initState() {
    super.initState();
    previews = CameraPreviews(widget.state.core);
    transfer = CameraTransfer(widget.state);
    connectionRequest = CameraConnectionRequest(widget.state.core)
      ..addListener(connectionProgressChanged);
    widget.state.cameraLive.addListener(liveChanged);
    widget.state.cameraDownloads.addListener(downloadsChanged);
    if (!widget.configuration) {
      widget.state.cameraVisible.addListener(visibilityChanged);
    }
    unawaited(status());
  }

  @override
  void dispose() {
    epoch++;
    connectionRequest.removeListener(connectionProgressChanged);
    connectionRequest.dispose();
    widget.state.cameraLive.removeListener(liveChanged);
    widget.state.cameraDownloads.removeListener(downloadsChanged);
    if (!widget.configuration) {
      widget.state.cameraVisible.removeListener(visibilityChanged);
    }
    previews.dispose();
    transfer.dispose();
    listScroll.dispose();
    host.dispose();
    port.dispose();
    // CameraConnectionRequest owns cancellation of its pending job. A second
    // cancel here could reach a transport already handed to the next page.
    super.dispose();
  }

  void connectionProgressChanged() {
    if (mounted) setState(() {});
  }

  void cancelCameraRequest() {
    if (!connectionRequest.busy) return;
    epoch++;
    connectionRequest.cancel();
    setState(() {
      busy = connected = false;
      session = job = '';
      items = [];
      error = '已取消连接与照片读取。';
    });
    previews.reset('');
  }

  void liveChanged() {
    if (!mounted) return;
    final phase = widget.state.cameraLive.phase;
    if (phase != lastLivePhase &&
        (phase == CameraLivePhase.waiting ||
            phase == CameraLivePhase.blocked) &&
        !busy) {
      unawaited(status(reload: false));
    }
    lastLivePhase = phase;
    if (exclusive) {
      previews.pause();
    } else if (browsingPhotos && photosReady) {
      previews.resume();
    }
    setState(() {});
  }

  void visibilityChanged() {
    if (!widget.state.cameraVisible.value) {
      previews.pause();
      return;
    }
    if (transfer.busy || exclusive) return;
    if (browsingPhotos && photosReady) previews.resume();
    if (!busy) unawaited(status(reload: false));
  }

  Future<void> status({bool reload = true, bool inspectOnly = false}) async {
    final request = ++epoch;
    try {
      final result = await widget.state.core.call('camera.status');
      if (!mounted || request != epoch) return;
      final changed = session != result['session'];
      setState(() {
        acceptCameraStatus(result);
      });
      previews.setSession(session);
      if (browsingPhotos && photosReady && !exclusive) {
        previews.resume();
      } else {
        previews.pause();
      }
      if (changed) {
        selection.clear();
        selecting = false;
      }
      if (widget.configuration && connected && session.isNotEmpty) {
        finishConnection();
        return;
      }
      if (!inspectOnly &&
          browsingPhotos &&
          photosReady &&
          !exclusive &&
          (reload || changed || items.isEmpty)) {
        await page();
      }
    } catch (failure) {
      if (mounted && request == epoch) setState(() => error = '$failure');
    }
  }

  Future<void> connectWired(String id) => connect(usbId: id);

  Future<void> connect({String? usbId}) async {
    if (exclusive || transfer.busy || busy) return;
    final request = ++epoch;
    setState(() {
      busy = true;
      error = null;
      job = 'camera-connect-${DateTime.now().microsecondsSinceEpoch}';
    });
    try {
      final result = await connectionRequest.run(
        'camera.connect',
        {
          'host': host.text.trim(),
          'port': int.tryParse(port.text) ?? 0,
          'protocol': usbId == null ? protocol : 'nikon',
          if (usbId != null) 'transport': 'usb',
          'deviceId': ?usbId,
        },
        job,
        timeout: const Duration(seconds: 125),
      );
      if (!mounted || request != epoch) return;
      if (result['connected'] != true ||
          result['session'] is! String ||
          (result['session'] as String).isEmpty) {
        throw const AppFailure('相机尚未建立连接，请确认后重试。');
      }
      setState(() {
        acceptCameraStatus(result);
        busy = false;
        job = '';
      });
      previews.setSession(session);
      if (widget.configuration) {
        finishConnection();
      } else if (browsingPhotos) {
        await page(refresh: false);
      }
    } catch (failure) {
      if (mounted && request == epoch) setState(() => error = '$failure');
    } finally {
      if (mounted && request == epoch) {
        setState(() {
          busy = false;
          job = '';
        });
      }
    }
  }

  void finishConnection() {
    // The completed connection belongs to the caller. Disposing this page must
    // never cancel its completed job after a slot/remote request takes over.
    busy = false;
    job = '';
    if (ModalRoute.of(context)?.isCurrent == true &&
        Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  void selectOverview(int value) {
    setState(() => overviewTab = value);
    if (browsingPhotos) {
      if (photosReady) previews.resume();
      if (!busy && !exclusive) unawaited(status(reload: false));
    } else {
      previews.pause();
    }
  }

  Future<void> page({bool next = false, bool refresh = true}) async {
    if (!browsingPhotos || !photosReady || exclusive || transfer.busy || busy) {
      return;
    }
    final request = ++epoch, expectedSession = session;
    final identity = 'camera-page-${DateTime.now().microsecondsSinceEpoch}';
    var failed = false;
    if (!next) previews.reset(session);
    setState(() {
      busy = true;
      error = null;
      warning = null;
      job = identity;
      if (!next) {
        items = [];
        offset = 0;
        hasMore = false;
        selection.clear();
      }
    });
    try {
      final result = await connectionRequest.run(
        'camera.page',
        {
          'session': session,
          'offset': next ? offset : 0,
          'limit': 24,
          'raw': raw,
          'refresh': !next && refresh,
        },
        identity,
        timeout: const Duration(seconds: 75),
      );
      if (!mounted || request != epoch || session != expectedSession) return;
      final rows = (result['items'] as List).map(object).toList();
      setState(() {
        items = next ? [...items, ...rows] : rows;
        inventoryReady = true;
        offset = result['nextOffset'] as int;
        hasMore = result['hasMore'] == true;
        warning = (result['unavailableStorages'] as num? ?? 0) > 0
            ? '部分存储卡暂不可读，请保持相机待机后刷新照片。'
            : null;
      });
    } catch (failure) {
      failed = true;
      if (mounted && request == epoch) setState(() => error = '$failure');
    } finally {
      if (mounted && request == epoch) {
        setState(() {
          busy = false;
          job = '';
        });
      }
    }
    if (failed && mounted && request == epoch) {
      unawaited(status(reload: false, inspectOnly: true));
    }
  }

  Future<void> download(Json item) async {
    if (busy || transfer.busy || exclusive) return;
    final request = ++epoch;
    previews.pause();
    setState(() {
      busy = true;
      error = null;
      job = '';
    });
    if (listScroll.hasClients) {
      unawaited(
        listScroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
    try {
      await transfer.start(session, item, raw: raw);
      if (!mounted || request != epoch) return;
      final result = await widget.state.core.call('camera.status');
      if (!mounted || request != epoch) return;
      setState(() {
        acceptCameraStatus(result);
        if (!connected) {
          items = [];
          offset = 0;
          hasMore = false;
        }
      });
      if (!connected) {
        previews.reset('');
      }
    } catch (failure) {
      if (mounted && request == epoch) setState(() => error = '$failure');
    } finally {
      previews.resume();
      if (mounted && request == epoch) {
        setState(() {
          busy = false;
          job = '';
        });
      }
    }
  }

  Future<void> disconnect() async {
    if (!mounted || busy || childOpen || session.isEmpty) return;
    final request = ++epoch, expectedSession = session;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.state.cameraDownloadsActive) {
        await widget.state.cameraDownloads.stop();
      }
      if (!mounted || request != epoch) return;
      if (widget.state.cameraLiveActive) {
        await widget.state.cameraLive.stop();
      }
      if (!mounted || request != epoch) return;
      final result = await widget.state.core.call('camera.disconnect', {
        'session': expectedSession,
      });
      if (mounted && request == epoch) {
        setState(() {
          acceptCameraStatus(result);
          if (session != expectedSession || !photosReady) {
            items = [];
            offset = 0;
            hasMore = false;
            selecting = false;
            selection.clear();
          }
        });
        previews.setSession(session);
        if (!photosReady) previews.pause();
      }
    } catch (failure) {
      if (mounted && request == epoch) report(context, failure);
    } finally {
      if (mounted && request == epoch) {
        setState(() {
          busy = false;
          job = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.configuration ? connectionView(context) : overview(context);

  Widget connectionStatus() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Text(
              '${connectionRequest.phase} · 已等待 ${connectionRequest.elapsedSeconds} 秒',
            ),
          ),
        ),
        TextButton(
          onPressed: cancelCameraRequest,
          child: Text(
            connectionRequest.operation == 'camera.connect' ? '取消连接' : '取消读取',
          ),
        ),
      ],
    ),
  );

  Widget connectionView(BuildContext context) => Scaffold(
    appBar: HueHeader(
      title: '连接相机',
      back: true,
      actions: [
        if (connected)
          IconButton(
            onPressed: busy ? null : disconnect,
            tooltip: '断开相机',
            icon: const Icon(Icons.link_off_rounded),
          ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Column(
        children: [
          if (busy && !transfer.busy)
            const LinearProgressIndicator(minHeight: 2),
          if (connectionRequest.busy) connectionStatus(),
          Expanded(
            child: ListView(
              controller: listScroll,
              padding: const EdgeInsets.fromLTRB(24, 2, 24, 28),
              children: [
                CameraTransferCard(transfer: transfer),
                if (!connected) ...[
                  WiredCameraPicker(
                    core: widget.state.core,
                    enabled: !busy,
                    onConnect: (id) => connectWired(id),
                  ),
                  const Divider(height: 32),
                  Text(
                    'Wi-Fi 无线连接',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    protocol == 'nikon' ? '连接后可浏览照片与导入预设。' : '连接后可浏览和下载 JPEG。',
                    style: TextStyle(
                      fontSize: 13,
                      color: HuePalette.of(context).secondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '相机类型',
                    style: TextStyle(
                      fontSize: 12,
                      color: HuePalette.of(context).secondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Semantics(
                    button: true,
                    label: '相机类型：${protocol == 'nikon' ? '尼康' : '富士 X-T20'}',
                    child: Material(
                      color: HuePalette.of(context).card,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: busy ? null : chooseProtocol,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 64),
                            child: Row(
                              children: [
                                HueIcon(
                                  HueIconKind.camera,
                                  size: 24,
                                  color: HuePalette.of(context).ink,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    protocol == 'nikon' ? '尼康' : '富士 X-T20',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                HueIcon(
                                  HueIconKind.chevron,
                                  size: 18,
                                  color: HuePalette.of(context).secondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: HuePalette.of(context).primaryContainer,
                      foregroundColor: HuePalette.of(context)
                          .onPrimaryContainer,
                      minimumSize: const Size(48, 50),
                    ),
                    onPressed: busy ? null : connect,
                    child: Text(busy ? '正在连接' : '连接相机'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(
                            () => settingsExpanded = !settingsExpanded,
                          ),
                    style: TextButton.styleFrom(
                      foregroundColor: HuePalette.of(context).ink,
                    ),
                    child: Text(settingsExpanded ? '收起连接设置' : '连接设置'),
                  ),
                  if (Theme.of(context).platform == TargetPlatform.iOS) ...[
                    Text(
                      '首次连接请允许“本地网络”访问；如果曾拒绝授权，请在设置中开启后重试。',
                      style: TextStyle(
                        fontSize: 12,
                        color: HuePalette.of(context).secondary,
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              try {
                                await widget.state.core.openCameraSettings();
                              } catch (failure) {
                                if (context.mounted) report(context, failure);
                              }
                            },
                      child: const Text('打开本地网络权限设置'),
                    ),
                  ],
                  if (settingsExpanded) ...[
                    const SizedBox(height: 20),
                    Text(
                      '相机地址',
                      style: TextStyle(
                        fontSize: 12,
                        color: HuePalette.of(context).secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      decoration: BoxDecoration(
                        color: HuePalette.of(context).card,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: host,
                            keyboardType: TextInputType.url,
                            decoration: const InputDecoration(
                              labelText: 'IP 地址',
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: port,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '端口'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      protocol == 'nikon'
                          ? '请先在系统设置中连接相机 Wi-Fi，并保持相机 Wi-Fi 开启。'
                          : '请先连接 X-T20 的 Wi-Fi，在机身按 OK 确认；当前支持 JPEG 浏览和下载。',
                      style: TextStyle(
                        fontSize: 12,
                        color: HuePalette.of(context).secondary,
                      ),
                    ),
                  ],
                ] else ...[
                  Text(model, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('已连接。请返回继续操作；浏览照片请进入同步 → 相机照片。'),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (error != null && !busy)
                  TextButton(
                    onPressed: () => hueRootPage<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DiagnosticsPage(state: widget.state),
                      ),
                    ),
                    child: const Text('导出诊断报告'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  String get emptyMessage => hasMore
      ? '尚未找到${raw ? ' RAW / NEF ' : ' JPEG '}照片，请继续读取相机目录。'
      : raw
      ? '未找到 RAW / NEF 照片，可切换到 JPEG 查看。'
      : '未找到 JPEG 照片，可切换到 RAW / NEF 查看。';

  Widget photoTools() => Wrap(
    spacing: 12,
    runSpacing: 4,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      ChoiceChip(
        label: const Text('JPEG'),
        selected: !raw,
        onSelected: busy || exclusive
            ? null
            : (_) {
                setState(() => raw = false);
                unawaited(page());
              },
      ),
      ChoiceChip(
        label: const Text('RAW / NEF'),
        selected: raw,
        onSelected: busy || exclusive
            ? null
            : (_) {
                setState(() => raw = true);
                unawaited(page());
              },
      ),
      IconButton(
        tooltip: '刷新照片',
        onPressed: busy || exclusive ? null : () => page(),
        icon: const Icon(Icons.refresh_rounded),
      ),
      TextButton(
        onPressed: busy || transfer.busy || exclusive
            ? null
            : () => setState(() {
                selecting = !selecting;
                selection.clear();
              }),
        child: Text(selecting ? '取消多选' : '多选下载'),
      ),
      if (selecting) ...[
        TextButton(
          onPressed: busy || exclusive
              ? null
              : () => setState(() {
                  selection.clear();
                  selection.addAll(
                    items.take(100).map((row) => row['handle'] as int),
                  );
                }),
          child: const Text('选择已读取照片'),
        ),
        FilledButton(
          onPressed: selection.isEmpty || busy || exclusive
              ? null
              : receiveSelection,
          child: Text('接收 ${selection.length} 张'),
        ),
      ],
      TextButton.icon(
        onPressed: () => hueRootPage<void>(
          context,
          MaterialPageRoute(
            builder: (_) => CameraDownloadsPage(state: widget.state),
          ),
        ),
        icon: const Icon(Icons.download_outlined),
        label: Text(widget.state.cameraDownloadsActive ? '查看下载进度' : '下载队列'),
      ),
      TextButton.icon(
        onPressed: busy || transfer.busy || exclusive
            ? null
            : () => openCameraTool(CameraSlotsPage(state: widget.state)),
        icon: const Icon(Icons.tune),
        label: const Text('相机预设槽位'),
      ),
    ],
  );

  Widget cameraGrid() => CameraPhotoGrid(
    items: items,
    previews: previews,
    transfer: transfer,
    onDownload: download,
    onMore: morePhotos,
    selection: selecting ? selection : null,
    onSelect: toggleSelection,
  );

  Widget downloadedPhotos() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: CameraTransferCard(transfer: transfer),
      ),
      Expanded(
        child: PhotoMasonry(
          rows: [
            for (final photo in widget.state.photos)
              {
                'id': photo.path,
                'name': photo.name,
                'raw': photo.info['raw'] == true,
                'date': photo.info['addedAt'] ?? 0,
              },
          ],
          phone: false,
          core: widget.state.core,
          onOpen: (row) async {
            await context.push<void>(
              '/photo/${Uri.encodeComponent(widget.state.photos.firstWhere((photo) => photo.path == row['id']).id)}',
            );
          },
          onLongPress: (row) async {
            await context.push<void>(
              '/photo/${Uri.encodeComponent(widget.state.photos.firstWhere((photo) => photo.path == row['id']).id)}',
            );
          },
        ),
      ),
    ],
  );

  Widget overview(BuildContext context) {
    final p = HuePalette.of(context);
    final compact = MediaQuery.sizeOf(context).height < 480;
    return Scaffold(
      appBar: HueHeader(
        title: '同步',
        compact: compact,
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: connected ? const Color(0xff42735b) : p.secondary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                connected ? '$model · 已连接' : '未连接',
                style: TextStyle(fontSize: 11, color: p.secondary),
              ),
            ],
          ),
          if (connected)
            IconButton(
              onPressed: busy ? null : disconnect,
              tooltip: '断开相机',
              icon: const Icon(Icons.link_off_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
            child: CapsuleSwitch(
              labels: const ['相机照片', '边拍边传', '已下载'],
              selected: overviewTab,
              onSelected: selectOverview,
            ),
          ),
          if (busy && !transfer.busy)
            const LinearProgressIndicator(minHeight: 2),
          if (connectionRequest.busy) connectionStatus(),
          if (overviewTab == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: InkWell(
                onTap: busy || exclusive
                    ? null
                    : () => connected
                          ? openCameraTool(
                              CameraRemotePage(state: widget.state),
                            )
                          : openConnection(),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 72),
                  padding: const EdgeInsets.fromLTRB(0, 10, 2, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: p.container,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const HueIcon(HueIconKind.camera),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '遥控拍摄',
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '实时取景与快门',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.2,
                                color: p.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      HueIcon(HueIconKind.chevron, color: p.primary),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: overviewTab == 1
                ? ProjectPresetsPage(
                    state: widget.state,
                    embedded: true,
                    onConnect: openConnection,
                  )
                : overviewTab == 2 && widget.state.photos.isNotEmpty
                ? downloadedPhotos()
                : connected && overviewTab == 0
                ? ListView(
                    controller: listScroll,
                    padding: EdgeInsets.fromLTRB(
                      20,
                      10,
                      20,
                      100 + hueNavigationInset(context),
                    ),
                    children: [
                      CameraTransferCard(transfer: transfer),
                      photoTools(),
                      const SizedBox(height: 12),
                      Text(
                        connectionMode == 'slots'
                            ? '相机预设槽位正在使用连接，照片尚未读取。'
                            : !inventoryReady
                            ? '照片目录尚未读取'
                            : '${raw ? 'RAW / NEF' : 'JPEG'} · 已读取 ${items.length} 张',
                        style: TextStyle(fontSize: 12, color: p.secondary),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: busy ? null : () => page(),
                          child: const Text('重试读取照片'),
                        ),
                      ],
                      if (warning != null) Text(warning!),
                      if (items.isEmpty &&
                          !busy &&
                          error == null &&
                          warning == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Text(emptyMessage),
                        ),
                      if (photosReady) cameraGrid(),
                      if (hasMore)
                        OutlinedButton(
                          onPressed: busy ? null : () => page(next: true),
                          child: const Text('读取更多照片'),
                        ),
                    ],
                  )
                : SingleChildScrollView(
                    controller: listScroll,
                    padding: const EdgeInsets.fromLTRB(28, 44, 28, 100),
                    child: Column(
                      children: [
                        CameraTransferCard(transfer: transfer),
                        if (!compact)
                          Container(
                            width: 84,
                            height: 84,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.card,
                              borderRadius: BorderRadius.circular(26),
                            ),
                            child: HueIcon(
                              overviewTab == 2
                                  ? HueIconKind.album
                                  : HueIconKind.camera,
                              size: 34,
                              color: p.secondary,
                            ),
                          ),
                        SizedBox(height: compact ? 0 : 16),
                        Text(
                          overviewTab == 2
                              ? '还没有已下载照片'
                              : overviewTab == 1
                              ? '边拍边传'
                              : '连接相机，开始浏览',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: compact ? 18 : 19,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: p.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          overviewTab == 2
                              ? '从相机下载的原图会保存在这里，\n断开连接也能继续查看。'
                              : overviewTab == 1
                              ? '连接相机后，接收拍摄的照片。'
                              : '连接相机 Wi-Fi 或使用 USB 数据线，\n照片会显示在这里。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.48,
                            color: p.secondary,
                          ),
                        ),
                        if (overviewTab != 2) ...[
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(48, 50),
                              ),
                              onPressed: openConnection,
                              child: const Text('连接相机'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
