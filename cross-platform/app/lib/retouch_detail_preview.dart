import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import 'domain.dart';
import 'editing_detail_preview.dart';
import 'retouch_original_controls.dart';

/// A readonly raster overlay in PhotoStage's existing normalized image plane.
/// The caller keeps its low-resolution image, coordinate size and gesture lease.
class RetouchDetailPreview extends StatefulWidget {
  const RetouchDetailPreview({
    super.key,
    required this.core,
    required this.owner,
    required this.sourcePath,
    required this.frame,
    required this.viewport,
    required this.isCurrent,
    required this.enabled,
    required this.invalidation,
  });
  final HueviaCore core;
  final String owner, sourcePath;
  final Json frame;
  final ValueListenable<RetouchPhotoViewport?> viewport;
  final bool Function() isCurrent;
  final bool enabled;
  final ValueListenable<int> invalidation;
  @override
  State<RetouchDetailPreview> createState() => _RetouchDetailPreviewState();
}

class _RetouchDetailPreviewState extends State<RetouchDetailPreview> {
  late EditingDetailPreviewController controller;
  double pixelRatio = 1;
  bool visible = true;
  @override
  void initState() {
    super.initState();
    createController();
    widget.viewport.addListener(viewportChanged);
    widget.invalidation.addListener(pause);
    configure();
  }

  void createController() {
    controller = EditingDetailPreviewController(
      core: widget.core,
      owner: widget.owner,
      sourcePath: widget.sourcePath,
      maxTileEdge: 2048,
      isCurrent: () => mounted && visible && widget.isCurrent(),
    );
  }

  void configure() {
    final recipe = widget.frame['_detailRecipe'];
    final width = widget.frame['width'] as num? ?? 0;
    final height = widget.frame['height'] as num? ?? 0;
    if (recipe is! Map || width <= 0 || height <= 0) {
      controller.setEnabled(false);
      return;
    }
    controller.setEnabled(widget.enabled && visible);
    controller.configure(
      recipe: object(recipe),
      revision: widget.frame['_detailRevision'] as int? ?? 0,
      frameIdentity: widget.frame['path'] as String,
      outputSize: Size(width.toDouble(), height.toDouble()),
      expectedSourceSha: widget.frame['sourceSha'] as String? ?? '',
    );
    viewportChanged();
  }

  // Called synchronously before a new engine mutation enters the serial worker.
  void pause() => controller.setEnabled(false);

  void viewportChanged() {
    final value = widget.viewport.value;
    if (value == null) return;
    final visible = value.imageFrame.intersect(value.clip);
    controller.setViewport(
      visibleRegion: value.visibleRegion,
      zoom: value.zoom,
      viewportPixelSize: visible.isEmpty
          ? Size.zero
          : visible.size * pixelRatio,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    pixelRatio = MediaQuery.devicePixelRatioOf(context);
    visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    configure();
  }

  @override
  void didUpdateWidget(RetouchDetailPreview old) {
    super.didUpdateWidget(old);
    if (old.viewport != widget.viewport) {
      old.viewport.removeListener(viewportChanged);
      widget.viewport.addListener(viewportChanged);
    }
    if (old.invalidation != widget.invalidation) {
      old.invalidation.removeListener(pause);
      widget.invalidation.addListener(pause);
    }
    if (old.core != widget.core ||
        old.owner != widget.owner ||
        old.sourcePath != widget.sourcePath) {
      controller.dispose();
      createController();
    }
    configure();
  }

  @override
  void dispose() {
    widget.viewport.removeListener(viewportChanged);
    widget.invalidation.removeListener(pause);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: EditingDetailTileLayer(controller: controller));
}
