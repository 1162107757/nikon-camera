import 'dart:async';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'widgets.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, required this.state});
  final AppState state;
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  final host = TextEditingController(text: '192.168.1.1'),
      port = TextEditingController(text: '15740');
  String protocol = 'nikon', session = '', model = '', job = '';
  bool busy = false, connected = false, raw = false, hasMore = false;
  int offset = 0, epoch = 0;
  String? error;
  List<Json> items = [];
  @override
  void initState() {
    super.initState();
    unawaited(status());
  }

  @override
  void dispose() {
    epoch++;
    host.dispose();
    port.dispose();
    if (busy && job.isNotEmpty) unawaited(widget.state.core.cancel(job));
    super.dispose();
  }

  Future<void> status() async {
    final request = ++epoch;
    try {
      final result = await widget.state.core.call('camera.status');
      if (!mounted || request != epoch) return;
      setState(() {
        connected = result['connected'] == true;
        session = result['session'] as String;
        model = result['model'] as String;
      });
      if (connected) await page();
    } catch (failure) {
      if (mounted && request == epoch) setState(() => error = '$failure');
    }
  }

  Future<void> connect() async {
    final request = ++epoch;
    setState(() {
      busy = true;
      error = null;
      job = 'camera-connect-${DateTime.now().microsecondsSinceEpoch}';
    });
    try {
      final result = await widget.state.core.call('camera.connect', {
        'host': host.text.trim(),
        'port': int.tryParse(port.text) ?? 0,
        'protocol': protocol,
      }, job);
      if (!mounted || request != epoch) return;
      setState(() {
        connected = result['connected'] == true;
        session = result['session'] as String;
        model = result['model'] as String;
      });
      await page();
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

  Future<void> page({bool next = false}) async {
    final request = ++epoch, expectedSession = session;
    final identity = 'camera-page-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      busy = true;
      error = null;
      job = identity;
    });
    try {
      final result = await widget.state.core.call('camera.page', {
        'session': session,
        'offset': next ? offset : 0,
        'limit': 24,
        'raw': raw,
      }, identity);
      if (!mounted || request != epoch || session != expectedSession) return;
      final rows = (result['items'] as List).map(object).toList();
      setState(() {
        items = next ? [...items, ...rows] : rows;
        offset = result['nextOffset'] as int;
        hasMore = result['hasMore'] == true;
      });
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

  Future<void> download(Json item) async {
    final request = ++epoch;
    setState(() {
      busy = true;
      error = null;
      job = 'camera-download-${DateTime.now().microsecondsSinceEpoch}';
    });
    try {
      final result = await widget.state.core.call('camera.download', {
        'session': session,
        'handle': item['handle'],
        'raw': raw,
      }, job);
      final info = await widget.state.core.call('media.info', {
        'path': result['path'],
      });
      await widget.state.registerPhoto(
        result['path'] as String,
        result['name'] as String,
        info,
      );
      if (mounted && request == epoch) {
        report(context, '${item['name']} 已保存到应用照片库');
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

  Future<void> disconnect() async {
    final request = ++epoch;
    setState(() => busy = true);
    try {
      await widget.state.core.call('camera.disconnect');
      if (mounted && request == epoch) {
        setState(() {
          connected = false;
          session = '';
          items = [];
        });
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('相机'),
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
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (!connected) ...[
                  Text(
                    '连接相机 Wi-Fi',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  const Text('先在系统设置中连接相机 Wi-Fi，然后返回这里。'),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<String>(
                    initialValue: protocol,
                    decoration: const InputDecoration(labelText: '相机协议'),
                    items: const [
                      DropdownMenuItem(
                        value: 'nikon',
                        child: Text('尼康 · PTP/IP'),
                      ),
                      DropdownMenuItem(
                        value: 'fujifilm',
                        child: Text('富士 X-T20 · 实验性照片读取'),
                      ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) => setState(() {
                            protocol = value!;
                            host.text = protocol == 'nikon'
                                ? '192.168.1.1'
                                : '';
                            port.text = protocol == 'nikon' ? '15740' : '55740';
                          }),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: host,
                    enabled: !busy,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: '相机地址'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: port,
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '端口'),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: busy ? null : connect,
                    child: Text(busy ? '正在连接' : '连接相机'),
                  ),
                ] else ...[
                  Text(model, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('已连接 · 原文件按字节接收'),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    children: [
                      ChoiceChip(
                        label: const Text('JPEG'),
                        selected: !raw,
                        onSelected: busy
                            ? null
                            : (_) {
                                setState(() => raw = false);
                                unawaited(page());
                              },
                      ),
                      ChoiceChip(
                        label: const Text('RAW / NEF'),
                        selected: raw,
                        onSelected: busy
                            ? null
                            : (_) {
                                setState(() => raw = true);
                                unawaited(page());
                              },
                      ),
                      IconButton(
                        tooltip: '刷新照片',
                        onPressed: busy ? null : () => page(),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (items.isEmpty && !busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Text('当前列表没有照片。'),
                    ),
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: Icon(
                            raw ? Icons.raw_on_outlined : Icons.image_outlined,
                          ),
                          title: Text(item['name'] as String),
                          subtitle: Text(
                            '${item['width']} × ${item['height']} · ${((item['bytes'] as num) / 1024 / 1024).toStringAsFixed(1)} MB',
                          ),
                          trailing: IconButton(
                            tooltip: '接收原文件',
                            onPressed: busy ? null : () => download(item),
                            icon: const Icon(Icons.download_outlined),
                          ),
                        ),
                      ),
                    ),
                  if (hasMore)
                    OutlinedButton(
                      onPressed: busy ? null : () => page(next: true),
                      child: const Text('读取更多照片'),
                    ),
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
                if (busy && job.isNotEmpty)
                  TextButton(
                    onPressed: () => widget.state.core.cancel(job),
                    child: const Text('取消操作'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
