import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'retouch_original_controls.dart' show retouchOriginalPhotoFrame;

/// A temporary size guide, controlled entirely by the owning editing tool.
///
/// Put this in a Positioned.fill beside the matching photo stage. [center] is
/// the last valid normalized image point; null uses the visible photo's center.
/// [radius] is relative to the original image's shorter edge, just like patch
/// and retouch brushes. Nothing here edits pixels or receives pointer events.
class RetouchBrushPreview extends StatelessWidget {
  const RetouchBrushPreview({
    super.key,
    required this.imageWidth,
    required this.imageHeight,
    required this.controller,
    required this.radius,
    this.center,
    this.visible = true,
    this.reserveBars = false,
    this.clampToBounds = true,
    this.keepVisible = false,
    this.color = const Color(0xfff4f5f7),
    this.outlineColor = const Color(0xcc000000),
  });

  final double imageWidth, imageHeight, radius;
  final TransformationController controller;
  final Offset? center;
  final bool visible, reserveBars;

  /// Shared photo navigation already resolves the exact source anchor.
  /// Standalone previews retain the original bounded-pan default.
  final bool clampToBounds;

  /// For size-slider feedback only: keep the display guide inside the visible
  /// photo where it fits. This never changes [center] or an actual stroke point.
  final bool keepVisible;
  final Color color, outlineColor;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.expand();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            if (!size.isFinite || size.isEmpty) {
              return const SizedBox.shrink();
            }
            final top = reserveBars ? math.min(48.0, size.height) : 0.0;
            final viewport = Rect.fromLTRB(
              0,
              top,
              size.width,
              reserveBars ? math.max(top, size.height - 48) : size.height,
            );
            return ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final frame = retouchOriginalPhotoFrame(
                  viewport: size,
                  imageWidth: imageWidth,
                  imageHeight: imageHeight,
                  transform: controller.value,
                  reserveBars: reserveBars,
                  clampToBounds: clampToBounds,
                );
                final geometry = RetouchBrushPreviewGeometry.resolve(
                  photoFrame: frame,
                  viewport: viewport,
                  radius: radius,
                  center: center,
                  keepVisible: keepVisible,
                );
                return ClipRect(
                  child: CustomPaint(
                    size: size,
                    painter: RetouchBrushPreviewPainter(
                      geometry: geometry,
                      color: color,
                      outlineColor: outlineColor,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Projection shared by tests and callers that already have an image frame.
@immutable
class RetouchBrushPreviewGeometry {
  const RetouchBrushPreviewGeometry._({
    required this.center,
    required this.normalizedCenter,
    required this.radius,
    required this.clip,
  });

  /// Center and radius in the preview widget's logical pixels.
  final Offset center;
  final double radius;

  /// The requested image point, including when the sizing guide is displaced
  /// to stay visible. Callers continue to own the actual stroke coordinates.
  final Offset normalizedCenter;
  final Rect clip;

  static RetouchBrushPreviewGeometry? resolve({
    required Rect photoFrame,
    required Rect viewport,
    required double radius,
    Offset? center,
    bool keepVisible = false,
  }) {
    if (!photoFrame.isFinite ||
        !photoFrame.size.isFinite ||
        photoFrame.isEmpty ||
        !viewport.isFinite ||
        !viewport.size.isFinite ||
        viewport.isEmpty ||
        !radius.isFinite ||
        radius <= 0) {
      return null;
    }
    final clip = photoFrame.intersect(viewport);
    if (clip.isEmpty) return null;
    final validPoint =
        center != null &&
        center.isFinite &&
        center.dx >= 0 &&
        center.dx <= 1 &&
        center.dy >= 0 &&
        center.dy <= 1;
    final anchor = validPoint
        ? Offset(
            photoFrame.left + center.dx * photoFrame.width,
            photoFrame.top + center.dy * photoFrame.height,
          )
        : clip.center;
    final projectedRadius =
        radius * math.min(photoFrame.width, photoFrame.height);
    if (!anchor.isFinite || !projectedRadius.isFinite || projectedRadius <= 0) {
      return null;
    }
    var point = anchor;
    if (keepVisible) {
      if (!clip.contains(point)) point = clip.center;
      // Allow for the outer stroke and antialiasing as well as the true radius.
      // When the true diameter is larger than the viewport, anchor one side
      // inside it so a real arc remains visible instead of enclosing the whole
      // viewport. This shifts only the sizing guide, never the stroke point.
      final inset = projectedRadius + 2;
      final fitsWidth = clip.width >= inset * 2;
      final fitsHeight = clip.height >= inset * 2;
      final x = fitsWidth
          ? point.dx.clamp(clip.left + inset, clip.right - inset)
          : clip.center.dx;
      final y = fitsHeight
          ? point.dy.clamp(clip.top + inset, clip.bottom - inset)
          : clip.center.dy;
      point = !fitsWidth && clip.width <= clip.height
          ? Offset(clip.right - inset, y)
          : !fitsHeight
          ? Offset(x, clip.bottom - inset)
          : Offset(x, y);
    }
    return RetouchBrushPreviewGeometry._(
      center: point,
      normalizedCenter: validPoint
          ? center
          : Offset(
              (anchor.dx - photoFrame.left) / photoFrame.width,
              (anchor.dy - photoFrame.top) / photoFrame.height,
            ),
      radius: projectedRadius,
      clip: clip,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RetouchBrushPreviewGeometry &&
      other.center == center &&
      other.normalizedCenter == normalizedCenter &&
      other.radius == radius &&
      other.clip == clip;

  @override
  int get hashCode => Object.hash(center, normalizedCenter, radius, clip);
}

/// An unfilled high-contrast ring; it does not represent an applied edit.
class RetouchBrushPreviewPainter extends CustomPainter {
  const RetouchBrushPreviewPainter({
    required this.geometry,
    this.color = const Color(0xfff4f5f7),
    this.outlineColor = const Color(0xcc000000),
  });

  final RetouchBrushPreviewGeometry? geometry;
  final Color color, outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final guide = geometry;
    if (guide == null) return;
    final clip = guide.clip.intersect(Offset.zero & size);
    if (clip.isEmpty) return;
    canvas.save();
    canvas.clipRect(clip);
    final paint = Paint()..style = PaintingStyle.stroke;
    canvas.drawCircle(
      guide.center,
      guide.radius,
      paint
        ..color = outlineColor
        ..strokeWidth = 3.5,
    );
    canvas.drawCircle(
      guide.center,
      guide.radius,
      paint
        ..color = color
        ..strokeWidth = 1.5,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(RetouchBrushPreviewPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.color != color ||
      oldDelegate.outlineColor != outlineColor;
}
