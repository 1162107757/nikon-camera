part of 'editor.dart';

extension _EditorDetailPreview on _EditorPageState {
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
        !managingTools;
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
