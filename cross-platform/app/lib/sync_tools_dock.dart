import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'legacy_glass_sheet.dart';

/// Local to Sync. User-selected B: a 52dp circular glass entry.
class SyncToolsDock extends StatefulWidget {
  const SyncToolsDock({
    super.key,
    required this.onDownloads,
    required this.onRemote,
    required this.onSlots,
    this.downloadActive = false,
    this.downloadRemaining = 0,
  });
  final VoidCallback? onDownloads, onRemote, onSlots;
  final bool downloadActive;
  final int downloadRemaining;
  @override
  State<SyncToolsDock> createState() => _SyncToolsDockState();
}

class _SyncToolsDockState extends State<SyncToolsDock> {
  bool expanded = false;
  Widget tool(
    IconData icon,
    String label,
    String detail,
    VoidCallback? callback,
  ) {
    final p = HuePalette.of(context);
    return InkWell(
      onTap: callback == null
          ? null
          : () {
              setState(() => expanded = false);
              callback();
            },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: callback == null ? Theme.of(context).disabledColor : p.ink,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: callback == null
                          ? Theme.of(context).disabledColor
                          : p.ink,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.4,
                      color: p.secondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: p.secondary),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context),
        remaining = math.max(0, widget.downloadRemaining);
    if (!expanded) {
      return SizedBox(
        key: const Key('sync-tools-dock'),
        width: 52,
        height: 52,
        child: Semantics(
          button: true,
          label: '相机工具${remaining > 0 ? '，$remaining 项下载待完成' : ''}',
          expanded: false,
          child: Tooltip(
            message: '相机工具',
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: LegacyGlassSheet(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => setState(() => expanded = true),
                        child: const Center(
                          child: ExcludeSemantics(
                            child: Icon(Icons.tune_rounded, size: 22),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (remaining > 0)
                  Positioned(
                    right: -2,
                    top: -3,
                    child: IgnorePointer(
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: p.primaryContainer,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.surface, width: 2),
                        ),
                        child: Text(
                          remaining > 99 ? '99+' : '$remaining',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            color: p.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return TapRegion(
      onTapOutside: (_) {
        if (mounted) setState(() => expanded = false);
      },
      child: ConstrainedBox(
        key: const Key('sync-tools-dock'),
        constraints: BoxConstraints(
          maxWidth: math.min(252, MediaQuery.sizeOf(context).width - 32),
          maxHeight: math.max(64, MediaQuery.sizeOf(context).height * .65),
        ),
        child: LegacyGlassSheet(
          child: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              key: const Key('sync-tools-panel'),
              padding: const EdgeInsets.fromLTRB(7, 6, 7, 9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 11, right: 1),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '相机工具',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '收起相机工具',
                          onPressed: () => setState(() => expanded = false),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ),
                  ),
                  tool(
                    Icons.downloading_rounded,
                    '下载队列',
                    remaining > 0
                        ? '$remaining 项待完成${widget.downloadActive ? ' · 正在下载' : ''}'
                        : '暂无进行中的下载',
                    widget.onDownloads,
                  ),
                  tool(
                    Icons.camera_alt_outlined,
                    '遥控拍照',
                    '全屏取景与拍摄',
                    widget.onRemote,
                  ),
                  tool(
                    Icons.grid_view_rounded,
                    '相机预设槽位',
                    '查看与写入 C1–C9',
                    widget.onSlots,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
