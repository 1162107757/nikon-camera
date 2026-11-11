import 'dart:async';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'widgets.dart';
import 'theme.dart';

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
  bool busy = false, connected = false, raw = false, hasMore = false;
  int offset = 0, epoch = 0;
  String? error;
  List<Json> items = [];
  int overviewTab = 0;

  Future<void> openConnection() async {
    await hueRootPage<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraPage(state: widget.state, configuration: true),
      ),
    );
    if (mounted) await status();
  }

  Future<void> connectionSettings() => showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('连接设置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: host,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: '相机地址'),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('完成'),
        ),
      ],
    ),
  );
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
  Widget build(BuildContext context) =>
      widget.configuration ? connectionView(context) : overview(context);

  Widget connectionView(BuildContext context) => Scaffold(
    appBar: HueHeader(
      title: 'Wi-Fi 无线连接',
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
          if (busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              children: [
                if (!connected) ...[
                  const Text('连接后可浏览照片与导入预设。', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 20),
                  Text(
                    '相机类型',
                    style: TextStyle(
                      fontSize: 12,
                      color: HuePalette.of(context).secondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: protocol,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 20,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'nikon', child: Text('尼康')),
                      DropdownMenuItem(
                        value: 'fujifilm',
                        child: Text('富士 X-T20'),
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
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : connect,
                    child: Text(busy ? '正在连接' : '连接相机'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: busy ? null : connectionSettings,
                    child: const Text('连接设置'),
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
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
            child: CapsuleSwitch(
              labels: const ['相机照片', '边拍边传', '已下载'],
              selected: overviewTab,
              onSelected: (value) => setState(() => overviewTab = value),
            ),
          ),
          if (overviewTab == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: InkWell(
                onTap: openConnection,
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
            child: connected && overviewTab == 0
                ? ListView(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      10,
                      20,
                      100 + hueNavigationInset(context),
                    ),
                    children: [
                      Text(
                        '共 ${items.length} 张',
                        style: TextStyle(fontSize: 12, color: p.secondary),
                      ),
                      for (final item in items)
                        ListTile(
                          title: Text(item['name'] as String),
                          onTap: () => download(item),
                        ),
                      if (hasMore)
                        OutlinedButton(
                          onPressed: busy ? null : () => page(next: true),
                          child: const Text('读取更多照片'),
                        ),
                    ],
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(28, 44, 28, 100),
                    child: Column(
                      children: [
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
                              : '在底部「设置」中连接相机 Wi-Fi，\n照片会显示在这里。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: p.secondary,
                          ),
                        ),
                        if (overviewTab != 2) ...[
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
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
