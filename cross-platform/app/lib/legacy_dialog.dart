import 'package:flutter/material.dart';

import 'theme.dart';

Future<T?> hueChoice<T>({
  required BuildContext context,
  required String title,
  required T selected,
  required List<(T, String)> choices,
}) => showDialog<T>(
  context: context,
  useRootNavigator: true,
  builder: (dialog) =>
      HueChoiceDialog<T>(title: title, selected: selected, choices: choices),
);

/// Geometry and radio marks from the original Android AppDialog.
class HueChoiceDialog<T> extends StatelessWidget {
  const HueChoiceDialog({
    super.key,
    required this.title,
    required this.selected,
    required this.choices,
  });
  final String title;
  final T selected;
  final List<(T, String)> choices;

  @override
  Widget build(BuildContext context) {
    final p = HuePalette(dark: HuePalette.of(context).dark, home: false);
    return Dialog(
      backgroundColor: p.card,
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: p.ink,
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in choices)
                      Semantics(
                        checked: option.$1 == selected,
                        inMutuallyExclusiveGroup: true,
                        child: InkWell(
                          onTap: () => Navigator.pop(context, option.$1),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(20, 8, 24, 8),
                              child: Row(
                                children: [
                                  CustomPaint(
                                    size: const Size(22, 22),
                                    painter: _RadioMark(
                                      p,
                                      option.$1 == selected,
                                    ),
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Text(
                                      option.$2,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.2,
                                        fontWeight: FontWeight.w400,
                                        color: p.ink,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(64, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    foregroundColor: p.secondary,
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadioMark extends CustomPainter {
  const _RadioMark(this.palette, this.selected);
  final HuePalette palette;
  final bool selected;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()..isAntiAlias = true;
    if (selected) {
      canvas.drawCircle(center, 9.5, paint..color = palette.primaryContainer);
      canvas.drawCircle(center, 4, paint..color = palette.onPrimaryContainer);
    } else {
      canvas.drawCircle(
        center,
        10.25,
        paint
          ..color = palette.secondary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RadioMark oldDelegate) =>
      selected != oldDelegate.selected || palette != oldDelegate.palette;
}
