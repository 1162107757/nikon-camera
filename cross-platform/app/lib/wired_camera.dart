import 'package:flutter/material.dart';

import 'domain.dart';
import 'camera_connection.dart';

class WiredCameraPicker extends StatefulWidget {
  const WiredCameraPicker({
    super.key,
    required this.core,
    required this.enabled,
    required this.onConnect,
    this.compact = false,
    this.onBusyChanged,
  });
  final bool compact;
  final ValueChanged<bool>? onBusyChanged;
  final HueviaCore core;
  final bool enabled;
  final Future<void> Function(String id) onConnect;
  @override
  State<WiredCameraPicker> createState() => _WiredCameraPickerState();
}

class _WiredCameraPickerState extends State<WiredCameraPicker> {
  List<Json>? devices;
  bool busy = false;
  String? error;
  late final CameraConnectionRequest request;
  @override
  void initState() {
    super.initState();
    request = CameraConnectionRequest(widget.core)
      ..addListener(progressChanged);
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
      if (mounted) setState(() => devices = rows);
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
      widget.onBusyChanged?.call(false);
    }
  }

  Future<void> connect(Json device) async {
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
      await widget.onConnect(id);
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
      widget.onBusyChanged?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
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
