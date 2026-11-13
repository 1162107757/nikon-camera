import 'dart:async';

import 'package:flutter/material.dart';

import 'domain.dart';

class CameraSlotsPage extends StatefulWidget {
  const CameraSlotsPage({
    super.key,
    required this.state,
    this.initialPreset,
    this.importOwner,
  });
  final AppState state;
  final Preset? initialPreset;
  final String? importOwner;
  @override
  State<CameraSlotsPage> createState() => _CameraSlotsPageState();
}

class _CameraSlotsPageState extends State<CameraSlotsPage> {
  Json data = {};
  String? error;
  bool busy = false, leaving = false, choosing = false;
  late final String owner =
      widget.importOwner ??
      (widget.state.session['user']?['id'] as String? ?? '');
  bool get current =>
      mounted &&
      !leaving &&
      widget.state.session['logoutPending'] != true &&
      (widget.state.session['user']?['id'] as String? ?? '') == owner;
  String session = '';
  HueviaCore get core => widget.state.core;
  List<Json> get slots => (data['items'] as List? ?? []).map(object).toList();
  Json get action => data['action'] is Map ? object(data['action']) : {};

  @override
  void initState() {
    super.initState();
    unawaited(open());
  }

  Future<void> run(Future<void> Function() operation) async {
    if (busy || !current) return;
    if (widget.state.cameraDownloadsActive ||
        widget.state.cameraManualTransferActive) {
      setState(() => error = '请先停止相机接收队列，再操作相机预设槽位。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
    } catch (failure) {
      error = '$failure';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open() => run(() async {
    if (session.isEmpty) {
      final status = await core.call('camera.status');
      if (!current) return;
      if (status['connected'] != true) {
        throw const AppFailure('请先通过 Wi-Fi 或 USB 连接尼康相机。');
      }
      session = status['session'] as String;
    }
    final opened = await core.call('camera.slots.open', {'session': session});
    final openedSession = opened['session'] as String;
    if (!current) {
      await core.call('camera.slots.close', {'session': openedSession});
      return;
    }
    data = opened;
    session = openedSession;
  });

  Future<void> refresh({bool reconcile = false}) => run(() async {
    data = await core.call(
      reconcile ? 'camera.slots.reconcile' : 'camera.slots.refresh',
      {'session': session},
    );
  });

  Future<void> prepare(Json slot, String kind) async {
    if (busy || choosing || !current) return;
    setState(() => choosing = true);
    try {
      await prepareAction(slot, kind);
    } catch (failure) {
      if (current) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => choosing = false);
    }
  }

  Future<void> prepareAction(Json slot, String kind) async {
    Json payload = {'session': session, 'target': slot['target'], 'kind': kind};
    if (kind == 'write' && widget.initialPreset != null) {
      final file = await core.call('library.export', {
        'id': widget.initialPreset!.id,
        'owner': owner,
      });
      if (!current) return;
      final tuning = await tuningChoices();
      if (!current || tuning == null) return;
      payload.addAll({'path': file['path'], ...tuning});
    } else if (kind == 'write') {
      final sources = slots
          .where(
            (item) => item['empty'] != true && item['target'] != slot['target'],
          )
          .toList();
      final source = await showModalBottomSheet<int>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('选择导入来源')),
                ListTile(
                  leading: const Icon(Icons.file_open_outlined),
                  title: const Text('从文件选择 NCP'),
                  subtitle: const Text('沿用原版兼容适配；写入前展示完整适配说明'),
                  onTap: () => Navigator.pop(context, 0),
                ),
                for (final item in sources)
                  ListTile(
                    leading: const Icon(Icons.copy_outlined),
                    title: Text('复制 ${item['label']} · ${item['name']}'),
                    onTap: () => Navigator.pop(context, item['target'] as int),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );
      if (!current || source == null) return;
      if (source == 0) {
        final selected = await core.pickFile(preset: true);
        if (!current || selected == null) return;
        final tuning = await tuningChoices();
        if (!current || tuning == null) return;
        payload.addAll({'path': selected['path'], ...tuning});
      } else {
        payload['source'] = source;
      }
    }
    Json? plan;
    await run(() async {
      plan = await core.call('camera.slots.prepare', payload);
    });
    if (!mounted || !current || plan == null) return;
    final confirmation = plan!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          kind == 'delete'
              ? '删除 ${confirmation['targetLabel']}？'
              : '${confirmation['overwrite'] == true ? '覆盖' : '写入'} ${confirmation['targetLabel']}？',
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('相机：${data['model']}'),
              Text(
                '当前：${confirmation['beforeName'] == '' ? '空槽位' : confirmation['beforeName']}',
              ),
              if (kind == 'write') Text('写入：${confirmation['name']}'),
              if (confirmation['explanation'] != '')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(confirmation['explanation'] as String),
                ),
              const SizedBox(height: 12),
              Text(
                kind == 'delete'
                    ? '删除后无法由应用撤销。执行后会读取 C1–C9，核对目标为空且其他槽位未变化。'
                    : '执行前再次核对槽位；写入后精确读回核对。响应丢失时保留待核对状态，不自动重复写入。',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(kind == 'delete' ? '确认删除此槽位' : '确认写入此槽位'),
          ),
        ],
      ),
    );
    if (!current || confirmed != true) return;
    await run(() async {
      data = await core.call('camera.slots.execute', {
        'session': session,
        'confirmationId': confirmation['confirmationId'],
        'confirmed': true,
      });
    });
  }

  Future<Json?> tuningChoices() async {
    int middle = 0, clarity = 0;
    return showDialog<Json>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('NCP 兼容适配参数'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('原文件没有以下新版机身参数。请明确选择适配值；这不代表与机身原生载入等效。'),
                Text('中等范围锐化 ${(middle / 4).toStringAsFixed(2)}'),
                Slider(
                  value: middle.toDouble(),
                  min: -20,
                  max: 20,
                  divisions: 40,
                  onChanged: (value) => update(() => middle = value.round()),
                ),
                Text('清晰度 ${(clarity / 4).toStringAsFixed(2)}'),
                Slider(
                  value: clarity.toDouble(),
                  min: -20,
                  max: 20,
                  divisions: 40,
                  onChanged: (value) => update(() => clarity = value.round()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                'middleQuarter': middle,
                'clarityQuarter': clarity,
              }),
              child: const Text('查看写入预览'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> finish() async {
    if (busy || choosing || leaving) return;
    leaving = true;
    try {
      if (data['session'] != null) {
        await core.call('camera.slots.close', {'session': session});
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
        title: const Text('已在相机核对槽位结果？'),
        content: Text(
          '请在原相机检查 ${action['targetLabel']}，并核对其他槽位。此确认只解除待核对状态，不会再次写入或自动还原。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续核对'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('已在相机核对'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await run(() async {
      data = await core.call('camera.slots.acknowledge', {
        'session': session,
        'confirmedOnCamera': true,
        'actionId': action['actionId'],
      });
    });
  }

  @override
  void dispose() {
    if (!leaving && data['session'] != null) {
      unawaited(
        core
            .call('camera.slots.close', {'session': session})
            .catchError((_) => <String, dynamic>{}),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = action['pending'] == true;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(finish());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('相机预设槽位'),
          leading: IconButton(
            onPressed: busy ? null : finish,
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回',
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                data['model'] as String? ?? '正在读取相机',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('读取照片菜单 C1–C9。选择槽位后可导入、复制或删除；每次操作都单独确认。'),
              if (widget.initialPreset != null) ...[
                const SizedBox(height: 8),
                Text('待导入：${widget.initialPreset!.name}。请选择目标槽位，核对后再写入。'),
              ],
              const SizedBox(height: 12),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
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
              if (pending) ...[
                const Text(
                  '上次操作结果待核对',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(action['message'] as String? ?? '相机可能已执行操作。先只读核对，再决定下一步。'),
                FilledButton.tonal(
                  onPressed: busy ? null : () => refresh(reconcile: true),
                  child: const Text('只读核对上次操作'),
                ),
                TextButton(
                  onPressed: busy ? null : acknowledge,
                  child: const Text('我已在相机手动核对'),
                ),
              ] else if (action['phase'] == 'verified' ||
                  action['phase'] == 'verifiedByReadback')
                const Text('已精确读回核对，目标及其他槽位符合预期。')
              else if (action['phase'] == 'unchangedByReadback')
                const Text('读回确认目标与操作前相同。可重新连接并再次选择操作。'),
              for (final slot in slots) ...[
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${slot['label']} · ${slot['empty'] == true ? '空槽位' : slot['name']}',
                  ),
                  subtitle: Text(
                    'SHA-256 ${(slot['sha256'] as String).substring(0, 12)}',
                  ),
                  trailing: PopupMenuButton<String>(
                    enabled:
                        !busy &&
                        !choosing &&
                        current &&
                        !pending &&
                        data['consumed'] != true,
                    onSelected: (kind) => unawaited(prepare(slot, kind)),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'write',
                        enabled: data['canWrite'] == true,
                        child: Text(slot['empty'] == true ? '导入到此槽位' : '覆盖此槽位'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        enabled:
                            data['canDelete'] == true && slot['empty'] != true,
                        child: const Text('删除此槽位'),
                      ),
                    ],
                  ),
                ),
              ],
              const Divider(),
              if (data['consumed'] == true)
                const Text('本次连接已尝试一次操作。继续操作前，请明确重新连接并读取槽位。'),
              if (data.isEmpty || data['consumed'] == true)
                OutlinedButton.icon(
                  onPressed: busy ? null : open,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新连接并读取槽位'),
                )
              else
                OutlinedButton.icon(
                  onPressed: busy ? null : refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('只读刷新槽位'),
                ),
              const SizedBox(height: 12),
              const Text('槽位操作期间不读取照片。返回后可在同步 → 相机照片主动浏览；若相机要求重新连接，请按提示操作。'),
            ],
          ),
        ),
      ),
    );
  }
}
