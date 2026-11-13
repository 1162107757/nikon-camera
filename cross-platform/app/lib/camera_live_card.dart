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
    setState(() => checking = true);
    try {
      final previous = await widget.state.cameraLive.available(selectedProject);
      if (!mounted || owner != expectedOwner || selectedProject != selected) {
        return;
      }
      final resume = previous['active'] == true;
      final confirmed = await hueDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(resume ? '继续上次拍摄？' : '开始边拍边传？'),
          content: Text(
            resume
                ? '保留已收照片与收片记录，核对相机后补收未完成的新照片。请保持应用在前台。'
                : '从现在开始接收新拍摄的 JPEG，自动加入此项目。${hasPreset ? '同时另存套用默认预设的成品。' : '未启用自动套用，只保存原图。'}相机中已有的照片不会补收。请保持应用在前台。',
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
          selectedProject == selected) {
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
    if (projectId.isEmpty) return;
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
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
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
                    for (final photo in photos)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.check_circle_outline),
                        title: Text(
                          photo['name'] as String? ?? '原图',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: const Text('原图已加入项目'),
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
                            'done' => '成品已保存',
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
    }
  }

  Future<void> expandPhoto(Photo photo) {
    final expectedOwner = owner;
    return showDialog<void>(
      context: context,
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
              body: valid
                  ? InteractiveViewer(
                      minScale: 1,
                      maxScale: 8,
                      child: Center(
                        child: Image.file(
                          File(photo.path),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Text(
                            '照片暂不可显示',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    )
                  : const Center(
                      child: Text(
                        '账号已改变，请重新打开拍摄项目。',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
            );
          },
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
      final active = live.active;
      final photo = current ? live.latestPhoto : null;
      final progress = live.phase == CameraLivePhase.processing
          ? live.renderProgress
          : live.phase == CameraLivePhase.receiving && live.total > 0
          ? (live.received / live.total).clamp(0.0, 1.0)
          : null;
      final title = active
          ? live.title
          : checking
          ? '正在核对相机'
          : '新照片会显示在这里';
      final receiving =
          active &&
          (live.phase == CameraLivePhase.receiving ||
              live.phase == CameraLivePhase.importing ||
              live.phase == CameraLivePhase.starting ||
              live.phase == CameraLivePhase.processing);
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
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
              IconButton(
                tooltip: '项目接收记录',
                onPressed: selected.isEmpty ? null : records,
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(21),
            child: SizedBox(
              height: (MediaQuery.sizeOf(context).width * .75).clamp(
                180.0,
                280.0,
              ),
              child: ColoredBox(
                color: const Color(0xff1c1c1b),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (photo != null)
                      Image.file(
                        File(photo.path),
                        key: ValueKey(photo.path),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Center(
                          child: Text(
                            '原图已加入项目',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                    else
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 58, 18, 88),
                          child: Text(
                            active && !current
                                ? '正在为 ${live.projectName} 接收照片'
                                : title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xffcad0d8),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 11,
                      top: 11,
                      right: 60,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xdc302b26),
                            borderRadius: BorderRadius.circular(23),
                          ),
                          child: Text(
                            hasPreset ? '默认 · 已启用项目预设' : '默认 · 不使用',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: IconButton(
                        tooltip: '放大当前照片',
                        onPressed: photo == null
                            ? null
                            : () => expandPhoto(photo),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xb82b2621),
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.open_in_full),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xe82b2621),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (progress != null)
                                    Text(
                                      '${(progress * 100).round()}%',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    key: const Key('live-transfer-action'),
                                    onPressed: active
                                        ? live.phase == CameraLivePhase.stopping
                                              ? null
                                              : () => unawaited(live.stop())
                                        : widget.enabled &&
                                              selected.isNotEmpty &&
                                              !checking &&
                                              !live.working &&
                                              live.phase !=
                                                  CameraLivePhase.stopping
                                        ? start
                                        : null,
                                    child: Text(
                                      active ? '停止边拍边传' : '开始边拍边传',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              if (receiving)
                                LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 3,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  current
                      ? '已接收 ${live.completed} 张 · 待处理 ${live.queued} 张${live.failed > 0 ? ' · 未完成 ${live.failed} 张' : ''}'
                      : '接收新拍摄的 JPEG，原图保留在应用相册',
                  style: TextStyle(color: palette.secondary, fontSize: 11),
                  maxLines: 2,
                ),
              ),
              TextButton(
                onPressed: selected.isEmpty ? null : records,
                child: const Text('接收记录'),
              ),
            ],
          ),
          if (current && live.name.isNotEmpty && receiving)
            Text(
              '${cameraByteCount(live.received)} / ${cameraByteCount(live.total)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: palette.secondary),
            ),
          if (current && live.error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                live.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (active && live.phase == CameraLivePhase.waiting) ...[
            const Text('重新连接同一台相机后继续，已接收照片保留。'),
            if (widget.onConnect != null)
              OutlinedButton(
                onPressed: () => unawaited(widget.onConnect!()),
                child: const Text('连接相机'),
              ),
          ],
          if (active && live.phase == CameraLivePhase.blocked)
            OutlinedButton(
              onPressed: live.working ? null : () => unawaited(live.retry()),
              child: const Text('重新核对'),
            ),
          if (active && live.phase == CameraLivePhase.paused)
            const Text('返回应用前台后继续发现新照片。'),
          if (!active)
            Text(
              hasPreset ? '默认预设的更改只影响之后的新照片，已排队照片保留原设置。' : '未启用自动套用，接收的原图会保留。',
              style: TextStyle(
                color: palette.secondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
        ],
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
