part of 'editor.dart';

extension _EditorDetailPreview on _EditorPageState {
  bool get editorFrameMatchesRecipe {
    final size = displayedPhotoSize;
    if (preview == null ||
        size == null ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        displayedRevision != revision ||
        detailRefreshPending ||
        rendering ||
        (debounce?.isActive ?? false) ||
        displayedOverlay?['recipe'] is! Map) {
      return false;
    }
    final accepted = object(displayedOverlay!['recipe']);
    final expected = recipe.clone().data;
    accepted.putIfAbsent('localData', () => '');
    expected.putIfAbsent('localData', () => '');
    return jsonEncode(accepted) == jsonEncode(expected);
  }

  void pauseEditorDetails({bool retire = false}) {
    detailRefreshPending = true;
    for (final controller in [effectDetails, comparisonDetails]) {
      if (retire) controller?.invalidate();
      controller?.setEnabled(false);
    }
  }

  Size? get displayedPhotoSize {
    final width = displayedOverlay?['outputWidth'];
    final height = displayedOverlay?['outputHeight'];
    if (width is! num || height is! num || width <= 0 || height <= 0) {
      return null;
    }
    return Size(width.toDouble(), height.toDouble());
  }

  EditingDetailPreviewController makeEditorDetails() {
    final source = widget.photo.path;
    return EditingDetailPreviewController(
      core: widget.state.core,
      owner: owner,
      sourcePath: source,
      maxTileEdge: 2048,
      isCurrent: () =>
          mounted && sameOwner && !leaving && widget.photo.path == source,
    );
  }

  void restoreEditorDetailHandoff(
    EditingDetailPreviewController? controller,
    EditingDetailHandoff? handoff, {
    required bool knownViewport,
  }) {
    if (handoff == null) return;
    if (controller == null || !editorFrameMatchesRecipe) {
      handoff.dispose();
      return;
    }
    final size = displayedPhotoSize!, bounds = editorPhotoViewportSize;
    if (!knownViewport || bounds.isEmpty) {
      // A rotated/resized window has no measured base-editor viewport yet.
      // Stage the clone until SplitCompare reports its real layout.
      controller.setViewport(
        visibleRegion: Rect.zero,
        zoom: 1,
        viewportPixelSize: Size.zero,
      );
      controller.adoptHandoff(handoff);
      return;
    }
    final imageRect = Alignment.center.inscribe(
      applyBoxFit(BoxFit.contain, size, bounds).destination,
      Offset.zero & bounds,
    );
    final plane = EditingViewportPlane.fromRecipe(
      object(displayedOverlay!['recipe']),
      sourceSize: Size(
        (displayedOverlay?['sourceWidth'] as num? ??
                widget.photo.info['width'] as num? ??
                1)
            .toDouble(),
        (displayedOverlay?['sourceHeight'] as num? ??
                widget.photo.info['height'] as num? ??
                1)
            .toDouble(),
      ),
      contentRect: histogramContentRect,
    );
    final matrix = editingViewport.matrixFor(
      viewport: bounds,
      imageRect: imageRect,
      plane: plane,
    );
    final inverse = Matrix4.inverted(matrix);
    final visible = Rect.fromPoints(
      MatrixUtils.transformPoint(inverse, Offset.zero),
      MatrixUtils.transformPoint(inverse, Offset(bounds.width, bounds.height)),
    ).intersect(imageRect);
    final scale = matrix.getMaxScaleOnAxis();
    controller.setViewport(
      visibleRegion: visible.isEmpty
          ? Rect.zero
          : Rect.fromLTRB(
              (visible.left - imageRect.left) / imageRect.width,
              (visible.top - imageRect.top) / imageRect.height,
              (visible.right - imageRect.left) / imageRect.width,
              (visible.bottom - imageRect.top) / imageRect.height,
            ),
      zoom: scale,
      viewportPixelSize:
          visible.size * scale * MediaQuery.devicePixelRatioOf(context),
    );
    controller.adoptHandoff(handoff);
  }

  ({
    EditingDetailPreviewController? effect,
    EditingDetailPreviewController? original,
  })
  editorDetailBindings({
    required BuildContext viewContext,
    String? heldComparison,
    Json? heldComparisonRecipe,
  }) {
    final size = displayedPhotoSize;
    if (!sameOwner || leaving || preview == null || size == null) {
      return (effect: null, original: null);
    }
    final held = heldComparison != null;
    if (held && heldComparisonRecipe == null) {
      return (effect: null, original: null);
    }
    // The maintained editor route and a full-screen colour workspace share
    // the recipe, but only the visible route may choose the detail viewport.
    if (!TickerMode.valuesOf(viewContext).enabled ||
        ModalRoute.of(viewContext)?.isCurrent == false) {
      return (
        effect: held ? comparisonDetails : effectDetails,
        original: compare && !held ? comparisonDetails : null,
      );
    }
    final frozen = held
        ? heldComparisonRecipe!
        : object(displayedOverlay?['recipe']);
    final effect = held
        ? (comparisonDetails ??= makeEditorDetails())
        : (effectDetails ??= makeEditorDetails());
    effect.configure(
      recipe: frozen,
      revision: displayedRevision,
      frameIdentity: heldComparison ?? preview!,
      outputSize: size,
      expectedSourceSha: sourceSha,
    );
    final enabled =
        !detailRefreshPending &&
        !exporting &&
        !analyzingCleanup &&
        (!managingTools ||
            (retouchDetailHandoffPending && editorFrameMatchesRecipe));
    effect.setEnabled(enabled);
    EditingDetailPreviewController? original;
    if (!held && compare && comparison != null) {
      original = comparisonDetails ??= makeEditorDetails();
      final neutral = Recipe().data;
      for (final key in ['geometry', 'border']) {
        if (frozen[key] != null) neutral[key] = frozen[key];
      }
      original.configure(
        recipe: neutral,
        revision: displayedRevision,
        frameIdentity: comparison!,
        outputSize: size,
        expectedSourceSha: sourceSha,
      );
      original.setEnabled(enabled);
    }
    return (effect: effect, original: original);
  }
}
