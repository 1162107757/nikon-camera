import 'package:flutter/material.dart';

import 'theme.dart';

enum PresetContextAction { pin, remove }

/// Presents actions only. The caller owns persistence and deletion confirmation.
Future<PresetContextAction?> showPresetContextMenu({
  required BuildContext context,
  required String presetName,
  required bool pinned,
}) {
  final theme = Theme.of(context);
  final p = HuePalette.of(context);
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  var closing = false;
  return showGeneralDialog<PresetContextAction>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: '关闭预设操作',
    barrierColor: Colors.black.withValues(alpha: p.dark ? .4 : .2),
    transitionDuration: reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 160),
    pageBuilder: (dialog, _, _) {
      void finish(PresetContextAction? action) {
        if (closing ||
            !dialog.mounted ||
            ModalRoute.of(dialog)?.isCurrent != true) {
          return;
        }
        closing = true;
        Navigator.pop(dialog, action);
      }

      return Theme(
        data: theme,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 360,
                    maxHeight: (constraints.maxHeight - 24).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child: _PresetContextMenu(
                    presetName: presetName,
                    pinned: pinned,
                    onAction: finish,
                    onClose: () => finish(null),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (_, animation, _, child) {
      final curve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, .035),
            end: Offset.zero,
          ).animate(curve),
          child: child,
        ),
      );
    },
  );
}

class _PresetContextMenu extends StatelessWidget {
  const _PresetContextMenu({
    required this.presetName,
    required this.pinned,
    required this.onAction,
    required this.onClose,
  });

  final String presetName;
  final bool pinned;
  final ValueChanged<PresetContextAction> onAction;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    final deleteColor = Theme.of(context).colorScheme.error;
    return Material(
      key: const ValueKey('preset-context-menu'),
      color: p.card,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: p.dark ? .3 : .14),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      presetName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: p.secondary,
                      ),
                    ),
                  ),
                  HueIconButton(
                    kind: HueIconKind.close,
                    label: '关闭预设操作',
                    disc: false,
                    iconSize: 18,
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            _ActionRow(
              key: const ValueKey('preset-context-pin-action'),
              label: pinned ? '取消置顶' : '置顶',
              color: p.ink,
              icon: ExcludeSemantics(
                child: CustomPaint(
                  size: const Size.square(20),
                  painter: _PinPainter(color: p.ink, unpin: pinned),
                ),
              ),
              onTap: () => onAction(PresetContextAction.pin),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 1, thickness: 1, color: p.outline),
            ),
            _ActionRow(
              key: const ValueKey('preset-context-remove-action'),
              label: '删除',
              color: deleteColor,
              icon: HueIcon(HueIconKind.delete, size: 20, color: deleteColor),
              onTap: () => onAction(PresetContextAction.remove),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    super.key,
    required this.label,
    required this.color,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final Color color;
  final Widget icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox.square(dimension: 20, child: icon),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Shares the original icon system's 24-unit grid, 1.8 stroke and round caps.
class _PinPainter extends CustomPainter {
  const _PinPainter({required this.color, required this.unpin});
  final Color color;
  final bool unpin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(8, 3)
        ..lineTo(16, 3)
        ..moveTo(9, 3)
        ..lineTo(9, 10)
        ..lineTo(6, 14)
        ..lineTo(18, 14)
        ..lineTo(15, 10)
        ..lineTo(15, 3)
        ..moveTo(12, 14)
        ..lineTo(12, 21),
      paint,
    );
    if (unpin) canvas.drawLine(const Offset(3, 3), const Offset(21, 21), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PinPainter old) =>
      old.color != color || old.unpin != unpin;
}
