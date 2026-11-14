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
import 'camera_connection_view.dart';
import 'camera_photo_sort.dart';
import 'camera_photo_toolbar.dart';
import 'legacy_glass_sheet.dart';
import 'sync_tools_dock.dart';

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

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  final host = TextEditingController(text: '192.168.1.1'),
      port = TextEditingController(text: '15740');
  String protocol = 'nikon', session = '', model = '', job = '';
  String connectionMode = 'none';
  bool inventoryReady = false;
  bool busy = false, connected = false, hasMore = false;
  bool loadingMore = false;
  String? paginationError;
  bool get raw => widget.state.cameraRaw;
  set raw(bool value) => widget.state.cameraRaw = value;
  late final CameraPreviews previews;
  late final CameraTransfer transfer;
  late final CameraConnectionRequest connectionRequest;
  StreamSubscription<dynamic>? maintenanceEvents;
  final listScroll = ScrollController();
  int offset = 0, epoch = 0;
  String? error;
  String? warning;
  List<Json> items = [];
  int overviewTab = 0;
  bool settingsExpanded = false, connectionUsb = false, usbBusy = false;
  bool deferPhotoRead = false;
  CameraPhotoSort photoSort = CameraPhotoSort.newest;
  List<Json>? sortedSource;
  CameraPhotoSort? sortedOrder;
  List<Json> sortedItems = [];
  int missingCaptureTimeCount = 0;

  List<Json> get displayedItems {
    if (!identical(sortedSource, items) || sortedOrder != photoSort) {
      sortedSource = items;
      sortedOrder = photoSort;
      sortedItems = sortedCameraPhotos(items, photoSort);
      missingCaptureTimeCount = items
          .where((row) => cameraCaptureTime(row['capturedAt']) == null)
          .length;
    }
    return sortedItems;
  }

  CameraLivePhase? lastLivePhase;
  bool selecting = false;
  bool childOpen = false;
  final Set<int> selection = {};
  bool get exclusive =>
      widget.state.cameraLiveActive || widget.state.cameraDownloadsActive;
  bool get browsingPhotos =>
      !widget.configuration &&
      inForeground &&
      !childOpen &&
      widget.state.cameraVisible.value &&
      overviewTab == 0;
  bool get photosReady => connected && connectionMode == 'photos';
  bool get inForeground {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null ||
        lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;
  }

  void acceptCameraStatus(Json value) {
    connected = value['connected'] == true;
    session = value['session'] as String? ?? '';
    model = value['model'] as String? ?? '';
    connectionMode =
        value['mode'] as String? ?? (connected ? 'photos' : 'none');
    inventoryReady = value['inventoryReady'] == true;
    final notice = value['connectionNotice'];
    if (!connected && notice is String && notice.isNotEmpty) error = notice;
  }

  Future<void> openCameraTool(
    Widget page, {
    bool allowExclusive = false,
    bool fullScreen = false,
    bool compact = false,
    Future<void> Function()? afterClose,
  }) async {
    if (childOpen || busy || transfer.busy || (!allowExclusive && exclusive)) {
      return;
    }
    setState(() => childOpen = true);
    previews.pause();
    try {
      if (fullScreen) {
        final route = MaterialPageRoute<void>(builder: (_) => page);
        final pushed = hueRootPage<void>(context, route);
        try {
          await pushed;
        } finally {
          await route.completed;
        }
      } else {
        await showLegacyGlassSheet<void>(
          context,
          isScrollControlled: !allowExclusive,
          enableDrag: allowExclusive,
          isDismissible: allowExclusive,
          builder: (_) => compact
              ? page
              : SizedBox(
                  height: MediaQuery.sizeOf(context).height * .88,
                  child: page,
                ),
        );
      }
    } finally {
      if (afterClose != null) {
        try {
          await afterClose();
        } catch (_) {
          /* Closing does not reconnect. */
        }
      }
      childOpen = false;
      if (mounted) {
        setState(() {});
        if (!exclusive && browsingPhotos && photosReady) previews.resume();
        await status(reload: false);
      }
    }
  }

  Future<void> openConnectedTool({required bool slots}) async {
    if (childOpen || busy || transfer.busy || exclusive) return;
    if (!connected) await openConnection(loadPhotos: false);
    if (!mounted || !connected || !widget.state.cameraVisible.value) return;
    Future<void>? remoteClosing;
    await openCameraTool(
      slots
          ? CameraSlotsPage(state: widget.state, embedded: true)
          : CameraRemotePage(
              state: widget.state,
              onClosing: (value) => remoteClosing = value,
            ),
      fullScreen: !slots,
      afterClose: slots
          ? null
          : () async {
              await remoteClosing;
            },
    );
  }

  Future<void> openDownloads() => openCameraTool(
    CameraDownloadsPage(state: widget.state, embedded: true, compact: true),
    allowExclusive: true,
    compact: true,
  );

  void loadNearEnd() {
    if (!mounted ||
        !listScroll.hasClients ||
        listScroll.position.extentAfter > 420 ||
        !browsingPhotos ||
        !photosReady ||
        !hasMore ||
        busy ||
        exclusive ||
        transfer.busy ||
        paginationError != null ||
        error != null) {
      return;
    }
    unawaited(page(next: true));
  }

  Future<List<Json>> morePhotos() async {
    if (!busy && !exclusive && hasMore) await page(next: true);
    return List<Json>.of(displayedItems);
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
    final selected = displayedItems
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
      await openDownloads();
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

  Future<void> openConnection({bool loadPhotos = false}) async {
    if (childOpen || busy || transfer.busy || exclusive) return;
    childOpen = true;
    previews.pause();
    try {
      final connected = await connectCamera(context, widget.state);
      if (mounted && connected) {
        childOpen = !loadPhotos;
        deferPhotoRead = !loadPhotos;
        await status(reload: loadPhotos, inspectOnly: !loadPhotos);
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
    WidgetsBinding.instance.addObserver(this);
    previews = CameraPreviews(widget.state.core);
    transfer = CameraTransfer(widget.state);
    connectionRequest = CameraConnectionRequest(widget.state.core)
      ..addListener(connectionProgressChanged);
    listScroll.addListener(loadNearEnd);
    widget.state.cameraLive.addListener(liveChanged);
    widget.state.cameraDownloads.addListener(downloadsChanged);
    if (!widget.configuration) {
      widget.state.cameraVisible.addListener(visibilityChanged);
      maintenanceEvents = widget.state.core.operationProgress.listen((event) {
        if (!mounted ||
            event is! Map ||
            event['kind'] != 'cameraConnectionChanged' ||
            !inForeground ||
            !widget.state.cameraVisible.value ||
            busy ||
            childOpen ||
            transfer.busy ||
            exclusive) {
          return;
        }
        unawaited(status(reload: false, inspectOnly: true));
      }, onError: (_) {});
    }
    unawaited(status());
  }

  @override
  void dispose() {
    epoch++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(maintenanceEvents?.cancel());
    connectionRequest.removeListener(connectionProgressChanged);
    connectionRequest.dispose();
    widget.state.cameraLive.removeListener(liveChanged);
    widget.state.cameraDownloads.removeListener(downloadsChanged);
    if (!widget.configuration) {
      widget.state.cameraVisible.removeListener(visibilityChanged);
    }
    previews.dispose();
    transfer.dispose();
    listScroll.removeListener(loadNearEnd);
    listScroll.dispose();
    host.dispose();
    port.dispose();
    // CameraConnectionRequest owns cancellation of its pending job. A second
    // cancel here could reach a transport already handed to the next page.
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.inactive) return;
    if (lifecycle != AppLifecycleState.resumed) {
      previews.pause();
    } else if (!widget.configuration &&
        widget.state.cameraVisible.value &&
        !busy &&
        !childOpen &&
        !transfer.busy &&
        !exclusive) {
      unawaited(status(reload: false));
    }
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
      if (mounted) setState(() {});
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
      final wasConnected = connected;
      setState(() {
        acceptCameraStatus(result);
        if (changed) {
          items = [];
          offset = 0;
          hasMore = false;
          paginationError = null;
          warning = null;
        }
        if (wasConnected &&
            !connected &&
            (result['connectionNotice'] is! String ||
                (result['connectionNotice'] as String).isEmpty)) {
          error = '相机连接已断开，请重新连接后继续。';
        }
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
          !deferPhotoRead &&
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
      paginationError = null;
      loadingMore = false;
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
    deferPhotoRead = false;
    final request = ++epoch, expectedSession = session;
    final identity = 'camera-page-${DateTime.now().microsecondsSinceEpoch}';
    var failed = false;
    if (!next) previews.reset(session);
    setState(() {
      busy = true;
      error = null;
      paginationError = null;
      loadingMore = next;
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
      final nextOffset = result['nextOffset'] as int;
      if (next && result['hasMore'] == true && nextOffset <= offset) {
        throw const AppFailure('相机目录暂未继续返回，请稍后重试。');
      }
      setState(() {
        final unique = <int, Json>{
          if (next)
            for (final row in items) row['handle'] as int: row,
          for (final row in rows) row['handle'] as int: row,
        };
        items = unique.values.toList();
        inventoryReady = true;
        offset = nextOffset;
        hasMore = result['hasMore'] == true;
        warning = (result['unavailableStorages'] as num? ?? 0) > 0
            ? '部分存储卡暂不可读，请保持相机待机后刷新照片。'
            : null;
      });
    } catch (failure) {
      failed = true;
      if (mounted && request == epoch) {
        setState(() {
          if (next) {
            paginationError = '$failure';
          } else {
            error = '$failure';
          }
        });
      }
    } finally {
      if (mounted && request == epoch) {
        setState(() {
          busy = false;
          loadingMore = false;
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

  Widget connectionView(BuildContext context) => CameraConnectionView(
    usb: connectionUsb,
    busy: busy,
    usbBusy: usbBusy,
    connected: connected && session.isNotEmpty,
    model: model,
    protocol: protocol,
    request: connectionRequest,
    error: error,
    settingsExpanded: settingsExpanded,
    host: host,
    port: port,
    transferCard: CameraTransferCard(transfer: transfer),
    usbPicker: WiredCameraPicker(
      core: widget.state.core,
      enabled: !busy,
      compact: true,
      onBusyChanged: (value) {
        if (mounted) setState(() => usbBusy = value);
      },
      onConnect: connectWired,
    ),
    onTransportChanged: (value) => setState(() {
      connectionUsb = value;
      error = null;
    }),
    onProtocol: chooseProtocol,
    onConnect: connect,
    onCancel: cancelCameraRequest,
    onSettings: () => setState(() => settingsExpanded = !settingsExpanded),
    onPermissionSettings: () async {
      try {
        await widget.state.core.openCameraSettings();
      } catch (failure) {
        if (context.mounted) report(context, failure);
      }
    },
    onReturn: finishConnection,
    onDisconnect: disconnect,
    onDiagnostics: () => hueRootPage<void>(
      context,
      MaterialPageRoute(builder: (_) => DiagnosticsPage(state: widget.state)),
    ),
  );

  String get emptyMessage => hasMore
      ? '尚未找到${raw ? ' RAW / NEF ' : ' JPEG '}照片，向上滑动继续加载。'
      : raw
      ? '未找到 RAW / NEF 照片，可切换到 JPEG 查看。'
      : '未找到 JPEG 照片，可切换到 RAW / NEF 查看。';

  Widget photoTools() {
    final visible = displayedItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CameraPhotoToolbar(
          count: visible.length,
          missingTimeCount: missingCaptureTimeCount,
          hasMore: hasMore,
          inventoryReady: inventoryReady,
          raw: raw,
          selecting: selecting,
          order: photoSort,
          onRawChanged: busy || exclusive || transfer.busy
              ? null
              : (value) {
                  setState(() => raw = value);
                  unawaited(page());
                },
          onOrderChanged: busy || exclusive
              ? null
              : (value) => setState(() => photoSort = value),
          onSelection: busy || exclusive || transfer.busy
              ? null
              : () => setState(() {
                  selecting = !selecting;
                  selection.clear();
                }),
        ),
        if (selecting)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: busy || exclusive
                    ? null
                    : () => setState(() {
                        selection.clear();
                        selection.addAll(
                          displayedItems
                              .take(100)
                              .map((row) => row['handle'] as int),
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
          ),
      ],
    );
  }

  Widget cameraGrid() => CameraPhotoGrid(
    items: displayedItems,
    order: photoSort,
    previews: previews,
    transfer: transfer,
    onDownload: download,
    onMore: morePhotos,
    sliver: true,
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
          if (busy && !transfer.busy && !loadingMore)
            const LinearProgressIndicator(minHeight: 2),
          if (connectionRequest.busy && !loadingMore) connectionStatus(),
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
                ? NotificationListener<OverscrollNotification>(
                    onNotification: (notification) {
                      if (notification.overscroll > 0) loadNearEnd();
                      return false;
                    },
                    child: RefreshIndicator(
                      onRefresh: () => page(),
                      child: CustomScrollView(
                        key: const PageStorageKey('sync-camera-photos'),
                        controller: listScroll,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CameraTransferCard(transfer: transfer),
                                  photoTools(),
                                  if (connectionMode == 'slots')
                                    Text(
                                      '相机预设槽位正在使用连接，照片尚未读取。',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: p.secondary,
                                      ),
                                    ),
                                  if (!inventoryReady ||
                                      (items.isEmpty && deferPhotoRead)) ...[
                                    const SizedBox(height: 20),
                                    Text(
                                      '相机已连接。需要浏览时，再读取照片。',
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 1.8,
                                        color: p.secondary,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    FilledButton(
                                      onPressed:
                                          busy ||
                                              exclusive ||
                                              transfer.busy ||
                                              !photosReady
                                          ? null
                                          : () => page(refresh: false),
                                      child: const Text('浏览相机照片'),
                                    ),
                                  ],
                                  if (error != null) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      error!,
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: busy ? null : () => page(),
                                      child: const Text('重试读取照片'),
                                    ),
                                  ],
                                  if (warning != null) Text(warning!),
                                  if (inventoryReady &&
                                      !deferPhotoRead &&
                                      items.isEmpty &&
                                      !busy &&
                                      error == null &&
                                      warning == null)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      child: Text(emptyMessage),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (photosReady)
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              sliver: cameraGrid(),
                            ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                20,
                                16,
                                20,
                                100 + hueNavigationInset(context),
                              ),
                              child: Center(
                                child: loadingMore
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : paginationError != null
                                    ? Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            paginationError!,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => page(next: true),
                                            child: const Text('重试加载'),
                                          ),
                                        ],
                                      )
                                    : Text(
                                        hasMore
                                            ? '上拉继续加载'
                                            : items.isEmpty
                                            ? ''
                                            : '已显示全部照片',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: p.secondary,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
                        if (overviewTab == 0 && error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
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
      floatingActionButton: !widget.state.cameraVisible.value || childOpen
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: hueNavigationInset(context) + 8),
              child: SyncToolsDock(
                onDownloads: busy || transfer.busy ? null : openDownloads,
                onRemote: busy || transfer.busy || exclusive
                    ? null
                    : () => openConnectedTool(slots: false),
                onSlots: busy || transfer.busy || exclusive
                    ? null
                    : () => openConnectedTool(slots: true),
                downloadActive: widget.state.cameraDownloadsActive,
                downloadRemaining: widget.state.cameraDownloads.current == null
                    ? 0
                    : (widget.state.cameraDownloads.items.length -
                              widget.state.cameraDownloads.done)
                          .clamp(0, 99999),
              ),
            ),
    );
  }
}
