import 'dart:math' as math;
import 'dart:typed_data';

import 'domain.dart';

/// The original AdjustmentRegion.Brush coverage, in the oriented source frame.
/// A bounded segment grid keeps long brush paths out of the per-pixel loop.
class SelectionCoverage {
  SelectionCoverage(Json region, this.width, this.height) {
    if (!width.isFinite ||
        !height.isFinite ||
        width < 1 ||
        height < 1 ||
        width > 65535 ||
        height > 65535) {
      throw const FormatException('选区照片尺寸无效。');
    }
    final rawStrokes = region['strokes'] as List? ?? const [];
    final rawShapes = region['shapes'] as List? ?? const [];
    if (rawStrokes.length + rawShapes.length > 64) {
      throw const FormatException('选区元素数量超限。');
    }
    var points = 0;
    for (final raw in rawStrokes) {
      final stroke = _SelectionStroke(object(raw), width, height);
      strokes.add(stroke);
      points += stroke.count;
      if (!stroke.erase) {
        left = math.min(left, stroke.left);
        top = math.min(top, stroke.top);
        right = math.max(right, stroke.right);
        bottom = math.max(bottom, stroke.bottom);
      }
    }
    if (points > 8192) throw const FormatException('选区轨迹总量超限。');
    var previous = 0;
    for (final raw in rawShapes) {
      final shape = object(raw);
      final index = (shape['strokeIndex'] as num).toInt();
      if (index < previous || index > strokes.length) {
        throw const FormatException('选区元素顺序无效。');
      }
      previous = index;
      shapes.add(shape);
      if (shape['subtract'] != true) {
        left = math.min(left, (shape['left'] as num).toDouble());
        top = math.min(top, (shape['top'] as num).toDouble());
        right = math.max(right, (shape['right'] as num).toDouble());
        bottom = math.max(bottom, (shape['bottom'] as num).toDouble());
      }
    }
    hasSelection = right > left && bottom > top;
    inverted = region['inverted'] == true && hasSelection;
    if (inverted) {
      left = top = 0;
      right = bottom = 1;
    }
    left = math.max(0, left);
    top = math.max(0, top);
    right = math.min(1, right);
    bottom = math.min(1, bottom);
  }
  final double width, height;
  final strokes = <_SelectionStroke>[];
  final shapes = <Json>[];
  double left = 1, top = 1, right = 0, bottom = 0;
  bool hasSelection = false, inverted = false;

  double weight(double x, double y) {
    if (!x.isFinite ||
        !y.isFinite ||
        x < left ||
        x > right ||
        y < top ||
        y > bottom) {
      return 0;
    }
    var amount = 0.0, shapeIndex = 0;
    for (var i = 0; i <= strokes.length; i++) {
      while (shapeIndex < shapes.length &&
          shapes[shapeIndex]['strokeIndex'] == i) {
        final shape = shapes[shapeIndex++];
        if (!(shape['subtract'] == true && amount == 0) &&
            !(shape['subtract'] != true && amount == 1)) {
          final w = shapeWeight(shape, x, y);
          amount = shape['subtract'] == true
              ? amount * (1 - w)
              : amount + (1 - amount) * w;
        }
      }
      if (i < strokes.length) {
        final stroke = strokes[i];
        if (!(stroke.erase && amount == 0) && !(!stroke.erase && amount == 1)) {
          final w = stroke.weight(x, y);
          amount = stroke.erase ? amount * (1 - w) : amount + (1 - amount) * w;
        }
      }
    }
    return (inverted ? 1 - amount : amount).clamp(0.0, 1.0);
  }

  static double shapeWeight(Json shape, double x, double y) {
    final l = (shape['left'] as num).toDouble(),
        t = (shape['top'] as num).toDouble(),
        r = (shape['right'] as num).toDouble(),
        b = (shape['bottom'] as num).toDouble();
    final dx = (x - (l + r) / 2) / ((r - l) / 2),
        dy = (y - (t + b) / 2) / ((b - t) / 2);
    final d = shape['kind'] == 'ellipse'
        ? math.sqrt(dx * dx + dy * dy)
        : math.max(dx.abs(), dy.abs());
    return falloff(d, (shape['feather'] as num).toDouble());
  }

  static double falloff(double distance, double feather) {
    if (distance >= 1) return 0;
    if (feather <= 0 || distance <= 1 - feather) return 1;
    final t = (distance - (1 - feather)) / feather;
    return 1 - t * t * (3 - 2 * t);
  }
}

class _SelectionStroke {
  _SelectionStroke(Json value, this.width, this.height) {
    final raw = value['points'] as List;
    if (raw.length < 2 || raw.length.isOdd || raw.length > 1024) {
      throw const FormatException('选区轨迹无效。');
    }
    count = raw.length ~/ 2;
    radius = (value['radius'] as num).toDouble() * math.min(width, height);
    feather = (value['feather'] as num).toDouble();
    erase = value['erase'] == true;
    if (!radius.isFinite ||
        radius <= 0 ||
        !feather.isFinite ||
        feather < 0 ||
        feather > 1) {
      throw const FormatException('画笔参数无效。');
    }
    segments = Float64List(count * 5);
    final counts = Uint32List(256);
    left = top = double.infinity;
    right = bottom = double.negativeInfinity;
    for (var i = 0; i < count; i++) {
      final x = (raw[i * 2] as num).toDouble(),
          y = (raw[i * 2 + 1] as num).toDouble();
      if (!x.isFinite || !y.isFinite || x < 0 || x > 1 || y < 0 || y > 1) {
        throw const FormatException('画笔坐标无效。');
      }
      final next = math.min(i + 1, count - 1) * 2;
      final ax = x * width,
          ay = y * height,
          vx = (raw[next] as num).toDouble() * width - ax,
          vy = (raw[next + 1] as num).toDouble() * height - ay;
      final offset = i * 5;
      segments[offset] = ax;
      segments[offset + 1] = ay;
      segments[offset + 2] = vx;
      segments[offset + 3] = vy;
      segments[offset + 4] = vx * vx + vy * vy;
      final l = (math.min(ax, ax + vx) - radius) / width,
          t = (math.min(ay, ay + vy) - radius) / height,
          r = (math.max(ax, ax + vx) + radius) / width,
          b = (math.max(ay, ay + vy) + radius) / height;
      left = math.min(left, l);
      top = math.min(top, t);
      right = math.max(right, r);
      bottom = math.max(bottom, b);
      for (var cy = cell(t); cy <= cell(b); cy++) {
        for (var cx = cell(l); cx <= cell(r); cx++) {
          counts[cy * 16 + cx]++;
        }
      }
    }
    starts = Uint32List(257);
    for (var i = 0; i < counts.length; i++) {
      starts[i + 1] = starts[i] + counts[i];
    }
    indexes = Uint16List(starts.last);
    final writing = Uint32List.fromList(starts.sublist(0, 256));
    for (var i = 0; i < count; i++) {
      final o = i * 5,
          ax = segments[o],
          ay = segments[o + 1],
          bx = ax + segments[o + 2],
          by = ay + segments[o + 3];
      for (
        var cy = cell((math.min(ay, by) - radius) / height);
        cy <= cell((math.max(ay, by) + radius) / height);
        cy++
      ) {
        for (
          var cx = cell((math.min(ax, bx) - radius) / width);
          cx <= cell((math.max(ax, bx) + radius) / width);
          cx++
        ) {
          final slot = cy * 16 + cx;
          indexes[writing[slot]++] = i;
        }
      }
    }
  }
  final double width, height;
  late final int count;
  late final double radius, feather;
  late final bool erase;
  late final Float64List segments;
  late final Uint32List starts;
  late final Uint16List indexes;
  late double left, top, right, bottom;
  static int cell(double value) => (value * 16).floor().clamp(0, 15);

  double weight(double nx, double ny) {
    if (nx < left || nx > right || ny < top || ny > bottom) return 0;
    final x = nx * width, y = ny * height, slot = cell(ny) * 16 + cell(nx);
    var distance = double.infinity;
    final solid = radius * (1 - feather), solidSquared = solid * solid;
    for (var j = starts[slot]; j < starts[slot + 1]; j++) {
      final o = indexes[j] * 5,
          ax = segments[o],
          ay = segments[o + 1],
          vx = segments[o + 2],
          vy = segments[o + 3],
          length = segments[o + 4];
      final t = length == 0
          ? 0.0
          : (((x - ax) * vx + (y - ay) * vy) / length).clamp(0.0, 1.0);
      final dx = x - ax - t * vx, dy = y - ay - t * vy;
      distance = math.min(distance, dx * dx + dy * dy);
      if (distance <= solidSquared) return 1;
    }
    return SelectionCoverage.falloff(math.sqrt(distance) / radius, feather);
  }
}

/// Run on the single coalescing mask worker. Pixels use premultiplied RGBA,
/// matching the original 38/255 cyan selection overlay, with at most 320² pixels.
Json buildSelectionMask(Json input) {
  final width = (input['width'] as num).toDouble(),
      height = (input['height'] as num).toDouble();
  final coverage = SelectionCoverage(object(input['region']), width, height);
  final scale = math.min(1.0, 320 / math.max(width, height));
  final w = math.max(2, (width * scale).round()),
      h = math.max(2, (height * scale).round());
  final bytes = Uint8List(w * h * 4);
  var positive = false;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final amount = coverage.weight((x + .5) / w, (y + .5) / h);
      positive |= amount > 0;
      final a = (amount * 38).round(), i = (y * w + x) * 4;
      bytes[i] = (121 * a / 255).round();
      bytes[i + 1] = (213 * a / 255).round();
      bytes[i + 2] = (239 * a / 255).round();
      bytes[i + 3] = a;
    }
  }
  return {'bytes': bytes, 'width': w, 'height': h, 'hasCoverage': positive};
}
