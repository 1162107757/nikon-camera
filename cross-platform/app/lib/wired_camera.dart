import 'package:flutter/material.dart';

import 'domain.dart';
import 'camera_connection.dart';
import 'theme.dart';

class WiredCameraPicker extends StatefulWidget {
  const WiredCameraPicker({
    super.key,
    required this.core,
    required this.enabled,
    required this.onConnect,
    this.compact = false,
    this.onBusyChanged,
    this.active = false,
    this.preferredId,
    this.recoverId,
    this.onRecover,
    this.builder,
  });
  final bool compact;
  final ValueChanged<bool>? onBusyChanged;

  /// Keeps discovery/selection alive while the shared connection page switches
  /// transport. Device selection never asks for permission in this layout.
  final Widget Function(BuildContext, Widget content, Widget primary)? builder;
  final bool active;
  final String? preferredId;
  final String? recoverId;
  final HueviaCore core;
  final bool enabled;
  final Future<void> Function(String id) onConnect;
  final Future<void> Function(String id)? onRecover;
  @override
  State<WiredCameraPicker> createState() => _WiredCameraPickerState();
}

class _WiredCameraPickerState extends State<WiredCameraPicker> {
  List<Json>? devices;
  bool busy = false;
  String? error;
  String? selectedId;
  late final CameraConnectionRequest request;
  @override
  void initState() {
    super.initState();
    selectedId = widget.preferredId;
    request = CameraConnectionRequest(widget.core)
      ..addListener(progressChanged);
    scheduleDetection();
  }

  @override
  void didUpdateWidget(WiredCameraPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && devices == null) {
      scheduleDetection();
    }
  }

  void scheduleDetection() {
    if (!widget.active) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active && devices == null) detect();
    });
  }

  void progressChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    request.removeListener(progressChanged);
    request.dispose();
    super.dispose();
  }

  Future<void> detect() async {
    if (busy || !widget.enabled) return;
    setState(() {
      busy = true;
      error = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      final result = await request.run(
        'camera.usb.devices',
        {},
        'camera-usb-discovery-${DateTime.now().microsecondsSinceEpoch}',
        timeout: const Duration(seconds: 50),
      );
      final rows = (result['items'] as List).map((row) => object(row)).toList();
      if (mounted) {
        setState(() {
          devices = rows;
          if (!rows.any((row) => row['id'] == selectedId)) {
            selectedId = rows.isEmpty ? null : rows.first['id'] as String?;
          }
        });
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
      widget.onBusyChanged?.call(false);
    }
  }

  Future<void> connect(Json device, {bool recover = false}) async {
    if (busy || !widget.enabled) return;
    final id = device['id'];
    if (id is! String || id.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    widget.onBusyChanged?.call(true);
    try {
      await widget.core.requestUsbPermission(id);
      if (!mounted) return;
      setState(() {
        devices = devices?.map((row) {
          return row['id'] == id ? {...row, 'permission': true} : row;
        }).toList();
      });
      if (recover) {
        await widget.onRecover?.call(id);
      } else {
        await widget.onConnect(id);
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
      widget.onBusyChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.builder != null) return approvedLayout(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.compact)
          Text('USB 有线传输', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (!widget.compact)
          const Text(
            '将尼康相机开机，通过支持数据传输的 USB 线连接手机。Android 需开启 OTG；iPhone 可使用 USB-C 或兼容的相机转接器。',
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: busy || !widget.enabled ? null : detect,
          icon: const Icon(Icons.usb_rounded),
          label: Text(busy ? '正在处理 USB 连接' : '检测 USB 相机'),
        ),
        if (request.busy)
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    '${request.phase} · 已等待 ${request.elapsedSeconds} 秒',
                  ),
                ),
              ),
              TextButton(onPressed: request.cancel, child: const Text('取消检测')),
            ],
          ),
        if (devices != null && devices!.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('尚未检测到相机。请检查数据线、转接器、PTP/MTP 模式和访问权限，稍后再次检测。'),
          ),
        for (final device in devices ?? <Json>[])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.camera_alt_outlined),
            title: Text(device['name'] as String? ?? 'Nikon USB 相机'),
            trailing: const Icon(Icons.chevron_right),
            subtitle: const Text('浏览并接收 JPEG / NEF 原文件'),
            enabled: !busy && widget.enabled,
            onTap: () => connect(device),
          ),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget approvedLayout(BuildContext context) {
    final p = HuePalette.of(context);
    final selected = (devices ?? <Json>[])
        .where((device) => device['id'] == selectedId)
        .firstOrNull;
    final disabled = busy || !widget.enabled;
    final recover =
        widget.onRecover != null &&
        selected != null &&
        selected['id'] == widget.recoverId;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final device in devices ?? <Json>[])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: p.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: device['id'] == selectedId
                      ? p.ink
                      : Colors.transparent,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: ValueKey('usb-device-${device['id']}'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                leading: const Icon(Icons.camera_alt_outlined, size: 30),
                title: Text(device['name'] as String? ?? 'Nikon USB 相机'),
                subtitle: Text(
                  device['permission'] == true ? '已检测到 · 已授权' : '已检测到 · 等待授权',
                ),
                trailing: device['id'] == selectedId
                    ? const Icon(Icons.check_circle_outline)
                    : null,
                selected: device['id'] == selectedId,
                enabled: !disabled,
                onTap: () =>
                    setState(() => selectedId = device['id'] as String),
              ),
            ),
          ),
        if (devices != null && devices!.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              '尚未检测到相机。请检查数据线、转接器和相机的 PTP/MTP 模式后重新检测。',
              style: TextStyle(color: p.secondary, height: 1.7),
            ),
          ),
        if (request.busy)
          Semantics(
            liveRegion: true,
            child: Text('${request.phase} · 已等待 ${request.elapsedSeconds} 秒'),
          ),
        Center(
          child: TextButton.icon(
            key: const Key('usb-detect'),
            onPressed: disabled ? null : detect,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(busy ? '正在检测 USB 相机…' : '重新检测'),
          ),
        ),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
    final primary = SizedBox(
      width: double.infinity,
      child: FilledButton(
        key: const Key('camera-usb-connect'),
        onPressed: request.busy
            ? request.cancel
            : disabled
            ? null
            : selected == null
            ? detect
            : () => connect(selected, recover: recover),
        style: FilledButton.styleFrom(
          backgroundColor: p.action,
          foregroundColor: p.onAction,
          minimumSize: const Size(48, 54),
          shape: const StadiumBorder(),
        ),
        child: Text(
          request.busy
              ? '取消检测'
              : busy
              ? '正在连接…'
              : selected == null
              ? '检测 USB 相机'
              : recover
              ? '恢复 USB 会话'
              : selected['permission'] == true
              ? '连接相机'
              : '授权并连接',
        ),
      ),
    );
    return widget.builder!(context, content, primary);
  }
}
