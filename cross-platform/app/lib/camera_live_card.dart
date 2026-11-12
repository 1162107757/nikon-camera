import 'dart:async';

import 'package:flutter/material.dart';

import 'camera_live.dart';
import 'camera_transfer.dart';
import 'domain.dart';
import 'theme.dart';
import 'widgets.dart';

class CameraLiveCard extends StatefulWidget {
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
  State<CameraLiveCard> createState() => _CameraLiveCardState();
}

class _CameraLiveCardState extends State<CameraLiveCard> {
  bool checking = false;
  Future<void> start() async {
    if (checking) return;
    setState(() => checking = true);
    try {
      final previous = await widget.state.cameraLive.available(
        widget.projectId,
      );
      if (!mounted) return;
      final resume = previous['active'] == true;
      final confirmed = await hueDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(resume ? '继续上次拍摄？' : '开始边拍边传？'),
          content: Text(
            resume
                ? '保留已收照片与收片记录，核对相机后补收未完成的新照片。请保持应用在前台。'
                : '从现在开始接收新拍摄的 JPEG，自动加入此项目。${widget.hasPreset ? '同时另存套用默认预设的成品。' : '未启用自动套用，只保存原图。'}相机中已有的照片不会补收。请保持应用在前台。',
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
      if (confirmed == true && mounted) {
        await widget.state.cameraLive.start(
          widget.projectId,
          widget.projectName,
          resume: resume,
        );
      }
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.state.cameraLive, palette = HuePalette.of(context);
    return AnimatedBuilder(
      animation: live,
      builder: (context, _) {
        final current = live.projectId == widget.projectId;
        final show = live.active || current;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  live.active ? live.title : '边拍边传',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  live.active
                      ? live.projectName
                      : '接收相机新拍的 JPEG，原图自动加入项目。已排队照片保留原设置，默认预设的更改只影响之后的新照片。',
                  style: TextStyle(
                    color: palette.secondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                if (show && (live.active || live.completed > 0)) ...[
                  const SizedBox(height: 8),
                  Text(
                    '已接收 ${live.completed} 张 · 待处理 ${live.queued} 张${live.failed > 0 ? ' · 未完成 ${live.failed} 张' : ''}',
                  ),
                ],
                if (live.active && live.phase == CameraLivePhase.receiving) ...[
                  const SizedBox(height: 8),
                  Text(live.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: live.total > 0 ? live.received / live.total : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${cameraByteCount(live.received)} / ${cameraByteCount(live.total)}',
                  ),
                ] else if (live.active &&
                    (live.phase == CameraLivePhase.starting ||
                        live.phase == CameraLivePhase.importing ||
                        live.phase == CameraLivePhase.processing)) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: live.phase == CameraLivePhase.processing
                        ? live.renderProgress
                        : null,
                  ),
                ],
                if (live.active && live.phase == CameraLivePhase.paused) ...[
                  const SizedBox(height: 8),
                  const Text('返回应用前台后继续发现新照片。'),
                ],
                if (live.active && live.phase == CameraLivePhase.waiting) ...[
                  const SizedBox(height: 8),
                  const Text('重新连接同一台相机后继续，已接收照片保留。'),
                ],
                if (show && live.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    live.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (live.active)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (live.phase == CameraLivePhase.waiting &&
                          widget.onConnect != null)
                        OutlinedButton(
                          onPressed: () => unawaited(widget.onConnect!()),
                          child: const Text('连接相机'),
                        ),
                      if (live.phase == CameraLivePhase.blocked)
                        OutlinedButton(
                          onPressed: () => unawaited(live.retry()),
                          child: const Text('重新核对'),
                        ),
                      OutlinedButton(
                        onPressed: () => unawaited(live.stop()),
                        child: const Text('停止边拍边传'),
                      ),
                    ],
                  )
                else
                  FilledButton(
                    onPressed:
                        widget.enabled &&
                            !checking &&
                            live.phase != CameraLivePhase.stopping &&
                            !live.working
                        ? start
                        : null,
                    child: Text(checking ? '正在核对相机' : '开始边拍边传'),
                  ),
                if (!live.active && !widget.hasPreset) ...[
                  const SizedBox(height: 8),
                  Text(
                    '未启用自动套用，接收的原图会保留。',
                    style: TextStyle(color: palette.secondary, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
