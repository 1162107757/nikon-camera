import 'package:flutter/material.dart';

import 'theme.dart';

enum PhoneAlbumCategory {
  all('all', '全部', Icons.grid_view_rounded),
  image('image', '图片', Icons.image_outlined),
  live('live', '实况', Icons.motion_photos_on),
  raw('raw', 'RAW', Icons.raw_on_outlined);

  const PhoneAlbumCategory(this.id, this.label, this.icon);
  final String id, label;
  final IconData icon;

  static PhoneAlbumCategory restored(Object? value) =>
      values.firstWhere((category) => category.id == value, orElse: () => all);
}

/// Phone-only filters. One row stays horizontally scrollable at large text sizes.
class PhoneAlbumCategories extends StatefulWidget {
  const PhoneAlbumCategories({
    super.key,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  final PhoneAlbumCategory selected;
  final ValueChanged<PhoneAlbumCategory> onSelected;
  final bool enabled;

  @override
  State<PhoneAlbumCategories> createState() => _PhoneAlbumCategoriesState();
}

class _PhoneAlbumCategoriesState extends State<PhoneAlbumCategories> {
  final keys = {
    for (final item in PhoneAlbumCategory.values) item: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    revealSelected();
  }

  @override
  void didUpdateWidget(PhoneAlbumCategories oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) revealSelected();
  }

  void revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final selectedContext = keys[widget.selected]?.currentContext;
      if (selectedContext != null) {
        Scrollable.ensureVisible(selectedContext, alignment: .5);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return LayoutBuilder(
      builder: (context, bounds) {
        final width =
            ((bounds.maxWidth -
                        40 -
                        (PhoneAlbumCategory.values.length - 1) * 7) /
                    PhoneAlbumCategory.values.length)
                .clamp(60.0, 82.0);
        return SingleChildScrollView(
          key: const ValueKey('phone-album-categories'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (final category in PhoneAlbumCategory.values) ...[
                if (category != PhoneAlbumCategory.all)
                  const SizedBox(width: 7),
                Semantics(
                  selected: category == widget.selected,
                  child: InkWell(
                    key: keys[category],
                    borderRadius: BorderRadius.circular(24),
                    onTap: widget.enabled
                        ? () => widget.onSelected(category)
                        : null,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Center(
                        child: Container(
                          key: ValueKey('category-pill-${category.id}'),
                          constraints: BoxConstraints(minWidth: width),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 7,
                          ),
                          decoration: ShapeDecoration(
                            color: category == widget.selected
                                ? p.ink
                                : p.container,
                            shape: const StadiumBorder(),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PhoneCategoryIcon(
                                category: category,
                                color: !widget.enabled
                                    ? p.secondary
                                    : category == widget.selected
                                    ? p.surface
                                    : p.ink,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                category.label,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.3,
                                  color: !widget.enabled
                                      ? p.secondary
                                      : category == widget.selected
                                      ? p.surface
                                      : p.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The five line symbols in the approved gallery prototype.
class PhoneCategoryIcon extends StatelessWidget {
  const PhoneCategoryIcon({
    super.key,
    required this.category,
    required this.color,
  });
  final PhoneAlbumCategory category;
  final Color color;
  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size(17, 17),
    painter: _CategoryPainter(category, color),
  );
}

class _CategoryPainter extends CustomPainter {
  const _CategoryPainter(this.category, this.color);
  final PhoneAlbumCategory category;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 20);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (category) {
      case PhoneAlbumCategory.all:
        for (final x in [1.5, 11.5]) {
          for (final y in [1.5, 11.5]) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, 7, 7),
                const Radius.circular(1.6),
              ),
              pen,
            );
          }
        }
      case PhoneAlbumCategory.image:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(1.5, 2, 17, 16),
            const Radius.circular(2),
          ),
          pen,
        );
        canvas.drawCircle(const Offset(6.5, 6.5), 1.2, pen);
        canvas.drawPath(
          Path()
            ..moveTo(2, 15)
            ..lineTo(7.5, 10)
            ..lineTo(11, 13)
            ..lineTo(14, 9)
            ..lineTo(18, 13),
          pen,
        );
      case PhoneAlbumCategory.live:
        for (final r in [8.5, 5.5, 2.5]) {
          canvas.drawCircle(const Offset(10, 10), r, pen);
        }
      case PhoneAlbumCategory.raw:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(1, 2, 18, 16),
            const Radius.circular(2),
          ),
          pen,
        );
        final label = TextPainter(
          text: TextSpan(
            text: 'RAW',
            style: TextStyle(
              fontSize: 6.2,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(
          canvas,
          Offset((20 - label.width) / 2, (20 - label.height) / 2),
        );
    }
  }

  @override
  bool shouldRepaint(_CategoryPainter old) =>
      old.category != category || old.color != color;
}
