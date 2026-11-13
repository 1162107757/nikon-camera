import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hue_icons.dart';

enum EditorMoreAction {
  favourite,
  histogram,
  versions,
  detail,
  allFilters,
  optimize,
  recipes,
  composition,
  copy,
  undoCopy,
  continueDraft,
  resetColour,
  restoreOriginal,
  delete,
}

@immutable
class EditorMoreState {
  const EditorMoreState({
    this.showFavourite = true,
    this.favourite = false,
    this.savingFavourite = false,
    this.histogram = false,
    this.ready = true,
    this.readable = true,
    this.parkedDraft = false,
    this.canDelete = false,
    this.regionName,
  });
  final bool showFavourite, favourite, savingFavourite, histogram, ready;
  final bool readable, parkedDraft, canDelete;
  final String? regionName;
}

@immutable
class EditorMoreEntry {
  const EditorMoreEntry(
    this.action,
    this.title,
    this.icon, {
    this.hint = '',
    this.group = 0,
    this.enabled = true,
    this.checked,
    this.danger = false,
    this.navigation = false,
  });
  final EditorMoreAction action;
  final String title, hint;
  final HueIconKind icon;
  final int group;
  final bool enabled, danger, navigation;
  final bool? checked;
}

List<EditorMoreEntry> editorMoreEntries(
  EditorMoreState state, {
  required HueIconKind Function(EditorMoreAction action) iconFor,
}) {
  EditorMoreEntry item(
    EditorMoreAction action,
    String title, {
    String hint = '',
    int group = 0,
    bool enabled = true,
    bool? checked,
    bool danger = false,
    bool navigation = false,
  }) => EditorMoreEntry(
    action,
    title,
    iconFor(action),
    hint: hint,
    group: group,
    enabled: enabled,
    checked: checked,
    danger: danger,
    navigation: navigation,
  );
  return [
    if (state.showFavourite)
      item(
        EditorMoreAction.favourite,
        state.favourite ? '取消收藏' : '收藏照片',
        enabled: !state.savingFavourite,
      ),
    item(
      EditorMoreAction.histogram,
      '直方图',
      enabled: state.ready,
      checked: state.histogram,
    ),
    item(EditorMoreAction.versions, '照片版本', navigation: true),
    if (state.ready) ...[
      item(EditorMoreAction.detail, '查看细节', navigation: true),
      item(EditorMoreAction.allFilters, '全部滤镜', hint: '在线与我的滤镜'),
      item(EditorMoreAction.optimize, '快速优化', hint: '自然、通透与人像'),
      item(EditorMoreAction.recipes, '照片配方', hint: '保存与应用本机配方'),
      item(EditorMoreAction.composition, '精细构图', hint: '裁切、拉直与透视'),
      item(
        EditorMoreAction.copy,
        '复制调色',
        hint: '用到其他照片',
        group: 1,
        enabled: state.readable,
        navigation: true,
      ),
      item(EditorMoreAction.undoCopy, '撤销复制', hint: '撤回上一次批量调色', group: 1),
      if (state.parkedDraft)
        item(
          EditorMoreAction.continueDraft,
          '继续编辑',
          hint: '恢复这张照片的草稿',
          group: 1,
        ),
      item(
        EditorMoreAction.resetColour,
        '重置调色',
        hint: state.regionName == null
            ? '保留滤镜与人像效果'
            : '仅清除${state.regionName}的调色',
        group: 2,
        enabled: state.readable,
      ),
      item(
        EditorMoreAction.restoreOriginal,
        '还原原图',
        hint: '清除全部编辑，可撤销',
        group: 2,
        enabled: state.readable,
        danger: true,
      ),
    ],
    if (state.canDelete)
      item(EditorMoreAction.delete, '删除照片', group: 3, danger: true),
  ];
}

/// PhotoActionsMenu.java: anchored, unanimated, 280 dp, 16 dp corners.
Future<EditorMoreAction?> showEditorMoreMenu(
  BuildContext anchor, {
  required List<EditorMoreEntry> entries,
  required bool Function() isCurrent,
  Listenable? lifecycle,
}) async {
  if (!anchor.mounted || !isCurrent()) return null;
  final box = anchor.findRenderObject();
  final navigator = Navigator.of(anchor, rootNavigator: true);
  final overlay = navigator.overlay?.context.findRenderObject();
  if (box is! RenderBox || overlay is! RenderBox) return null;
  final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  final route = _EditorMoreRoute(
    anchor: rect,
    entries: entries,
    isValid: isCurrent,
    lifecycle: lifecycle,
  );
  final result = await navigator.push(route);
  return isCurrent() ? result : null;
}

class _EditorMoreRoute extends PopupRoute<EditorMoreAction> {
  _EditorMoreRoute({
    required this.anchor,
    required this.entries,
    required this.isValid,
    this.lifecycle,
  });
  final Rect anchor;
  final List<EditorMoreEntry> entries;
  final bool Function() isValid;
  final Listenable? lifecycle;
  @override
  Color get barrierColor => Colors.transparent;
  @override
  bool get barrierDismissible => true;
  @override
  String get barrierLabel => '关闭照片操作';
  @override
  Duration get transitionDuration => Duration.zero;
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => _EditorMorePopup(route: this);
}

class _EditorMorePopup extends StatefulWidget {
  const _EditorMorePopup({required this.route});
  final _EditorMoreRoute route;
  @override
  State<_EditorMorePopup> createState() => _EditorMorePopupState();
}

class _EditorMorePopupState extends State<_EditorMorePopup> {
  bool closing = false;
  @override
  void initState() {
    super.initState();
    widget.route.lifecycle?.addListener(changed);
  }

  void changed() {
    if (widget.route.isValid() || closing || !mounted) return;
    closing = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.route.isActive) {
        Navigator.of(context).removeRoute(widget.route);
      }
    });
  }

  @override
  void dispose() {
    widget.route.lifecycle?.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (closing || !widget.route.isValid()) return const SizedBox();
    final rows = <Widget>[];
    int? previous;
    for (final entry in widget.route.entries) {
      if (previous != null && previous != entry.group) {
        rows.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: SizedBox(
              height: 1,
              child: ColoredBox(color: Color(0x1af4efe9)),
            ),
          ),
        );
      }
      previous = entry.group;
      rows.add(
        _EditorMoreRow(
          entry: entry,
          onSelected: () {
            if (entry.enabled && widget.route.isValid()) {
              Navigator.pop(context, entry.action);
            }
          },
        ),
      );
    }
    return CustomSingleChildLayout(
      delegate: _MenuPosition(
        widget.route.anchor,
        MediaQuery.paddingOf(context),
        Directionality.of(context),
      ),
      child: Material(
        key: const ValueKey('photo-actions-menu'),
        color: const Color(0xff19211d),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        elevation: 8,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(8),
          child: Column(mainAxisSize: MainAxisSize.min, children: rows),
        ),
      ),
    );
  }
}

class _MenuPosition extends SingleChildLayoutDelegate {
  _MenuPosition(this.anchor, this.safe, this.direction);
  final Rect anchor;
  final EdgeInsets safe;
  final TextDirection direction;
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final width = math.max(48.0, math.min(280.0, constraints.maxWidth - 24));
    final below = constraints.maxHeight - safe.bottom - anchor.bottom - 6;
    final above = anchor.top - safe.top - 6;
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(48.0, math.max(below, above)),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = size.height - safe.bottom - anchor.bottom - 6;
    final above = anchor.top - safe.top - 6;
    final x = direction == TextDirection.rtl
        ? anchor.right - childSize.width
        : anchor.left;
    final y = below >= childSize.height || below >= above
        ? anchor.bottom + 6
        : anchor.top - 6 - childSize.height;
    return Offset(
      x.clamp(12, math.max(12.0, size.width - childSize.width - 12)),
      y.clamp(
        safe.top,
        math.max(safe.top, size.height - safe.bottom - childSize.height),
      ),
    );
  }

  @override
  bool shouldRelayout(_MenuPosition oldDelegate) =>
      anchor != oldDelegate.anchor ||
      safe != oldDelegate.safe ||
      direction != oldDelegate.direction;
}

class _EditorMoreRow extends StatefulWidget {
  const _EditorMoreRow({required this.entry, required this.onSelected});
  final EditorMoreEntry entry;
  final VoidCallback onSelected;
  @override
  State<_EditorMoreRow> createState() => _EditorMoreRowState();
}

class _EditorMoreRowState extends State<_EditorMoreRow> {
  bool focused = false;
  EditorMoreEntry get entry => widget.entry;
  VoidCallback get onSelected => widget.onSelected;
  @override
  Widget build(BuildContext context) {
    const text = Color(0xfff4f5f7),
        muted = Color(0xffc8cdca),
        yellow = Color(0xffffe335),
        danger = Color(0xffedaaa3);
    final foreground = entry.danger
        ? danger
        : entry.checked == true
        ? yellow
        : text;
    return Semantics(
      label: '${entry.title}${entry.hint.isEmpty ? '' : '，${entry.hint}'}',
      button: true,
      enabled: entry.enabled,
      checked: entry.checked,
      excludeSemantics: true,
      onTap: entry.enabled ? onSelected : null,
      child: Opacity(
        opacity: entry.enabled ? 1 : .4,
        child: InkWell(
          key: ValueKey('photo-action-${entry.action.name}'),
          borderRadius: BorderRadius.circular(10),
          splashColor: const Color(0x22ffe335),
          focusColor: const Color(0x18ffe335),
          onTap: entry.enabled ? onSelected : null,
          onFocusChange: (value) => setState(() => focused = value),
          child: Container(
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: focused ? Border.all(color: yellow) : null,
            ),
            constraints: BoxConstraints(
              minHeight: entry.hint.isEmpty ? 48 : 56,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  HueIcon(
                    entry.icon,
                    size: 20,
                    color: entry.danger ? danger : muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          maxLines: 2,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (entry.hint.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            entry.hint,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: entry.checked == true
                        ? const HueIcon(
                            HueIconKind.check,
                            size: 18,
                            color: yellow,
                          )
                        : entry.navigation
                        ? const HueIcon(
                            HueIconKind.chevron,
                            size: 18,
                            color: muted,
                          )
                        : null,
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

/// AlbumPanel's 48 dp header target, 6 dp inset disk and 20 dp original glyph.
class EditorHeaderButton extends StatefulWidget {
  const EditorHeaderButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
  });
  final HueIconKind icon;
  final String label;
  final VoidCallback? onPressed;
  @override
  State<EditorHeaderButton> createState() => _EditorHeaderButtonState();
}

class _EditorHeaderButtonState extends State<EditorHeaderButton> {
  bool pressed = false, focused = false;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.onPressed != null,
    label: widget.label,
    excludeSemantics: true,
    onTap: widget.onPressed,
    child: Tooltip(
      message: widget.label,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onPressed,
            onHighlightChanged: (value) => setState(() => pressed = value),
            onFocusChange: (value) => setState(() => focused = value),
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            focusColor: Colors.transparent,
            child: Center(
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: pressed
                      ? const Color(0xc9233028)
                      : focused
                      ? const Color(0xc93a4231)
                      : const Color(0x6e0e1513),
                  border: focused
                      ? Border.all(color: const Color(0xffffe335))
                      : null,
                ),
                child: HueIcon(
                  widget.icon,
                  size: 20,
                  color: widget.onPressed == null
                      ? const Color(0x4df4f5f7)
                      : const Color(0xfff4f5f7),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class EditorMiddleTitle extends StatelessWidget {
  const EditorMiddleTitle(this.text, {super.key, required this.style});
  final String text;
  final TextStyle style;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final direction = Directionality.of(context),
          scaler = MediaQuery.textScalerOf(context);
      bool fits(String value) {
        final painter = TextPainter(
          text: TextSpan(text: value, style: style),
          textDirection: direction,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final result = painter.width <= bounds.maxWidth;
        painter.dispose();
        return result;
      }

      var label = text;
      if (!fits(label)) {
        final points = text.runes.toList();
        var low = 0, high = points.length;
        while (low < high) {
          final count = (low + high + 1) ~/ 2;
          final first = (count + 1) ~/ 2, last = count ~/ 2;
          final value =
              '${String.fromCharCodes(points.take(first))}…${String.fromCharCodes(points.skip(points.length - last))}';
          if (fits(value)) {
            low = count;
          } else {
            high = count - 1;
          }
        }
        final first = (low + 1) ~/ 2, last = low ~/ 2;
        label =
            '${String.fromCharCodes(points.take(first))}…${String.fromCharCodes(points.skip(points.length - last))}';
      }
      return Semantics(
        label: text,
        excludeSemantics: true,
        child: Tooltip(
          message: text,
          child: Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: style,
          ),
        ),
      );
    },
  );
}
