part of 'editor.dart';

extension _EmbeddedEditorTools on _EditorPageState {
  Future<T?> openEmbeddedWorkspace<T>(
    Widget Function(
      ValueChanged<T?> finish,
      ValueChanged<VoidCallback?> backReady,
    )
    builder,
  ) {
    if (embeddedTool != null || !mounted || !sameOwner) return Future.value();
    final result = Completer<T?>();
    final epoch = ++embeddedToolEpoch;
    embeddedPhotoViewportSize = editorPhotoViewportSize;
    void finish(T? value, {bool rebuild = true}) {
      if (result.isCompleted) return;
      if (epoch == embeddedToolEpoch) {
        void clear() {
          embeddedTool = null;
          embeddedBack = null;
          retireEmbeddedTool = null;
        }

        if (rebuild && mounted) {
          refreshWorkspace(clear);
        } else {
          clear();
        }
      }
      result.complete(value);
    }

    retireEmbeddedTool = () => finish(null, rebuild: false);
    final workspace = builder((value) => finish(value), (back) {
      if (epoch == embeddedToolEpoch && !result.isCompleted) {
        embeddedBack = back;
      }
    });
    refreshWorkspace(() => embeddedTool = workspace);
    return result.future;
  }

  Widget embeddedWorkspaceLayout(
    BuildContext context,
    Widget photo,
    Widget panel,
  ) => LayoutBuilder(
    builder: (context, bounds) {
      if (editorHorizontalLayout) {
        return Row(
          children: [
            Expanded(
              child: KeyedSubtree(
                key: const Key('editor-photo-viewport'),
                child: photo,
              ),
            ),
            SizedBox(width: bounds.maxWidth * .46, child: panel),
          ],
        );
      }
      final height =
          (panel is EditingToolPanel
                  ? bounds.maxHeight -
                        panel.preferredHeight.clamp(
                          math.min(96.0, bounds.maxHeight * .55),
                          bounds.maxHeight * .55,
                        )
                  : embeddedPhotoViewportSize.height > 0
                  ? embeddedPhotoViewportSize.height
                  : bounds.maxHeight * .61)
              .clamp(
                math.min(100.0, math.max(0.0, bounds.maxHeight - 72)),
                math.max(0.0, bounds.maxHeight - 72),
              )
              .toDouble();
      return Column(
        children: [
          SizedBox(
            height: height,
            child: KeyedSubtree(
              key: const Key('editor-photo-viewport'),
              child: photo,
            ),
          ),
          Expanded(child: panel),
        ],
      );
    },
  );

  Json? get embeddedInitialFrame => preview == null
      ? null
      : {
          'path': preview,
          'width': displayedPhotoSize?.width.toInt() ?? 1,
          'height': displayedPhotoSize?.height.toInt() ?? 1,
          'sourceWidth':
              displayedOverlay?['sourceWidth'] ??
              widget.photo.info['width'] ??
              1,
          'sourceHeight':
              displayedOverlay?['sourceHeight'] ??
              widget.photo.info['height'] ??
              1,
          '_viewportContentRect': {
            'left': histogramContentRect.left,
            'top': histogramContentRect.top,
            'right': histogramContentRect.right,
            'bottom': histogramContentRect.bottom,
          },
          'sourceSha': sourceSha,
          'recipe': jsonDecode(
            jsonEncode(displayedOverlay?['recipe'] ?? recipe.data),
          ),
          '_detailRecipe': jsonDecode(
            jsonEncode(displayedOverlay?['recipe'] ?? recipe.data),
          ),
          '_detailRevision': displayedRevision,
          '_borrowedEditorFrame': true,
        };
}
