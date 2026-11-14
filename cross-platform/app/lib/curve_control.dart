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
    this.onEnd,
  });
  final List<List<int>> curves;
  final bool enabled;
  final VoidCallback onStart;
  final ValueChanged<List<List<int>>> onChanged;
  final VoidCallback? onEnd;
  @override
  State<CurveControl> createState() => _CurveControlState();
}

class _CurveControlState extends State<CurveControl> {
  int channel = 0, selected = 0;
  final colors = const [
    Color(0xffffe335),
    Color(0xffee8e86),
    Color(0xff8bca95),
    Color(0xff97b7ef),
  ];
  List<List<int>>? gesture;
  final pointers = <int>{};
  bool interrupted = false;
  List<int> get points => (gesture ?? widget.curves)[channel];
  void update(List<int> value) {
    final all = (gesture ?? widget.curves)
        .map((p) => List<int>.from(p))
        .toList();
    all[channel] = value;
    if (gesture != null) gesture = all;
    widget.onChanged(all);
  }

  void start() {
    if (!widget.enabled || gesture != null || interrupted) return;
    gesture = widget.curves.map((p) => List<int>.from(p)).toList();
    widget.onStart();
  }

  void finish() {
    if (gesture == null) return;
    gesture = null;
    widget.onEnd?.call();
  }

  void atomic(VoidCallback edit) {
    if (!widget.enabled) return;
    widget.onStart();
    edit();
    widget.onEnd?.call();
  }

  void addPoint() => atomic(() {
    if (points.length >= 24) return;
    final segment = math.min(selected, points.length ~/ 2 - 2);
    final x0 = points[segment * 2], x1 = points[(segment + 1) * 2];
    if (x1 - x0 < 2) return;
    final x = (x0 + x1) ~/ 2;
    final y = _CurveShape(points).value(x).round();
    final next = List<int>.from(points)..insertAll((segment + 1) * 2, [x, y]);
    setState(() => selected = segment + 1);
    update(next);
  });

  Future<void> exactPoint() async {
    if (!widget.enabled) return;
    final chosenChannel = channel, chosenPoint = selected;
    final frozen = List<int>.from(points);
    final input = TextEditingController(text: '${frozen[selected * 2]}');
    final output = TextEditingController(text: '${frozen[selected * 2 + 1]}');
    String? error;
    final route = DialogRoute<List<int>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (_, refresh) => AlertDialog(
          title: const Text('控制点'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('curve-exact-input'),
                  controller: input,
                  enabled:
                      chosenPoint > 0 && chosenPoint < frozen.length ~/ 2 - 1,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '输入，0–255'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('curve-exact-output'),
                  controller: output,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '输出，0–255',
                    errorText: error,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final x = int.tryParse(input.text.trim()),
                    y = int.tryParse(output.text.trim());
                if (x == null ||
                    y == null ||
                    x < 0 ||
                    x > 255 ||
                    y < 0 ||
                    y > 255 ||
                    (chosenPoint > 0 && x <= frozen[chosenPoint * 2 - 2]) ||
                    (chosenPoint < frozen.length ~/ 2 - 1 &&
                        x >= frozen[chosenPoint * 2 + 2])) {
                  refresh(() => error = '范围0–255，输入点不能交叉');
                  return;
                }
                Navigator.pop(dialog, [x, y]);
              },
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    final result = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    input.dispose();
    output.dispose();
    if (!mounted ||
        !widget.enabled ||
        result == null ||
        channel != chosenChannel ||
        selected != chosenPoint) {
      return;
    }
    if (points.length != frozen.length ||
        !List.generate(
          points.length,
          (i) => points[i] == frozen[i],
        ).every((v) => v)) {
      return;
    }
    atomic(() {
      final next = List<int>.from(points);
      next[selected * 2] = selected == 0
          ? 0
          : selected == points.length ~/ 2 - 1
          ? 255
          : result[0];
      next[selected * 2 + 1] = result[1];
      update(next);
    });
  }

  void move(Offset position, Size size, {bool begin = false}) {
    if (!widget.enabled || interrupted) return;
    final x = (position.dx / size.width * 255).round().clamp(0, 255);
    final y = ((1 - position.dy / size.height) * 255).round().clamp(0, 255);
    final next = List<int>.from(points);
    if (begin) {
      start();
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
      if (distance <= 28) {
        setState(() {});
        return;
      }
      if (next.length >= 24 ||
          x <= 0 ||
          x >= 255 ||
          [for (var i = 0; i < next.length; i += 2) next[i]].contains(x)) {
        interrupted = true;
        finish();
        return;
      }
      if (distance > 28) {
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
    setState(() => update(next));
  }

  @override
  Widget build(BuildContext context) {
    selected = selected.clamp(0, points.length ~/ 2 - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < 4; i++)
                  SizedBox(
                    width: 64,
                    height: 48,
                    child: TextButton(
                      key: ValueKey('curve-channel-$i'),
                      onPressed: widget.enabled && gesture == null
                          ? () => setState(() {
                              channel = i;
                              selected = 0;
                            })
                          : null,
                      style: TextButton.styleFrom(
                        foregroundColor: channel == i
                            ? const Color(0xffffe335)
                            : const Color(0xfff4f5f7),
                        backgroundColor: channel == i
                            ? const Color(0x26ffe335)
                            : Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(48, 48),
                        textStyle: const TextStyle(fontSize: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(['RGB', '红', '绿', '蓝'][i]),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          key: const Key('legacy-curve-graph'),
          height: 132,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.biggest;
                return Semantics(
                  label: '${['RGB', '红', '绿', '蓝'][channel]}通道曲线',
                  child: Listener(
                    onPointerDown: (event) {
                      pointers.add(event.pointer);
                      if (pointers.length > 1) {
                        interrupted = true;
                        finish();
                      }
                    },
                    onPointerUp: (event) {
                      pointers.remove(event.pointer);
                      if (pointers.isEmpty) interrupted = false;
                    },
                    onPointerCancel: (event) {
                      pointers.remove(event.pointer);
                      finish();
                      if (pointers.isEmpty) interrupted = false;
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanDown: widget.enabled
                          ? (e) => move(e.localPosition, size, begin: true)
                          : null,
                      onPanUpdate: widget.enabled
                          ? (e) => move(e.localPosition, size)
                          : null,
                      onPanEnd: (_) => finish(),
                      onPanCancel: finish,
                      child: CustomPaint(
                        painter: _CurvePainter(
                          points,
                          selected,
                          colors[channel],
                          const Color(0x24ffffff),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: widget.enabled && selected > 0
                    ? () => setState(() => selected--)
                    : null,
                child: const Text('上一点'),
              ),
            ),
            Expanded(
              flex: 2,
              child: TextButton(
                key: const Key('curve-point-value'),
                onPressed: widget.enabled ? exactPoint : null,
                child: Text(
                  '${points[selected * 2]} → ${points[selected * 2 + 1]}',
                  style: const TextStyle(
                    color: Color(0xffffe335),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: widget.enabled && selected < points.length ~/ 2 - 1
                    ? () => setState(() => selected++)
                    : null,
                child: const Text('下一点'),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: widget.enabled && points.length < 24
                    ? addPoint
                    : null,
                child: const Text('加点'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed:
                    widget.enabled &&
                        selected > 0 &&
                        selected < points.length ~/ 2 - 1
                    ? () => atomic(() {
                        final next = List<int>.from(points)
                          ..removeRange(selected * 2, selected * 2 + 2);
                        setState(() => selected--);
                        update(next);
                      })
                    : null,
                child: const Text('删点'),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: !widget.enabled
                    ? null
                    : () => atomic(() {
                        update([0, 0, 255, 255]);
                        setState(() => selected = 0);
                      }),
                child: const Text('重置通道'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: !widget.enabled
                    ? null
                    : () => atomic(() {
                        widget.onChanged(
                          List.generate(4, (_) => [0, 0, 255, 255]),
                        );
                        setState(() => selected = 0);
                      }),
                child: const Text('重置曲线'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CurveShape {
  _CurveShape(this.points) {
    final n = points.length ~/ 2;
    for (var i = 0; i < n - 1; i++) {
      h.add((points[(i + 1) * 2] - points[i * 2]).toDouble());
      d.add((points[(i + 1) * 2 + 1] - points[i * 2 + 1]) / h.last);
    }
    m = List.filled(n, 0.0)
      ..[0] = d[0]
      ..[n - 1] = d[n - 2];
    for (var i = 1; i < n - 1; i++) {
      if (d[i - 1] * d[i] > 0) {
        final w1 = 2 * h[i] + h[i - 1], w2 = h[i] + 2 * h[i - 1];
        m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i]);
      }
    }
  }
  final List<int> points;
  final h = <double>[], d = <double>[];
  late final List<double> m;
  double value(int x) {
    var part = 0;
    while (part < points.length ~/ 2 - 2 && x > points[(part + 1) * 2]) {
      part++;
    }
    final t = (x - points[part * 2]) / h[part], t2 = t * t, t3 = t2 * t;
    return ((2 * t3 - 3 * t2 + 1) * points[part * 2 + 1] +
            (t3 - 2 * t2 + t) * h[part] * m[part] +
            (-2 * t3 + 3 * t2) * points[(part + 1) * 2 + 1] +
            (t3 - t2) * h[part] * m[part + 1])
        .clamp(0, 255)
        .toDouble();
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
        i == selected ? 5 : 4,
        Paint()..color = i == selected ? Colors.white : const Color(0xffffe335),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => true;
}
