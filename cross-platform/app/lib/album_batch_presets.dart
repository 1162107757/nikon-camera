import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'album_preset_preview.dart';
import 'batch_export.dart';
import 'domain.dart';
import 'legacy_glass_sheet.dart';
import 'photo_grid.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> showAlbumBatchPresets(
  BuildContext context,
  AppState state,
  List<Json> rows, {
  required bool phone,
}) {
  final owner = state.session['user']?['id'] as String? ?? '';
  return showLegacyGlassSheet<void>(
    context,
    enableDrag: false,
    isDismissible: false,
    builder: (sheetContext) {
      if (owner != (state.session['user']?['id'] as String? ?? '')) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('账号已改变，请关闭后重新选择照片。'),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
      return AlbumBatchPresets(state: state, rows: rows, phone: phone);
    },
  );
}

/// One modal retains the album and selection throughout preview and export.
class AlbumBatchPresets extends StatefulWidget {
  const AlbumBatchPresets({
    super.key,
    required this.state,
    required this.rows,
    required this.phone,
  });
  final AppState state;
  final List<Json> rows;
  final bool phone;
  @override
  State<AlbumBatchPresets> createState() => _AlbumBatchPresetsState();
}

class _AlbumBatchPresetsState extends State<AlbumBatchPresets> {
  late final batch = BatchExport(
    widget.state,
    widget.rows,
    phone: widget.phone,
    presetBatch: true,
  );
  late AlbumPresetPreview preview = AlbumPresetPreview(
    widget.state,
    batch,
    isCurrent: () =>
        mounted && !batch.accountInvalid && !starting && !batch.locked,
  );
  Preset? selected;
  List<Preset> online = [];
  bool useOnline = false, loadingOnline = false, starting = false;
  String? catalogError, actionError;
  int photoIndex = 0;
  double strength = 100;
  String size = 'full';
  bool get task => starting || batch.locked;
  bool get working => starting || batch.busy;
  String identity(Preset preset) =>
      preset.online ? preset.data['sha256'] as String : preset.id;

  @override
  void initState() {
    super.initState();
    strength = batch.strength.toDouble();
    size = batch.size;
    if (batch.preset != null) {
      selected = widget.state.presets
          .where((p) => p.id == batch.preset)
          .firstOrNull;
      if (selected == null && batch.editorPreset != null) {
        selected = Preset(batch.editorPreset!, online: true);
      }
    }
    batch.addListener(changed);
    preview.addListener(changed);
    if (!batch.locked) unawaited(updatePreview());
  }

  void changed() {
    if (!mounted) return;
    if (batch.accountInvalid) unawaited(preview.stop());
    setState(() {});
  }

  Future<void> updatePreview() async {
    if (task || batch.accountInvalid) return;
    await preview.update(
      item: batch.items[photoIndex],
      preset: selected,
      strength: strength.round(),
    );
  }

  Future<void> loadOnline() async {
    if (loadingOnline || batch.accountInvalid) return;
    setState(() {
      loadingOnline = true;
      catalogError = null;
    });
    try {
      final value = await widget.state.core.call('editor.catalog');
      if (!mounted || batch.accountInvalid) return;
      if (!['ok', 'cached'].contains(value['status'])) {
        throw const AppFailure('在线预设暂不可用，请重试。');
      }
      final distinct = <String, Preset>{};
      for (final row in value['items'] as List) {
        final p = Preset(object(row), online: true);
        final id = p.data['sha256'];
        if (id is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(id)) {
          distinct[id] = p;
        }
      }
      setState(() => online = distinct.values.toList());
    } catch (_) {
      if (mounted && !batch.accountInvalid) {
        setState(() => catalogError = '在线预设加载失败，本地预设仍可使用。');
      }
    } finally {
      if (mounted) setState(() => loadingOnline = false);
    }
  }

  Future<void> run() async {
    if (working ||
        batch.accountInvalid ||
        (!batch.locked && selected == null)) {
      return;
    }
    setState(() {
      starting = true;
      actionError = null;
    });
    try {
      // Drain read-only preview work before the export queue takes ownership.
      await preview.stop();
      if (!mounted || batch.accountInvalid) return;
      await batch.run(
        presetId: selected?.online == true
            ? selected!.data['sha256'] as String
            : selected?.id,
        onlinePreset: selected?.online == true ? selected!.data : null,
        amount: strength.round(),
        exportSize: size,
        systemAlbum: true,
      );
    } catch (failure) {
      if (mounted && !batch.accountInvalid) {
        setState(() => actionError = '$failure');
      }
    } finally {
      if (mounted) setState(() => starting = false);
    }
  }

  Future<void> newTask() async {
    if (working || batch.accountInvalid) return;
    setState(() {
      starting = true;
      actionError = null;
    });
    final previous = preview;
    try {
      await previous.stop();
      if (!mounted || batch.accountInvalid) return;
      previous.removeListener(changed);
      previous.dispose();
      preview = AlbumPresetPreview(
        widget.state,
        batch,
        isCurrent: () =>
            mounted && !batch.accountInvalid && !starting && !batch.locked,
      )..addListener(changed);
      await batch.newTask();
      if (!mounted || batch.accountInvalid) return;
      setState(() {
        selected = null;
        strength = 100;
      });
    } catch (_) {
      if (mounted) {
        batch.locked = true;
        batch.recoveryError = '批量任务记录暂不可写，请重试。';
      }
    } finally {
      if (mounted) {
        setState(() => starting = false);
        if (!batch.locked && !batch.accountInvalid) unawaited(updatePreview());
      }
    }
  }

  @override
  void dispose() {
    batch.removeListener(changed);
    preview.removeListener(changed);
    preview.dispose();
    batch.dispose();
    super.dispose();
  }

  Widget photo(BatchPhoto item, {double? width, double? height}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        height: height,
        child: item.output != null
            ? Image.file(
                File(item.output!),
                fit: BoxFit.cover,
                cacheWidth: 256,
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Icons.photo_outlined)),
              )
            : albumSelectionThumbnail(
                widget.state.core,
                item.row,
                phone: widget.phone,
              ),
      ),
    );
  }

  Widget thumbnail(Preset preset) => FutureBuilder<AlbumPresetPreviewFrame?>(
    key: ValueKey(
      '${identityHashCode(preview)}:$photoIndex:${identity(preset)}',
    ),
    future: preview.thumbnail(preset),
    builder: (context, result) {
      final frame = result.data;
      return frame == null || frame.sourceSha != preview.frame?.sourceSha
          ? const Center(child: Icon(Icons.photo_outlined, size: 24))
          : RawImage(image: frame.image, fit: BoxFit.cover);
    },
  );

  Widget picker(BuildContext context) {
    final p = HuePalette.of(context);
    final presets = useOnline ? online : widget.state.presets;
    final frame = preview.frame;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        SizedBox(
          height: math.min(156, MediaQuery.sizeOf(context).height * .25),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: p.container,
                  child: frame == null
                      ? Center(child: Text(preview.busy ? '正在准备预览…' : '照片预览'))
                      : RawImage(image: frame.image, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${photoIndex + 1} / ${batch.items.length}'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: batch.items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) => Semantics(
              button: true,
              selected: photoIndex == index,
              label: '预览第 ${index + 1} 张照片',
              child: InkWell(
                onTap: () {
                  setState(() => photoIndex = index);
                  unawaited(updatePreview());
                },
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: photoIndex == index ? p.ink : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: photo(batch.items[index], width: 48, height: 44),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        CapsuleSwitch(
          labels: const ['我的预设', '在线预设'],
          selected: useOnline ? 1 : 0,
          onSelected: (index) {
            setState(() => useOnline = index == 1);
            if (useOnline && online.isEmpty) unawaited(loadOnline());
          },
        ),
        const SizedBox(height: 10),
        if (useOnline && loadingOnline) const Text('正在加载在线预设…'),
        if (useOnline && catalogError != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  catalogError!,
                  style: TextStyle(color: p.secondary),
                ),
              ),
              TextButton(onPressed: loadOnline, child: const Text('重试')),
            ],
          ),
        if (presets.isEmpty && !loadingOnline)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              useOnline ? '暂无可用在线预设' : '暂无本地预设，可切换到在线预设',
              textAlign: TextAlign.center,
            ),
          ),
        if (presets.isNotEmpty)
          SizedBox(
            height: 80 + MediaQuery.textScalerOf(context).scale(11) * 3.2,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: presets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = presets[index];
                final chosen =
                    selected != null &&
                    selected!.online == item.online &&
                    identity(selected!) == identity(item);
                return SizedBox(
                  width: 88,
                  child: InkWell(
                    key: ValueKey(
                      'album-batch-preset-${item.online ? 'online' : 'local'}-${identity(item)}',
                    ),
                    onTap: () {
                      setState(() => selected = item);
                      unawaited(updatePreview());
                    },
                    child: Column(
                      children: [
                        Container(
                          height: 76,
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: chosen ? p.ink : Colors.transparent,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox.expand(child: thumbnail(item)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: chosen
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        Row(
          children: [
            const Text('强度'),
            Expanded(
              child: Slider(
                value: strength,
                min: 0,
                max: 100,
                onChanged: selected == null
                    ? null
                    : (value) {
                        setState(() => strength = value);
                        unawaited(updatePreview());
                      },
              ),
            ),
            Text('${strength.round()}%'),
          ],
        ),
        if (preview.error != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  '预览暂不可用，请重试或选择其他预设。',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              TextButton(onPressed: updatePreview, child: const Text('重试')),
            ],
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('导出设置'),
          subtitle: Text('JPEG · ${size == 'full' ? '原尺寸' : '分享尺寸'} · 手机相册'),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'full', label: Text('原尺寸')),
                ButtonSegment(value: 'share', label: Text('分享尺寸')),
              ],
              selected: {size},
              onSelectionChanged: (value) =>
                  setState(() => size = value.single),
            ),
          ],
        ),
        Text(
          '保留其他调节 · 原图保留',
          textAlign: TextAlign.center,
          style: TextStyle(color: p.secondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget progress(BuildContext context) {
    final p = HuePalette.of(context);
    final completed = batch.publishesExternally
        ? batch.published
        : batch.completed;
    final fraction =
        (batch.completed + (batch.publishesExternally ? batch.published : 0)) /
        (batch.items.length * (batch.publishesExternally ? 2 : 1));
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        if (batch.done) const Icon(Icons.check_circle, size: 40),
        const SizedBox(height: 12),
        Text(
          batch.done
              ? '已保存 $completed 张照片'
              : working
              ? '正在批量处理'
              : batch.stopped
              ? '已停止处理'
              : '部分照片未完成',
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          '${selected?.name ?? '原任务预设'} · ${starting ? strength.round() : batch.strength}%',
        ),
        const SizedBox(height: 16),
        if (!batch.done) LinearProgressIndicator(value: fraction),
        const SizedBox(height: 10),
        Text('已保存 $completed / ${batch.items.length} 张 · 手机相册'),
        if (batch.failed > 0) Text('${batch.failed} 张未完成，可单独重试'),
        if (actionError != null || batch.recoveryError != null)
          Text(
            actionError ?? batch.recoveryError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 12),
        for (final item in batch.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: photo(item, width: 48, height: 48),
            title: Text(
              item.photo?.name ?? item.row['name'] as String? ?? '照片',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              item.error == null ? item.phase : '未完成 · ${item.error}',
            ),
            trailing: item.receipt != null
                ? const Icon(Icons.check_circle_outline)
                : null,
            onTap: item.output == null ? null : () => showResult(item),
          ),
        if (batch.done)
          TextButton(
            onPressed: () => showResult(
              batch.items.firstWhere((item) => item.output != null),
            ),
            child: const Text('查看结果'),
          ),
        if (!working && !batch.done && batch.recoveryError == null)
          TextButton(onPressed: newTask, child: const Text('新建批量任务')),
        const SizedBox(height: 10),
        Text(
          batch.done ? '原图和原有编辑均保留' : '停止处理后，已完成的照片会保留',
          style: TextStyle(color: p.secondary),
        ),
      ],
    );
  }

  Future<void> showResult(BatchPhoto item) => showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ListenableBuilder(
        listenable: batch,
        builder: (context, _) => batch.accountInvalid
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('账号已改变，照片预览已关闭。'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: InteractiveViewer(
                      child: Image.file(
                        File(item.output!),
                        cacheWidth: 1600,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('照片暂不可用'),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    final available =
        (MediaQuery.sizeOf(context).height -
                MediaQuery.paddingOf(context).vertical -
                24)
            .clamp(120.0, double.infinity);
    return PopScope(
      canPop: !working,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) report(context, '请先停止批量处理，再关闭。');
      },
      child: SizedBox(
        height: math.min(task ? 520 : 720, available),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '批量套用预设',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭批量预设',
                    onPressed: working ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: batch.accountInvalid
                  ? const Center(child: Text('账号已改变，请关闭后重新选择照片。'))
                  : task
                  ? progress(context)
                  : picker(context),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (batch.accountInvalid)
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'),
                    )
                  else if (working)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: starting || batch.stopped
                            ? null
                            : () => unawaited(batch.cancel()),
                        child: const Text('停止处理'),
                      ),
                    )
                  else if (batch.recoveryError != null)
                    FilledButton(
                      onPressed: newTask,
                      child: const Text('新建批量任务'),
                    )
                  else if (batch.done)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('完成'),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const Key('album-batch-preset-run'),
                        onPressed:
                            batch.locked ||
                                selected != null &&
                                    preview.frame != null &&
                                    preview.error == null &&
                                    !preview.busy
                            ? run
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: p.action,
                          foregroundColor: p.onAction,
                          minimumSize: const Size(48, 48),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          batch.locked
                              ? '继续处理未完成项'
                              : '套用并导出 ${batch.items.length} 张',
                        ),
                      ),
                    ),
                  if (!task)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '另存新副本到手机相册',
                        style: TextStyle(color: p.secondary, fontSize: 11),
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
