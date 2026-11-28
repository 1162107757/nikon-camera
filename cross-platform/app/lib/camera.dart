import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

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
import 'camera_location.dart';
import 'camera_slots.dart';
import 'camera_downloads.dart';
import 'camera_connection.dart';
import 'camera_connection_view.dart';
import 'camera_photo_sort.dart';
import 'camera_photo_toolbar.dart';
import 'legacy_glass_sheet.dart';
import 'sync_tools_dock.dart';
import 'sync_content_viewport.dart';

import 'package:go_router/go_router.dart';

Future<bool> connectCamera(
  BuildContext context,
  AppState state, {
  bool reuseConnected = false,
}) async =>
    await hueRootPage<bool>(
      context,
      MaterialPageRoute<bool>(
        builder: (_) => CameraPage(
          state: state,
          configuration: true,
          reuseConnected: reuseConnected,
        ),
      ),
    ) ==
    true;

class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    required this.state,
    this.configuration = false,
    this.reuseConnected = false,
    this.attachedUsbId,
    this.connectOnAttachment = false,
  });
  final AppState state;
  final bool configuration;
  final bool reuseConnected;
  final String? attachedUsbId;
  final bool connectOnAttachment;
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  final host = TextEditingController(text: '192.168.1.1'),
      port = TextEditingController(text: '15740');
  String protocol = 'nikon', session = '', model = '', job = '';
  String connectionMode = 'none';
  bool connectedUsb = false;
  bool closingWiredSession = false;
  bool inventoryReady = false;
  bool busy = false, connected = false, hasMore = false;
  bool loadingMore = false;
  String? paginationError;
  bool get raw => widget.state.cameraRaw;
  set raw(bool value) => widget.state.cameraRaw = value;
  late final CameraPreviews previews;
  late final CameraTransfer transfer;
  late final CameraConnectionRequest connectionRequest;
  Future<void>? initialStatus;
  bool cameraStatusKnown = false;
  StreamSubscription<dynamic>? maintenanceEvents;
  final listScroll = ScrollController();
  int offset = 0, epoch = 0, statusRevision = 0;
  String? error;
  String? usbRecoveryId;
  String? connectionNotice;
  // Status notifications must not retry a failed/empty first page in a loop.
  // Explicit refresh, filter changes, pagination and retry still call page().
  String photoReadSession = '';
  String? get visibleError => connected ? error : connectionNotice ?? error;
  String? warning;
  List<Json> items = [];
  int overviewTab = 0;
  bool settingsExpanded = false, connectionUsb = false, usbBusy = false;
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
  bool get hasAndroidUsbSession =>
      connectedUsb && widget.state.core.platform == 'android';
  bool get canDisconnect =>
      !childOpen &&
      session.isNotEmpty &&
      (!busy || hasAndroidUsbSession && transfer.busy && !closingWiredSession);
  bool get browsingPhotos =>
      !widget.configuration &&
      inForeground &&
      !childOpen &&
      !closingWiredSession &&
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
    final wasConnected = connected;
    final previousUsb = connectedUsb;
    final firstStatus = !cameraStatusKnown;
    cameraStatusKnown = true;
    connected = value['connected'] == true;
    session = value['session'] as String? ?? '';
    model = value['model'] as String? ?? '';
    connectionMode =
        value['mode'] as String? ?? (connected ? 'photos' : 'none');
    inventoryReady = value['inventoryReady'] == true;
    connectedUsb = value['transport'] == 'usb';
    if (connected &&
        (!wasConnected || connectedUsb != previousUsb) &&
        (!firstStatus || widget.attachedUsbId == null || connectedUsb)) {
      connectionUsb = connectedUsb;
    }
    final notice = value['connectionNotice'];
    if (connected) {
      connectionNotice = null;
    } else if (notice is String && notice.isNotEmpty) {
      connectionNotice = notice;
    }
  }

  Future<void> openCameraTool(
    Widget page, {
    bool allowExclusive = false,
    bool fullScreen = false,
    bool compact = false,
    bool refreshPhotosAfterClose = false,
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
      childOpen = false;
      if (mounted) setState(() {});
      if (afterClose != null) {
        try {
          await afterClose();
        } catch (_) {
          /* Closing does not reconnect. */
        }
      }
      if (mounted) {
        if (!exclusive && browsingPhotos && photosReady) previews.resume();
        await status(reload: refreshPhotosAfterClose);
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
      refreshPhotosAfterClose: !slots && connectedUsb,
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

  Future<void> openLocation() async {
    if (childOpen || busy || transfer.busy || exclusive) return;
    if (connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先断开相机的 Wi-Fi 或 USB 连接，再开启蓝牙定位同步。')),
      );
      return;
    }
    await openCameraTool(
      CameraLocationPage(session: widget.state.cameraLocation),
      fullScreen: true,
    );
  }

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
    if (busy || transfer.busy || exclusive || handle is! int) return;
    setState(() {
      if (!selection.remove(handle)) {
        if (selection.length < 100) selection.add(handle);
      }
    });
  }

  void beginSelection(Json item) {
    final handle = item['handle'];
    if (busy || transfer.busy || exclusive || handle is! int) return;
    setState(() {
      selecting = true;
      selection
        ..clear()
        ..add(handle);
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
      await queueDownloads(selected, target, expectedSession);
    } catch (failure) {
      if (mounted) report(context, failure);
    }
  }

  Future<void> queueDownloads(
    List<Json> selected,
    Json target,
    String expectedSession,
  ) async {
    final status = await widget.state.core.call('camera.status');
    if (!mounted) return;
    if (expectedSession != session ||
        status['session'] != expectedSession ||
        exclusive) {
      throw const AppFailure('相机会话已改变，请重新选择照片。');
    }
    final downloads = widget.state.cameraDownloads;
    await downloads.create(status, selected, target);
    if (!mounted) return;
    if (selecting) {
      setState(() {
        selecting = false;
        selection.clear();
      });
    }
    unawaited(downloads.resume(downloads.current!['id'] as String));
    await openDownloads();
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

  Future<bool> openConnection({
    bool? loadPhotos,
    bool waitForStatus = true,
  }) async {
    if (!mounted || childOpen || closingWiredSession) return false;
    final browseAfter = loadPhotos ?? browsingPhotos;
    setState(() => childOpen = true);
    previews.pause();
    var didConnect = false;
    try {
      didConnect = await connectCamera(context, widget.state);
    } finally {
      childOpen = false;
      if (mounted) setState(() {});
    }
    if (!mounted) return false;
    // The navigation lease ends when the route closes, not when a later
    // transport snapshot eventually returns.
    if (didConnect) {
      final refresh = status(reload: browseAfter, inspectOnly: !browseAfter);
      if (waitForStatus) {
        await refresh;
      } else {
        unawaited(refresh);
      }
    } else {
      unawaited(status(reload: false, inspectOnly: true));
    }
    if (mounted && !exclusive && browsingPhotos && photosReady) {
      previews.resume();
    }
    return didConnect;
  }

  Future<void> chooseProtocol() async {
    final selected = await hueChoice<String>(
      context: context,
      title: '选择相机类型',
      selected: protocol,
      choices: const [('nikon', '尼康'), ('fujifilm', '富士')],
    );
    if (!mounted || selected == null || selected == protocol) return;
    setState(() {
      protocol = selected;
      host.text = protocol == 'nikon' ? '192.168.1.1' : '192.168.0.1';
      port.text = protocol == 'nikon' ? '15740' : '55740';
      error = null;
    });
  }

  @override
  void initState() {
    super.initState();
    connectionUsb = widget.attachedUsbId != null;
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
            childOpen) {
          return;
        }
        unawaited(status(reload: false, inspectOnly: true));
      }, onError: (_) {});
    }
    final statusRequest = initialStatus = status();
    unawaited(statusRequest.whenComplete(() => initialStatus = null));
    final attachedUsbId = widget.attachedUsbId;
    if (widget.connectOnAttachment && attachedUsbId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await statusRequest;
        if (mounted &&
            inForeground &&
            connectionUsb &&
            ModalRoute.of(context)?.isCurrent == true) {
          await connect(usbId: attachedUsbId, onlyIfDisconnected: true);
        }
      });
    }
  }

  @override
  void dispose() {
    epoch++;
    statusRevision++;
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
        !childOpen) {
      unawaited(
        status(reload: false, inspectOnly: busy || transfer.busy || exclusive),
      );
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
      closingWiredSession = false;
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
    if (browsingPhotos && photosReady) previews.resume();
    if (!childOpen) {
      unawaited(
        status(reload: false, inspectOnly: busy || transfer.busy || exclusive),
      );
    }
  }

  Future<void> status({bool reload = true, bool inspectOnly = false}) async {
    final request = ++statusRevision, operation = epoch;
    try {
      final result = await widget.state.core.call('camera.status');
      if (!mounted ||
          request != statusRevision ||
          operation != epoch ||
          childOpen && !widget.configuration) {
        return;
      }
      final previousSession = session;
      final changed = session != result['session'];
      final wasConnected = connected;
      setState(() {
        acceptCameraStatus(result);
        if (changed) {
          error = null;
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
          connectionNotice = '相机连接已断开，请重新连接后继续。';
        }
      });
      if ((!connected || changed) &&
          (previousSession.isNotEmpty ||
              !connected && widget.attachedUsbId == null)) {
        retireSessionWork(previousSession);
      }
      if (connected && session.isNotEmpty) {
        widget.state.cameraLive.connectionRestored(session: session);
      }
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
      // Only an internal operation such as preset import may reuse a known
      // connection without showing this page. An explicit connect entry must
      // remain visible even when a stale native snapshot still says connected.
      if (widget.configuration &&
          widget.reuseConnected &&
          connected &&
          session.isNotEmpty) {
        finishConnection();
        return;
      }
      if (!inspectOnly &&
          browsingPhotos &&
          photosReady &&
          !exclusive &&
          (reload || changed || photoReadSession != session)) {
        await page();
      }
    } catch (failure) {
      if (mounted && request == statusRevision && operation == epoch) {
        setState(() => error = '$failure');
      }
    }
  }

  void retireSessionWork(String previousSession) {
    const reason = '相机连接已改变，请重新连接后继续，已接收的照片会保留。';
    final state = widget.state;
    if (state.cameraLiveActive) {
      final live = state.cameraLive;
      live.connectionLost(
        expectedSession: previousSession.isEmpty
            ? live.session
            : previousSession,
        reason: reason,
      );
    }
    if (state.cameraDownloadsActive) {
      final queue = state.cameraDownloads;
      queue.connectionLost(
        expectedSession: previousSession.isEmpty
            ? queue.activeSession
            : previousSession,
        reason: reason,
      );
    }
    unawaited(
      state
          .stopCameraManualTransfer(
            expectedSession: previousSession.isEmpty ? null : previousSession,
          )
          .catchError((Object _) {}),
    );
    final oldPageRequest =
        connectionRequest.busy && connectionRequest.operation == 'camera.page';
    if (busy && (!connectionRequest.busy || oldPageRequest)) {
      final oldJob = job;
      epoch++;
      setState(() {
        busy = loadingMore = false;
        closingWiredSession = false;
        job = '';
      });
      if (oldPageRequest) {
        connectionRequest.cancel(message: reason);
      } else if (oldJob.isNotEmpty) {
        unawaited(widget.state.core.cancel(oldJob).catchError((Object _) {}));
      }
    }
  }

  Future<void> connectWired(String id) => connect(usbId: id);

  Future<void> recoverWired(String id) =>
      connect(usbId: id, onlyIfDisconnected: true, recoverUsbSession: true);

  Future<void> drainWiredTransfer(String expectedSession, int request) async {
    final state = widget.state;
    previews.pause();
    Future<void> stopSafely(Future<void> Function() stop) async {
      try {
        await stop();
      } catch (failure) {
        // The serialized native request can still close the exact USB session.
        if (mounted && request == epoch) report(context, failure);
      }
    }

    await stopSafely(
      () => state.stopCameraManualTransfer(
        expectedSession: expectedSession,
        preserveConnection: true,
      ),
    );
    if (!mounted || request != epoch) return;
    if (state.cameraDownloadsActive) {
      final queue = state.cameraDownloads;
      if (queue.activeSession.isEmpty ||
          queue.activeSession == expectedSession) {
        await stopSafely(() => queue.stop());
      }
    }
    if (!mounted || request != epoch) return;
    if (state.cameraLiveActive) {
      final live = state.cameraLive;
      if (live.session.isEmpty || live.session == expectedSession) {
        await stopSafely(() => live.stop());
      }
    }
  }

  Future<void> chooseFujifilmWifi() async {
    final result = await showFujifilmWifiDialog(context);
    if (!mounted || result == null) return;
    try {
      await widget.state.core.requestCameraWifiPermission();
      if (!mounted || protocol != 'fujifilm' || connectionUsb || busy) return;
      await connect(wifi: result);
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    }
  }

  Future<void> connect({
    String? usbId,
    bool onlyIfDisconnected = false,
    bool recoverUsbSession = false,
    FujifilmWifiChoice? wifi,
  }) async {
    if (onlyIfDisconnected &&
        (!cameraStatusKnown ||
            connected ||
            busy ||
            connectionRequest.busy ||
            exclusive ||
            widget.state.cameraManualTransferActive)) {
      return;
    }
    if (busy || connectionRequest.busy) {
      setState(() => error = '本次连接仍在进行，可以先取消后重试。');
      return;
    }
    final state = widget.state;
    if (state.core.platform == 'android' &&
        !cameraStatusKnown &&
        (exclusive || state.cameraManualTransferActive)) {
      // A fresh connection screen may still be waiting on the current transfer
      // for its first status. Identify its transport before choosing how to stop.
      setState(() => busy = true);
      await (initialStatus ?? status(reload: false, inspectOnly: true));
      if (!mounted) return;
      setState(() => busy = false);
      if (!cameraStatusKnown) {
        setState(() => error = '暂时无法确认当前相机连接，请重试。');
        return;
      }
    }
    final request = ++epoch;
    final replaceSession = hasAndroidUsbSession ? session : '';
    setState(() {
      busy = true;
      closingWiredSession = replaceSession.isNotEmpty;
      error = null;
      usbRecoveryId = null;
      connectionNotice = null;
      paginationError = null;
      loadingMore = false;
      job = 'camera-connect-${DateTime.now().microsecondsSinceEpoch}';
    });
    var connectionSent = false;
    try {
      if (replaceSession.isNotEmpty) {
        await drainWiredTransfer(replaceSession, request);
      } else if (!onlyIfDisconnected) {
        // Retire old local producers by their own session before reconnecting.
        if (widget.state.cameraLiveActive) {
          final live = widget.state.cameraLive;
          final oldCameraJob = live.pendingCameraJob;
          live.connectionLost(expectedSession: live.session);
          if (oldCameraJob != null) {
            await widget.state.core
                .cancel(oldCameraJob)
                .timeout(const Duration(seconds: 2));
          }
        }
        if (widget.state.cameraDownloadsActive) {
          final queue = widget.state.cameraDownloads;
          final oldCameraJob = queue.pendingCameraJob;
          queue.connectionLost(expectedSession: queue.activeSession);
          if (oldCameraJob != null) {
            await widget.state.core
                .cancel(oldCameraJob)
                .timeout(const Duration(seconds: 2));
          }
        }
        await widget.state.stopCameraManualTransfer();
      }
      if (!mounted || request != epoch) return;
      if (widget.state.cameraManualTransferActive) {
        throw const AppFailure('另一项照片传输仍在结束，请稍后重新连接。');
      }
      await state.stopCameraLocation();
      if (!mounted || request != epoch) return;
      connectionSent = true;
      final result = await connectionRequest.run(
        'camera.connect',
        {
          'host': host.text.trim(),
          'port': int.tryParse(port.text) ?? 0,
          'protocol': usbId == null ? protocol : 'nikon',
          if (wifi != null) ...{
            'wifiSsid': wifi.ssid,
            'wifiPassword': wifi.password,
          },
          if (usbId == null &&
              protocol == 'fujifilm' &&
              state.core.platform == 'android' &&
              (host.text.trim().isEmpty || host.text.trim() == '192.168.0.1'))
            'automaticHost': true,
          if (usbId != null) 'transport': 'usb',
          if (replaceSession.isNotEmpty) 'replaceSession': replaceSession,
          if (onlyIfDisconnected) 'requireDisconnected': true,
          if (recoverUsbSession) 'recoverUsbSession': true,
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
        closingWiredSession = false;
        busy = false;
        job = '';
      });
      widget.state.cameraLive.connectionRestored(session: session);
      previews.setSession(session);
      if (widget.configuration && widget.attachedUsbId == null) {
        finishConnection();
      } else if (browsingPhotos) {
        await page(refresh: false);
      }
    } catch (failure) {
      if (mounted && request == epoch) {
        if (connectionSent) {
          // A replacement attempt may already have closed the old transport.
          // Inspect the native session rather than resurrecting its old badge.
          final revision = ++statusRevision;
          Json? actual;
          try {
            actual = await widget.state.core
                .call('camera.status')
                .timeout(const Duration(seconds: 3));
          } catch (_) {
            // An unavailable status cannot certify the old session as usable.
          }
          if (!mounted || request != epoch || revision != statusRevision) {
            return;
          }
          final previousSession = session;
          setState(() {
            acceptCameraStatus(actual ?? {'connected': false, 'session': ''});
            connectionNotice = null;
            error = '$failure';
            if (usbId != null &&
                failure is AppFailure &&
                failure.details is Map &&
                (failure.details as Map)['recoverUsbSession'] == true) {
              usbRecoveryId = usbId;
            }
          });
          if (!onlyIfDisconnected &&
              (!connected || session != previousSession)) {
            retireSessionWork(previousSession);
          }
          previews.setSession(session);
        } else {
          setState(() => error = '$failure');
        }
      }
    } finally {
      if (mounted && request == epoch) {
        setState(() {
          busy = false;
          closingWiredSession = false;
          job = '';
        });
        if (replaceSession.isNotEmpty &&
            browsingPhotos &&
            photosReady &&
            !exclusive) {
          previews.resume();
        }
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
      if (value == 1 && (!connected || session.isEmpty)) {
        unawaited(openConnection(loadPhotos: false, waitForStatus: false));
      }
    }
  }

  Future<void> page({bool next = false, bool refresh = true}) async {
    if (!browsingPhotos || !photosReady || exclusive || transfer.busy || busy) {
      return;
    }
    final request = ++epoch, expectedSession = session;
    if (!next) photoReadSession = expectedSession;
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
    final expectedSession = session;
    final target = await chooseDownloadTarget(context, widget.state);
    if (!mounted || target == null) return;
    if (expectedSession != session || busy || transfer.busy || exclusive) {
      throw const AppFailure('相机会话已改变，请重新选择照片。');
    }
    if (target['kind'] != 'app') {
      await queueDownloads([item], target, expectedSession);
      return;
    }
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
      if (!closingWiredSession) previews.resume();
      if (mounted && request == epoch) {
        setState(() {
          busy = false;
          job = '';
        });
      }
    }
  }

  Future<void> disconnect() async {
    if (!mounted || !canDisconnect) return;
    final confirmedSession = session;
    setState(() => childOpen = true);
    bool? confirmed;
    try {
      confirmed = await hueDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('断开相机连接？'),
          content: Text(
            widget.state.cameraLiveActive ||
                    widget.state.cameraDownloadsActive ||
                    widget.state.cameraManualTransferActive
                ? '断开后将停止边拍边传和相机接收任务，已接收的照片会保留。'
                : '断开后需要重新连接才能导入预设或接收相机照片。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('保持连接'),
            ),
            TextButton(
              key: const Key('confirm-camera-disconnect'),
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('断开连接'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => childOpen = false);
    }
    if (!mounted ||
        confirmed != true ||
        !canDisconnect ||
        session != confirmedSession) {
      return;
    }
    final request = ++epoch, expectedSession = session;
    final gracefulUsb = hasAndroidUsbSession;
    setState(() {
      busy = true;
      closingWiredSession = gracefulUsb;
      error = null;
    });
    try {
      if (gracefulUsb) {
        await drainWiredTransfer(expectedSession, request);
      } else {
        await widget.state.stopCameraManualTransfer(
          expectedSession: expectedSession,
        );
        if (!mounted || request != epoch) return;
        if (widget.state.cameraDownloadsActive) {
          await widget.state.cameraDownloads.stop(preserveConnection: false);
        }
        if (!mounted || request != epoch) return;
        if (widget.state.cameraLiveActive) {
          await widget.state.cameraLive.stop(preserveConnection: false);
        }
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
          closingWiredSession = false;
          job = '';
        });
        if (gracefulUsb && browsingPhotos && photosReady && !exclusive) {
          previews.resume();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !closingWiredSession || connectionRequest.busy,
    child: widget.configuration ? connectionView(context) : overview(context),
  );

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

  Widget connectionView(BuildContext context) => WiredCameraPicker(
    core: widget.state.core,
    enabled: !busy,
    compact: true,
    preferredId: widget.attachedUsbId,
    active: connectionUsb && !(connected && connectedUsb),
    onBusyChanged: (value) {
      if (mounted) setState(() => usbBusy = value);
    },
    onConnect: connectWired,
    recoverId: usbRecoveryId,
    onRecover: recoverWired,
    builder: (context, picker, primary) => CameraConnectionView(
      usb: connectionUsb,
      busy: busy,
      closingWiredSession: closingWiredSession,
      usbBusy: usbBusy,
      connected:
          connected && session.isNotEmpty && connectionUsb == connectedUsb,
      model: model,
      protocol: protocol,
      request: connectionRequest,
      error: visibleError,
      settingsExpanded: settingsExpanded,
      host: host,
      port: port,
      transferCard: CameraTransferCard(transfer: transfer),
      usbPicker: picker,
      usbPrimaryAction: primary,
      onTransportChanged: (value) => setState(() {
        connectionUsb = value;
        error = null;
        usbRecoveryId = null;
        connectionNotice = null;
      }),
      onProtocol: chooseProtocol,
      onConnect: () => connect(),
      onChooseFujifilmWifi: widget.state.core.platform == 'android'
          ? chooseFujifilmWifi
          : null,
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
          selectedCount: selection.length,
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
          onSelectAll: busy || exclusive || transfer.busy
              ? null
              : () => setState(() {
                  selection
                    ..clear()
                    ..addAll(
                      displayedItems
                          .take(100)
                          .map((row) => row['handle'] as int),
                    );
                }),
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
    onBeginSelection: beginSelection,
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
    final location = widget.state.cameraLocation;
    return Scaffold(
      appBar: HueHeader(
        title: '同步',
        compact: compact,
        actions: [
          ListenableBuilder(
            listenable: location,
            builder: (context, _) {
              if (!connected && location.connected) {
                return TextButton.icon(
                  onPressed: openLocation,
                  icon: const Icon(Icons.bluetooth_connected, size: 16),
                  label: Text(
                    location.positionSent ? '蓝牙 · 位置已发送' : '蓝牙 · 等待定位',
                  ),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                );
              }
              return Row(
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
              );
            },
          ),
          if (connected)
            IconButton(
              onPressed: canDisconnect ? disconnect : null,
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
              gap: 8,
              padding: const EdgeInsets.all(6),
              height: 60,
            ),
          ),
          if (closingWiredSession)
            const WiredSessionClosingStatus()
          else if (busy && !transfer.busy && !loadingMore)
            const LinearProgressIndicator(minHeight: 2),
          if (connectionRequest.busy && !loadingMore) connectionStatus(),
          Expanded(
            child: SyncContentViewport(
              child: overviewTab == 1
                  ? ProjectPresetsPage(
                      state: widget.state,
                      embedded: true,
                      cameraActionsEnabled: !closingWiredSession,
                      onConnect: () => openConnection(
                        loadPhotos: false,
                        waitForStatus: false,
                      ),
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
                                    if (visibleError != null) ...[
                                      const SizedBox(height: 12),
                                      Text(
                                        visibleError!,
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
                          if (overviewTab == 0 && visibleError != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              visibleError!,
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
          ),
        ],
      ),
      floatingActionButton: !widget.state.cameraVisible.value || childOpen
          ? null
          : Padding(
              padding: EdgeInsets.only(bottom: hueNavigationInset(context) + 8),
              child: SyncToolsDock(
                selectionCount: overviewTab == 0 && connected && selecting
                    ? selection.length
                    : 0,
                onDownloadSelection: busy || transfer.busy || exclusive
                    ? null
                    : receiveSelection,
                onDownloads: busy || transfer.busy ? null : openDownloads,
                onRemote: busy || transfer.busy || exclusive
                    ? null
                    : () => openConnectedTool(slots: false),
                onSlots: busy || transfer.busy || exclusive
                    ? null
                    : () => openConnectedTool(slots: true),
                onLocation:
                    !kIsWeb &&
                        (defaultTargetPlatform == TargetPlatform.android ||
                            defaultTargetPlatform == TargetPlatform.iOS)
                    ? openLocation
                    : null,
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
