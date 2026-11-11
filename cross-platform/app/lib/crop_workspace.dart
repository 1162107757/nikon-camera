import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';

const _yellow = Color(0xffffe335), _white = Color(0xfff4f5f7);

/// Coordinates are fractions of the oriented, rotated full frame, as in
/// PhotoGeometry. The tentative workspace never writes the photo's draft.
class CropWorkspace extends StatefulWidget {
  const CropWorkspace({
    super.key,
    required this.core,
    required this.photo,
    required this.owner,
    required this.recipe,
  });
  final HueviaCore core;
  final Photo photo;
  final String owner;
  final Json recipe;
  @override
  State<CropWorkspace> createState() => _CropWorkspaceState();
}

class _CropWorkspaceState extends State<CropWorkspace> {
  late Json geometry = {...object(widget.recipe['geometry'] ?? {})};
  late Rect crop = Rect.fromLTRB(
    (geometry['left'] as num? ?? 0) / 1000000,
    (geometry['top'] as num? ?? 0) / 1000000,
    (geometry['right'] as num? ?? 1000000) / 1000000,
    (geometry['bottom'] as num? ?? 1000000) / 1000000,
  );
  String? image, error, job;
  Size pixels = const Size(1, 1);
  bool busy = true;
  int generation = 0;
  double ratio = -1;
  String transform = 'angle';
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    unawaited(render());
  }

  Future<void> discard(String? value) async {
    if (value == null ||
        !p.isWithin(p.join(widget.core.root, 'previews'), value)) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      await FileImage(File(value)).evict();
      await File(value).delete();
    } on FileSystemException {
      /* Disposable owned preview. */
    }
  }

  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    if (job != null) unawaited(widget.core.cancel(job!));
    unawaited(discard(image));
    super.dispose();
  }

  Future<void> render() async {
    final serial = ++generation, previous = job;
    final identity = 'crop-${DateTime.now().microsecondsSinceEpoch}';
    job = identity;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (previous != null) await widget.core.cancel(previous);
      final result = await widget.core.call('media.preview', {
        'path': widget.photo.path,
        'owner': widget.owner,
        'recipe': {
          ...widget.recipe,
          'border': <String, dynamic>{},
          'geometry': {
            ...geometry,
            'left': 0,
            'top': 0,
            'right': 1000000,
            'bottom': 1000000,
          },
        },
      }, identity);
      if (!mounted || serial != generation) {
        await discard(result['path'] as String);
        return;
      }
      final old = image;
      setState(() {
        image = result['path'] as String;
        pixels = Size(
          ((result['geometryWidth'] ?? result['width']) as num).toDouble(),
          ((result['geometryHeight'] ?? result['height']) as num).toDouble(),
        );
        fitRatio();
      });
      await discard(old);
    } catch (failure) {
      if (mounted && serial == generation) setState(() => error = '$failure');
    } finally {
      if (mounted && serial == generation) {
        setState(() {
          busy = false;
          job = null;
        });
      }
    }
  }

  void fitRatio() {
    if (ratio < 0) return;
    final normalized = ratio == 0 ? 1.0 : ratio / pixels.aspectRatio;
    double w = crop.width, h = crop.height;
    if (w / h > normalized) {
      w = h * normalized;
    } else {
      h = w / normalized;
    }
    crop = Rect.fromCenter(center: crop.center, width: w, height: h);
  }

  void mutate(VoidCallback action) {
    setState(action);
    debounce?.cancel();
    // Disable applying/hit testing until the new geometry has been rendered.
    generation++;
    setState(() => busy = true);
    debounce = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(render()),
    );
  }

  Widget controls() => SingleChildScrollView(
    child: Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in const [
                ('原图', 0.0),
                ('自由', -1.0),
                ('1:1', 1.0),
                ('4:3', 4 / 3),
                ('2:3', 2 / 3),
                ('3:2', 1.5),
                ('9:16', 9 / 16),
                ('电影 · 2.35:1', 2.35),
              ])
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          ratio = entry.$2;
                          fitRatio();
                        }),
                  style: TextButton.styleFrom(
                    foregroundColor: ratio == entry.$2 ? _yellow : _white,
                    minimumSize: const Size(48, 48),
                  ),
                  child: Text(entry.$1),
                ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: busy
                    ? null
                    : () => mutate(() {
                        geometry['turns'] =
                            ((geometry['turns'] as int? ?? 0) + 1) % 4;
                        crop = const Rect.fromLTRB(0, 0, 1, 1);
                      }),
                child: const Text('旋转 90°'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: busy
                    ? null
                    : () => mutate(() {
                        geometry['mirrored'] = geometry['mirrored'] != true;
                        crop = Rect.fromLTRB(
                          1 - crop.right,
                          crop.top,
                          1 - crop.left,
                          crop.bottom,
                        );
                      }),
                child: const Text('水平翻转'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: busy
                    ? null
                    : () => mutate(() {
                        geometry = {};
                        crop = const Rect.fromLTRB(0, 0, 1, 1);
                        ratio = -1;
                      }),
                child: const Text('重置'),
              ),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(
              width: 104,
              child: DropdownButton<String>(
                value: transform,
                isExpanded: true,
                dropdownColor: const Color(0xff292724),
                style: const TextStyle(color: _white, fontSize: 12),
                items: const [
                  DropdownMenuItem(value: 'angle', child: Text('拉直')),
                  DropdownMenuItem(
                    value: 'horizontalPerspective',
                    child: Text('水平透视'),
                  ),
                  DropdownMenuItem(
                    value: 'verticalPerspective',
                    child: Text('垂直透视'),
                  ),
                ],
                onChanged: (value) => setState(() => transform = value!),
              ),
            ),
            Expanded(
              child: Slider(
                value: (geometry[transform] as num? ?? 0).toDouble(),
                min: transform == 'angle' ? -450 : -100,
                max: transform == 'angle' ? 450 : 100,
                activeColor: _yellow,
                label: transform == 'angle'
                    ? '${((geometry[transform] as num? ?? 0) / 10).toStringAsFixed(1)}°'
                    : '${geometry[transform] ?? 0}',
                onChanged: (value) =>
                    mutate(() => geometry[transform] = value.round()),
              ),
            ),
          ],
        ),
        Text(
          '裁切范围 ${(crop.width * 100).toStringAsFixed(1)}% × ${(crop.height * 100).toStringAsFixed(1)}%',
          style: const TextStyle(color: _white, fontSize: 12),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              error!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        if (error != null)
          TextButton(
            onPressed: () => unawaited(render()),
            child: const Text('重试预览'),
          ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: ThemeData.dark().copyWith(
      colorScheme: const ColorScheme.dark(primary: _yellow),
    ),
    child: Scaffold(
      backgroundColor: const Color(0xff242b27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _white,
        title: const Text('构图', style: TextStyle(fontSize: 13)),
        centerTitle: true,
        leading: IconButton(
          tooltip: '返回编辑照片',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          TextButton(
            onPressed: busy || error != null
                ? null
                : () => Navigator.pop(context, {
                    ...geometry,
                    'left': (crop.left * 1000000).round(),
                    'top': (crop.top * 1000000).round(),
                    'right': (crop.right * 1000000).round(),
                    'bottom': (crop.bottom * 1000000).round(),
                  }),
            child: const Text('应用'),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, box) {
            final canvas = Stack(
              children: [
                Positioned.fill(
                  child: image == null
                      ? const Center(child: CircularProgressIndicator())
                      : CropCanvas(
                          image: image!,
                          pixels: pixels,
                          crop: crop,
                          enabled: !busy,
                          aspect: ratio < 0
                              ? null
                              : ratio == 0
                              ? pixels.aspectRatio
                              : ratio,
                          onChanged: (value) => setState(() => crop = value),
                          onRetry: () => unawaited(render()),
                        ),
                ),
                if (busy)
                  const Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            );
            return box.maxWidth > box.maxHeight
                ? Row(
                    children: [
                      Expanded(child: canvas),
                      SizedBox(
                        width: math.min(320, box.maxWidth * .45),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: controls(),
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: canvas),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: box.maxHeight * .48,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                          child: controls(),
                        ),
                      ),
                    ],
                  );
          },
        ),
      ),
    ),
  );
}

class CropCanvas extends StatefulWidget {
  const CropCanvas({
    super.key,
    required this.image,
    required this.pixels,
    required this.crop,
    required this.onChanged,
    this.aspect,
    this.enabled = true,
    this.onRetry,
  });
  final String image;
  final Size pixels;
  final Rect crop;
  final ValueChanged<Rect> onChanged;
  final double? aspect;
  final bool enabled;
  final VoidCallback? onRetry;
  @override
  State<CropCanvas> createState() => _CropCanvasState();
}

class _CropCanvasState extends State<CropCanvas> {
  Rect frame = Rect.zero, start = Rect.zero;
  Offset down = Offset.zero;
  int edges = 0;
  static const left = 1, top = 2, right = 4, bottom = 8;
  Rect get actual => Rect.fromLTRB(
    frame.left + widget.crop.left * frame.width,
    frame.top + widget.crop.top * frame.height,
    frame.left + widget.crop.right * frame.width,
    frame.top + widget.crop.bottom * frame.height,
  );
  void begin(DragStartDetails d) {
    final r = actual, p = d.localPosition;
    edges = (p.dx - r.left).abs() <= 24
        ? left
        : (p.dx - r.right).abs() <= 24
        ? right
        : 0;
    if ((p.dy - r.top).abs() <= 24) edges |= top;
    if ((p.dy - r.bottom).abs() <= 24) edges |= bottom;
    if (!r.inflate(24).contains(p)) edges = -1;
    start = widget.crop;
    down = p;
  }

  void update(DragUpdateDetails d) {
    if (edges < 0 || frame.isEmpty) return;
    final dx = (d.localPosition.dx - down.dx) / frame.width,
        dy = (d.localPosition.dy - down.dy) / frame.height;
    if (edges == 0) {
      final x = (start.left + dx).clamp(0.0, 1 - start.width),
          y = (start.top + dy).clamp(0.0, 1 - start.height);
      widget.onChanged(Rect.fromLTWH(x, y, start.width, start.height));
      return;
    }
    double l = start.left, t = start.top, r = start.right, b = start.bottom;
    if (edges & left != 0) l = (l + dx).clamp(0.0, r - .025);
    if (edges & right != 0) r = (r + dx).clamp(l + .025, 1.0);
    if (edges & top != 0) t = (t + dy).clamp(0.0, b - .025);
    if (edges & bottom != 0) b = (b + dy).clamp(t + .025, 1.0);
    final aspect = widget.aspect;
    if (aspect != null) {
      final normalized = aspect / widget.pixels.aspectRatio;
      // Anchor the opposite corner. Constrain both dimensions together so
      // dragging against an edge cannot silently break the selected ratio.
      final anchor = Offset(
        edges & left != 0 ? start.right : start.left,
        edges & top != 0 ? start.bottom : start.top,
      );
      final growLeft = edges & left != 0, growUp = edges & top != 0;
      var w = r - l, h = b - t;
      if (edges & (left | right) != 0) {
        h = w / normalized;
      } else {
        w = h * normalized;
      }
      final limitW = growLeft ? anchor.dx : 1 - anchor.dx,
          limitH = growUp ? anchor.dy : 1 - anchor.dy;
      final factor = math.min(1.0, math.min(limitW / w, limitH / h));
      w *= factor;
      h *= factor;
      l = growLeft ? anchor.dx - w : anchor.dx;
      r = l + w;
      t = growUp ? anchor.dy - h : anchor.dy;
      b = t + h;
    }
    widget.onChanged(Rect.fromLTRB(l, t, r, b));
  }

  Rect shifted(double dx, double dy, {double resize = 0}) {
    final r = widget.crop;
    final w = (r.width + resize).clamp(.05, 1.0),
        h = widget.aspect == null
            ? (r.height + resize).clamp(.05, 1.0)
            : math.min(1.0, w * widget.pixels.aspectRatio / widget.aspect!);
    final width = widget.aspect == null
        ? w
        : h * widget.aspect! / widget.pixels.aspectRatio;
    final x = (r.center.dx + dx - width / 2).clamp(0.0, 1 - width),
        y = (r.center.dy + dy - h / 2).clamp(0.0, 1 - h);
    return Rect.fromLTWH(x, y, width, h);
  }

  void nudge(double dx, double dy, {double resize = 0}) =>
      widget.onChanged(shifted(dx, dy, resize: resize));
  String label(Rect r) =>
      '${(r.width * 100).round()}% × ${(r.height * 100).round()}%';

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = applyBoxFit(
        BoxFit.contain,
        widget.pixels,
        Size(math.max(1, box.maxWidth - 48), math.max(1, box.maxHeight - 48)),
      ).destination;
      frame = Alignment.center.inscribe(size, Offset.zero & box.biggest);
      return Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (!widget.enabled || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft) {
            nudge(-.01, 0);
          } else if (key == LogicalKeyboardKey.arrowRight) {
            nudge(.01, 0);
          } else if (key == LogicalKeyboardKey.arrowUp) {
            nudge(0, -.01);
          } else if (key == LogicalKeyboardKey.arrowDown) {
            nudge(0, .01);
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: Semantics(
          label: '裁切范围，可拖动四角或边缘调整，拖动内部移动',
          value: label(widget.crop),
          increasedValue: widget.enabled
              ? label(shifted(0, 0, resize: .05))
              : null,
          decreasedValue: widget.enabled
              ? label(shifted(0, 0, resize: -.05))
              : null,
          onIncrease: widget.enabled ? () => nudge(0, 0, resize: .05) : null,
          onDecrease: widget.enabled ? () => nudge(0, 0, resize: -.05) : null,
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.down,
            key: const ValueKey('crop-canvas'),
            behavior: HitTestBehavior.opaque,
            onPanStart: widget.enabled ? begin : null,
            onPanUpdate: widget.enabled ? update : null,
            child: Stack(
              children: [
                Positioned.fromRect(
                  rect: frame,
                  child: Image.file(
                    File(widget.image),
                    fit: BoxFit.fill,
                    excludeFromSemantics: true,
                    errorBuilder: (_, _, _) => Center(
                      child: TextButton(
                        onPressed: widget.onRetry,
                        child: const Text('重试预览'),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(painter: _CropOverlay(frame, actual)),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _CropOverlay extends CustomPainter {
  _CropOverlay(this.frame, this.crop);
  final Rect frame, crop;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(frame)
        ..addRect(crop),
      Paint()..color = const Color(0x99000000),
    );
    final paint = Paint()
      ..color = _white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(crop, paint);
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(crop.left + crop.width * i / 3, crop.top),
        Offset(crop.left + crop.width * i / 3, crop.bottom),
        paint..color = const Color(0x88ffffff),
      );
      canvas.drawLine(
        Offset(crop.left, crop.top + crop.height * i / 3),
        Offset(crop.right, crop.top + crop.height * i / 3),
        paint,
      );
    }
    for (final p in [
      crop.topLeft,
      crop.topRight,
      crop.bottomLeft,
      crop.bottomRight,
    ]) {
      final x = p.dx == crop.left ? 1.0 : -1.0,
          y = p.dy == crop.top ? 1.0 : -1.0;
      canvas.drawPath(
        Path()
          ..moveTo(p.dx, p.dy + y * 15)
          ..lineTo(p.dx, p.dy)
          ..lineTo(p.dx + x * 15, p.dy),
        paint
          ..color = _yellow
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_CropOverlay old) =>
      old.crop != crop || old.frame != frame;
}
