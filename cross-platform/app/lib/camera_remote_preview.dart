import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'domain.dart';
import 'editor_histogram.dart';

enum RemoteGrid {
  thirds(3, '九宫格'),
  quarters(4, '16 宫格'),
  off(0, '关闭网格');

  const RemoteGrid(this.divisions, this.label);
  final int divisions;
  final String label;
}

/// Display coordinates of the entire frame, including any cropped area.
Rect remoteFrameRect(Size viewport, Json frame, {BoxFit fit = BoxFit.contain}) {
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
  final fitted = applyBoxFit(fit, source, viewport);
  final scale = fitted.destination.width / fitted.source.width;
  return Alignment.center.inscribe(source * scale, Offset.zero & viewport);
}

bool remoteFrameIsFresh(DateTime? receivedAt, DateTime now) =>
    receivedAt != null &&
    !receivedAt.isAfter(now) &&
    now.difference(receivedAt) <= const Duration(seconds: 3);

bool _sameFrameGeometry(Json first, Json second) {
  final width = first['width'], height = first['height'];
  final nextWidth = second['width'], nextHeight = second['height'];
  if (width is! num ||
      height is! num ||
      nextWidth is! num ||
      nextHeight is! num) {
    return false;
  }
  final a = width * nextHeight, b = nextWidth * height;
  return (first['rotation'] ?? 0) == (second['rotation'] ?? 0) &&
      (a - b).abs() <= math.max(a, b) * .01;
}

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
    this.fit = BoxFit.contain,
    this.frameInsets = EdgeInsets.zero,
    this.histogramRgb = false,
    this.histogramInsets = const EdgeInsets.all(12),
  });
  final bool available;
  final Json frame;
  final bool viewing, busy, histogram, foreground, fresh;
  final RemoteGrid grid;
  final BoxFit fit;
  final EdgeInsets frameInsets;
  final bool histogramRgb;
  final EdgeInsets histogramInsets;
  final void Function(double x, double y)? onFocus;
  final void Function(EditorHistogramData? data) onHistogram;
  final VoidCallback? onResume;
  @override
  State<CameraRemotePreview> createState() => _CameraRemotePreviewState();
}

class _CameraRemotePreviewState extends State<CameraRemotePreview> {
  EditorHistogramData? data;
  ui.Image? displayImage;
  Json displayGeometry = const {}, displayedFrame = const {};
  Json acceptedGeometry = const {};
  Json? pendingGeometry, queuedFrame;
  Offset? focus;
  Offset chartPosition = Offset.zero;
  int streamEpoch = 0;
  bool decoding = false;

  @override
  void initState() {
    super.initState();
    enqueue(widget.frame);
  }

  @override
  void didUpdateWidget(CameraRemotePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.histogram) data = null;
    if (oldWidget.frame['path'] != widget.frame['path'] ||
        oldWidget.frame['sequence'] != widget.frame['sequence'] ||
        (!oldWidget.histogram && widget.histogram)) {
      enqueue(widget.frame);
    }
  }

  void enqueue(Json frame) {
    if (frame['path'] is! String) {
      streamEpoch++;
      queuedFrame = pendingGeometry = null;
      displayGeometry = displayedFrame = acceptedGeometry = const {};
      retireDisplayImage();
      data = null;
      focus = null;
      return;
    }
    // Require a second matching frame before switching orientation or crop.
    // One inconsistent frame must not zoom the preview or move the grid.
    if (acceptedGeometry.isEmpty) {
      acceptedGeometry = frame;
    } else if (!_sameFrameGeometry(acceptedGeometry, frame)) {
      final candidate = pendingGeometry;
      pendingGeometry = frame;
      if (candidate == null ||
          candidate['sequence'] == frame['sequence'] ||
          !_sameFrameGeometry(candidate, frame)) {
        return;
      }
      acceptedGeometry = frame;
    }
    pendingGeometry = null;
    queuedFrame = frame;
    if (!decoding) unawaited(decodeFrames());
  }

  void retireDisplayImage() {
    if (displayImage case final image?) {
      displayImage = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
    }
  }

  Future<void> decodeFrames() async {
    decoding = true;
    try {
      while (mounted && queuedFrame != null) {
        final next = queuedFrame!;
        queuedFrame = null;
        final epoch = streamEpoch;
        ui.Image? image;
        try {
          // The camera alternates filenames. Decode this snapshot without the
          // file-path image cache and keep the previous frame until it is ready.
          final jpeg = await File(next['path'] as String).readAsBytes();
          image = await decode(jpeg, 1280);
          if (!mounted || streamEpoch != epoch) continue;
          final decoded = image;
          setState(() {
            retireDisplayImage();
            displayImage = decoded;
            displayedFrame = next;
            if (!_sameFrameGeometry(displayGeometry, next)) {
              displayGeometry = next;
              focus = null;
            }
          });
          image = null;
          if (!widget.histogram) continue;
          final measured = await measure(jpeg);
          if (mounted && streamEpoch == epoch && widget.histogram) {
            setState(() => data = measured);
          }
        } catch (_) {
          // A missed or unreadable frame leaves the last displayed image in place.
        } finally {
          image?.dispose();
        }
      }
    } finally {
      decoding = false;
    }
  }

  Future<ui.Image> decode(Uint8List bytes, int width) async {
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: width,
      allowUpscaling: false,
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  Future<EditorHistogramData?> measure(Uint8List jpeg) async {
    final image = await decode(jpeg, 192);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) return null;
      return EditorHistogramData.fromRgba(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        image.width,
        image.height,
      );
    } finally {
      image.dispose();
    }
  }

  @override
  void dispose() {
    streamEpoch++;
    displayImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final screen = Offset.zero & size;
      final viewport = widget.fit == BoxFit.contain
          ? widget.frameInsets.deflateRect(screen)
          : screen;
      final decoded = displayImage;
      // Use the decoded pixel ratio. The camera's reported dimensions are
      // useful for AF coordinates but must never stretch a decoded frame.
      final pixels = decoded == null
          ? const <String, dynamic>{}
          : {
              'width': decoded.width,
              'height': decoded.height,
              'rotation': displayGeometry['rotation'],
            };
      final image = remoteFrameRect(
        viewport.size,
        pixels,
        fit: widget.fit,
      ).shift(viewport.topLeft);
      final visible = image.intersect(viewport);
      final ready = decoded != null && !image.isEmpty;
      final viewing = widget.viewing && widget.foreground && widget.fresh;
      final canFocus =
          ready &&
          viewing &&
          !widget.busy &&
          _sameFrameGeometry(displayGeometry, pixels) &&
          _sameFrameGeometry(displayGeometry, widget.frame) &&
          widget.onFocus != null;
      final insets = widget.histogramInsets;
      final left = math.min(insets.left, math.max(0.0, size.width - 108));
      final top = math.min(insets.top, math.max(0.0, size.height - 70));
      final chartWidth = math.min(108.0, size.width - left);
      final chartHeight = math.min(70.0, size.height - top);
      final travel = Offset(
        math.max(0, size.width - chartWidth - left - insets.right),
        math.max(0, size.height - chartHeight - top - insets.bottom),
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
                  onTapUp: canFocus
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
                                (displayGeometry['rotation'] as num? ?? 0)
                                    .toInt() ~/
                                90,
                            child: RawImage(
                              key: const Key('remote-frame-image'),
                              image: decoded,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      if (ready && widget.fit == BoxFit.cover)
                        const Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x59202d26),
                                    Color(0x00202d26),
                                    Color(0x00111a17),
                                    Color(0x73111a17),
                                  ],
                                  stops: [0, .24, .66, 1],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (ready && widget.grid != RemoteGrid.off)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              key: const Key('remote-grid'),
                              painter: _RemoteGrid(
                                visible,
                                widget.grid.divisions,
                              ),
                            ),
                          ),
                        ),
                      if (focus != null && ready && viewing)
                        Positioned(
                          left: image.left + image.width * focus!.dx - 24,
                          top: image.top + image.height * focus!.dy - 20,
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _RemoteFocusMark(
                                displayedFrame['focusKnown'] == true &&
                                    displayedFrame['focused'] == true,
                              ),
                              size: const Size(48, 40),
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
              if (widget.histogram && ready && viewing)
                Positioned(
                  left: left + travel.dx * chartPosition.dx,
                  top: top + travel.dy * chartPosition.dy,
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
                          color: const Color(0xdc131d18),
                          border: Border.all(color: const Color(0x45eff7ef)),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      widget.histogramRgb ? 'RGB' : '亮度',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xffeff4e8),
                                      ),
                                    ),
                                  ),
                                  const Icon(Icons.open_in_full, size: 12),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: EditorHistogramPainter(
                                    data: data,
                                    rgb: widget.histogramRgb,
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

class _RemoteFocusMark extends CustomPainter {
  const _RemoteFocusMark(this.locked);

  final bool locked;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(1, 11)
      ..lineTo(1, 1)
      ..lineTo(11, 1)
      ..moveTo(size.width - 11, 1)
      ..lineTo(size.width - 1, 1)
      ..lineTo(size.width - 1, 11)
      ..moveTo(1, size.height - 11)
      ..lineTo(1, size.height - 1)
      ..lineTo(11, size.height - 1)
      ..moveTo(size.width - 11, size.height - 1)
      ..lineTo(size.width - 1, size.height - 1)
      ..lineTo(size.width - 1, size.height - 11);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = locked ? const Color(0xffd6ecbb) : const Color(0xfff6f1eb),
    );
  }

  @override
  bool shouldRepaint(_RemoteFocusMark oldDelegate) =>
      oldDelegate.locked != locked;
}

class _RemoteGrid extends CustomPainter {
  const _RemoteGrid(this.image, this.divisions);
  final Rect image;
  final int divisions;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x96f2fff0)
      ..strokeWidth = 1;
    for (var i = 1; i < divisions; i++) {
      final x = image.left + image.width * i / divisions;
      final y = image.top + image.height * i / divisions;
      canvas.drawLine(Offset(x, image.top), Offset(x, image.bottom), paint);
      canvas.drawLine(Offset(image.left, y), Offset(image.right, y), paint);
    }
  }

  @override
  bool shouldRepaint(_RemoteGrid oldDelegate) =>
      oldDelegate.image != image || oldDelegate.divisions != divisions;
}
