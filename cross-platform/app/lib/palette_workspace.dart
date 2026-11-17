import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hue_icons.dart';

/// Fixed photo/pad layout. Hiding the pad is independent from applying edits.
class PaletteWorkspace extends StatefulWidget {
  const PaletteWorkspace({
    super.key,
    required this.photo,
    required this.controls,
    required this.color,
    required this.tone,
    required this.amount,
    required this.onCancel,
    required this.onApply,
    required this.onReset,
    required this.onTool,
    this.enabled = true,
    this.working = false,
    this.scope = '全图',
    this.onUndo,
    this.onRedo,
    this.onScope,
    this.readouts,
  });

  final Widget photo;
  final Widget Function(
    double padHeight,
    ValueChanged<bool> onGesture,
    bool showReadouts,
  )
  controls;
  final Widget Function(ValueChanged<bool> onGesture)? readouts;
  final ValueChanged<BuildContext>? onScope;
  final int color, tone, amount;
  final VoidCallback onCancel, onApply, onReset;
  final ValueChanged<int> onTool;
  final VoidCallback? onUndo, onRedo;
  final bool enabled, working;
  final String scope;

  @override
  State<PaletteWorkspace> createState() => _PaletteWorkspaceState();
}

class _PaletteWorkspaceState extends State<PaletteWorkspace> {
  bool expanded = true, gesturing = false;
  static const yellow = Color(0xffffe335);
  static const white = Color(0xfff4f5f7);
  static const muted = Color(0xffc8cdca);

  bool get canToggle => widget.enabled && !gesturing;
  void toggle([bool? value]) {
    if (!canToggle || value == expanded) return;
    setState(() => expanded = value ?? !expanded);
  }

  String signed(int value) => value > 0 ? '+$value' : '$value';

  Widget header() => SafeArea(
    top: false,
    bottom: false,
    minimum: const EdgeInsets.symmetric(horizontal: 12),
    child: SizedBox(
      height: 48,
      child: Row(
        children: [
          TextButton(
            onPressed: widget.enabled ? widget.onCancel : null,
            style: actionStyle(),
            child: const Text('取消'),
          ),
          if (widget.onScope != null)
            Builder(
              builder: (anchor) => IconButton(
                key: const Key('palette-scope'),
                tooltip: '涂抹范围，当前${widget.scope}',
                onPressed: widget.enabled
                    ? () => widget.onScope!(anchor)
                    : null,
                icon: HueIcon(
                  HueIconKind.brush,
                  color: widget.scope == '全图' ? muted : yellow,
                ),
              ),
            ),
          Expanded(
            child: Semantics(
              button: true,
              expanded: expanded,
              label: expanded ? '收起调色盘' : '展开调色盘',
              child: InkWell(
                key: const Key('palette-panel-toggle'),
                onTap: canToggle ? () => toggle() : null,
                child: Tooltip(
                  message: expanded ? '收起调色盘' : '展开调色盘',
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            widget.scope == '全图'
                                ? '调色盘'
                                : '调色盘 · ${widget.scope}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_up,
                          color: muted,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          TextButton(
            key: const Key('palette-reset'),
            onPressed: widget.enabled ? widget.onReset : null,
            style: actionStyle(),
            child: const Text('重置'),
          ),
          FilledButton(
            key: const Key('palette-apply'),
            onPressed: widget.enabled ? widget.onApply : null,
            style: FilledButton.styleFrom(
              backgroundColor: yellow,
              foregroundColor: const Color(0xff202923),
              minimumSize: const Size(56, 40),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: widget.working
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('应用'),
          ),
        ],
      ),
    ),
  );

  ButtonStyle actionStyle([Color color = muted]) => TextButton.styleFrom(
    foregroundColor: color,
    minimumSize: const Size(48, 48),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    textStyle: const TextStyle(fontSize: 12),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  Widget toolbar() => SizedBox(
    key: const Key('palette-tools-toolbar'),
    height: 70,
    child: Row(
      children: [
        for (final item in [
          (2, '调色盘', HueIconKind.palette),
          (5, '曲线', HueIconKind.curve),
          (6, 'HSL', HueIconKind.hsl),
          (7, '去灰', HueIconKind.cleanup),
        ])
          Expanded(
            child: Semantics(
              button: true,
              selected: item.$1 == 2,
              label: item.$1 == 2 ? '展开调色盘' : item.$2,
              child: InkWell(
                key: Key('palette-tool-${item.$1}'),
                onTap: !widget.enabled
                    ? null
                    : item.$1 == 2
                    ? () => toggle(true)
                    : () => widget.onTool(item.$1),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 36,
                      height: 34,
                      child: Center(
                        child: HueIcon(
                          item.$3,
                          size: 22,
                          color: item.$1 == 2 ? yellow : white,
                        ),
                      ),
                    ),
                    Text(
                      item.$2,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11,
                        color: item.$1 == 2 ? yellow : white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget collapsedPanel() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      header(),
      Padding(
        key: const Key('palette-collapsed-values'),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Row(
          children: [
            IconButton(
              tooltip: '撤销调色盘',
              onPressed: widget.enabled ? widget.onUndo : null,
              icon: const HueIcon(HueIconKind.undo, color: muted),
            ),
            Expanded(
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  Text(
                    '颜色 ${signed(widget.color)}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  Text(
                    '影调 ${signed(widget.tone)}',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  Text(
                    '强度 ${widget.amount}%',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '重做调色盘',
              onPressed: widget.enabled ? widget.onRedo : null,
              icon: const HueIcon(HueIconKind.redo, color: muted),
            ),
          ],
        ),
      ),
      toolbar(),
    ],
  );

  void gestureChanged(bool value) {
    if (mounted && gesturing != value) setState(() => gesturing = value);
  }

  Widget photo(bool metadataInPhoto) => GestureDetector(
    key: const Key('palette-photo-stage'),
    behavior: HitTestBehavior.translucent,
    onTap: expanded && canToggle ? () => toggle(false) : null,
    child: Column(
      children: [
        Expanded(
          child: KeyedSubtree(
            key: const Key('editor-photo-viewport'),
            child: widget.photo,
          ),
        ),
        if (expanded && metadataInPhoto)
          ColoredBox(
            key: const Key('palette-photo-readouts'),
            color: const Color(0xff18221f),
            child: AbsorbPointer(
              absorbing: !widget.enabled,
              child: widget.readouts!(gestureChanged),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final horizontal =
          bounds.maxWidth >= 640 && bounds.maxWidth > bounds.maxHeight;
      final panelWidth = horizontal
          ? expanded
                ? math.min(390.0, bounds.maxWidth * .46)
                : 330.0
          : bounds.maxWidth;
      final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
      final fieldWidth = math.max(
        1.0,
        panelWidth - 24 - math.max(40.0, 30 * scale) * 2,
      );
      final preferredPad =
          (fieldWidth / 2.1).clamp(96.0, 160.0) +
          math.max(16.0, 10 * scale) * 2;
      final metadataInPhoto =
          horizontal && bounds.maxHeight < 320 && widget.readouts != null;
      final fixedHeight =
          56 + (metadataInPhoto ? 0 : 48) + math.max(48.0, 30 * scale);
      final panelHeight = horizontal
          ? math.min(bounds.maxHeight, preferredPad + fixedHeight)
          : math.min(preferredPad + fixedHeight, bounds.maxHeight * .62);
      final padHeight = math.max(48.0, panelHeight - fixedHeight);
      final panel = expanded
          ? SizedBox(
              key: const Key('palette-expanded-panel'),
              height: panelHeight,
              child: Column(
                children: [
                  header(),
                  widget.controls(padHeight, gestureChanged, !metadataInPhoto),
                ],
              ),
            )
          : collapsedPanel();
      if (horizontal) {
        return Row(
          children: [
            Expanded(child: photo(metadataInPhoto)),
            SizedBox(
              width: panelWidth,
              child: ColoredBox(
                color: const Color(0xff18221f),
                child: Align(
                  alignment: expanded
                      ? Alignment.topCenter
                      : Alignment.bottomCenter,
                  child: panel,
                ),
              ),
            ),
          ],
        );
      }
      return Column(
        children: [
          Expanded(child: photo(false)),
          ColoredBox(color: const Color(0xff18221f), child: panel),
        ],
      );
    },
  );
}
