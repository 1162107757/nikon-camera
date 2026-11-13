import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'batch_export.dart';
import 'editor.dart';
import 'album_operations.dart';
import 'domain.dart';
import 'photo_grid.dart';
import 'theme.dart';
import 'widgets.dart';

/// Lets the shell hide its navigation while the album keeps its existing grid.
class AlbumSelectionChanged extends Notification {
  const AlbumSelectionChanged(this.active);
  final bool active;
}

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
  final Set<String> removed = {};
  List<Json> get rows =>
      widget.rows.where((row) => !removed.contains(row['id'])).toList();
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
        compact: MediaQuery.sizeOf(context).height < 480,
        endPadding: 12,
        navigation: HueIconButton(
          kind: HueIconKind.close,
          label: '取消选择',
          disc: false,
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: '删除所选照片',
            icon: const Icon(Icons.delete_outline),
            onPressed: selected.isEmpty
                ? null
                : () => hueRootPage<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AlbumDeletePage(
                        state: widget.state,
                        rows: rows
                            .where((r) => selected.contains(r['id']))
                            .toList(),
                        phone: widget.phone,
                        onDeleted: (ids) {
                          if (mounted) {
                            setState(() {
                              removed.addAll(ids);
                              selected.removeAll(ids);
                            });
                          }
                        },
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            height: 48,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor: p.secondary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(fontSize: 14, height: 1.17),
              ),
              onPressed: () => toggle(rows),
              child: Text(selected.length == rows.length ? '取消全选' : '全选'),
            ),
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
                enabled: false,
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: Text(
                    '共 ${rows.length} 张',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: p.secondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: PhotoMasonry(
              rows: rows,
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
      bottomNavigationBar: AlbumSelectionDock(
        onPressed: selected.isEmpty
            ? null
            : () => hueRootPage<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => BatchExportPage(
                    state: widget.state,
                    phone: widget.phone,
                    rows: rows
                        .where((row) => selected.contains(row['id']))
                        .toList(),
                  ),
                ),
              ),
      ),
    );
  }
}

class AlbumSelectionDock extends StatelessWidget {
  const AlbumSelectionDock({
    super.key,
    required this.onPressed,
    this.onExport,
    this.onDelete,
    this.inline = false,
    this.phone = false,
  });
  final VoidCallback? onPressed;
  final VoidCallback? onExport, onDelete;
  final bool inline, phone;
  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    final extra =
        ((MediaQuery.textScalerOf(context).scale(12) / 12 - 1.3).clamp(
                  0,
                  double.infinity,
                ) *
                20)
            .round();
    final compact = MediaQuery.sizeOf(context).height < 480;
    final height = (compact ? 64.0 : 76.0) + extra;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: p.card,
              elevation: 6,
              shadowColor: const Color(0x18000000),
              borderRadius: BorderRadius.circular(24),
              child: SizedBox(
                width: double.infinity,
                height: height,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      for (final action in [
                        (
                          inline && !phone ? '编辑' : '批量编辑',
                          HueIconKind.edit,
                          onPressed,
                        ),
                        if (inline && !phone)
                          ('导出', HueIconKind.download, onExport),
                        if (inline && !phone)
                          ('删除', HueIconKind.delete, onDelete),
                      ])
                        Expanded(
                          child: TextButton(
                            onPressed: action.$3,
                            style: TextButton.styleFrom(
                              foregroundColor: p.ink,
                              disabledForegroundColor: p.ink.withValues(
                                alpha: .45,
                              ),
                              padding: EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: compact ? 0 : 6,
                              ),
                              minimumSize: const Size(0, 48),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 12,
                                height: 1.17,
                                letterSpacing: 0,
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                HueIcon(
                                  action.$2,
                                  size: 24,
                                  color: action.$3 == null
                                      ? p.ink.withValues(alpha: .45)
                                      : p.ink,
                                ),
                                const SizedBox(height: 6),
                                Text(action.$1),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
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
    this.saveToGallery = false,
  });
  final AppState state;
  final List<Json> rows;
  final bool phone;
  final bool saveToGallery;
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
  bool sharing = false, editing = false, systemAlbum = false;
  @override
  void initState() {
    super.initState();
    systemAlbum = widget.saveToGallery;
    if (batch.locked) {
      preset = batch.preset ?? '__keep__';
      size = batch.size;
      strength = batch.strength.toDouble();
      systemAlbum = batch.saveToGallery;
    }
  }

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
        systemAlbum: systemAlbum,
      );
    } catch (failure) {
      if (mounted) report(context, failure);
    }
  }

  Future<void> edit(BatchPhoto item) async {
    if (batch.busy || batch.locked || editing || batch.accountInvalid) return;
    setState(() => editing = true);
    try {
      batch.stopped = false;
      await batch.prepare(item);
      if (!mounted || batch.accountInvalid) return;
      await hueRootPage<void>(
        context,
        MaterialPageRoute(
          builder: (_) => EditorPage(state: widget.state, photo: item.photo!),
        ),
      );
      batch.invalidateRecipe(item);
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) setState(() => editing = false);
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
      canPop: !batch.busy && !editing,
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
            const Text('点击照片逐张使用完整编辑器，返回后按各自草稿统一导出。任务开始后会冻结全部设置，可停止后继续。'),
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
            DropdownButtonFormField<bool>(
              initialValue: systemAlbum,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '保存目标'),
              items: const [
                DropdownMenuItem(value: false, child: Text('应用成品')),
                DropdownMenuItem(value: true, child: Text('同时保存手机相册')),
              ],
              onChanged: batch.locked || editing
                  ? null
                  : (value) => setState(() => systemAlbum = value!),
            ),
            const SizedBox(height: 16),
            if (batch.busy || editing) const LinearProgressIndicator(),
            if (batch.recoveryError != null)
              Text(
                batch.recoveryError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                batch.accountInvalid
                    ? '账号已改变，任务停止。请重新选择照片。'
                    : '已保存成品 ${batch.completed}/${batch.items.length} 张${batch.saveToGallery ? ' · 手机相册 ${batch.published}/${batch.items.length}' : ''}${batch.failed > 0 ? ' · ${batch.failed} 张未完成' : ''}${batch.stopped ? ' · 已停止' : ''}',
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
                onTap: batch.locked || editing
                    ? null
                    : () => unawaited(edit(item)),
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
                if (batch.busy || editing)
                  OutlinedButton(
                    onPressed: batch.stopped
                        ? null
                        : () => unawaited(batch.cancel()),
                    child: Text(batch.stopped ? '正在停止…' : '停止处理'),
                  )
                else if (!batch.done)
                  FilledButton(
                    onPressed: batch.accountInvalid || editing ? null : run,
                    child: Text(batch.locked ? '继续处理未完成项' : '开始批量导出'),
                  ),
                if (batch.completed > 0 && !batch.busy)
                  OutlinedButton(
                    onPressed: sharing || batch.accountInvalid ? null : share,
                    child: Text('分享已完成的 ${batch.completed} 张'),
                  ),
                if ((batch.done || batch.recoveryError != null) && !batch.busy)
                  TextButton(
                    onPressed: () => unawaited(batch.newTask()),
                    child: const Text('新建一次批量任务'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
