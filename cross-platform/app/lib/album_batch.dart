import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'batch_export.dart';
import 'domain.dart';
import 'photo_grid.dart';
import 'theme.dart';
import 'widgets.dart';

class AlbumSelectionPage extends StatefulWidget {
  const AlbumSelectionPage({
    super.key,
    required this.state,
    required this.rows,
    required this.phone,
  });
  final AppState state;
  final List<Json> rows;
  final bool phone;
  @override
  State<AlbumSelectionPage> createState() => _AlbumSelectionPageState();
}

class _AlbumSelectionPageState extends State<AlbumSelectionPage> {
  final Set<String> selected = {};
  void toggle(List<Json> rows) {
    final ids = rows.map((row) => row['id'] as String).toSet();
    if (ids.every(selected.contains)) {
      setState(() => selected.removeAll(ids));
    } else if (selected.union(ids).length > 100) {
      report(context, '一次最多选择 100 张照片。');
    } else {
      setState(() => selected.addAll(ids));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return Scaffold(
      appBar: HueHeader(
        title: '已选 ${selected.length} 张',
        navigation: HueIconButton(
          kind: HueIconKind.close,
          label: '取消选择',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: () => toggle(widget.rows),
            child: Text(selected.length == widget.rows.length ? '取消全选' : '全选'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: IgnorePointer(
              child: CapsuleSwitch(
                labels: const ['应用相册', '手机相册'],
                selected: widget.phone ? 1 : 0,
                onSelected: (_) {},
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 24),
                child: Text(
                  '共 ${widget.rows.length} 张',
                  style: TextStyle(fontSize: 12, color: p.secondary),
                ),
              ),
            ),
          ),
          Expanded(
            child: PhotoMasonry(
              rows: widget.rows,
              phone: widget.phone,
              core: widget.state.core,
              selected: selected,
              onGroup: toggle,
              bottomPadding: 16,
              onOpen: (row) async => toggle([row]),
              onLongPress: (row) async => toggle([row]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
          child: FilledButton(
            onPressed: selected.isEmpty
                ? null
                : () => hueRootPage<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BatchExportPage(
                        state: widget.state,
                        phone: widget.phone,
                        rows: widget.rows
                            .where((row) => selected.contains(row['id']))
                            .toList(),
                      ),
                    ),
                  ),
            child: const Text('批量编辑'),
          ),
        ),
      ),
    );
  }
}

class BatchExportPage extends StatefulWidget {
  const BatchExportPage({
    super.key,
    required this.state,
    required this.rows,
    required this.phone,
  });
  final AppState state;
  final List<Json> rows;
  final bool phone;
  @override
  State<BatchExportPage> createState() => _BatchExportPageState();
}

class _BatchExportPageState extends State<BatchExportPage> {
  late final BatchExport batch = BatchExport(
    widget.state,
    widget.rows,
    phone: widget.phone,
  );
  String preset = '__keep__', size = 'full';
  double strength = 100;
  bool sharing = false;
  @override
  void dispose() {
    batch.dispose();
    super.dispose();
  }

  Future<void> run() async {
    try {
      await batch.run(
        presetId: preset == '__keep__' ? null : preset,
        amount: strength.round(),
        exportSize: size,
      );
    } catch (failure) {
      if (mounted) report(context, failure);
    }
  }

  Future<void> share() async {
    if (sharing || batch.busy || batch.accountInvalid) return;
    setState(() => sharing = true);
    try {
      await SharePlus.instance.share(
        ShareParams(
          sharePositionOrigin: shareAnchor(context),
          files: batch.items
              .where((item) => item.output != null)
              .map((item) => XFile(item.output!))
              .toList(),
        ),
      );
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) setState(() => sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: batch,
    builder: (context, _) => PopScope(
      canPop: !batch.busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && batch.busy) report(context, '请先停止批量处理，再返回。');
      },
      child: Scaffold(
        appBar: const HueHeader(title: '批量编辑', back: true),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              '已选 ${batch.items.length} 张',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text('原图保留。JPEG 成品保存到「成品版本」，可在完成后分享。'),
            if (widget.rows.any((row) => row['raw'] == true))
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('RAW 使用上次显影设置；首次使用相机白平衡和高光保护，生成 JPEG 工作副本。'),
              ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: preset,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '统一预设'),
              items: [
                const DropdownMenuItem(
                  value: '__keep__',
                  child: Text('保留各自编辑'),
                ),
                const DropdownMenuItem(value: '', child: Text('无滤镜 · 保留其他调节')),
                for (final item in widget.state.presets)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(item.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: batch.locked
                  ? null
                  : (value) => setState(() => preset = value!),
            ),
            if (preset != '__keep__' && preset.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('预设强度 ${strength.round()}%'),
              Slider(
                value: strength,
                min: 0,
                max: 100,
                divisions: 100,
                onChanged: batch.locked
                    ? null
                    : (value) => setState(() => strength = value),
              ),
            ],
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'full', label: Text('完整尺寸')),
                ButtonSegment(value: 'share', label: Text('长边 2048')),
              ],
              selected: {size},
              onSelectionChanged: batch.locked
                  ? null
                  : (value) => setState(() => size = value.single),
            ),
            const SizedBox(height: 20),
            if (batch.busy) const LinearProgressIndicator(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                batch.accountInvalid
                    ? '账号已改变，任务停止。请重新选择照片。'
                    : '已保存 ${batch.completed}/${batch.items.length} 张${batch.failed > 0 ? ' · ${batch.failed} 张未完成' : ''}${batch.stopped ? ' · 已停止' : ''}',
              ),
            ),
            for (final item in batch.items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  item.row['name'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(item.error ?? item.phase),
                trailing: item.output != null
                    ? const Icon(Icons.check_circle_outline)
                    : null,
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (batch.busy)
                  OutlinedButton(
                    onPressed: batch.stopped
                        ? null
                        : () => unawaited(batch.cancel()),
                    child: Text(batch.stopped ? '正在停止…' : '停止处理'),
                  )
                else if (batch.completed < batch.items.length)
                  FilledButton(
                    onPressed: batch.accountInvalid ? null : run,
                    child: Text(batch.locked ? '继续处理未完成项' : '开始批量导出'),
                  ),
                if (batch.completed > 0 && !batch.busy)
                  OutlinedButton(
                    onPressed: sharing || batch.accountInvalid ? null : share,
                    child: Text('分享已完成的 ${batch.completed} 张'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
