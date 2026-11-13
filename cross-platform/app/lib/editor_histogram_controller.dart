import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'editor_histogram.dart';

/// Read-only statistics of the working sRGB photograph, before the display border.
class EditorHistogramController extends ChangeNotifier {
  EditorHistogramController({
    required this.core,
    required this.owner,
    required this.path,
    required this.isCurrent,
  });
  final HueviaCore core;
  final String owner, path;
  final bool Function() isCurrent;
  EditorHistogramData? data;
  ui.Image? warning;
  bool visible = false, rgb = false, shadows = false, highlights = false;
  bool updating = false, closed = false;
  bool warningCurrent = false;
  String? error, job;
  int generation = 0;
  Json? requestedRecipe;
  String sourceSha = '';
  bool get current => !closed && isCurrent();

  void changed() {
    if (!closed) notifyListeners();
  }

  void markUpdating() {
    if (!visible || !current) return;
    generation++;
    if (job != null) unawaited(core.cancel(job!));
    job = null;
    updating = true;
    warningCurrent = false;
    changed();
  }

  void toggle(Json recipe, String sha) {
    visible = !visible;
    if (visible) {
      unawaited(update(recipe, sha));
    } else {
      generation++;
      updating = false;
      if (job != null) unawaited(core.cancel(job!));
      job = null;
    }
    changed();
  }

  void setRgb(bool value) {
    rgb = value;
    changed();
  }

  void setShadows(bool value) {
    shadows = value;
    unawaited(rebuildWarning());
    changed();
  }

  void setHighlights(bool value) {
    highlights = value;
    unawaited(rebuildWarning());
    changed();
  }

  Future<void> discard(String? value) async {
    if (value == null || core.root.isEmpty) return;
    final directory = p.normalize(p.join(core.root, 'previews'));
    if (!p.isWithin(directory, p.normalize(value))) return;
    try {
      if (await FileSystemEntity.type(value, followLinks: false) ==
              FileSystemEntityType.file &&
          p.equals(
            p.normalize(value),
            p.normalize(await File(value).resolveSymbolicLinks()),
          )) {
        await File(value).delete();
      }
    } on FileSystemException {
      /* Disposable preview; never touch the source. */
    }
  }

  Future<void> update(Json recipe, String sha) async {
    requestedRecipe = Recipe(data: recipe).data;
    sourceSha = sha;
    if (!visible || !current) return;
    final token = ++generation;
    if (job != null) unawaited(core.cancel(job!));
    final id = 'histogram-${DateTime.now().microsecondsSinceEpoch}';
    job = id;
    updating = true;
    warningCurrent = false;
    error = null;
    changed();
    String? file;
    ui.Codec? codec;
    ui.Image? image;
    try {
      final frozen = Recipe(data: recipe).data
        ..['border'] = <String, dynamic>{};
      final result = await core.call('media.reviewPreview', {
        'owner': owner,
        'path': path,
        'recipe': frozen,
        'maxEdge': 1280,
        'snapshot': true,
        'expectedSourceSha': sha,
      }, id);
      file = result['path'] as String?;
      if (!current || token != generation) return;
      if (file == null || !p.isWithin(p.join(core.root, 'previews'), file)) {
        throw const AppFailure('直方图未取得有效预览。');
      }
      codec = await ui.instantiateImageCodec(await File(file).readAsBytes());
      image = (await codec.getNextFrame()).image;
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (!current || token != generation) return;
      if (bytes == null) throw const AppFailure('无法读取直方图像素。');
      data = EditorHistogramData.fromRgba(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        image.width,
        image.height,
      );
      warningCurrent = true;
      await rebuildWarning();
    } catch (failure) {
      if (current && token == generation) error = '$failure';
    } finally {
      image?.dispose();
      codec?.dispose();
      await discard(file);
      if (current && token == generation) {
        updating = false;
        job = null;
        changed();
      }
    }
  }

  Future<void> rebuildWarning() async {
    final value = data;
    final expectedShadows = shadows, expectedHighlights = highlights;
    if (!current || value == null || (!shadows && !highlights)) {
      final old = warning;
      warning = null;
      old?.dispose();
      changed();
      return;
    }
    final bytes = value.makeWarningRgba(
      shadows: shadows,
      highlights: highlights,
    );
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      Uint8List.fromList(bytes),
      value.width,
      value.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final next = await completer.future;
    if (!current ||
        !identical(value, data) ||
        shadows != expectedShadows ||
        highlights != expectedHighlights) {
      next.dispose();
      return;
    }
    final old = warning;
    warning = next;
    changed();
    old?.dispose();
  }

  void invalidate() {
    generation++;
    if (job != null) unawaited(core.cancel(job!));
    job = null;
    visible = false;
    updating = false;
    data = null;
    warningCurrent = false;
    warning?.dispose();
    warning = null;
    changed();
  }

  @override
  void dispose() {
    closed = true;
    generation++;
    if (job != null) unawaited(core.cancel(job!));
    warning?.dispose();
    warning = null;
    super.dispose();
  }
}
