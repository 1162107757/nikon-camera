import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'collage_chrome.dart';
import 'collage_composition.dart';

/// One bounded decoded set shared by every layout and template thumbnail.
class CollageThumbnailCache extends ChangeNotifier {
  final images = <String, ui.Image>{};
  int _serial = 0;
  bool _disposed = false;

  Future<void> load(List<String> paths) async {
    final serial = ++_serial, wanted = paths.toSet();
    for (final path in images.keys.toList()) {
      if (!wanted.contains(path)) images.remove(path)?.dispose();
    }
    for (final path in wanted.where((p) => !images.containsKey(p))) {
      ui.Image? decoded;
      try {
        final bytes = await File(path).readAsBytes();
        final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
        ui.ImageDescriptor? descriptor;
        ui.Codec? codec;
        try {
          descriptor = await ui.ImageDescriptor.encoded(buffer);
          final factor = math.min(
            1.0,
            192 / math.max(descriptor.width, descriptor.height),
          );
          codec = await descriptor.instantiateCodec(
            targetWidth: math.max(1, (descriptor.width * factor).round()),
            targetHeight: math.max(1, (descriptor.height * factor).round()),
          );
          decoded = (await codec.getNextFrame()).image;
        } finally {
          codec?.dispose();
          descriptor?.dispose();
          buffer.dispose();
        }
        if (_disposed || serial != _serial) {
          decoded.dispose();
          return;
        }
        images[path] = decoded;
      } catch (_) {
        decoded?.dispose();
      }
    }
    if (!_disposed && serial == _serial) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _serial++;
    for (final image in images.values) {
      image.dispose();
    }
    images.clear();
    super.dispose();
  }
}

class CollageThumbnail extends StatelessWidget {
  const CollageThumbnail({
    super.key,
    required this.cache,
    required this.paths,
    required this.sizes,
    required this.transforms,
    required this.style,
  });
  final CollageThumbnailCache cache;
  final List<String> paths;
  final List<Size> sizes;
  final List<CollageTransform> transforms;
  final CollageStyle style;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: cache,
    builder: (context, _) {
      if (paths.length < 2 || !paths.any(cache.images.containsKey)) {
        return const ColoredBox(
          color: collageUiContainer,
          child: Center(
            child: Icon(Icons.photo_outlined, size: 20, color: collageUiMuted),
          ),
        );
      }
      final plan = composeCollage(sizes, style, 256, transforms: transforms);
      return CustomPaint(
        painter: _ThumbnailPainter(
          paths.map((p) => cache.images[p]).toList(),
          plan,
          style,
          transforms,
        ),
        child: const SizedBox.expand(),
      );
    },
  );
}

class _ThumbnailPainter extends CustomPainter {
  _ThumbnailPainter(this.images, this.plan, this.style, this.transforms);
  final List<ui.Image?> images;
  final CollagePlan plan;
  final CollageStyle style;
  final List<CollageTransform> transforms;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    // Fit actual layout geometry; thumbnail viewing never changes the recipe.
    final factor = math.min(
      size.width / plan.size.width,
      size.height / plan.size.height,
    );
    canvas.drawRect(Offset.zero & size, Paint()..color = collageUiContainer);
    canvas.translate(
      (size.width - plan.size.width * factor) / 2,
      (size.height - plan.size.height * factor) / 2,
    );
    canvas.scale(factor);
    canvas.drawRect(Offset.zero & plan.size, Paint()..color = style.background);
    final matrix = collageColorMatrix(style);
    for (var i = 0; i < images.length; i++) {
      if (images[i] case final image?) {
        paintCollageImage(
          canvas,
          image,
          plan.cells[i],
          transforms[i],
          contain: style.contain,
          matrix: matrix,
          radius: style.radius * plan.size.width / 390,
        );
      }
    }
    paintCollageTexts(canvas, style.texts, plan.size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ThumbnailPainter oldDelegate) => true;
}
