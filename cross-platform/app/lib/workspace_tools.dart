import 'dart:math' as math;

import 'package:flutter/material.dart';

const workspaceWhite = Color(0xfff4f5f7),
    workspaceMuted = Color(0xffc8cdca),
    workspaceYellow = Color(0xffffe335);

/// Original PhotoWorkspaceUi authored 24-unit paths (1.6px stroke).
class WorkspaceGlyph extends StatelessWidget {
  const WorkspaceGlyph(
    this.name, {
    super.key,
    this.size = 24,
    this.color = workspaceWhite,
  });
  final String name;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _Glyph(name, color)),
    ),
  );
}

class _Glyph extends CustomPainter {
  const _Glyph(this.name, this.color);
  final String name;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x, double y, double x1, double y1) =>
        canvas.drawLine(Offset(x, y), Offset(x1, y1), ink);
    void path(Path value) => canvas.drawPath(value, ink);
    switch (name) {
      case 'close':
        line(5, 5, 19, 19);
        line(19, 5, 5, 19);
      case 'undo':
      case 'redo':
        if (name == 'redo') {
          canvas.translate(24, 0);
          canvas.scale(-1, 1);
        }
        canvas.drawArc(
          const Rect.fromLTRB(3.5, 3.5, 20.5, 20.5),
          225 * math.pi / 180,
          300 * math.pi / 180,
          false,
          ink,
        );
        line(5.99, 1.89, 5.99, 5.99);
        line(5.99, 5.99, 10.09, 5.99);
      case 'more':
        for (final x in [5.0, 12.0, 19.0]) {
          canvas.drawCircle(Offset(x, 12), .9, ink);
        }
      case 'eye':
        path(
          Path()
            ..moveTo(2, 12)
            ..quadraticBezierTo(12, -1, 22, 12)
            ..quadraticBezierTo(12, 25, 2, 12),
        );
        canvas.drawCircle(const Offset(12, 12), 3, ink);
      case 'brush':
        path(
          Path()
            ..moveTo(8, 14)
            ..lineTo(17, 3)
            ..quadraticBezierTo(19, 1, 21, 3)
            ..quadraticBezierTo(22, 4, 20, 6)
            ..lineTo(11, 17),
        );
        path(
          Path()
            ..moveTo(10.5, 17)
            ..cubicTo(12, 22, 5, 22, 3, 21)
            ..cubicTo(6, 20, 3, 16, 7, 15),
        );
      case 'selection-circle':
      case 'radial':
        canvas.drawCircle(const Offset(12, 12), 8, ink);
      case 'selection-rectangle':
        canvas.drawRect(const Rect.fromLTRB(4, 4, 20, 20), ink);
      case 'linear':
        line(4, 4, 20, 4);
        line(4, 20, 20, 20);
        line(12, 7, 12, 17);
        canvas.drawCircle(const Offset(12, 12), 2.5, ink);
      case 'clone':
        canvas.drawCircle(const Offset(8, 8), 4, ink);
        canvas.drawCircle(const Offset(16, 16), 4, ink);
        line(9, 14, 14, 9);
      case 'fit':
        line(4, 9, 4, 4);
        line(4, 4, 9, 4);
        line(15, 4, 20, 4);
        line(20, 4, 20, 9);
        line(20, 15, 20, 20);
        line(20, 20, 15, 20);
        line(9, 20, 4, 20);
        line(4, 20, 4, 15);
      default:
        canvas.drawCircle(const Offset(12, 12), 8, ink);
        line(8, 12, 16, 12);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Glyph old) => old.name != name || old.color != color;
}

class WorkspaceTool extends StatefulWidget {
  const WorkspaceTool({
    super.key,
    required this.icon,
    required this.tooltip,
    this.label,
    this.selected = false,
    this.onPressed,
    this.width = 48,
    this.height = 48,
  });
  final String icon, tooltip;
  final String? label;
  final bool selected;
  final VoidCallback? onPressed;
  final double width, height;
  @override
  State<WorkspaceTool> createState() => _WorkspaceToolState();
}

class _WorkspaceToolState extends State<WorkspaceTool> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null, labeled = widget.label != null;
    final color = !enabled
        ? workspaceWhite.withAlpha(80)
        : widget.selected || pressed
        ? workspaceYellow
        : workspaceWhite;
    final face = pressed
        ? const Color(0xe62e3827)
        : labeled
        ? widget.selected
              ? const Color(0xe6111713)
              : const Color(0x9c101412)
        : const Color(0x6e0e1513);
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 3.2);
    final circle = Container(
      width: labeled ? 39 : 36,
      height: labeled ? 39 : 36,
      decoration: BoxDecoration(color: face, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: WorkspaceGlyph(widget.icon, size: labeled ? 21 : 24, color: color),
    );
    Widget content = circle;
    if (labeled) {
      content = Padding(
        padding: const EdgeInsets.only(top: 3, bottom: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            circle,
            const SizedBox(height: 4),
            SizedBox(
              height: 24 * scale,
              child: Center(
                child: Text(
                  widget.label!,
                  maxLines: 1,
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.normal,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Semantics(
      label: widget.tooltip,
      button: true,
      enabled: enabled,
      selected: widget.selected,
      child: Tooltip(
        message: widget.tooltip,
        child: InkWell(
          onTap: widget.onPressed,
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(24),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          onHighlightChanged: (value) {
            if (mounted) setState(() => pressed = value);
          },
          child: ExcludeSemantics(
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: Center(child: content),
            ),
          ),
        ),
      ),
    );
  }
}
