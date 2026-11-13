import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'domain.dart';
import 'updates_ios.dart';
import 'theme.dart';

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key, required this.state});
  final AppState state;
  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  static const channel = MethodChannel('cc.huevia/updates');
  static const events = EventChannel('cc.huevia/update-events');
  Json status = {};
  String error = '';
  StreamSubscription<dynamic>? subscription;
  bool invoking = false;
  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) return;
    subscription = events.receiveBroadcastStream().listen((event) {
      if (mounted && event is Map) setState(() => status = object(event));
    }, onError: (_) {});
    unawaited(run('check'));
  }

  @override
  void dispose() {
    unawaited(subscription?.cancel());
    super.dispose();
  }

  Future<void> run(String method, [Json arguments = const {}]) async {
    if (invoking) return;
    setState(() {
      invoking = true;
      error = '';
    });
    try {
      final result = await channel.invokeMapMethod<String, dynamic>(
        method,
        arguments,
      );
      if (mounted && result != null) setState(() => status = result);
    } on PlatformException catch (failure) {
      if (mounted) setState(() => error = failure.message ?? '更新操作未完成。');
    } on MissingPluginException {
      if (mounted) setState(() => error = '此安装包缺少更新组件，请从原分发入口安装完整版本。');
    } finally {
      if (mounted) setState(() => invoking = false);
    }
  }

  Future<void> download() async {
    var mobileAllowed = false;
    if (status['metered'] == true) {
      mobileAllowed =
          await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: const Text('使用流量下载？'),
              content: const Text('安装包下载可能产生移动数据费用。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('稍后'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: const Text('继续下载'),
                ),
              ],
            ),
          ) ==
          true;
      if (!mobileAllowed) return;
    }
    await run('download', {'mobileAllowed': mobileAllowed});
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) return IosUpdatesPage(root: widget.state.core.root);
    final release = status['release'] is Map
        ? object(status['release'])
        : <String, dynamic>{};
    final busy =
        invoking ||
        [
          'checking',
          'downloading',
          'verifying',
        ].any((key) => status[key] == true);
    final failure = error.isEmpty ? status['error'] as String? ?? '' : error;
    return Scaffold(
      appBar: const HueHeader(title: '应用更新', back: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '当前版本 ${status['versionName'] ?? '正在读取…'}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: status['channel'] as String? ?? 'stable',
              decoration: const InputDecoration(labelText: '更新通道'),
              items: const [
                DropdownMenuItem(value: 'stable', child: Text('正式版')),
                DropdownMenuItem(value: 'beta', child: Text('测试版')),
              ],
              onChanged: busy || status['mandatory'] == true
                  ? null
                  : (value) => run('channel', {'channel': value}),
            ),
            const SizedBox(height: 24),
            Text(status['status'] as String? ?? '正在检查新版本…'),
            if (busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(
                  value: status['downloading'] == true
                      ? (status['progress'] as num? ?? 0) / 100
                      : null,
                ),
              ),
            if (release.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '新版本 ${release['versionName']}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '安装包 ${((release['byteLength'] as num? ?? 0) / 1048576).toStringAsFixed(1)} MiB',
              ),
              const SizedBox(height: 12),
              Text(release['notes'] as String? ?? ''),
            ],
            if (failure.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  failure,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            if (release.isNotEmpty)
              FilledButton(
                onPressed: busy
                    ? null
                    : () => status['verified'] == true
                          ? run('install')
                          : download(),
                child: Text(status['verified'] == true ? '校验并打开系统安装' : '下载更新'),
              ),
            if (status['downloading'] == true)
              TextButton(
                onPressed: () => run('cancel'),
                child: const Text('取消下载'),
              ),
            TextButton(
              onPressed: busy ? null : () => run('check'),
              child: const Text('重新检查'),
            ),
            const SizedBox(height: 16),
            const Text(
              '安装前会重新校验文件 SHA-256、包名、版本和签名。请先完成相机传输任务；若系统要求允许此来源安装，授权后返回再点击安装。',
            ),
          ],
        ),
      ),
    );
  }
}
