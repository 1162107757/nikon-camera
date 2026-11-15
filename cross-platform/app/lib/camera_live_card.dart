import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'camera_live.dart';
import 'camera_transfer.dart';
import 'domain.dart';
import 'theme.dart';
import 'widgets.dart';

/// Compatibility entry used by the project page; the content is also embeddable
/// directly in the Sync host without adding a nested scrolling surface.
class CameraLiveCard extends StatelessWidget {
  const CameraLiveCard({
    super.key,
    required this.state,
    required this.projectId,
    required this.projectName,
    required this.hasPreset,
    this.enabled = true,
    this.onConnect,
  });
  final AppState state;
  final String projectId, projectName;
  final bool hasPreset, enabled;
  final Future<void> Function()? onConnect;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Colors.transparent,
    child: CameraLivePanel(
      state: state,
      projectId: projectId,
      projectName: projectName,
      hasPreset: hasPreset,
      enabled: enabled,
      onConnect: onConnect,
    ),
  );
}

class CameraLivePanel extends StatefulWidget {
  const CameraLivePanel({
    super.key,
    required this.state,
    this.projectId = '',
    this.projectName = '',
    this.hasPreset = false,
    this.enabled = true,
    this.onConnect,
    this.embedded = true,
  });
  final AppState state;
  final String projectId, projectName;
  final bool hasPreset, enabled, embedded;
  final Future<void> Function()? onConnect;
  @override
  State<CameraLivePanel> createState() => _CameraLivePanelState();
}

class _CameraLivePanelState extends State<CameraLivePanel> {
  bool checking = false;
  bool recordsOpening = false;
  String get selected => widget.projectId.isNotEmpty
      ? widget.projectId
      : widget.state.cameraLive.projectId;
  String get label => widget.projectId.isNotEmpty
      ? widget.projectName
      : widget.state.cameraLive.projectName;
  String get owner => widget.state.session['user']?['id'] as String? ?? '';
  bool get hasPreset => widget.hasPreset;

  Future<void> start() async {
    if (checking || selected.isEmpty) return;
    final selectedProject = selected, expectedOwner = owner;
    final live = widget.state.cameraLive,
        format = widget.state.cameraLive.selectedFormat;
    final formatLabel = format == CameraLiveFormat.raw ? 'RAW 原片' : 'JPEG';
    setState(() => checking = true);
    try {
      final previous = await widget.state.cameraLive.available(selectedProject);
      if (!mounted ||
          owner != expectedOwner ||
          selectedProject != selected ||
          live.selectedFormat != format) {
        return;
      }
      final resume = previous['active'] == true;
      final previousFormat = previous['format'] == 'raw'
          ? CameraLiveFormat.raw
          : CameraLiveFormat.jpeg;
      if (resume && previousFormat != format) {
        final previousLabel = previousFormat == CameraLiveFormat.raw
            ? 'RAW 原片'
            : 'JPEG';
        await hueDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('上次接收格式不同'),
            content: Text(
              '上次任务接收 $previousLabel，当前选择 $formatLabel。请先选择 $previousLabel 继续并停止上次任务，再切换格式开始。已接收的照片会保留。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }
      final confirmed = await hueDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(resume ? '继续上次拍摄？' : '开始边拍边传？'),
          content: Text(
            resume
                ? '继续接收 $formatLabel，保留已收照片与收片记录，核对相机后补收未完成的新照片。请保持应用在前台。'
                : '从现在开始接收新拍摄的 $formatLabel，自动加入此项目。${hasPreset ? '同时另存套用默认预设的成品。' : '未启用自动套用，只保存原图。'}相机中已有的照片不会补收。请保持应用在前台。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(resume ? '继续拍摄' : '开始拍摄'),
            ),
          ],
        ),
      );
      if (confirmed == true &&
          mounted &&
          owner == expectedOwner &&
          selectedProject == selected &&
          live.selectedFormat == format) {
        await widget.state.cameraLive.start(
          selectedProject,
          label,
          resume: resume,
        );
      }
    } catch (failure) {
      if (mounted && owner == expectedOwner) report(context, failure);
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> records() async {
    final expectedOwner = owner, projectId = selected;
    if (projectId.isEmpty || recordsOpening) return;
    setState(() => recordsOpening = true);
    try {
      final project = await widget.state.core.call('project.open', {
        'owner': expectedOwner,
        'projectId': projectId,
      });
      if (!mounted ||
          owner != expectedOwner ||
          selected != projectId ||
          widget.state.session['logoutPending'] == true) {
        return;
      }
      final photos = (project['photos'] as List? ?? []).map(object).toList();
      final tasks = (project['tasks'] as List? ?? []).map(object).toList();
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          top: false,
          key: const Key('live-transfer-records-sheet'),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .8,
            ),
            child: AnimatedBuilder(
              animation: widget.state,
              builder: (context, _) {
                if (owner != expectedOwner ||
                    widget.state.session['logoutPending'] == true) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('账号已改变，请重新打开拍摄项目。'),
                  );
                }
                return ListView(
                  key: const Key('live-transfer-records-list'),
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    const Text(
                      '接收记录',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(project['name'] as String? ?? label),
                    if (photos.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('此项目尚无已接收照片。'),
                      ),
                    for (var index = 0; index < photos.length; index++)
                      ListTile(
                        key: ValueKey('live-record-photo-$index'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(
                          photos[index]['name'] as String? ?? '原图',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: const Text('原图已加入项目'),
                        onTap:
                            photos[index]['path'] is! String ||
                                (photos[index]['path'] as String).isEmpty
                            ? null
                            : () {
                                if (owner != expectedOwner ||
                                    widget.state.session['logoutPending'] ==
                                        true) {
                                  return;
                                }
                                final row = photos[index];
                                final photo = Photo(
                                  row['path'] as String,
                                  row['name'] as String? ?? '原图',
                                  row,
                                );
                                final latest =
                                    widget.state.cameraLive.latestPhoto;
                                unawaited(
                                  expandPhoto(
                                    photo,
                                    previewPath: latest?.path == photo.path
                                        ? widget
                                              .state
                                              .cameraLive
                                              .latestPreviewPath
                                        : null,
                                  ),
                                );
                              },
                      ),
                    if (tasks.isNotEmpty) ...[
                      const Divider(),
                      const Text('默认预设处理'),
                      for (final task in tasks)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            task['name'] as String? ?? '照片',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(switch (task['status']) {
                            'queued' => '等待套用',
                            'done' || 'saved' => '成品已保存',
                            'error' => task['error'] as String? ?? '处理未完成',
                            _ => '正在核对处理记录',
                          }),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      );
    } catch (failure) {
      if (mounted && owner == expectedOwner) report(context, failure);
    } finally {
      if (mounted) setState(() => recordsOpening = false);
    }
  }

  bool isRaw(Photo photo) =>
      photo.info['raw'] == true ||
      RegExp(
        r'\.(nef|nrw|dng|arw|cr2|cr3|raf|rw2|orf)$',
        caseSensitive: false,
      ).hasMatch(photo.name);

  Future<void> expandPhoto(Photo photo, {String? previewPath}) {
    final expectedOwner = owner;
    final raw = isRaw(photo);
    final image =
        previewPath ??
        (raw ? photo.info['thumbnailPath'] as String? : photo.path);
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) => Dialog.fullscreen(
        child: AnimatedBuilder(
          animation: widget.state,
          builder: (context, _) {
            final valid =
                owner == expectedOwner &&
                widget.state.session['logoutPending'] != true;
            return Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(valid ? photo.name : '拍摄照片'),
              ),
              body: valid && image != null
                  ? InteractiveViewer(
                      minScale: 1,
                      maxScale: 8,
                      child: Center(
                        child: Image.file(
                          File(image),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Text(
                            '预览暂不可用，原图已保留',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        valid ? 'RAW 原片已保存，预览暂不可用' : '账号已改变，请重新打开拍摄项目。',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }

  Widget action(CameraLive live, {bool large = false}) {
    final stopping = live.phase == CameraLivePhase.stopping;
    final reconnect = live.transportRetired;
    final enabled = reconnect
        ? widget.onConnect != null && !checking
        : live.active
        ? !stopping
        : widget.enabled &&
              selected.isNotEmpty &&
              !checking &&
              !live.working &&
              !stopping;
    final palette = HuePalette.of(context);
    return FilledButton(
      key: const Key('live-transfer-action'),
      onPressed: !enabled
          ? null
          : reconnect
          ? () => unawaited(widget.onConnect!())
          : live.active
          ? () => unawaited(live.stop())
          : start,
      style: FilledButton.styleFrom(
        minimumSize: Size(double.infinity, large ? 68 : 48),
        padding: EdgeInsets.symmetric(
          horizontal: large ? 20 : 16,
          vertical: large ? 14 : 10,
        ),
        backgroundColor: live.active
            ? palette.ink.withValues(alpha: .07)
            : palette.primaryContainer,
        foregroundColor: live.active ? palette.ink : palette.onPrimaryContainer,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (checking || stopping)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              reconnect
                  ? Icons.link_rounded
                  : live.active
                  ? Icons.stop_rounded
                  : Icons.play_arrow_rounded,
              size: large ? 32 : 24,
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              reconnect
                  ? '连接相机'
                  : stopping
                  ? '正在停止边拍边传'
                  : live.active
                  ? '停止边拍边传'
                  : '开始边拍边传',
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: large ? 20 : 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget preview(CameraLive live, Photo? photo, bool current, double height) {
    final palette = HuePalette.of(context);
    final image = photo == null ? null : live.latestPreviewPath;
    final raw = photo != null && isRaw(photo);
    final idle = !live.active && photo == null;
    final title = live.transportRetired
        ? '相机已断开'
        : live.active
        ? live.title
        : '边拍边传已停止';
    return SizedBox(
      key: const Key('live-transfer-preview'),
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: ColoredBox(
          color: palette.ink.withValues(alpha: .055),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                Image.file(
                  File(image),
                  key: ValueKey(image),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        raw ? 'RAW 原片已保存，预览暂不可用' : '预览暂不可用，原图已保留',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                )
              else if (!idle)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          raw ? Icons.raw_on : Icons.camera_alt_outlined,
                          size: 44,
                          color: palette.secondary,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          photo != null
                              ? raw
                                    ? 'RAW 原片已保存，预览暂不可用'
                                    : '原图已保存，预览暂不可用'
                              : !current && live.active
                              ? '正在为 ${live.projectName} 接收照片'
                              : title,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.secondary),
                        ),
                      ],
                    ),
                  ),
                ),
              if (idle) ...[
                Positioned(
                  left: 0,
                  right: 0,
                  top: 20,
                  child: Icon(
                    Icons.camera_alt_outlined,
                    size: 44,
                    color: palette.secondary,
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: action(live, large: true),
                  ),
                ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 18,
                  child: Text(
                    live.transportRetired ? '重新连接后可继续，已收照片保留' : '拍摄后自动接收新照片',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: palette.secondary),
                  ),
                ),
              ],
              if (!idle)
                Positioned(
                  left: 12,
                  top: 12,
                  right: photo == null ? 12 : 60,
                  child: Row(
                    children: [
                      Flexible(
                        flex: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: live.active
                                ? const Color(0xe63e7251)
                                : const Color(0xcc33312b),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (photo != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 4,
                          child: Text(
                            photo.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (photo != null)
                Positioned(
                  right: 8,
                  top: 8,
                  child: IconButton(
                    tooltip: '放大当前照片',
                    onPressed: () => expandPhoto(photo, previewPath: image),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xb82b2621),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.open_in_full),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([widget.state.cameraLive, widget.state]),
    builder: (context, _) {
      final live = widget.state.cameraLive, palette = HuePalette.of(context);
      final current = live.projectId == selected && live.owner == owner;
      final photo = current ? live.latestPhoto : null;
      final raw = live.selectedFormat == CameraLiveFormat.raw;
      final locked =
          checking ||
          live.active ||
          live.working ||
          live.phase == CameraLivePhase.starting ||
          live.phase == CameraLivePhase.stopping;
      final receiving =
          live.active &&
          {
            CameraLivePhase.starting,
            CameraLivePhase.receiving,
            CameraLivePhase.importing,
            CameraLivePhase.processing,
          }.contains(live.phase);
      final progress = live.phase == CameraLivePhase.processing
          ? live.renderProgress
          : live.phase == CameraLivePhase.receiving && live.total > 0
          ? (live.received / live.total).clamp(0.0, 1.0)
          : null;
      final content = LayoutBuilder(
        builder: (context, bounds) {
          final scale = MediaQuery.textScalerOf(context)
              .scale(1)
              .clamp(1.0, 2.0);
          final minimumHeight = 220 + (scale - 1) * 60;
          final height = (bounds.maxWidth * .75)
              .clamp(minimumHeight, 280.0)
              .toDouble();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 22,
                    color: palette.secondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label.isEmpty ? '选择拍摄项目' : label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: '项目接收记录',
                    child: TextButton.icon(
                      key: const Key('live-transfer-records'),
                      onPressed: selected.isEmpty || recordsOpening
                          ? null
                          : records,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 48),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(
                        Icons.format_list_bulleted_rounded,
                        size: 20,
                      ),
                      label: const Text('接收记录'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '传输格式',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              SegmentedButton<CameraLiveFormat>(
                key: const Key('live-transfer-format'),
                segments: const [
                  ButtonSegment(
                    value: CameraLiveFormat.jpeg,
                    label: Text('JPEG'),
                  ),
                  ButtonSegment(
                    value: CameraLiveFormat.raw,
                    label: Text('RAW 原片'),
                  ),
                ],
                selected: {live.selectedFormat},
                showSelectedIcon: false,
                onSelectionChanged: locked
                    ? null
                    : (selection) {
                        if (selection.length == 1) {
                          live.selectFormat(selection.single);
                        }
                      },
                style: ButtonStyle(
                  minimumSize: const WidgetStatePropertyAll(Size(44, 48)),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? palette.primaryContainer.withValues(
                            alpha: states.contains(WidgetState.disabled)
                                ? .65
                                : 1,
                          )
                        : Colors.transparent,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? palette.onPrimaryContainer
                        : states.contains(WidgetState.disabled)
                        ? palette.secondary
                        : palette.ink,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                raw ? '保留 RAW 原片，可稍后显影' : 'JPEG 适合快速预览',
                style: TextStyle(fontSize: 12, color: palette.secondary),
              ),
              const SizedBox(height: 12),
              preview(live, photo, current, height),
              if (live.active || photo != null) ...[
                const SizedBox(height: 8),
                action(live),
              ],
              if (receiving) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress, minHeight: 3),
              ],
              const SizedBox(height: 8),
              Text(
                current
                    ? '已接收 ${live.completed} 张 · 待处理 ${live.queued} 张${live.failed > 0 ? ' · 未完成 ${live.failed} 张' : ''}'
                    : '接收新拍摄的 ${raw ? 'RAW 原片' : 'JPEG'}，原图保留在应用相册',
                maxLines: 2,
                style: TextStyle(color: palette.secondary, fontSize: 12),
              ),
              if (current && live.name.isNotEmpty && receiving)
                Text(
                  '${cameraByteCount(live.received)} / ${cameraByteCount(live.total)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: palette.secondary),
                ),
              if (live.formatNotice != null) ...[
                const SizedBox(height: 8),
                Text(
                  live.formatNotice!,
                  style: TextStyle(fontSize: 12, color: palette.secondary),
                ),
              ],
              if (current && live.error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    live.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (live.active && live.phase == CameraLivePhase.waiting) ...[
                const Text('重新连接同一台相机后继续，已接收照片保留。'),
                if (widget.onConnect != null)
                  OutlinedButton(
                    onPressed: () => unawaited(widget.onConnect!()),
                    child: const Text('连接相机'),
                  ),
              ],
              if (live.active && live.phase == CameraLivePhase.blocked)
                OutlinedButton(
                  onPressed: live.working
                      ? null
                      : () => unawaited(live.retry()),
                  child: const Text('重新核对'),
                ),
              if (live.active && live.phase == CameraLivePhase.paused)
                const Text('返回应用前台后继续发现新照片。'),
              if (!live.active) ...[
                const SizedBox(height: 8),
                Text(
                  hasPreset
                      ? '默认预设的更改只影响之后的新照片，已排队照片保留原设置。'
                      : '未启用自动套用，接收的原图会保留。',
                  style: TextStyle(
                    color: palette.secondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          );
        },
      );
      if (!widget.embedded) {
        return Scaffold(
          appBar: AppBar(title: const Text('边拍边传')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: content,
            ),
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: content,
      );
    },
  );
}
