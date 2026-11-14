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
    this.initialDetails,
  });
  final HueviaCore core;
  final String owner, sourcePath;
  final Json frame;
  final ValueListenable<RetouchPhotoViewport?> viewport;
  final bool Function() isCurrent;
  final bool enabled;
  final ValueListenable<int> invalidation;
  final EditingDetailHandoff? initialDetails;
  @override
  State<RetouchDetailPreview> createState() => RetouchDetailPreviewState();
}

class RetouchDetailPreviewState extends State<RetouchDetailPreview> {
  late EditingDetailPreviewController controller;
  double pixelRatio = 1;
  bool visible = true;
  RetouchPhotoViewport? layoutViewport;
  EditingDetailHandoff? consumedDetails;
  Json? pendingFrame;
  RetouchPhotoViewport? Function()? pendingViewport;
  int replacementGeneration = 0;

  bool get hasSharpFrame =>
      mounted &&
      visible &&
      widget.isCurrent() &&
      widget.enabled &&
      controller.tile?.frameIdentity == widget.frame['path'];

  Future<bool> prepareFrame(
    Json next, {
    required RetouchPhotoViewport? Function() resolveViewport,
  }) async {
    if (!hasSharpFrame || pendingFrame != null) return false;
    final recipe = next['_detailRecipe'];
    final width = next['width'] as num? ?? 0;
    final height = next['height'] as num? ?? 0;
    if (recipe is! Map ||
        width <= 0 ||
        height <= 0 ||
        next['path'] is! String) {
      return false;
    }
    final frozenSha = controller.tile?.sourceSha;
    if ((next['sourceSha'] is! String ||
            (next['sourceSha'] as String).isEmpty) &&
        frozenSha != null &&
        frozenSha.isNotEmpty) {
      // Ordinary previews omit this field. Keep the verified source in the
      // accepted DTO so its widget commit cannot invalidate the new sharp tile.
      next['sourceSha'] = frozenSha;
    }
    final generation = ++replacementGeneration;
    pendingFrame = next;
    pendingViewport = resolveViewport;
    viewportChanged();
    final ready = await controller.prepareReplacement(
      recipe: object(recipe),
      revision: next['_detailRevision'] as int? ?? 0,
      frameIdentity: next['path'] as String,
      outputSize: Size(width.toDouble(), height.toDouble()),
      expectedSourceSha: next['sourceSha'] as String? ?? '',
    );
    if (!mounted ||
        generation != replacementGeneration ||
        !widget.isCurrent()) {
      return false;
    }
    if (!ready) {
      pendingFrame = null;
      pendingViewport = null;
    }
    // On success the caller commits its base frame in this microtask, before
    // the next paint. Keep the pending profile until that widget update arrives.
    return ready;
  }

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
    if (pendingFrame != null) {
      controller.setEnabled(widget.enabled && visible);
      viewportChanged();
      return;
    }
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
  void pause() {
    replacementGeneration++;
    pendingFrame = null;
    pendingViewport = null;
    controller.setEnabled(false);
  }

  void viewportChanged() {
    final value =
        pendingViewport?.call() ?? layoutViewport ?? widget.viewport.value;
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

  void consumeInitialDetails() {
    final details = widget.initialDetails;
    if (details == null ||
        identical(details, consumedDetails) ||
        layoutViewport == null ||
        pendingFrame != null ||
        !visible ||
        !widget.enabled ||
        !widget.isCurrent()) {
      return;
    }
    consumedDetails = details;
    // configure() and viewportChanged() have selected this frame's full profile
    // and actual layout. The controller still validates owner/source/profile.
    controller.adoptHandoff(details);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    pixelRatio = MediaQuery.devicePixelRatioOf(context);
    visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    layoutViewport = RetouchPhotoViewportScope.maybeOf(context);
    configure();
    consumeInitialDetails();
  }

  @override
  void didUpdateWidget(RetouchDetailPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initialDetails, widget.initialDetails) &&
        !identical(oldWidget.initialDetails, consumedDetails)) {
      oldWidget.initialDetails?.dispose();
    }
    if (pendingFrame?['path'] == widget.frame['path']) {
      pendingFrame = null;
      pendingViewport = null;
    }
    if (oldWidget.viewport != widget.viewport) {
      oldWidget.viewport.removeListener(viewportChanged);
      widget.viewport.addListener(viewportChanged);
    }
    if (oldWidget.invalidation != widget.invalidation) {
      oldWidget.invalidation.removeListener(pause);
      widget.invalidation.addListener(pause);
    }
    if (oldWidget.core != widget.core ||
        oldWidget.owner != widget.owner ||
        oldWidget.sourcePath != widget.sourcePath) {
      replacementGeneration++;
      pendingFrame = null;
      pendingViewport = null;
      controller.dispose();
      createController();
    }
    layoutViewport = RetouchPhotoViewportScope.maybeOf(context);
    configure();
    consumeInitialDetails();
  }

  @override
  void dispose() {
    replacementGeneration++;
    widget.viewport.removeListener(viewportChanged);
    widget.invalidation.removeListener(pause);
    controller.dispose();
    if (!identical(widget.initialDetails, consumedDetails)) {
      widget.initialDetails?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: EditingDetailTileLayer(controller: controller));
}
