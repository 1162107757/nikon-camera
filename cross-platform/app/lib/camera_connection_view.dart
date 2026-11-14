import 'package:flutter/material.dart';

import 'camera_connection.dart';
import 'legacy_glass_sheet.dart';
import 'theme.dart';

/// Presentation only. The caller retains the bounded, cancellable connection.
class CameraConnectionView extends StatelessWidget {
  const CameraConnectionView({
    super.key,
    required this.usb,
    required this.busy,
    required this.usbBusy,
    required this.connected,
    required this.model,
    required this.protocol,
    required this.request,
    required this.error,
    required this.settingsExpanded,
    required this.host,
    required this.port,
    required this.usbPicker,
    required this.transferCard,
    required this.onTransportChanged,
    required this.onProtocol,
    required this.onConnect,
    required this.onCancel,
    required this.onSettings,
    required this.onPermissionSettings,
    required this.onReturn,
    required this.onDisconnect,
    required this.onDiagnostics,
  });
  final bool usb, busy, usbBusy, connected, settingsExpanded;
  final String model, protocol;
  final String? error;
  final CameraConnectionRequest request;
  final TextEditingController host, port;
  final Widget usbPicker, transferCard;
  final ValueChanged<bool> onTransportChanged;
  final VoidCallback onProtocol,
      onConnect,
      onCancel,
      onSettings,
      onPermissionSettings,
      onReturn,
      onDisconnect,
      onDiagnostics;

  Widget step(
    BuildContext context,
    int number,
    String title,
    String detail, {
    Widget? action,
  }) {
    final p = HuePalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 23,
            height: 23,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: p.outline),
            ),
            child: Text(
              '$number',
              style: TextStyle(fontSize: 11, color: p.secondary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                    color: p.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.75,
                    color: p.secondary,
                  ),
                ),
                ?action,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> wifiGuide(BuildContext context) => showLegacyGlassSheet<void>(
    context,
    builder: (sheet) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      child: ListView(
        shrinkWrap: true,
        primary: false,
        padding: EdgeInsets.zero,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '连接相机的 Wi-Fi',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: '关闭指引',
                onPressed: () => Navigator.pop(sheet),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            Theme.of(context).platform == TargetPlatform.iOS
                ? '打开 iPhone 的“设置” → “Wi-Fi”，选择相机网络并完成连接，然后返回 Huevia，点击“开始连接”。'
                : '打开手机的系统 Wi-Fi 设置，选择相机网络。完成连接后返回 Huevia，点击“开始连接”。',
            style: const TextStyle(fontSize: 14, height: 1.8),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(sheet),
              child: const Text('知道了'),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context),
        ios = Theme.of(context).platform == TargetPlatform.iOS;
    final locked = busy || usbBusy;
    return Scaffold(
      appBar: HueHeader(
        title: '',
        back: true,
        actions: [
          Text(
            usb ? 'USB' : 'Wi-Fi',
            style: TextStyle(fontSize: 12, color: p.secondary),
          ),
          if (connected)
            IconButton(
              tooltip: '断开相机',
              onPressed: locked ? null : onDisconnect,
              icon: const Icon(Icons.link_off_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 18),
                children: [
                  Text(
                    '连接相机',
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.3,
                      letterSpacing: -.7,
                      fontWeight: FontWeight.w600,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '选择连接方式，保持相机开启。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.7,
                      color: p.secondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: p.container,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        for (final mode in [false, true])
                          Expanded(
                            child: Semantics(
                              selected: usb == mode,
                              child: TextButton.icon(
                                onPressed: locked
                                    ? null
                                    : () => onTransportChanged(mode),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 44),
                                  backgroundColor: usb == mode
                                      ? p.card
                                      : Colors.transparent,
                                  foregroundColor: p.ink,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: Icon(
                                  mode ? Icons.usb_rounded : Icons.wifi_rounded,
                                  size: 19,
                                ),
                                label: Text(mode ? 'USB' : 'Wi-Fi'),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  transferCard,
                  if (connected) ...[
                    const SizedBox(height: 30),
                    const Icon(Icons.check_circle_outline, size: 40),
                    const SizedBox(height: 18),
                    Text(model, style: const TextStyle(fontSize: 22)),
                    const SizedBox(height: 12),
                    const Text(
                      '相机已连接。返回上一页继续操作。',
                      style: TextStyle(height: 1.8),
                    ),
                  ] else if (request.busy) ...[
                    const SizedBox(height: 30),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.all(17),
                        decoration: BoxDecoration(
                          color: p.container,
                          borderRadius: BorderRadius.circular(19),
                        ),
                        child: Icon(
                          usb ? Icons.usb : Icons.link_rounded,
                          size: 27,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        request.phase,
                        style: TextStyle(
                          fontSize: 22,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                          color: p.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      usb
                          ? '保持数据线连接；查看系统访问提示和相机屏幕，按提示允许连接。'
                          : '保持手机连接相机 Wi-Fi；查看系统授权提示和机身屏幕。',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.8,
                        color: p.secondary,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '已用 ${request.elapsedSeconds} 秒 · 可随时取消',
                      style: TextStyle(fontSize: 12, color: p.secondary),
                    ),
                  ] else ...[
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: Semantics(
                          liveRegion: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                error!.contains('超时')
                                    ? Icons.schedule_rounded
                                    : Icons.info_outline,
                                color: Theme.of(context).colorScheme.error,
                                size: 30,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                error!.contains('超时')
                                    ? '连接等待已超时'
                                    : error!.startsWith('已取消')
                                    ? '本次连接已取消'
                                    : '未能连接相机',
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 9),
                              Text(
                                error!,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.8,
                                  color: p.secondary,
                                ),
                              ),
                              TextButton(
                                onPressed: onDiagnostics,
                                child: const Text('导出诊断报告'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (usb) ...[
                      step(context, 1, '用数据线连接相机与手机', '使用支持数据传输的线缆，保持相机开启。'),
                      step(
                        context,
                        2,
                        '确认 USB 模式与访问权限',
                        '按系统和机身提示选择支持的照片传输模式，并允许设备访问。',
                      ),
                      const SizedBox(height: 18),
                      usbPicker,
                    ] else ...[
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        minVerticalPadding: 10,
                        onTap: locked ? null : onProtocol,
                        title: Text(
                          '相机类型',
                          style: TextStyle(fontSize: 13, color: p.secondary),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              protocol == 'nikon' ? '尼康' : '富士 X-T20',
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.chevron_right, size: 17),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: p.outline),
                      step(context, 1, '在相机上开启 Wi-Fi', '保持机身的无线连接界面开启。'),
                      step(
                        context,
                        2,
                        '让手机连接相机的 Wi-Fi',
                        '在系统 Wi-Fi 设置中选择相机网络。',
                        action: TextButton.icon(
                          onPressed: () => wifiGuide(context),
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: const Text(
                            '查看 Wi-Fi 连接指引',
                            style: TextStyle(fontSize: 12),
                          ),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(48, 44),
                          ),
                        ),
                      ),
                      step(
                        context,
                        3,
                        '回到 Huevia，开始连接',
                        protocol == 'nikon'
                            ? '机身出现连接提示时，请在相机上确认。'
                            : '请在 X-T20 机身按 OK；当前支持 JPEG 浏览和下载。',
                      ),
                      if (ios)
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.shield_outlined,
                                size: 15,
                                color: p.secondary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '首次连接请允许“本地网络”访问。',
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.7,
                                    color: p.secondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      Divider(height: 1, color: p.outline),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text(
                          '连接设置',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: Icon(
                          settingsExpanded
                              ? Icons.expand_less
                              : Icons.chevron_right,
                          size: 18,
                        ),
                        onTap: onSettings,
                      ),
                      if (settingsExpanded) ...[
                        TextField(
                          controller: host,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(labelText: 'IP 地址'),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: port,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: '端口'),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (ios)
                        TextButton(
                          onPressed: locked ? null : onPermissionSettings,
                          child: const Text(
                            '打开本地网络权限设置',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (request.busy)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: onCancel,
                        child: const Text('取消连接'),
                      ),
                    )
                  else if (connected || !usb)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('camera-connect'),
                        onPressed: locked
                            ? null
                            : connected
                            ? onReturn
                            : onConnect,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 50),
                          backgroundColor: p.action,
                          foregroundColor: p.onAction,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          connected
                              ? '返回继续操作'
                              : error == null
                              ? '开始连接'
                              : '重新连接',
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    request.busy ? '取消后停止本次连接，保留连接方式。' : '连接成功后，直接返回上一页。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.7,
                      color: p.secondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
