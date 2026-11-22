import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'domain.dart';

enum CollageLayout { horizontal, vertical, grid }

class CollagePlan {
  const CollagePlan(this.size, this.cells);
  final Size size;
  final List<Rect> cells;
}

enum CollageMode { collage, template, longImage }

enum CollageTool { layout, filter, adjust, text }

const collageRatios = <double>[
  3 / 4,
  1,
  9 / 16,
  2 / 3,
  1 / 2,
  4 / 3,
  3 / 2,
  16 / 9,
];
const collageRatioLabels = [
  '3:4',
  '1:1',
  '9:16',
  '2:3',
  '1:2',
  '4:3',
  '3:2',
  '16:9',
];
const collageFilterLabels = ['原图', '清透', '暖调', '冷调', '胶片', '黑白'];
const collageTemplateLabels = ['经典', '留白', '电影', '胶片', '杂志', '极简'];
const collageAccent = Color(0xffb8ff19);

class CollageTransform {
  const CollageTransform({
    this.scale = 1,
    this.offset = Offset.zero,
    this.turns = 0,
    this.mirror = false,
  });
  final double scale;
  final Offset offset;
  final int turns;
  final bool mirror;
  CollageTransform copyWith({
    double? scale,
    Offset? offset,
    int? turns,
    bool? mirror,
  }) => CollageTransform(
    scale: scale ?? this.scale,
    offset: offset ?? this.offset,
    turns: turns ?? this.turns,
    mirror: mirror ?? this.mirror,
  );
}

class CollageText {
  const CollageText({
    this.value = '',
    this.position = const Offset(.5, .85),
    this.size = 24,
    this.color = Colors.white,
    this.bold = false,
  });
  final String value;
  final Offset position;
  final double size;
  final Color color;
  final bool bold;
  CollageText copyWith({
    String? value,
    Offset? position,
    double? size,
    Color? color,
    bool? bold,
  }) => CollageText(
    value: value ?? this.value,
    position: position ?? this.position,
    size: size ?? this.size,
    color: color ?? this.color,
    bold: bold ?? this.bold,
  );
}

class CollageStyle {
  const CollageStyle({
    this.mode = CollageMode.collage,
    this.ratio = 0,
    this.pattern = 0,
    this.template = 0,
    this.gap = 0,
    this.background = Colors.white,
    this.contain = false,
    this.horizontal = false,
    this.filter = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.warmth = 0,
    this.radius = 0,
    this.texts = const [],
  });
  final CollageMode mode;
  final int ratio, pattern, template, filter;
  final double gap, brightness, contrast, saturation, warmth, radius;
  final Color background;
  final bool contain, horizontal;
  final List<CollageText> texts;
  CollageStyle copyWith({
    CollageMode? mode,
    int? ratio,
    int? pattern,
    int? template,
    double? gap,
    Color? background,
    bool? contain,
    bool? horizontal,
    int? filter,
    double? brightness,
    double? contrast,
    double? saturation,
    double? warmth,
    double? radius,
    List<CollageText>? texts,
  }) => CollageStyle(
    mode: mode ?? this.mode,
    ratio: ratio ?? this.ratio,
    pattern: pattern ?? this.pattern,
    template: template ?? this.template,
    gap: gap ?? this.gap,
    background: background ?? this.background,
    contain: contain ?? this.contain,
    horizontal: horizontal ?? this.horizontal,
    filter: filter ?? this.filter,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    warmth: warmth ?? this.warmth,
    radius: radius ?? this.radius,
    texts: texts ?? this.texts,
  );
  CollageStyle applyTemplate(int index) => copyWith(
    mode: CollageMode.template,
    template: index,
    pattern: [0, 0, 1, 2, 3, 0][index],
    gap: [0.0, 12.0, 8.0, 10.0, 14.0, 22.0][index],
    background: [
      Colors.white,
      Colors.white,
      Colors.black,
      const Color(0xffeee6d5),
      const Color(0xffe8e7e2),
      Colors.white,
    ][index],
    radius: index == 5 ? 8 : 0,
  );
}

List<Rect> _strips(
  int count,
  bool vertical, [
  Rect bounds = const Rect.fromLTWH(0, 0, 1, 1),
]) => List.generate(
  count,
  (i) => vertical
      ? Rect.fromLTWH(
          bounds.left + bounds.width * i / count,
          bounds.top,
          bounds.width / count,
          bounds.height,
        )
      : Rect.fromLTWH(
          bounds.left,
          bounds.top + bounds.height * i / count,
          bounds.width,
          bounds.height / count,
        ),
);

/// Every thumbnail is the exact normalized partition used by the output.
List<List<Rect>> collagePatterns(int count) {
  if (count < 2 || count > 9) return [];
  final columns = count <= 4 ? 2 : 3,
      rows = (count / (count <= 4 ? 2 : 3)).ceil();
  final grid = <Rect>[];
  for (var row = 0, used = 0; row < rows; row++) {
    final n = math.min(columns, count - used);
    grid.addAll(_strips(n, true, Rect.fromLTWH(0, row / rows, 1, 1 / rows)));
    used += n;
  }
  final result = <List<Rect>>[
    grid,
    _strips(count, false),
    _strips(count, true),
  ];
  for (final fraction in [.5, 2 / 3]) {
    result.add([
      Rect.fromLTWH(0, 0, fraction, 1),
      ..._strips(count - 1, false, Rect.fromLTWH(fraction, 0, 1 - fraction, 1)),
    ]);
    result.add([
      Rect.fromLTWH(1 - fraction, 0, fraction, 1),
      ..._strips(count - 1, false, Rect.fromLTWH(0, 0, 1 - fraction, 1)),
    ]);
    result.add([
      Rect.fromLTWH(0, 0, 1, fraction),
      ..._strips(count - 1, true, Rect.fromLTWH(0, fraction, 1, 1 - fraction)),
    ]);
    result.add([
      Rect.fromLTWH(0, 1 - fraction, 1, fraction),
      ..._strips(count - 1, true, Rect.fromLTWH(0, 0, 1, 1 - fraction)),
    ]);
  }
  if (count == 4) {
    final mixed = [
      const Rect.fromLTWH(0, 0, 1, .5),
      const Rect.fromLTWH(0, .5, .5, .25),
      const Rect.fromLTWH(0, .75, .5, .25),
      const Rect.fromLTWH(.5, .5, .5, .5),
    ];
    for (var rotation = 0; rotation < 4; rotation++) {
      for (final mirror in [false, true]) {
        result.add(
          mixed.map((cell) {
            var rect = cell;
            if (mirror) {
              rect = Rect.fromLTWH(
                1 - rect.right,
                rect.top,
                rect.width,
                rect.height,
              );
            }
            for (var turn = 0; turn < rotation; turn++) {
              rect = Rect.fromLTWH(
                1 - rect.bottom,
                rect.left,
                rect.height,
                rect.width,
              );
            }
            return rect;
          }).toList(),
        );
      }
    }
  } else if (count >= 5) {
    for (var first = 2; first <= math.min(count - 2, 4); first++) {
      result.add([
        ..._strips(first, true, const Rect.fromLTWH(0, 0, 1, .5)),
        ..._strips(count - first, true, const Rect.fromLTWH(0, .5, 1, .5)),
      ]);
      result.add([
        ..._strips(first, false, const Rect.fromLTWH(0, 0, .5, 1)),
        ..._strips(count - first, false, const Rect.fromLTWH(.5, 0, .5, 1)),
      ]);
    }
  }
  return result;
}

CollagePlan composeCollage(
  List<Size> sources,
  CollageStyle style,
  int edge, {
  List<CollageTransform>? transforms,
}) {
  // Keep the original validation and bounded long-image geometry.
  final validated = planCollage(
    List.generate(
      sources.length,
      (i) => transforms != null && transforms[i].turns.isOdd
          ? Size(sources[i].height, sources[i].width)
          : sources[i],
    ),
    style.horizontal ? CollageLayout.horizontal : CollageLayout.vertical,
    style.gap,
    edge,
  );
  if (style.mode == CollageMode.longImage) return validated;
  final ratio = collageRatios[style.ratio.clamp(0, collageRatios.length - 1)];
  var width = ratio >= 1 ? edge.toDouble() : edge * ratio;
  var height = ratio >= 1 ? edge / ratio : edge.toDouble();
  if (width * height > 12000000) {
    final scale = math.sqrt(12000000 / (width * height));
    width *= scale;
    height *= scale;
  }
  final size = Size(width.floorToDouble(), height.floorToDouble());
  final patterns = collagePatterns(sources.length),
      pattern = patterns[style.pattern % patterns.length];
  final gap = (style.gap / 390 * size.width).clamp(
    0.0,
    math.min(size.width, size.height) / 12,
  );
  return CollagePlan(
    size,
    pattern
        .map(
          (r) => Rect.fromLTRB(
            r.left * size.width + gap / 2,
            r.top * size.height + gap / 2,
            r.right * size.width - gap / 2,
            r.bottom * size.height - gap / 2,
          ),
        )
        .toList(),
  );
}

List<double> _multiply(List<double> a, List<double> b) =>
    List.generate(20, (i) {
      final row = i ~/ 5, col = i % 5;
      var value = col == 4 ? a[row * 5 + 4] : 0.0;
      for (var k = 0; k < 4; k++) {
        value += a[row * 5 + k] * b[k * 5 + col];
      }
      return value;
    });

List<double> collageColorMatrix(CollageStyle style) {
  final preset = style.filter;
  final saturation = preset == 5
      ? 0.0
      : (1 +
                style.saturation +
                (preset == 1
                    ? .12
                    : preset == 4
                    ? -.18
                    : 0))
            .clamp(0.0, 2.0);
  const luma = [.2126, .7152, .0722];
  var matrix = List<double>.generate(20, (i) {
    final row = i ~/ 5, col = i % 5;
    return row == 3
        ? (col == 3 ? 1 : 0)
        : col < 3
        ? luma[col] * (1 - saturation) + (row == col ? saturation : 0)
        : 0;
  });
  final contrast =
          1 +
          style.contrast * .7 +
          (preset == 4
              ? -.08
              : preset == 1
              ? .05
              : 0),
      offset = 128 * (1 - contrast) + style.brightness * 90;
  final warmth =
      style.warmth * 24 +
      (preset == 2
          ? 14
          : preset == 3
          ? -14
          : preset == 4
          ? 6
          : 0);
  matrix = _multiply([
    contrast,
    0,
    0,
    0,
    offset + warmth,
    0,
    contrast,
    0,
    0,
    offset,
    0,
    0,
    contrast,
    0,
    offset - warmth,
    0,
    0,
    0,
    1,
    0,
  ], matrix);
  return matrix;
}

void paintCollageImage(
  Canvas canvas,
  ui.Image image,
  Rect cell,
  CollageTransform transform, {
  required bool contain,
  required List<double> matrix,
  double radius = 0,
}) {
  final turned = transform.turns.isOdd,
      iw = turned ? image.height : image.width,
      ih = turned ? image.width : image.height;
  final factor =
      (contain
          ? math.min(cell.width / iw, cell.height / ih)
          : math.max(cell.width / iw, cell.height / ih)) *
      transform.scale.clamp(1.0, 4.0);
  final excessX = math.max(0.0, iw * factor - cell.width) / 2,
      excessY = math.max(0.0, ih * factor - cell.height) / 2;
  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(cell, Radius.circular(radius)));
  canvas.translate(
    cell.center.dx + transform.offset.dx.clamp(-1.0, 1.0) * excessX,
    cell.center.dy + transform.offset.dy.clamp(-1.0, 1.0) * excessY,
  );
  canvas.rotate(transform.turns * math.pi / 2);
  canvas.scale(transform.mirror ? -factor : factor, factor);
  canvas.drawImage(
    image,
    Offset(-image.width / 2, -image.height / 2),
    Paint()
      ..filterQuality = FilterQuality.high
      ..colorFilter = ColorFilter.matrix(matrix),
  );
  canvas.restore();
}

Rect collageTextRect(CollageText text, Size size, TextPainter painter) {
  final center = Offset(
    text.position.dx * size.width,
    text.position.dy * size.height,
  );
  return Rect.fromLTWH(
    (center.dx - painter.width / 2).clamp(
      0.0,
      math.max(0.0, size.width - painter.width),
    ),
    (center.dy - painter.height / 2).clamp(
      0.0,
      math.max(0.0, size.height - painter.height),
    ),
    painter.width,
    painter.height,
  );
}

void paintCollageTexts(Canvas canvas, List<CollageText> texts, Size size) {
  for (final text in texts.where((t) => t.value.isNotEmpty)) {
    final painter = TextPainter(
      text: TextSpan(
        text: text.value,
        style: TextStyle(
          fontSize: text.size * size.width / 390,
          color: text.color,
          fontWeight: text.bold ? FontWeight.w700 : FontWeight.w400,
          height: 1.25,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: size.width * .9);
    painter.paint(canvas, collageTextRect(text, size, painter).topLeft);
    painter.dispose();
  }
}

/// One geometry plan serves both the preview and the saved image.
CollagePlan planCollage(
  List<Size> sources,
  CollageLayout layout,
  double gap,
  int edge,
) {
  if (sources.length < 2 ||
      sources.length > 9 ||
      gap < 0 ||
      gap > 40 ||
      edge < 256 ||
      edge > 4096 ||
      sources.any(
        (s) =>
            !s.width.isFinite ||
            !s.height.isFinite ||
            s.width <= 0 ||
            s.height <= 0,
      )) {
    throw const AppFailure('请选择 2–9 张有效照片。');
  }
  final space = gap * 4, cells = <Rect>[];
  double width, height;
  if (layout == CollageLayout.grid) {
    final columns = sources.length <= 4 ? 2 : 3,
        rows = (sources.length / (sources.length <= 4 ? 2 : 3)).ceil();
    width = columns * 1000 + (columns + 1) * space;
    height = rows * 1000 + (rows + 1) * space;
    for (var i = 0; i < sources.length; i++) {
      cells.add(
        Rect.fromLTWH(
          space + (i % columns) * (1000 + space),
          space + (i ~/ columns) * (1000 + space),
          1000,
          1000,
        ),
      );
    }
  } else {
    var cursor = space;
    for (final source in sources) {
      final ratio = (source.width / source.height).clamp(.05, 20.0);
      final w = layout == CollageLayout.horizontal ? 1000 * ratio : 1000.0;
      final h = layout == CollageLayout.vertical ? 1000 / ratio : 1000.0;
      cells.add(
        Rect.fromLTWH(
          layout == CollageLayout.horizontal ? cursor : space,
          layout == CollageLayout.vertical ? cursor : space,
          w,
          h,
        ),
      );
      cursor += (layout == CollageLayout.horizontal ? w : h) + space;
    }
    width = layout == CollageLayout.horizontal ? cursor : 1000 + space * 2;
    height = layout == CollageLayout.vertical ? cursor : 1000 + space * 2;
  }
  var scale = edge / math.max(width, height);
  if (width * height * scale * scale > 12000000) {
    scale = math.sqrt(12000000 / (width * height));
  }
  final size = Size(
    math.max(1, (width * scale).floor()).toDouble(),
    math.max(1, (height * scale).floor()).toDouble(),
  );
  return CollagePlan(
    size,
    cells
        .map(
          (r) => Rect.fromLTRB(
            r.left * scale,
            r.top * scale,
            math.min(size.width, r.right * scale),
            math.min(size.height, r.bottom * scale),
          ),
        )
        .toList(),
  );
}
