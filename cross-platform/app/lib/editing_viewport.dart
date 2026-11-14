import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show listEquals;

typedef EditingWorkspaceLayoutBuilder = Widget Function(
  BuildContext context,
  Widget photo,
  Widget panel,
);

/// Navigation only: maps each tool's displayed photo back to the upright source.
/// Geometry follows PhotoGeometry; it never changes a recipe or brush coordinates.
class EditingViewportPlane {
  EditingViewportPlane._(
    this._forward, {
    this.contentRect = const Rect.fromLTWH(0, 0, 1, 1),
  }) : _inverse = Matrix4.inverted(_forward);

  factory EditingViewportPlane.fromRecipe(
    Map<String, dynamic> recipe, {
    Size sourceSize = const Size(1, 1),
    Rect contentRect = const Rect.fromLTWH(0, 0, 1, 1),
  }) {
    final value = recipe['geometry'];
    final g = value is Map ? value : const {};
    double number(String key, double fallback) =>
        (g[key] as num?)?.toDouble() ?? fallback;
    final turns = number('turns', 0).round() % 4;
    final angle = number('angle', 0) / 10 * math.pi / 180;
    final horizontal = number('horizontalPerspective', 0) * .004;
    final vertical = number('verticalPerspective', 0) * .004;
    final left = number('left', 0) / 1000000;
    final top = number('top', 0) / 1000000;
    final right = number('right', 1000000) / 1000000;
    final bottom = number('bottom', 1000000) / 1000000;
    final width = sourceSize.width > 0 ? sourceSize.width : 1.0;
    final height = sourceSize.height > 0 ? sourceSize.height : 1.0;
    final frameWidth = turns.isEven ? width : height;
    final frameHeight = turns.isEven ? height : width;
    final c = math.cos(angle), s = math.sin(angle);
    final zoom =
        c +
        s.abs() * math.max(frameWidth / frameHeight, frameHeight / frameWidth);
    var matrix = Matrix4.identity();
    for (var i = 0; i < turns; i++) {
      matrix = _matrix(0, -1, 1, 1, 0, 0) * matrix;
    }
    final a = zoom * c, b = -zoom * s * frameHeight / frameWidth;
    final d = zoom * s * frameWidth / frameHeight, e = zoom * c;
    matrix = _matrix(a, b, .5 - (a + b) / 2, d, e, .5 - (d + e) / 2) * matrix;
    if (horizontal != 0 || vertical != 0) {
      final k = 1 - (horizontal + vertical) / 2;
      final fill = 1 + (horizontal.abs() + vertical.abs()) / 2;
      matrix =
          _matrix(
            fill + horizontal / 2,
            vertical / 2,
            (k - fill) / 2,
            horizontal / 2,
            fill + vertical / 2,
            (k - fill) / 2,
            horizontal,
            vertical,
            k,
          ) *
          matrix;
    }
    if (g['mirrored'] == true) {
      matrix = _matrix(-1, 0, 1, 0, 1, 0) * matrix;
    }
    final cropWidth = right > left ? right - left : 1.0;
    final cropHeight = bottom > top ? bottom - top : 1.0;
    matrix =
        _matrix(
          1 / cropWidth,
          0,
          -left / cropWidth,
          0,
          1 / cropHeight,
          -top / cropHeight,
        ) *
        matrix;
    if (contentRect.width > 0 && contentRect.height > 0) {
      matrix =
          _matrix(
            contentRect.width,
            0,
            contentRect.left,
            0,
            contentRect.height,
            contentRect.top,
          ) *
          matrix;
    }
    return EditingViewportPlane._(matrix, contentRect: contentRect);
  }

  static final identity = EditingViewportPlane._(Matrix4.identity());
  final Matrix4 _forward, _inverse;
  final Rect contentRect;

  static Matrix4 _matrix(
    double a,
    double b,
    double c,
    double d,
    double e,
    double f, [
    double g = 0,
    double h = 0,
    double k = 1,
  ]) => Matrix4.identity()
    ..setEntry(0, 0, a)
    ..setEntry(0, 1, b)
    ..setEntry(0, 3, c)
    ..setEntry(1, 0, d)
    ..setEntry(1, 1, e)
    ..setEntry(1, 3, f)
    ..setEntry(3, 0, g)
    ..setEntry(3, 1, h)
    ..setEntry(3, 3, k);

  Offset toSource(Offset point) => MatrixUtils.transformPoint(_inverse, point);
  Offset fromSource(Offset point) =>
      MatrixUtils.transformPoint(_forward, point);

  double density(Rect imageRect, Offset sourcePoint) {
    final m = _forward;
    final q =
        m.entry(3, 0) * sourcePoint.dx +
        m.entry(3, 1) * sourcePoint.dy +
        m.entry(3, 3);
    final x =
        m.entry(0, 0) * sourcePoint.dx +
        m.entry(0, 1) * sourcePoint.dy +
        m.entry(0, 3);
    final y =
        m.entry(1, 0) * sourcePoint.dx +
        m.entry(1, 1) * sourcePoint.dy +
        m.entry(1, 3);
    final dx =
        (m.entry(0, 0) * q - m.entry(3, 0) * x) / (q * q) * imageRect.width;
    final dy =
        (m.entry(1, 0) * q - m.entry(3, 0) * y) / (q * q) * imageRect.height;
    return math.sqrt(dx * dx + dy * dy);
  }

  @override
  bool operator ==(Object other) =>
      other is EditingViewportPlane &&
      listEquals(_forward.storage, other._forward.storage);
  @override
  int get hashCode => Object.hashAll(_forward.storage);
}

/// One photo session owns this state; tools borrow it without saving it to drafts.
class EditingViewportState {
  Offset focus = const Offset(.5, .5);
  double zoom = 1;
  double _densityFraction = 1;
  bool _hasSample = false;
  int revision = 0;

  void reset() {
    focus = const Offset(.5, .5);
    zoom = 1;
    _densityFraction = 1;
    _hasSample = false;
    revision++;
  }

  /// An applied crop may remove the inspected point; keep the nearest detail visible.
  void constrainToPlane(EditingViewportPlane plane) {
    final local = plane.fromSource(focus);
    final rect = plane.contentRect;
    final nearest = Offset(
      local.dx.clamp(rect.left, rect.right).toDouble(),
      local.dy.clamp(rect.top, rect.bottom).toDouble(),
    );
    final next = plane.toSource(nearest);
    if (next.dx.isFinite && next.dy.isFinite && next != focus) {
      focus = next;
      revision++;
    }
  }

  void capture(
    TransformationController transform, {
    required Size viewport,
    required Rect imageRect,
    EditingViewportPlane? plane,
  }) {
    if (viewport.isEmpty || imageRect.isEmpty) return;
    final actualPlane = plane ?? EditingViewportPlane.identity;
    final center = transform.toScene(viewport.center(Offset.zero));
    final point = Offset(
      (center.dx - imageRect.left) / imageRect.width,
      (center.dy - imageRect.top) / imageRect.height,
    );
    final source = actualPlane.toSource(point);
    final scale = transform.value.getMaxScaleOnAxis();
    final density = actualPlane.density(imageRect, source);
    if (!source.dx.isFinite ||
        !source.dy.isFinite ||
        !scale.isFinite ||
        density <= 0 ||
        !density.isFinite) {
      return;
    }
    focus = source;
    zoom = scale;
    _densityFraction = scale * density / viewport.width;
    _hasSample = true;
    revision++;
  }

  Matrix4 matrixFor({
    required Size viewport,
    required Rect imageRect,
    EditingViewportPlane? plane,
    double minScale = 1,
    double maxScale = 32,
  }) {
    if (viewport.isEmpty || imageRect.isEmpty || !_hasSample) {
      return Matrix4.identity();
    }
    final actualPlane = plane ?? EditingViewportPlane.identity;
    final density = actualPlane.density(imageRect, focus);
    if (density <= 0 || !density.isFinite) return Matrix4.identity();
    final scale = (_densityFraction * viewport.width / density)
        .clamp(minScale, maxScale)
        .toDouble();
    final local = actualPlane.fromSource(focus);
    final point = Offset(
      imageRect.left + local.dx * imageRect.width,
      imageRect.top + local.dy * imageRect.height,
    );
    final center = viewport.center(Offset.zero);
    return Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(0, 3, center.dx - point.dx * scale)
      ..setEntry(1, 3, center.dy - point.dy * scale);
  }
}

/// Adapts a tool's existing transform, including layout changes, without a fit flash.
class EditingViewportBinding {
  EditingViewportBinding({required this.shared, required this.transform}) {
    transform.addListener(_capture);
  }
  final EditingViewportState shared;
  final TransformationController transform;
  Size _viewport = Size.zero;
  Rect _imageRect = Rect.zero;
  EditingViewportPlane _plane = EditingViewportPlane.identity;
  bool _active = false, _applying = false;
  int _seenRevision = -1;

  void layout({
    required Size viewport,
    required Rect imageRect,
    EditingViewportPlane? plane,
    bool active = true,
  }) {
    final actualPlane = plane ?? EditingViewportPlane.identity;
    final changed =
        !_active ||
        viewport != _viewport ||
        imageRect != _imageRect ||
        actualPlane != _plane;
    _active = active;
    _viewport = viewport;
    _imageRect = imageRect;
    _plane = actualPlane;
    if (!active ||
        viewport.isEmpty ||
        imageRect.isEmpty ||
        (!changed && _seenRevision == shared.revision)) {
      return;
    }
    _applying = true;
    try {
      transform.value = shared.matrixFor(
        viewport: viewport,
        imageRect: imageRect,
        plane: actualPlane,
      );
      if (!shared._hasSample) {
        shared.capture(
          transform,
          viewport: viewport,
          imageRect: imageRect,
          plane: actualPlane,
        );
      }
      _seenRevision = shared.revision;
    } finally {
      _applying = false;
    }
  }

  void _capture() {
    if (!_active || _applying) return;
    shared.capture(
      transform,
      viewport: _viewport,
      imageRect: _imageRect,
      plane: _plane,
    );
    _seenRevision = shared.revision;
  }

  void dispose() => transform.removeListener(_capture);
}
