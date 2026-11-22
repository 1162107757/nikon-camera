part of 'editor.dart';

/// The original colour dialogs keep a photograph above a compact control pane.
/// Changes remain tentative until Apply; Back and Cancel restore the entry state.
extension _EditorColorWorkspace on _EditorPageState {
  bool get colorFrameMatchesRecipe {
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
    // Compare the complete accepted recipe: local edits, RAW settings,
    // geometry and border all determine the displayed pixels and image plane.
    // The render queue adds an empty localData even to recipes without one.
    final accepted = object(displayedOverlay!['recipe']);
    final expected = recipe.clone().data;
    accepted.putIfAbsent('localData', () => '');
    expected.putIfAbsent('localData', () => '');
    return jsonEncode(accepted) == jsonEncode(expected);
  }

  void beginColorGesture() {
    if (!toolsEnabled) return;
    checkpoint();
    beginParameterGesture();
  }

  Widget legacyColorControls(
    int page, {
    double paletteHeight = 208,
    VoidCallback? onUndo,
    VoidCallback? onRedo,
    ValueChanged<bool>? onExpanded,
    bool compactPalette = false,
    ValueChanged<bool>? onPaletteGesture,
    bool showPaletteReadouts = true,
  }) {
    if (page == 5) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: CurveControl(
          curves:
              (adjustmentRecipe.data['curves'] as List? ??
                      List.generate(4, (_) => [0, 0, 255, 255]))
                  .map((row) => List<int>.from(row as List))
                  .toList(),
          enabled: toolsEnabled,
          onStart: beginColorGesture,
          onEnd: endParameterGesture,
          onChanged: (value) => changeAdjustment(
            () => adjustmentRecipe.data['curves'] = value,
            snapshot: false,
          ),
        ),
      );
    }
    if (page == 6) {
      return LegacyHslControls(
        values: List<int>.from(
          adjustmentRecipe.data['hsl'] as List? ?? List.filled(24, 0),
        ),
        selectedBand: hslBand,
        onBandChanged: (band) {
          if (!toolsEnabled) return;
          refreshWorkspace(() => hslBand = band);
          panelRevision.value++;
        },
        enabled: toolsEnabled,
        onStart: beginColorGesture,
        onEnd: endParameterGesture,
        onChanged: (values) => changeAdjustment(
          () => adjustmentRecipe.data['hsl'] = values,
          snapshot: false,
        ),
      );
    }
    if (page == 2) {
      final value = object(adjustmentRecipe.data['palette'] ?? {});
      return LegacyPaletteControls(
        color: value['color'] as int? ?? 0,
        tone: value['tone'] as int? ?? 0,
        amount: value['amount'] as int? ?? 100,
        scope: adjustmentScope,
        padHeight: paletteHeight,
        compact: compactPalette,
        showReadouts: showPaletteReadouts,
        enabled: toolsEnabled,
        onStart: () {
          onPaletteGesture?.call(true);
          beginColorGesture();
        },
        onEnd: () {
          endParameterGesture();
          onPaletteGesture?.call(false);
        },
        onUndo: onUndo,
        onRedo: onRedo,
        onChanged: (color, tone, amount) => changeAdjustment(() {
          adjustmentRecipe.data['palette'] = {
            'color': color,
            'tone': tone,
            'amount': amount,
          };
        }, snapshot: false),
        onReset: resetPalette,
      );
    }
    final value = object(adjustmentRecipe.data['cleanup'] ?? {});
    return LegacyCleanupControls(
      amount: value['amount'] as int? ?? 0,
      haze: value['haze'] as int? ?? 100,
      noise: value['noise'] as int? ?? 100,
      hasAnalysis:
          (adjustmentRecipe.data['cleanupData'] as String? ?? '').isNotEmpty,
      analyzing: analyzingCleanup,
      enabled: toolsEnabled,
      onStart: beginColorGesture,
      onEnd: endParameterGesture,
      onUndo: onUndo,
      onRedo: onRedo,
      onExpandedChanged: onExpanded,
      onAnalyze: () => unawaited(analyzeCleanup()),
      onCancelAnalysis: analyzingCleanup && activeJob != null
          ? () => unawaited(widget.state.core.cancel(activeJob!))
          : null,
      onChanged: (amount, haze, noise) => changeAdjustment(() {
        adjustmentRecipe.data['cleanup'] = {
          'amount': amount,
          'haze': haze,
          'noise': noise,
        };
      }, snapshot: false),
      onReset: () {
        beginColorGesture();
        changeAdjustment(() {
          adjustmentRecipe.data.remove('cleanupData');
          adjustmentRecipe.data['cleanup'] = {
            'amount': 0,
            'haze': 100,
            'noise': 100,
          };
        }, snapshot: false);
        endParameterGesture();
      },
    );
  }

  Future<void> advancedColorTool(int page) async {
    if (!toolsEnabled || colorToolActive) return;
    refreshWorkspace(() => colorToolActive = true);
    try {
      await settleLocalAdjustments();
      if (mounted && toolsEnabled && !colorFrameMatchesRecipe) {
        await render(readOnly: true);
      }
    } catch (failure) {
      if (mounted) {
        refreshWorkspace(() => colorToolActive = false);
        report(context, failure);
      }
      return;
    }
    if (!mounted || !toolsEnabled || !colorFrameMatchesRecipe) {
      if (mounted) refreshWorkspace(() => colorToolActive = false);
      return;
    }
    final before = recipe.clone(), regionBefore = selectedRegionId;
    final savedUndo = undo.map((v) => v.clone()).toList();
    final savedRedo = redo.map((v) => v.clone()).toList();
    final beforeCompare = compare;
    final entryOverlay = object(jsonDecode(jsonEncode(displayedOverlay)));
    String? entryImage;
    final entry = preview;
    if (entry != null &&
        p.isWithin(p.join(widget.state.core.root, 'previews'), entry)) {
      try {
        final copy = p.join(
          widget.state.core.root,
          'previews',
          'colour-entry-${DateTime.now().microsecondsSinceEpoch}${p.extension(entry)}',
        );
        entryImage = (await File(entry).copy(copy)).path;
      } on FileSystemException {
        /* The normal photo preview remains available. */
      }
    }
    if (!mounted || !sameOwner) {
      if (mounted) refreshWorkspace(() => colorToolActive = false);
      await discardPreview(entryImage);
      return;
    }
    debounce?.cancel();
    undo.clear();
    redo.clear();
    refreshWorkspace(() {
      colorToolActive = true;
      compare = false;
    });
    var expanded = false, working = false, closing = false;
    final title = {2: '调色盘', 5: '曲线', 6: 'HSL', 7: '去灰'}[page]!;
    if (page == 7 &&
        (adjustmentRecipe.data['cleanupData'] as String? ?? '').isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && sameOwner && colorToolActive && !closing) {
          unawaited(analyzeCleanup());
        }
      });
    }
    bool? applied;
    int? nextColorTool;
    var changed = false;
    try {
      applied = await openEmbeddedWorkspace<bool>(
        (complete, backReady) => Builder(
          builder: (toolContext) => StatefulBuilder(
            builder: (_, refresh) {
              Future<void> finish(bool accept) async {
                if (working || closing) return;
                refresh(() {
                  working = true;
                });
                if (!accept && analyzingCleanup) {
                  final job = activeJob;
                  refreshWorkspace(() {
                    activeJob = null;
                    analyzingCleanup = false;
                  });
                  if (job != null) {
                    try {
                      await widget.state.core.cancel(job);
                    } catch (_) {
                      /* The retired analysis cannot install its result. */
                    }
                  }
                }
                if (accept && mounted && sameOwner) {
                  try {
                    await settleLocalAdjustments();
                    if (jsonEncode(recipe.data) != jsonEncode(before.data) ||
                        !colorFrameMatchesRecipe) {
                      await render(readOnly: true);
                    }
                    if (!mounted ||
                        !sameOwner ||
                        error != null ||
                        displayedRevision != revision) {
                      if (toolContext.mounted) refresh(() => working = false);
                      return;
                    }
                  } catch (failure) {
                    if (mounted && sameOwner) {
                      refreshWorkspace(() => error = '$failure');
                    }
                    if (toolContext.mounted) refresh(() => working = false);
                    panelRevision.value++;
                    return;
                  }
                }
                if (!toolContext.mounted) return;
                refresh(() => closing = true);
                await WidgetsBinding.instance.endOfFrame;
                if (toolContext.mounted) {
                  complete(accept && sameOwner);
                }
              }

              Future<void> stepHistory(bool forward) async {
                if (working || !toolsEnabled) return;
                refresh(() => working = true);
                await history(forward);
                if (toolContext.mounted) refresh(() => working = false);
              }

              backReady(() => unawaited(finish(false)));
              return Theme(
                data: workspaceTheme,
                child: ValueListenableBuilder<int>(
                  valueListenable: panelRevision,
                  builder: (_, _, _) => LayoutBuilder(
                    builder: (_, box) {
                      final horizontal = editorHorizontalLayout;
                      final available = (box.maxHeight - 48).clamp(
                        0.0,
                        double.infinity,
                      );
                      final desired = page == 5
                          ? 330.0
                          : page == 6
                          ? 264.0
                          : page == 7
                          ? (expanded ? 312.0 : 156.0)
                          : (available * .54).clamp(324.0, 456.0);
                      final paneHeight = desired.clamp(0.0, available * .58);
                      final paletteHeight = horizontal
                          ? 288.0
                          : (paneHeight - 152).clamp(172.0, 304.0);
                      Widget controls() => AbsorbPointer(
                        absorbing: working || closing || !sameOwner,
                        child: SingleChildScrollView(
                          key: const Key('legacy-color-controls-scroll'),
                          child: legacyColorControls(
                            page,
                            paletteHeight: paletteHeight,
                            onUndo: undo.isNotEmpty
                                ? () => unawaited(stepHistory(false))
                                : null,
                            onRedo: redo.isNotEmpty
                                ? () => unawaited(stepHistory(true))
                                : null,
                            onExpanded: (value) =>
                                refresh(() => expanded = value),
                          ),
                        ),
                      );
                      Widget photo() => photoViewport(
                        viewContext: toolContext,
                        compareButtonAtBottom: page == 2 || page == 7,
                        compareReadOnly: true,
                      );
                      if (page == 2) {
                        final palette = object(
                          adjustmentRecipe.data['palette'] ?? {},
                        );
                        return PaletteWorkspace(
                          key: const Key('palette-workspace'),
                          enabled: !working && !closing && sameOwner,
                          working: working,
                          scope: adjustmentScope,
                          color: palette['color'] as int? ?? 0,
                          tone: palette['tone'] as int? ?? 0,
                          amount: palette['amount'] as int? ?? 100,
                          photo: KeyedSubtree(
                            key: const Key('legacy-color-photo-stage'),
                            child: photo(),
                          ),
                          controls: (height, onGesture, showReadouts) =>
                              AbsorbPointer(
                                absorbing: working || closing || !sameOwner,
                                child: legacyColorControls(
                                  2,
                                  paletteHeight: height,
                                  compactPalette: true,
                                  onPaletteGesture: onGesture,
                                  showPaletteReadouts: showReadouts,
                                  onUndo: undo.isNotEmpty
                                      ? () => unawaited(stepHistory(false))
                                      : null,
                                  onRedo: redo.isNotEmpty
                                      ? () => unawaited(stepHistory(true))
                                      : null,
                                ),
                              ),
                          readouts: (onGesture) => (legacyColorControls(
                            2,
                            compactPalette: true,
                            onPaletteGesture: onGesture,
                            onUndo: undo.isNotEmpty
                                ? () => unawaited(stepHistory(false))
                                : null,
                            onRedo: redo.isNotEmpty
                                ? () => unawaited(stepHistory(true))
                                : null,
                          ) as LegacyPaletteControls).readouts(toolContext),
                          onScope: (anchor) =>
                              unawaited(showRegionScope(anchorContext: anchor)),
                          onCancel: () => unawaited(finish(false)),
                          onApply: () => unawaited(finish(true)),
                          onReset: resetPalette,
                          onUndo: undo.isNotEmpty
                              ? () => unawaited(stepHistory(false))
                              : null,
                          onRedo: redo.isNotEmpty
                              ? () => unawaited(stepHistory(true))
                              : null,
                          onTool: (next) {
                            nextColorTool = next;
                            unawaited(finish(true));
                          },
                        );
                      }
                      final header = SizedBox(
                        height: 48,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 68,
                              child: TextButton(
                                onPressed: working
                                    ? null
                                    : () => unawaited(finish(false)),
                                child: const Text('取消'),
                              ),
                            ),
                            Builder(
                              builder: (anchor) => IconButton(
                                tooltip: '涂抹范围，当前$adjustmentScope',
                                onPressed: !working && toolsEnabled
                                    ? () =>
                                          showRegionScope(anchorContext: anchor)
                                    : null,
                                icon: const HueIcon(
                                  HueIconKind.brush,
                                  color: _editorWhite,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                sameOwner
                                    ? title +
                                          (adjustmentScope == '全图'
                                              ? ''
                                              : ' · $adjustmentScope')
                                    : '账号已改变',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _editorWhite,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 68,
                              child: TextButton(
                                onPressed:
                                    !working && !analyzingCleanup && sameOwner
                                    ? () => unawaited(finish(true))
                                    : null,
                                child: Text(
                                  working ? '更新中' : '应用',
                                  style: const TextStyle(color: _editorYellow),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                      return embeddedWorkspaceLayout(
                        toolContext,
                        KeyedSubtree(
                          key: const Key('legacy-color-photo-stage'),
                          child: photo(),
                        ),
                        Column(
                          children: [
                            header,
                            Expanded(
                              child: horizontal
                                  ? Align(
                                      alignment: Alignment.topCenter,
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 330,
                                        ),
                                        child: controls(),
                                      ),
                                    )
                                  : controls(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      );
      if (!mounted || !sameOwner) return;
      await settleLocalAdjustments();
      if (!mounted || !sameOwner) return;
      changed = jsonEncode(recipe.data) != jsonEncode(before.data);
      if (changed) refreshWorkspace(() => managingTools = true);
      if (applied != true && changed) {
        debounce?.cancel();
        previewGeneration++;
        previewQueue.reset();
        revision++;
        refreshWorkspace(() {
          recipe = before.clone();
          selectedRegionId = regionBefore;
          compare = beforeCompare;
          if (entryImage != null) {
            final discarded = preview;
            preview = entryImage;
            entryImage = null;
            displayedOverlay = entryOverlay;
            displayedRevision = revision;
            if (discarded != null && discarded != preview) {
              unawaited(discardPreview(discarded));
            }
          }
        });
        await reloadLocalState();
      } else if (applied != true) {
        refreshWorkspace(() {
          selectRegion(regionBefore);
          compare = beforeCompare;
        });
      }
      undo
        ..clear()
        ..addAll(savedUndo);
      redo
        ..clear()
        ..addAll(savedRedo);
      if (applied == true && changed) {
        undo.add(before);
        if (undo.length > 40) undo.removeAt(0);
        redo.clear();
      }
    } finally {
      unawaited(discardPreview(entryImage));
      if (mounted && sameOwner) {
        if (applied == true && changed) {
          try {
            await saveDraft();
          } catch (failure) {
            if (mounted && sameOwner) report(context, failure);
          }
        }
        if (mounted && sameOwner) {
          refreshWorkspace(() {
            colorToolActive = false;
            adjustingParameter = false;
            managingTools = false;
          });
          panelRevision.value++;
          if (changed) unawaited(render());
        }
      }
    }
    if (nextColorTool != null && applied == true && mounted && sameOwner) {
      await advancedColorTool(nextColorTool!);
    }
  }

  void resetPalette() {
    if (!toolsEnabled) return;
    beginColorGesture();
    changeAdjustment(
      () => adjustmentRecipe.data['palette'] = {
        'color': 0,
        'tone': 0,
        'amount': 100,
      },
      snapshot: false,
    );
    endParameterGesture();
  }
}
