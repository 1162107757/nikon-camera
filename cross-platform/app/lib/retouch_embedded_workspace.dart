part of 'retouch_workspace.dart';

/// An editor-owned photo plane with a replaceable, bounded tool panel.
/// No Navigator, Scaffold or second portrait state is created for sub-tools.
extension _EmbeddedPortraitWorkspace on _RetouchWorkspaceState {
  Future<List<int>?> openInlineBlemishes(
    Widget Function(ValueChanged<List<int>?>, ValueChanged<VoidCallback?>)
    builder,
  ) {
    final result = Completer<List<int>?>();
    inlineBlemishResult = result;
    final page = builder(finishInlineBlemishes, (back) {
      if (identical(inlineBlemishResult, result)) inlineBlemishBack = back;
    });
    refreshPortrait(
      () => inlineBlemishes = widget.embedded
          ? page
          : Material(color: const Color(0xff0e0d0c), child: page),
    );
    return result.future;
  }

  void finishInlineBlemishes(List<int>? value, {bool rebuild = true}) {
    final result = inlineBlemishResult;
    if (result == null) return;
    void clear() {
      inlineBlemishResult = null;
      inlineBlemishBack = null;
      inlineBlemishes = null;
    }

    if (rebuild && mounted) {
      refreshPortrait(clear);
    } else {
      clear();
    }
    if (!result.isCompleted) result.complete(value);
  }

  Future<SelectionResult?> openInlineSelection(
    String ownedFrame,
    Widget Function(ValueChanged<SelectionResult?>, ValueChanged<VoidCallback?>)
    builder,
  ) {
    final result = Completer<SelectionResult?>();
    temporary.add(ownedFrame);
    inlineSelectionResult = result;
    inlineSelectionOwnedPath = ownedFrame;
    final page = builder(finishInlineSelection, (back) {
      if (!identical(inlineSelectionResult, result)) return;
      inlineSelectionBack = back;
      if (back != null) temporary.remove(ownedFrame);
    });
    refreshPortrait(() {
      inlineSelection = widget.embedded
          ? page
          : Material(color: const Color(0xff0e0d0c), child: page);
    });
    return result.future;
  }

  void finishInlineSelection(SelectionResult? value, {bool rebuild = true}) {
    final result = inlineSelectionResult;
    if (result == null) return;
    final owned = inlineSelectionOwnedPath;
    void clear() {
      inlineSelectionResult = null;
      inlineSelectionBack = null;
      inlineSelectionOwnedPath = null;
      inlineSelection = null;
    }

    if (rebuild && mounted) {
      refreshPortrait(clear);
    } else {
      clear();
    }
    if (owned != null && temporary.remove(owned)) {
      unawaited(WidgetsBinding.instance.endOfFrame.then((_) => remove(owned)));
    }
    if (!result.isCompleted) result.complete(value);
  }

  Future<void> beginInlineRegion(SelectionResult selection) async {
    final epoch = operationEpoch;
    if (!operationCurrent(epoch) || data == null) return;
    final target = selection.regionId;
    final region = (selection.localState['regions'] as List)
        .map(object)
        .firstWhere((r) => r['id'] == target);
    refreshPortrait(() {
      regionStart = data;
      regionFrameBefore = frame;
      regionUndoBefore = List.of(undo);
      regionRedoBefore = List.of(redo);
      regionIntentBefore = toolIntent;
      regionChoosingBefore = choosingGroup;
      regionTabBefore = tab;
      regionSelectedBefore = selected;
      overrideRegionId = target;
      overrideRegionName = region['name'] as String?;
      undo.clear();
      redo.clear();
      selected = 0;
      tab = 1;
      toolIntent = 'overview';
      choosingGroup = true;
      busy = true;
      error = null;
    });
    try {
      final next = await call('media.retouchDescribe', {
        'localData': selection.localState['localData'],
      });
      final image = await render(next);
      if (operationCurrent(epoch) && regionStart != null) {
        refreshPortrait(() {
          data = next;
          frame = image;
        });
      }
    } catch (failure) {
      if (operationCurrent(epoch)) refreshPortrait(() => error = '$failure');
    } finally {
      if (operationCurrent(epoch)) refreshPortrait(() => busy = false);
    }
  }

  Future<void> finishInlineRegion(bool apply) async {
    final before = regionStart;
    if (before == null || !current || apply && busy) return;
    final accepted = data;
    final changed = accepted?['localData'] != before['localData'];
    final childId = overrideRegionId, childName = overrideRegionName;
    refreshPortrait(() {
      retireToolWork();
      busy = apply && changed;
      // The authoritative parent description is requested without a regional
      // target. Keep the sub-transaction live until that description succeeds.
      overrideRegionId = overrideRegionName = null;
    });
    final epoch = operationEpoch;
    Json next = before;
    Json? image;
    if (apply && changed) {
      try {
        next = await call('media.retouchDescribe', {
          'localData': accepted!['localData'],
        });
        if (next['sourcePositioning'] == true) {
          image = await render(
            next,
            sourcePositioned:
                regionChoosingBefore != true && regionTabBefore != 2,
          );
        }
        if (!operationCurrent(epoch) || regionStart != before) return;
      } catch (failure) {
        if (operationCurrent(epoch)) {
          refreshPortrait(() {
            overrideRegionId = childId;
            overrideRegionName = childName;
            busy = false;
            error = '$failure';
          });
        }
        return;
      }
    }
    if (!operationCurrent(epoch) || regionStart != before) return;
    refreshPortrait(() {
      undo
        ..clear()
        ..addAll(regionUndoBefore ?? []);
      redo
        ..clear()
        ..addAll(regionRedoBefore ?? []);
      if (apply && changed) {
        undo.add(before);
        if (undo.length > 32) undo.removeAt(0);
        redo.clear();
      }
      data = next;
      frame = apply && changed ? image ?? frame : regionFrameBefore;
      toolIntent = regionIntentBefore ?? 'overview';
      choosingGroup = regionChoosingBefore ?? true;
      tab = regionTabBefore ?? 1;
      selected = regionSelectedBefore ?? 0;
      regionStart = regionFrameBefore = null;
      regionUndoBefore = regionRedoBefore = null;
      regionIntentBefore = null;
      regionChoosingBefore = null;
      regionTabBefore = regionSelectedBefore = null;
      busy = false;
      error = notice = null;
    });
    unawaited(refreshPortraitOverlay());
  }

  String get embeddedToolTitle => patchMode
      ? '修补${data?['sourcePositioning'] == true ? ' · 塑形前定位' : ''}'
      : toolIntent == 'overview'
      ? '人像'
      : toolIntent == 'natural'
      ? '自然精修'
      : toolIntent == 'body'
      ? '塑形'
      : toolIntent == 'skin'
      ? '皮肤'
      : '面部';

  Widget embeddedPortraitLayout(BuildContext context) => Theme(
    data: hueviaTheme(Brightness.dark, home: false),
    child: LayoutBuilder(
      builder: (context, bounds) {
        final photo = patchMode ? originalPatchPhoto() : originalStage();
        final panel = Column(
          children: [
            embeddedPortraitToolbar(),
            Expanded(
              child: RetouchOriginalDock(
                choosingGroup: !patchMode && choosingGroup,
                entries: [
                  for (final item in [
                    (1, '皮肤', 'skin'),
                    (0, '面部', 'face'),
                    if (editingRegionId?.isNotEmpty != true) (2, '塑形', 'body'),
                    (3, '自然精修', 'natural'),
                    if (editingRegionId?.isNotEmpty != true) (4, '修补', 'heal'),
                  ])
                    RetouchOriginalToolButton(
                      label: item.$2,
                      icon: item.$3,
                      entry: true,
                      onPressed: busy || data == null
                          ? null
                          : () => unawaited(
                              item.$1 == 4
                                  ? openOriginalPatch()
                                  : originalSection(
                                      item.$1 == 3 ? 1 : item.$1,
                                      natural: item.$1 == 3,
                                    ),
                            ),
                    ),
                ],
                controls: patchMode
                    ? [
                        const Text(
                          '涂抹需要移除的小范围，松手后自动寻找附近干净纹理。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: retouchOriginalMuted,
                          ),
                        ),
                        originalBrushSlider(patch: true),
                        originalAction(
                          '移除最后一个修补',
                          busy || (data?['patchCount'] as int? ?? 0) == 0
                              ? null
                              : () => unawaited(
                                  perform('media.retouchChange', {
                                    'action': 'removePatch',
                                    'index': (data!['patchCount'] as int) - 1,
                                  }),
                                ),
                        ),
                      ]
                    : tab == 0
                    ? originalFaceControls()
                    : tab == 1
                    ? originalSkinControls()
                    : originalBodyControls(),
              ),
            ),
          ],
        );
        final builder = widget.embeddedLayoutBuilder;
        if (builder != null) return builder(context, photo, panel);
        // Standalone embedding callers can omit the editor's fixed-plane layout.
        return Column(
          children: [
            Expanded(child: photo),
            SizedBox(
              height: math.min(280, bounds.maxHeight * .45),
              child: panel,
            ),
          ],
        );
      },
    ),
  );

  Widget embeddedPortraitToolbar() {
    final inner = patchChildOpen || bodyStart != null;
    final canApply =
        !busy &&
        current &&
        data != null &&
        brushRadiusStart == null &&
        points.isEmpty &&
        scalarStart == null &&
        lightStart == null &&
        originalGestureDown == null &&
        !photoSampling &&
        (patchMode || originalPortraitReady);
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            tooltip: patchChildOpen
                ? '取消修补并返回人像'
                : bodyStart != null
                ? '取消塑形并返回人像'
                : regionStart != null && toolIntent == 'overview'
                ? '取消局部并返回人像'
                : toolIntent == 'overview' || widget.patch
                ? '取消人像精修'
                : '返回人像工具',
            onPressed: exitRequested ? null : requestExit,
            icon: RetouchOriginalGlyph(
              (toolIntent == 'overview' && regionStart == null) || widget.patch
                  ? 'close'
                  : 'back',
            ),
          ),
          Expanded(
            child: Text(
              embeddedToolTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: retouchOriginalText),
            ),
          ),
          if ((toolIntent != 'overview' || regionStart != null) &&
              !widget.patch)
            TextButton(
              onPressed: exitRequested ? null : cancelWorkspace,
              child: const Text('取消人像'),
            ),
          TextButton(
            onPressed: !canApply
                ? null
                : () {
                    unawaited(finishToneSelection());
                    if (bodyStart != null) {
                      unawaited(finishOriginalBody(true));
                    } else {
                      applyWorkspace();
                    }
                  },
            child: Text(
              inner
                  ? (patchChildOpen ? '应用修补' : '应用塑形')
                  : regionStart != null
                  ? '应用局部'
                  : widget.patch
                  ? '应用修补'
                  : '应用人像',
            ),
          ),
        ],
      ),
    );
  }
}
