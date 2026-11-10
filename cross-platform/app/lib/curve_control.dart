import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Edits the original engine's four PCHIP point curves in 8-bit sRGB coordinates.
class CurveControl extends StatefulWidget {
  const CurveControl({
    super.key,
    required this.curves,
    required this.enabled,
    required this.onStart,
    required this.onChanged,
  });
  final List<List<int>> curves;
  final bool enabled;
  final VoidCallback onStart;
  final ValueChanged<List<List<int>>> onChanged;
  @override
  State<CurveControl> createState() => _CurveControlState();
}

class _CurveControlState extends State<CurveControl> {
  int channel = 0, selected = 0;
  final colors = const [Colors.grey, Colors.red, Colors.green, Colors.blue];
  List<int> get points => widget.curves[channel];
  void update(List<int> value) {
    final all = widget.curves.map((p) => List<int>.from(p)).toList();
    all[channel] = value;
    widget.onChanged(all);
  }

  void move(Offset position, Size size, {bool begin = false}) {
    if (!widget.enabled) return;
    final x = (position.dx / size.width * 255).round().clamp(0, 255);
    final y = ((1 - position.dy / size.height) * 255).round().clamp(0, 255);
    final next = List<int>.from(points);
    if (begin) {
      widget.onStart();
      var distance = double.infinity;
      for (var i = 0; i < next.length; i += 2) {
        final d =
            (Offset(
                      next[i] / 255 * size.width,
                      (1 - next[i + 1] / 255) * size.height,
                    ) -
                    position)
                .distance;
        if (d < distance) {
          selected = i ~/ 2;
          distance = d;
        }
      }
      if (distance > 28 &&
          next.length < 24 &&
          x > 0 &&
          x < 255 &&
          ![for (var i = 0; i < next.length; i += 2) next[i]].contains(x)) {
        var at = 0;
        while (at < next.length && next[at] < x) {
          at += 2;
        }
        next.insertAll(at, [x, y]);
        selected = at ~/ 2;
      }
    }
    selected = selected.clamp(0, next.length ~/ 2 - 1);
    final index = selected * 2;
    if (index > 0 && index < next.length - 2) {
      next[index] = x.clamp(next[index - 2] + 1, next[index + 2] - 1);
    }
    next[index + 1] = y;
    update(next);
  }

  @override
  Widget build(BuildContext context) {
    selected = selected.clamp(0, points.length ~/ 2 - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (var i = 0; i < 4; i++)
              ChoiceChip(
                label: Text(['RGB', '红', '绿', '蓝'][i]),
                selected: channel == i,
                onSelected: (_) => setState(() {
                  channel = i;
                  selected = 0;
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '点击添加控制点，拖动调整曲线。最多 12 个点。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return Semantics(
                label: '${['RGB', '红', '绿', '蓝'][channel]}通道曲线',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanDown: widget.enabled
                      ? (e) => move(e.localPosition, size, begin: true)
                      : null,
                  onPanUpdate: widget.enabled
                      ? (e) => move(e.localPosition, size)
                      : null,
                  child: CustomPaint(
                    painter: _CurvePainter(
                      points,
                      selected,
                      channel == 0
                          ? Theme.of(context).colorScheme.primary
                          : colors[channel],
                      Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text('输入 ${points[selected * 2]} · 输出 ${points[selected * 2 + 1]}'),
        Slider(
          min: 0,
          max: 255,
          value: points[selected * 2 + 1].toDouble(),
          onChangeStart: widget.enabled ? (_) => widget.onStart() : null,
          onChanged: !widget.enabled
              ? null
              : (value) {
                  final next = List<int>.from(points);
                  next[selected * 2 + 1] = value.round();
                  update(next);
                },
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: !widget.enabled
                  ? null
                  : () {
                      widget.onStart();
                      update([0, 0, 255, 255]);
                      setState(() => selected = 0);
                    },
              child: const Text('重置此通道'),
            ),
            TextButton(
              onPressed:
                  !widget.enabled ||
                      selected == 0 ||
                      selected == points.length ~/ 2 - 1
                  ? null
                  : () {
                      widget.onStart();
                      final next = List<int>.from(points)
                        ..removeRange(selected * 2, selected * 2 + 2);
                      selected = math.max(0, selected - 1);
                      update(next);
                    },
              child: const Text('删除控制点'),
            ),
          ],
        ),
      ],
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.points, this.selected, this.color, this.grid);
  final List<int> points;
  final int selected;
  final Color color, grid;
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      canvas.drawLine(
        Offset(size.width * i / 4, 0),
        Offset(size.width * i / 4, size.height),
        line,
      );
      canvas.drawLine(
        Offset(0, size.height * i / 4),
        Offset(size.width, size.height * i / 4),
        line,
      );
    }
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), line);
    final n = points.length ~/ 2, d = <double>[], h = <double>[];
    final m = List.filled(n, 0.0);
    for (var i = 0; i < n - 1; i++) {
      h.add((points[(i + 1) * 2] - points[i * 2]).toDouble());
      d.add((points[(i + 1) * 2 + 1] - points[i * 2 + 1]) / h.last);
    }
    m[0] = d[0];
    m[n - 1] = d[n - 2];
    for (var i = 1; i < n - 1; i++) {
      if (d[i - 1] * d[i] > 0) {
        final w1 = 2 * h[i] + h[i - 1], w2 = h[i] + 2 * h[i - 1];
        m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i]);
      }
    }
    final path = Path();
    var part = 0;
    for (var x = 0; x < 256; x++) {
      while (part < n - 2 && x > points[(part + 1) * 2]) {
        part++;
      }
      final t = (x - points[part * 2]) / h[part], t2 = t * t, t3 = t2 * t;
      final y =
          ((2 * t3 - 3 * t2 + 1) * points[part * 2 + 1] +
                  (t3 - 2 * t2 + t) * h[part] * m[part] +
                  (-2 * t3 + 3 * t2) * points[(part + 1) * 2 + 1] +
                  (t3 - t2) * h[part] * m[part + 1])
              .clamp(0, 255);
      final point = Offset(x / 255 * size.width, (1 - y / 255) * size.height);
      if (x == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(
        Offset(
          points[i * 2] / 255 * size.width,
          (1 - points[i * 2 + 1] / 255) * size.height,
        ),
        i == selected ? 7 : 5,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => true;
}
