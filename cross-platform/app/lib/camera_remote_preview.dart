import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'domain.dart';
import 'editor_histogram.dart';

/// Display coordinates, including camera-reported rotation and letterboxing.
Rect remoteFrameRect(Size viewport, Json frame) {
  final width = frame['width'], height = frame['height'];
  if (width is! num ||
      height is! num ||
      width <= 0 ||
      height <= 0 ||
      viewport.isEmpty) {
    return Rect.zero;
  }
  final rotated = (frame['rotation'] as num? ?? 0).toInt() % 180 != 0;
  final source = rotated
      ? Size(height.toDouble(), width.toDouble())
      : Size(width.toDouble(), height.toDouble());
  final size = applyBoxFit(BoxFit.contain, source, viewport).destination;
  return Alignment.center.inscribe(size, Offset.zero & viewport);
}

bool remoteFrameIsFresh(DateTime? receivedAt, DateTime now) =>
    receivedAt != null &&
    !receivedAt.isAfter(now) &&
    now.difference(receivedAt) <= const Duration(seconds: 3);

class CameraRemotePreview extends StatefulWidget {
  const CameraRemotePreview({
    super.key,
    required this.frame,
    this.available = true,
    required this.viewing,
    required this.busy,
    required this.grid,
    required this.histogram,
    required this.onFocus,
    required this.onHistogram,
    required this.onResume,
    this.foreground = true,
    this.fresh = true,
  });
  final bool available;
  final Json frame;
  final bool viewing, busy, grid, histogram, foreground, fresh;
  final void Function(double x, double y)? onFocus;
  final void Function(EditorHistogramData? data) onHistogram;
  final VoidCallback? onResume;
  @override
  State<CameraRemotePreview> createState() => _CameraRemotePreviewState();
}

class _CameraRemotePreviewState extends State<CameraRemotePreview> {
  EditorHistogramData? data;
  Offset? focus;
  Offset chartPosition = const Offset(.03, 1);
  bool rgb = false;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(measure());
  }

  @override
  void didUpdateWidget(CameraRemotePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frame['path'] != widget.frame['path'] ||
        oldWidget.frame['sequence'] != widget.frame['sequence']) {
      unawaited(measure());
    }
  }

  Future<void> measure() async {
    final current = ++generation, path = widget.frame['path'];
    if (path is! String) {
      data = null;
      return;
    }
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(
        await File(path).readAsBytes(),
        targetWidth: 192,
        allowUpscaling: false,
      );
      image = (await codec.getNextFrame()).image;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null || !mounted || generation != current) return;
      final measured = EditorHistogramData.fromRgba(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        image.width,
        image.height,
      );
      setState(() => data = measured);
    } catch (_) {
      if (mounted && generation == current) setState(() => data = null);
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final image = remoteFrameRect(size, widget.frame);
      final path = widget.frame['path'];
      final ready = path is String && !image.isEmpty;
      final viewing = widget.viewing && widget.foreground && widget.fresh;
      final chartWidth = math.min(190.0, math.max(120.0, size.width - 24));
      const chartHeight = 76.0;
      final travel = Offset(
        math.max(0, size.width - chartWidth - 24),
        math.max(0, size.height - chartHeight - 24),
      );
      return ClipRect(
        child: ColoredBox(
          color: const Color(0xff090a0a),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const Key('remote-frame-focus'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp:
                      !widget.busy && viewing && ready && widget.onFocus != null
                      ? (tap) {
                          if (!image.contains(tap.localPosition)) return;
                          final point = Offset(
                            (tap.localPosition.dx - image.left) / image.width,
                            (tap.localPosition.dy - image.top) / image.height,
                          );
                          setState(() => focus = point);
                          widget.onFocus!(point.dx, point.dy);
                        }
                      : null,
                  child: Stack(
                    children: [
                      if (ready)
                        Positioned.fromRect(
                          rect: image,
                          child: RotatedBox(
                            quarterTurns:
                                (widget.frame['rotation'] as num? ?? 0)
                                    .toInt() ~/
                                90,
                            child: Image.file(
                              File(path),
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              cacheWidth: 1280,
                              key: ValueKey(widget.frame['sequence']),
                              errorBuilder: (_, _, _) =>
                                  const Center(child: Text('取景帧无法显示')),
                            ),
                          ),
                        ),
                      if (ready && widget.grid)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              key: const Key('remote-grid'),
                              painter: _RemoteGrid(image),
                            ),
                          ),
                        ),
                      if (focus != null && ready && viewing)
                        Positioned(
                          left: image.left + image.width * focus!.dx - 24,
                          top: image.top + image.height * focus!.dy - 20,
                          child: IgnorePointer(
                            child: Container(
                              width: 48,
                              height: 40,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  width: 2,
                                  color:
                                      widget.frame['focusKnown'] == true &&
                                          widget.frame['focused'] == true
                                      ? const Color(0xff9ac8ae)
                                      : const Color(0xfff3b493),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (!viewing || !ready)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0xd9121313),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            !widget.available
                                ? '此相机未提供实时取景'
                                : !widget.foreground ||
                                      (ready && !widget.fresh) ||
                                      (ready && !widget.viewing)
                                ? '取景已暂停'
                                : !widget.viewing
                                ? '取景已关闭'
                                : '等待相机实时画面',
                          ),
                          if (!widget.busy && widget.onResume != null) ...[
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: widget.onResume,
                              child: const Text('恢复取景'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              if (widget.histogram)
                Positioned(
                  left: 12 + travel.dx * chartPosition.dx,
                  top: 12 + travel.dy * chartPosition.dy,
                  width: chartWidth,
                  height: chartHeight,
                  child: Semantics(
                    label: '取景直方图，点按放大，拖动调整位置',
                    button: true,
                    child: GestureDetector(
                      key: const Key('remote-histogram'),
                      onTap: () => widget.onHistogram(data),
                      onPanUpdate: (drag) => setState(
                        () => chartPosition = Offset(
                          travel.dx == 0
                              ? 0
                              : (chartPosition.dx + drag.delta.dx / travel.dx)
                                    .clamp(0, 1),
                          travel.dy == 0
                              ? 0
                              : (chartPosition.dy + drag.delta.dy / travel.dy)
                                    .clamp(0, 1),
                        ),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xe6191a18),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(9),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                !ready
                                    ? '等待取景'
                                    : viewing
                                    ? '取景 · 亮度'
                                    : '上次取景 · 已暂停',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xffbeb9b2),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: Opacity(
                                  opacity: viewing ? 1 : .4,
                                  child: CustomPaint(
                                    size: Size.infinite,
                                    painter: EditorHistogramPainter(
                                      data: data,
                                      rgb: rgb,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _RemoteGrid extends CustomPainter {
  const _RemoteGrid(this.image);
  final Rect image;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x88ffffff)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = image.left + image.width * i / 3;
      final y = image.top + image.height * i / 3;
      canvas.drawLine(Offset(x, image.top), Offset(x, image.bottom), paint);
      canvas.drawLine(Offset(image.left, y), Offset(image.right, y), paint);
    }
  }

  @override
  bool shouldRepaint(_RemoteGrid oldDelegate) => oldDelegate.image != image;
}
