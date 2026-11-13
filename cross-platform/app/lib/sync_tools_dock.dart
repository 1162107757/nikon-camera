import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'legacy_glass_sheet.dart';

/// Local to the Sync scaffold: no global overlay survives a tab change.
class SyncToolsDock extends StatefulWidget {
  const SyncToolsDock({
    super.key,
    required this.onDownloads,
    required this.onRemote,
    required this.onSlots,
    this.downloadLabel = '下载队列',
    this.downloadActive = false,
  });

  final VoidCallback? onDownloads, onRemote, onSlots;
  final String downloadLabel;
  final bool downloadActive;

  @override
  State<SyncToolsDock> createState() => _SyncToolsDockState();
}

class _SyncToolsDockState extends State<SyncToolsDock> {
  bool expanded = false;

  Widget tool(IconData icon, String label, VoidCallback? callback) => InkWell(
    onTap: callback == null
        ? null
        : () {
            setState(() => expanded = false);
            callback();
          },
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: callback == null
                ? Theme.of(context).disabledColor
                : HuePalette.of(context).ink,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              style: TextStyle(
                color: callback == null
                    ? Theme.of(context).disabledColor
                    : HuePalette.of(context).ink,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return ConstrainedBox(
      key: const Key('sync-tools-dock'),
      constraints: BoxConstraints(
        maxWidth: math.min(232, MediaQuery.sizeOf(context).width - 48),
        maxHeight: math.max(64, MediaQuery.sizeOf(context).height * .65),
      ),
      child: LegacyGlassSheet(
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (expanded)
                Flexible(
                  child: SingleChildScrollView(
                    key: const Key('sync-tools-panel'),
                    child: Column(
                      children: [
                        tool(
                          Icons.downloading_rounded,
                          widget.downloadLabel,
                          widget.onDownloads,
                        ),
                        tool(
                          Icons.camera_alt_outlined,
                          '遥控拍照',
                          widget.onRemote,
                        ),
                        tool(Icons.grid_view_rounded, '相机预设槽位', widget.onSlots),
                        Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: p.outline,
                        ),
                      ],
                    ),
                  ),
                ),
              Semantics(
                expanded: expanded,
                child: InkWell(
                  onTap: () => setState(() => expanded = !expanded),
                  borderRadius: BorderRadius.circular(26),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          expanded ? Icons.close_rounded : Icons.tune_rounded,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('相机工具')),
                        if (widget.downloadActive)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.downloading_rounded,
                              size: 18,
                              color: p.primary,
                            ),
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
    );
  }
}
