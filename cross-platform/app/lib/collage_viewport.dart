import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'collage_composition.dart';
import 'collage_chrome.dart';

/// Viewing the composition and cropping a source are separate gesture modes.
class CollageViewport extends StatefulWidget {
  const CollageViewport({
    super.key,
    required this.paths,
    required this.sizes,
    required this.transforms,
    required this.style,
    required this.selected,
    required this.enabled,
    required this.photoEditing,
    required this.textEditing,
    required this.onSelected,
    required this.onTransform,
    required this.onStyle,
  });
  final List<String> paths;
  final List<Size> sizes;
  final List<CollageTransform> transforms;
  final CollageStyle style;
  final int? selected;
  final bool enabled, photoEditing, textEditing;
  final ValueChanged<int?> onSelected;
  final void Function(int, CollageTransform) onTransform;
  final ValueChanged<CollageStyle> onStyle;
  @override
  CollageViewportState createState() => CollageViewportState();
}

class CollageViewportState extends State<CollageViewport> {
  final view = TransformationController();
  final images = <String, ui.Image>{};
  int serial = 0;
  bool loading = true, failed = false, fitPending = true, viewChanged = false;
  Size viewport = Size.zero, scene = Size.zero;
  int? gesturePhoto;
  CollageTransform gestureTransform = const CollageTransform();
  Offset gestureOrigin = Offset.zero, gestureText = Offset.zero;

  void fit() {
    if (!mounted || viewport.isEmpty || scene.isEmpty) return;
    final scale = math.min(
      viewport.width / scene.width,
      viewport.height / scene.height,
    );
    view.value = Matrix4.identity()
      ..translateByDouble(
        (viewport.width - scene.width * scale) / 2,
        (viewport.height - scene.height * scale) / 2,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, scale, 1);
    viewChanged = false;
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(CollageViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paths.join('\n') != widget.paths.join('\n')) {
      load();
      fitPending = true;
    }
    if (oldWidget.style.mode != widget.style.mode ||
        oldWidget.style.ratio != widget.style.ratio ||
        oldWidget.style.pattern != widget.style.pattern ||
        oldWidget.style.horizontal != widget.style.horizontal) {
      fitPending = true;
    }
  }

  Future<void> load() async {
    final attempt = ++serial;
    loading = true;
    failed = false;
    final wanted = widget.paths.toSet();
    for (final path in images.keys.toList()) {
      if (!wanted.contains(path)) images.remove(path)?.dispose();
    }
    for (final path in wanted.where((path) => !images.containsKey(path))) {
      ui.Image? image;
      try {
        final bytes = await File(path).readAsBytes(),
            buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        ui.ImageDescriptor? descriptor;
        ui.Codec? codec;
        try {
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          final scale = math.min(
            1.0,
            640 / math.max(descriptor.width, descriptor.height),
          );
          codec = await descriptor.instantiateCodec(
            targetWidth: math.max(1, (descriptor.width * scale).round()),
            targetHeight: math.max(1, (descriptor.height * scale).round()),
          );
          image = (await codec.getNextFrame()).image;
        } finally {
          codec?.dispose();
          descriptor?.dispose();
          buffer.dispose();
        }
        if (!mounted || attempt != serial) {
          image.dispose();
          return;
        }
        images[path] = image;
      } catch (_) {
        image?.dispose();
        if (mounted && attempt == serial) failed = true;
      }
    }
    if (mounted && attempt == serial) setState(() => loading = false);
  }

  @override
  void dispose() {
    serial++;
    view.dispose();
    for (final image in images.values) {
      image.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plan = composeCollage(
      widget.sizes,
      widget.style,
      1024,
      transforms: widget.transforms,
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        final nextViewport = Size(bounds.maxWidth, bounds.maxHeight);
        final nextScene = Size(390, 390 / plan.size.aspectRatio);
        if (nextScene != scene || (!viewChanged && nextViewport != viewport)) {
          fitPending = true;
        }
        viewport = nextViewport;
        scene = nextScene;
        if (fitPending) {
          fitPending = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) fit();
          });
        }
        final fittedScale = math.min(
          viewport.width / scene.width,
          viewport.height / scene.height,
        );
        final editing = widget.photoEditing || widget.textEditing;
        return InteractiveViewer(
          key: const ValueKey('collage-viewer'),
          transformationController: view,
          constrained: false,
          alignment: Alignment.topLeft,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          minScale: math.max(.0001, fittedScale / 4),
          maxScale: math.max(8, fittedScale * 8),
          panEnabled: widget.enabled && !editing,
          scaleEnabled: widget.enabled && !editing,
          onInteractionStart: (_) {
            if (!editing) viewChanged = true;
          },
          child: SizedBox(
            width: scene.width,
            height: scene.height,
            child: GestureDetector(
              key: const ValueKey('collage-canvas'),
              behavior: HitTestBehavior.opaque,
              onTapUp: !widget.enabled || widget.textEditing
                  ? null
                  : (details) {
                      final point =
                          details.localPosition /
                          (scene.width / plan.size.width);
                      final index = plan.cells.indexWhere(
                        (cell) => cell.contains(point),
                      );
                      widget.onSelected(
                        index < 0 || index == widget.selected ? null : index,
                      );
                    },
              onScaleStart: !widget.enabled || !editing
                  ? null
                  : (details) {
                      gestureOrigin = details.localFocalPoint;
                      gestureText =
                          widget.style.texts.firstOrNull?.position ??
                          const Offset(.5, .85);
                      gesturePhoto = null;
                      final i = widget.selected;
                      final point =
                          details.localFocalPoint /
                          (scene.width / plan.size.width);
                      if (widget.photoEditing &&
                          i != null &&
                          i < plan.cells.length &&
                          plan.cells[i].contains(point)) {
                        gesturePhoto = i;
                        gestureTransform = widget.transforms[i];
                      }
                    },
              onScaleUpdate: !widget.enabled || !editing
                  ? null
                  : (details) {
                      final delta = details.localFocalPoint - gestureOrigin;
                      if (widget.textEditing) {
                        final text = widget.style.texts.firstOrNull;
                        if (text != null) {
                          widget.onStyle(
                            widget.style.copyWith(
                              texts: [
                                text.copyWith(
                                  position: Offset(
                                    (gestureText.dx + delta.dx / scene.width)
                                        .clamp(.03, .97),
                                    (gestureText.dy + delta.dy / scene.height)
                                        .clamp(.03, .97),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                      } else if (gesturePhoto case final i?) {
                        final cell = plan.cells[i],
                            factor = scene.width / plan.size.width;
                        widget.onTransform(
                          i,
                          gestureTransform.copyWith(
                            scale: (gestureTransform.scale * details.scale)
                                .clamp(1.0, 4.0),
                            offset: Offset(
                              (gestureTransform.offset.dx +
                                      delta.dx / (cell.width * factor) * 2)
                                  .clamp(-1.0, 1.0),
                              (gestureTransform.offset.dy +
                                      delta.dy / (cell.height * factor) * 2)
                                  .clamp(-1.0, 1.0),
                            ),
                          ),
                        );
                      }
                    },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _CompositionPainter(
                      widget.paths.map((p) => images[p]).toList(),
                      plan,
                      widget.style,
                      widget.transforms,
                      widget.selected,
                      editing,
                    ),
                  ),
                  if (loading)
                    const Center(
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (!loading && failed)
                    const Center(
                      child: ColoredBox(
                        color: Colors.black54,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                            '部分照片预览不可用，请替换后重试',
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompositionPainter extends CustomPainter {
  _CompositionPainter(
    this.images,
    this.plan,
    this.style,
    this.transforms,
    this.selected,
    this.editing,
  );
  final List<ui.Image?> images;
  final CollagePlan plan;
  final CollageStyle style;
  final List<CollageTransform> transforms;
  final int? selected;
  final bool editing;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / plan.size.width;
    canvas.scale(scale);
    canvas.drawRect(Offset.zero & plan.size, Paint()..color = style.background);
    final matrix = collageColorMatrix(style);
    for (var i = 0; i < images.length; i++) {
      if (images[i] != null) {
        paintCollageImage(
          canvas,
          images[i]!,
          plan.cells[i],
          transforms[i],
          contain: style.contain,
          matrix: matrix,
          radius: style.radius * plan.size.width / 390,
        );
      }
    }
    paintCollageTexts(canvas, style.texts, plan.size);
    if (selected != null && selected! < plan.cells.length) {
      canvas.drawRect(
        plan.cells[selected!].deflate(1 / scale),
        Paint()
          ..color = (editing ? collageUiAccent : Colors.white)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale,
      );
    }
  }

  @override
  bool shouldRepaint(_CompositionPainter old) => true;
}
