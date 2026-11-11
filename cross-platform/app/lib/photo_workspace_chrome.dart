import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PhotoWorkspaceSystemBars extends StatelessWidget {
  const PhotoWorkspaceSystemBars({
    super.key,
    required this.child,
    this.color = const Color(0xff0a0908),
  });
  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle(
      statusBarColor: color,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: color,
      systemNavigationBarDividerColor: color,
      systemNavigationBarIconBrightness: Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarContrastEnforced: false,
    ),
    child: child,
  );
}

/// Matches PhotoPrismaStyle.Backdrop using the same bounded native sample.
class PhotoAtmosphere extends StatelessWidget {
  const PhotoAtmosphere({super.key, this.image});
  final String? image;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: Color(0xff242b27)),
      if (image != null)
        Image.file(
          File(image!),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => const SizedBox(),
        ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x8917221e), Color(0x2b15211d), Color(0x9e131b1b)],
            stops: [0, .48, 1],
          ),
        ),
      ),
    ],
  );
}

class CropRatioIcon extends StatelessWidget {
  const CropRatioIcon(this.ratio, {super.key, required this.color});
  final double ratio;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 30,
    child: CustomPaint(painter: _RatioPainter(ratio == 0 ? .8 : ratio, color)),
  );
}

class _RatioPainter extends CustomPainter {
  const _RatioPainter(this.ratio, this.color);
  final double ratio;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    var h = size.height * .82, w = h * ratio;
    if (w > size.width * .9) {
      w = size.width * .9;
      h = w / ratio;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h),
        const Radius.circular(2),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_RatioPainter old) =>
      ratio != old.ratio || color != old.color;
}
