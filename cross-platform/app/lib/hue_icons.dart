import 'dart:math' as math;

import 'package:flutter/material.dart';

// Original ui/AppIcon.java paths, coordinates, stroke width and round joins.
enum HueIconKind {
  filter,
  exposure,
  contrast,
  saturation,
  temperature,
  brush,
  splitCompare,
  cleanup,
  sort,
  presets,
  album,
  camera,
  settings,
  search,
  plus,
  back,
  adjust,
  more,
  chevron,
  down,
  person,
  wifi,
  usb,
  info,
  help,
  download,
  refresh,
  file,
  close,
  star,
  undo,
  redo,
  compare,
  crop,
  rotate,
  flipHorizontal,
  curve,
  palette,
  frame,
  check,
  edit,
  brightness,
  highlights,
  shadows,
  whites,
  blacks,
  tint,
  vibrance,
  clarity,
  sharpening,
  lumaDenoise,
  colorDenoise,
  grain,
  vignette,
  hsl,
  patch,
  starFilled,
  histogram,
  stack,
  detail,
  grid,
  recipe,
  receipts,
  delete,
  moreVertical,
}

class HueIcon extends StatelessWidget {
  const HueIcon(this.kind, {super.key, this.size = 24, this.color});
  final HueIconKind kind;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _Painter(
          kind,
          color ?? Theme.of(context).colorScheme.onSurface,
        ),
      ),
    ),
  );
}

class _Painter extends CustomPainter {
  const _Painter(this.kind, this.color);
  final HueIconKind kind;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(List<double> p) {
      final path = Path()..moveTo(p[0], p[1]);
      for (var i = 2; i < p.length; i += 2) {
        path.lineTo(p[i], p[i + 1]);
      }
      canvas.drawPath(path, ink);
    }

    void round(double l, double t, double r, double b, double radius) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(l, t, r, b),
            Radius.circular(radius),
          ),
          ink,
        );
    void circle(double x, double y, double r) =>
        canvas.drawCircle(Offset(x, y), r, ink);
    void arc(
      double l,
      double t,
      double r,
      double b,
      double start,
      double sweep,
    ) => canvas.drawArc(
      Rect.fromLTRB(l, t, r, b),
      start * math.pi / 180,
      sweep * math.pi / 180,
      false,
      ink,
    );
    switch (kind) {
      case HueIconKind.filter:
        circle(9, 9, 5.5);
        circle(15, 9, 5.5);
        circle(12, 15, 5.5);
      case HueIconKind.saturation:
        circle(9, 10, 6);
        circle(15, 10, 6);
        circle(12, 16, 6);
      case HueIconKind.brightness:
      case HueIconKind.exposure:
        circle(12, 12, 5);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          line([
            12 + math.cos(a) * 8,
            12 + math.sin(a) * 8,
            12 + math.cos(a) * 10,
            12 + math.sin(a) * 10,
          ]);
        }
        if (kind == HueIconKind.exposure) {
          line([10, 12, 14, 12]);
          line([12, 10, 12, 14]);
        }
      case HueIconKind.contrast:
      case HueIconKind.blacks:
        circle(12, 12, 9);
        canvas.save();
        canvas.clipRect(
          kind == HueIconKind.blacks
              ? const Rect.fromLTRB(3, 3, 12, 21)
              : const Rect.fromLTRB(12, 3, 21, 21),
        );
        ink.style = PaintingStyle.fill;
        circle(12, 12, 8);
        ink.style = PaintingStyle.stroke;
        canvas.restore();
      case HueIconKind.whites:
        circle(11, 13, 7);
        circle(11, 13, 3);
        line([18, 2, 18, 6]);
        line([16, 4, 20, 4]);
      case HueIconKind.highlights:
      case HueIconKind.shadows:
        circle(12, 12, 8);
        for (final y in [8.0, 12.0, 16.0]) {
          line([
            kind == HueIconKind.highlights ? 12 : 6,
            y,
            kind == HueIconKind.highlights ? 18 : 12,
            y,
          ]);
        }
        line([12, 4, 12, 20]);
      case HueIconKind.temperature:
        round(9, 3, 15, 17, 3);
        circle(12, 18, 4);
        line([12, 7, 12, 18]);
      case HueIconKind.tint:
        canvas.drawPath(
          Path()
            ..moveTo(12, 2)
            ..cubicTo(10, 7, 4, 11, 5, 16)
            ..cubicTo(6, 24, 19, 24, 19, 16)
            ..cubicTo(19, 11, 14, 6, 12, 2),
          ink,
        );
      case HueIconKind.vibrance:
        line([12, 3, 21, 20, 3, 20, 12, 3]);
        circle(12, 14, 3);
      case HueIconKind.clarity:
        canvas.drawRect(const Rect.fromLTRB(4, 4, 20, 20), ink);
        line([8, 8, 16, 8, 16, 16, 8, 16, 8, 8]);
      case HueIconKind.sharpening:
        line([12, 3, 21, 21, 3, 21, 12, 3]);
        line([12, 9, 12, 16]);
      case HueIconKind.lumaDenoise:
        for (final point in const [
          Offset(4, 5),
          Offset(8, 8),
          Offset(4, 12),
          Offset(8, 16),
          Offset(4, 20),
        ]) {
          circle(point.dx, point.dy, .55);
        }
        canvas.drawPath(
          Path()
            ..moveTo(12, 19)
            ..cubicTo(21, 18, 12, 6, 21, 5),
          ink,
        );
      case HueIconKind.colorDenoise:
        circle(6, 6, 3);
        circle(16, 6, 3);
        circle(6, 16, 3);
        line([12, 17, 15, 20, 21, 13]);
      case HueIconKind.grain:
        for (var y = 0; y < 4; y++) {
          for (var x = 0; x < 4; x++) {
            canvas.drawCircle(
              Offset(4.5 + x * 5, 4.5 + y * 5),
              (x + y).isEven ? 1.05 : .55,
              Paint()..color = color,
            );
          }
        }
      case HueIconKind.vignette:
        round(3, 4, 21, 20, 3);
        canvas.drawOval(const Rect.fromLTRB(8, 7, 16, 17), ink);
        line([3, 9, 8, 4]);
        line([16, 4, 21, 9]);
        line([3, 15, 8, 20]);
        line([16, 20, 21, 15]);
      case HueIconKind.hsl:
        circle(12, 12, 9);
        circle(12, 12, 2.5);
        for (var i = 0; i < 3; i++) {
          final angle = (-90 + i * 120) * math.pi / 180;
          line([
            12 + math.cos(angle) * 3,
            12 + math.sin(angle) * 3,
            12 + math.cos(angle) * 9,
            12 + math.sin(angle) * 9,
          ]);
        }
      case HueIconKind.patch:
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(-math.pi / 4);
        canvas.translate(-12, -12);
        round(6, 2, 18, 22, 4);
        canvas.drawRect(const Rect.fromLTRB(8, 8, 16, 16), ink);
        circle(10, 5, .5);
        circle(14, 19, .5);
        canvas.restore();
      case HueIconKind.brush:
        line([10, 15, 7, 12, 17, 3, 21, 7, 12, 17, 10, 15]);
        canvas.drawPath(
          Path()
            ..moveTo(7, 14)
            ..cubicTo(2, 14, 6, 20, 2, 21)
            ..cubicTo(8, 23, 12, 19, 9, 16),
          ink,
        );
      case HueIconKind.splitCompare:
        line([12, 3, 12, 21]);
        canvas.drawPath(
          Path()
            ..moveTo(9, 5)
            ..lineTo(5, 5)
            ..quadraticBezierTo(3, 5, 3, 7)
            ..lineTo(3, 17)
            ..quadraticBezierTo(3, 19, 5, 19)
            ..lineTo(9, 19)
            ..moveTo(15, 5)
            ..lineTo(19, 5)
            ..quadraticBezierTo(21, 5, 21, 7)
            ..lineTo(21, 17)
            ..quadraticBezierTo(21, 19, 19, 19)
            ..lineTo(15, 19),
          ink,
        );
        line([16, 9, 19, 12, 16, 15]);
      case HueIconKind.cleanup:
        arc(8, 5, 16, 13, 180, 180);
        line([12, 1, 12, 3]);
        line([4, 5, 6, 6]);
        line([18, 6, 20, 5]);
        line([3, 14, 21, 14]);
        line([5, 18, 19, 18]);
        line([8, 22, 16, 22]);
      case HueIconKind.sort:
        line([8, 21, 8, 3]);
        line([4, 7, 8, 3, 12, 7]);
        line([16, 3, 16, 21]);
        line([12, 17, 16, 21, 20, 17]);
      case HueIconKind.edit:
        final pencil = Path()
          ..moveTo(4, 16)
          ..lineTo(15.7, 4.3)
          ..quadraticBezierTo(17.5, 2.5, 19.3, 4.3)
          ..lineTo(19.7, 4.7)
          ..quadraticBezierTo(21.5, 6.5, 19.7, 8.3)
          ..lineTo(8, 20)
          ..lineTo(3, 21)
          ..close();
        canvas.drawPath(pencil, ink);
        line([14, 6, 18, 10]);
      case HueIconKind.presets:
        round(3, 3, 21, 21, 2);
        circle(8, 8, 1.6);
        line([4, 18, 10, 12, 14, 16, 17, 12, 21, 17]);
      case HueIconKind.album:
        round(6, 6, 22, 22, 2);
        line([3, 17, 2, 17, 2, 2, 17, 2, 17, 3]);
        line([7, 18, 12, 13, 16, 17, 19, 14, 22, 18]);
      case HueIconKind.camera:
        line([3, 7, 7, 7, 9, 4, 15, 4, 17, 7, 21, 7, 21, 21, 3, 21, 3, 7]);
        circle(12, 13, 4);
      case HueIconKind.settings:
        final path = Path();
        for (var t = 0; t < 8; t++) {
          for (var v = 0; v < 4; v++) {
            final a = (-101.25 + t * 45 + v * 11.25) * math.pi / 180,
                r = v < 2 ? 10.0 : 8.0,
                x = 12 + math.cos(a) * r,
                y = 12 + math.sin(a) * r;
            if (t == 0 && v == 0) {
              path.moveTo(x, y);
            } else {
              path.lineTo(x, y);
            }
          }
        }
        path.close();
        canvas.drawPath(path, ink);
        circle(12, 12, 3.2);
      case HueIconKind.search:
        circle(10, 10, 6);
        line([15, 15, 21, 21]);
      case HueIconKind.plus:
        line([12, 5, 12, 19]);
        line([5, 12, 19, 12]);
      case HueIconKind.back:
        line([14, 4, 6, 12, 14, 20]);
        line([6, 12, 22, 12]);
      case HueIconKind.adjust:
        line([3, 6, 21, 6]);
        line([3, 12, 21, 12]);
        line([3, 18, 21, 18]);
        circle(8, 6, 2);
        circle(16, 12, 2);
        circle(9, 18, 2);
      case HueIconKind.more:
        for (final x in [5.0, 12.0, 19.0]) {
          circle(x, 12, 1);
        }
      case HueIconKind.moreVertical:
        for (final y in [5.0, 12.0, 19.0]) {
          circle(12, y, 1);
        }
      case HueIconKind.chevron:
        line([9, 5, 16, 12, 9, 19]);
      case HueIconKind.down:
        line([4, 8, 12, 16, 20, 8]);
      case HueIconKind.person:
        circle(12, 7.5, 4);
        arc(4, 13, 20, 27, 180, 180);
        line([4, 20, 20, 20]);
      case HueIconKind.wifi:
        arc(1, 4, 23, 22, 210, 120);
        arc(5, 9, 19, 21, 215, 110);
        circle(12, 19, 1);
      case HueIconKind.usb:
        line([12, 21, 12, 3]);
        line([9, 6, 12, 3, 15, 6]);
        line([12, 16, 7, 12, 7, 8]);
        line([12, 12, 17, 9, 17, 6]);
        circle(7, 6.5, 1.5);
        canvas.drawRect(const Rect.fromLTRB(15.5, 3, 18.5, 6), ink);
        circle(12, 21, 1.2);
      case HueIconKind.info:
        circle(12, 12, 9);
        circle(12, 7, .1);
        line([12, 11, 12, 17]);
      case HueIconKind.help:
        circle(12, 12, 10);
        arc(8, 6, 16, 14, 190, 210);
        line([12, 13, 12, 15]);
        circle(12, 18, .1);
      case HueIconKind.download:
        line([12, 3, 12, 16]);
        line([7, 11, 12, 16, 17, 11]);
        line([4, 16, 4, 21, 20, 21, 20, 16]);
      case HueIconKind.refresh:
        arc(3.5, 3.5, 20.5, 20.5, 20, 280);
        line([16.25, 4.64, 20.5, 9]);
        line([20.5, 3.5, 20.5, 9, 15, 9]);
      case HueIconKind.file:
        line([5, 2, 14, 2, 20, 8, 20, 22, 5, 22, 5, 2]);
        line([14, 2, 14, 8, 20, 8]);
      case HueIconKind.close:
        line([6, 6, 18, 18]);
        line([18, 6, 6, 18]);
      case HueIconKind.star:
      case HueIconKind.starFilled:
        final path = Path();
        for (var i = 0; i < 10; i++) {
          final a = (-90 + i * 36) * math.pi / 180, r = i.isEven ? 10.0 : 4.5;
          if (i == 0) {
            path.moveTo(12 + math.cos(a) * r, 12 + math.sin(a) * r);
          } else {
            path.lineTo(12 + math.cos(a) * r, 12 + math.sin(a) * r);
          }
        }
        path.close();
        if (kind == HueIconKind.starFilled) ink.style = PaintingStyle.fill;
        canvas.drawPath(path, ink);
      case HueIconKind.histogram:
        line([3, 4, 3, 21, 22, 21]);
        line([7, 17, 7, 12]);
        line([11, 17, 11, 6]);
        line([15, 17, 15, 3]);
        line([19, 17, 19, 10]);
      case HueIconKind.stack:
        round(3, 3, 16, 16, 1.5);
        round(8, 8, 21, 21, 1.5);
      case HueIconKind.detail:
        circle(10, 10, 6);
        line([15, 15, 21, 21]);
        line([7, 10, 13, 10]);
        line([10, 7, 10, 13]);
      case HueIconKind.grid:
        round(3, 3, 10, 10, 1);
        round(14, 3, 21, 10, 1);
        round(3, 14, 10, 21, 1);
        round(14, 14, 21, 21, 1);
      case HueIconKind.recipe:
        round(5, 3, 19, 21, 2);
        line([8, 9, 16, 9]);
        circle(11, 9, 1.5);
        line([8, 15, 16, 15]);
        circle(14, 15, 1.5);
      case HueIconKind.receipts:
        round(3, 3, 21, 21, 3);
        for (final y in [8.0, 12.0, 16.0]) {
          circle(7, y, .1);
          line([11, y, y == 16 ? 15 : 17, y]);
        }
      case HueIconKind.delete:
        line([4, 6, 20, 6]);
        line([9, 6, 9, 3, 15, 3, 15, 6]);
        line([6, 6, 7, 21, 17, 21, 18, 6]);
        line([10, 10, 10, 17]);
        line([14, 10, 14, 17]);
      case HueIconKind.undo:
      case HueIconKind.redo:
        if (kind == HueIconKind.redo) {
          canvas.translate(24, 0);
          canvas.scale(-1, 1);
        }
        arc(3.5, 3.5, 20.5, 20.5, 225, 300);
        line([5.99, 1.89, 5.99, 5.99, 10.09, 5.99]);
      case HueIconKind.compare:
        canvas.drawRect(const Rect.fromLTRB(3, 5, 21, 19), ink);
        line([12, 2, 12, 22]);
      case HueIconKind.crop:
        line([7, 3, 7, 17, 21, 17]);
        line([3, 7, 17, 7, 17, 21]);
      case HueIconKind.curve:
        line([3, 3, 3, 21, 21, 21]);
        canvas.drawPath(
          Path()
            ..moveTo(4, 19)
            ..cubicTo(15, 19, 9, 5, 21, 4),
          ink,
        );
      case HueIconKind.palette:
        round(3, 3, 21, 21, 3);
        line([7, 12, 17, 12]);
        line([12, 7, 12, 17]);
        circle(15.5, 8.5, 2.5);
      case HueIconKind.frame:
        round(3, 3, 21, 21, 2);
        canvas.drawRect(const Rect.fromLTRB(7, 7, 17, 17), ink);
      case HueIconKind.check:
        line([4, 12, 9, 17, 21, 5]);
      case HueIconKind.rotate:
        arc(3, 3, 21, 21, 45, 300);
        line([16, 10, 21, 10, 21, 5]);
        line([12, 7, 17, 12, 12, 17, 7, 12, 12, 7]);
      case HueIconKind.flipHorizontal:
        line([12, 2, 12, 22]);
        line([8, 5, 3, 19, 8, 19, 8, 5]);
        line([16, 5, 21, 19, 16, 19, 16, 5]);
    }
  }

  @override
  bool shouldRepaint(_Painter old) => kind != old.kind || color != old.color;
}
