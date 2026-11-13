part of 'editor.dart';

// Native copy receipts live for the runtime lifetime and are scoped to an owner.
final _editorCopyReceipts = Expando<Map<String, String>>();

extension _EditorMenuActions on _EditorPageState {
  bool get ownedAlbumPhoto =>
      widget.state.core.root.isNotEmpty &&
      p.isWithin(
        p.join(widget.state.core.root, 'originals'),
        widget.photo.path,
      ) &&
      widget.photo.info['projectId'] == null &&
      widget.photo.info['live'] != true;

  HueIconKind menuIcon(EditorMoreAction action) => switch (action) {
    EditorMoreAction.favourite =>
      widget.state.starredPhotos.contains(widget.photo.starKey)
          ? HueIconKind.starFilled
          : HueIconKind.star,
    EditorMoreAction.histogram => HueIconKind.histogram,
    EditorMoreAction.versions => HueIconKind.stack,
    EditorMoreAction.detail => HueIconKind.detail,
    EditorMoreAction.allFilters => HueIconKind.grid,
    EditorMoreAction.optimize => HueIconKind.cleanup,
    EditorMoreAction.recipes || EditorMoreAction.copy => HueIconKind.recipe,
    EditorMoreAction.composition => HueIconKind.crop,
    EditorMoreAction.undoCopy => HueIconKind.undo,
    EditorMoreAction.continueDraft => HueIconKind.receipts,
    EditorMoreAction.resetColour => HueIconKind.adjust,
    EditorMoreAction.restoreOriginal => HueIconKind.refresh,
    EditorMoreAction.delete => HueIconKind.delete,
  };

  Future<void> editorOptions(BuildContext anchor) async {
    if (!toolsEnabled) return;
    final fingerprint = jsonEncode(recipe.data), region = selectedRegionId;
    bool current() =>
        mounted &&
        toolsEnabled &&
        selectedRegionId == region &&
        jsonEncode(recipe.data) == fingerprint;
    final action = await showEditorMoreMenu(
      anchor,
      lifecycle: widget.state,
      isCurrent: current,
      entries: editorMoreEntries(
        EditorMoreState(
          showFavourite: ownedAlbumPhoto,
          canDelete: ownedAlbumPhoto,
          favourite: widget.state.starredPhotos.contains(widget.photo.starKey),
          savingFavourite: savingFavourite,
          histogram: histogram.visible,
          parkedDraft: parkedDraft != null,
          regionName: selectedRegion == null ? null : adjustmentScope,
        ),
        iconFor: menuIcon,
      ),
    );
    if (action == null || !current()) return;
    switch (action) {
      case EditorMoreAction.favourite:
        await toggleFavourite();
      case EditorMoreAction.histogram:
        histogram.toggle(recipe.clone().data, sourceSha);
      case EditorMoreAction.versions:
        await openTool(savedVersions: true);
      case EditorMoreAction.detail:
        await openDetails();
      case EditorMoreAction.allFilters:
        await advancedTool(0);
      case EditorMoreAction.optimize:
        refreshWorkspace(() => tab = 9);
        panelRevision.value++;
      case EditorMoreAction.recipes:
        await openTool();
      case EditorMoreAction.composition:
        await openCrop();
      case EditorMoreAction.copy:
        await openTool(copying: true);
      case EditorMoreAction.undoCopy:
        await undoLastCopy();
      case EditorMoreAction.continueDraft:
        await continueParkedDraft();
      case EditorMoreAction.resetColour:
        resetColour();
      case EditorMoreAction.restoreOriginal:
        await resetPhoto();
      case EditorMoreAction.delete:
        await deleteFromEditor();
    }
  }

  Future<void> toggleFavourite() async {
    if (!toolsEnabled || savingFavourite || !ownedAlbumPhoto) return;
    refreshWorkspace(() => savingFavourite = true);
    try {
      final value = await widget.state.core.call('photo.star', {
        'owner': owner,
        'path': widget.photo.path,
        'starred': !widget.state.starredPhotos.contains(widget.photo.starKey),
      });
      if (!mounted || !sameOwner) return;
      widget.state.acceptPhotoStars(
        owner,
        List<String>.from(value['keys'] as List),
      );
    } catch (failure) {
      if (mounted && sameOwner) report(context, failure);
    } finally {
      if (mounted) refreshWorkspace(() => savingFavourite = false);
    }
  }

  void rememberCopy(Json receipt) {
    final id = receipt['receipt'];
    if (id is String && id.isNotEmpty) {
      (_editorCopyReceipts[widget.state.core] ??= <String, String>{})[owner] =
          id;
    }
  }

  Future<void> undoLastCopy() async {
    if (!toolsEnabled) return;
    final receipts = _editorCopyReceipts[widget.state.core],
        id = receipts?[owner];
    if (id == null) {
      report(context, const AppFailure('没有可撤销的批量调色。'));
      return;
    }
    refreshWorkspace(() => managingTools = true);
    try {
      final result = await widget.state.core.call('photo.copyUndo', {
        'owner': owner,
        'receipt': id,
      });
      if (!mounted || !sameOwner) return;
      receipts?.remove(owner);
      report(
        context,
        AppFailure(
          '已撤销 ${result['restored'] ?? result['changed'] ?? 0} 张照片的调色。',
        ),
      );
    } catch (failure) {
      if (mounted && sameOwner) report(context, failure);
    } finally {
      if (mounted) refreshWorkspace(() => managingTools = false);
    }
  }

  void resetColour() {
    changeAdjustment(() {
      final data = adjustmentRecipe.data;
      data['values'] = List.filled(recipe.values.length, 0);
      for (final key in [
        'curves',
        'curve',
        'hsl',
        'palette',
        'cleanup',
        'cleanupData',
      ]) {
        data.remove(key);
      }
    });
  }

  Future<void> continueParkedDraft() async {
    final previous = parkedDraft;
    if (previous == null || !toolsEnabled) return;
    await settleLocalAdjustments();
    if (!mounted || !sameOwner) return;
    checkpoint();
    refreshWorkspace(() {
      recipe = previous.clone();
      parkedDraft = null;
      compare = false;
      selectedRegionId = null;
    });
    await reloadLocalState();
    revision++;
    panelRevision.value++;
    await saveDraft();
    unawaited(render());
  }

  Future<void> deleteFromEditor() async {
    if (!toolsEnabled || !ownedAlbumPhoto) return;
    await hueRootPage<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AlbumDeletePage(
          state: widget.state,
          phone: false,
          rows: [
            {'id': widget.photo.id, 'name': widget.photo.name},
          ],
          onDeleted: (ids) {
            if (mounted && sameOwner && ids.contains(widget.photo.id)) {
              photoDeleted = true;
              refreshWorkspace(() => allowPop = true);
            }
          },
        ),
      ),
    );
    if (mounted && sameOwner && photoDeleted) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> openDetails() async {
    if (!toolsEnabled) return;
    debounce?.cancel();
    final wasFresh = preview != null && displayedRevision == revision;
    revision++;
    refreshWorkspace(() => managingTools = true);
    EditorDetailsResult? result;
    try {
      await settleLocalAdjustments();
      if (activeJob != null) await widget.state.core.cancel(activeJob!);
      if (!mounted || !sameOwner) return;
      final frozen = recipe.clone().data, fingerprint = jsonEncode(recipe.data);
      bool current() =>
          mounted &&
          sameOwner &&
          !leaving &&
          jsonEncode(recipe.data) == fingerprint;
      final inspected = await widget.state.core.call('source.inspect', {
        'owner': owner,
        'path': widget.photo.path,
      });
      if (!mounted || !current()) return;
      final sha = inspected['sourceSha'];
      if (sha is! String || sha.isEmpty) throw const AppFailure('未取得原图校验证据。');
      sourceSha = sha;
      result = await hueRootPage<EditorDetailsResult>(
        context,
        MaterialPageRoute(
          builder: (_) => EditorDetailsPage(
            state: widget.state,
            photo: widget.photo,
            owner: owner,
            recipe: frozen,
            expectedSourceSha: sha,
            isCurrent: current,
            hasRaw: widget.photo.info['rawSource'] is String,
          ),
        ),
      );
    } catch (failure) {
      if (mounted && sameOwner) report(context, failure);
    } finally {
      if (mounted) {
        refreshWorkspace(() {
          managingTools = false;
          if (sameOwner && wasFresh) displayedRevision = revision;
        });
        if (sameOwner) {
          if (wasFresh) {
            unawaited(refreshRegionLayer());
          } else {
            unawaited(render(readOnly: true));
          }
        }
      }
    }
    if (result == EditorDetailsResult.raw && mounted && toolsEnabled) {
      await openLinkedRaw();
    }
  }

  void histogramChanged() {
    if (mounted) refreshWorkspace(() {});
  }

  Widget histogramPanel() => EditorHistogramPanel(
    data: histogram.data,
    updating: histogram.updating,
    error: histogram.error,
    rgb: histogram.rgb,
    shadows: histogram.shadows,
    highlights: histogram.highlights,
    onRgb: histogram.setRgb,
    onShadows: histogram.setShadows,
    onHighlights: histogram.setHighlights,
    onExplain: explainHistogram,
  );

  Rect get histogramContentRect {
    final border = object(recipe.data['border'] ?? {});
    final template = border['template'] as int? ?? 0;
    final size =
        compositionFrame ??
        Size(
          histogram.data?.width.toDouble() ?? 1,
          histogram.data?.height.toDouble() ?? 1,
        );
    final w = size.width, h = size.height;
    final margin = (border['margin'] as num? ?? 100) / 100;
    final outputW =
        w +
        (w *
                (template == 1
                    ? .22
                    : template == 2
                    ? .45
                    : 0) *
                margin)
            .round();
    final outputH =
        h +
        (w *
                (template == 1
                    ? .145
                    : template == 2
                    ? .14
                    : template == 3
                    ? .112
                    : 0) *
                margin)
            .round();
    final x = template == 1
        ? (outputW - w) / 2
        : template == 2
        ? outputW - w - w * .08 * margin
        : 0.0;
    final y = template == 1
        ? w * .06 * margin
        : template == 2
        ? w * .07 * margin
        : 0.0;
    return Rect.fromLTWH(x / outputW, y / outputH, w / outputW, h / outputH);
  }

  Future<void> explainHistogram() async {
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('直方图与溢出提醒'),
        content: SingleChildScrollView(
          child: Text(
            editorHistogramExplanation(histogram.data, error: histogram.error),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void cancelQuick() {
    quickGeneration++;
    quickDebounce?.cancel();
    final job = quickJob;
    quickJob = null;
    if (job != null) unawaited(widget.state.core.cancel(job));
    if (mounted) {
      refreshWorkspace(() => analyzingCleanup = false);
      panelRevision.value++;
    }
  }

  Future<void> chooseQuick(
    int style, {
    int? amount,
    bool snapshot = true,
  }) async {
    if (!sameOwner ||
        leaving ||
        !restored ||
        managingTools ||
        exporting ||
        (analyzingCleanup && quickJob == null)) {
      return;
    }
    if (style == 0) {
      cancelQuick();
      quickBase = null;
      quickStyle = 0;
      await resetPhoto();
      return;
    }
    cancelQuick();
    debounce?.cancel();
    await settleLocalAdjustments();
    if (!mounted || !sameOwner || leaving) return;
    revision++;
    final token = ++quickGeneration, frozen = recipe.clone();
    final matching = quickAppliedFingerprint == jsonEncode(frozen.data);
    final base = matching
        ? (quickBase?.clone() ?? frozen.clone())
        : frozen.clone();
    if (!matching) {
      quickPortrait = null;
    }
    final fingerprint = jsonEncode(frozen.data);
    final strength =
        amount ??
        (style == 1
            ? 55
            : style == 2
            ? 48
            : 45);
    final id = 'quick-${DateTime.now().microsecondsSinceEpoch}';
    quickJob = id;
    refreshWorkspace(() {
      analyzingCleanup = true;
      error = null;
    });
    bool current() =>
        mounted &&
        sameOwner &&
        !leaving &&
        token == quickGeneration &&
        jsonEncode(recipe.data) == fingerprint;
    try {
      if (activeJob != null) await widget.state.core.cancel(activeJob!);
      final inspected = await widget.state.core.call('source.inspect', {
        'owner': owner,
        'path': widget.photo.path,
        if (sourceSha.isNotEmpty) 'expectedSourceSha': sourceSha,
      }, id);
      if (!current()) return;
      final sha = inspected['sourceSha'];
      if (sha is! String ||
          sha.isEmpty ||
          (sourceSha.isNotEmpty && sourceSha != sha)) {
        throw const AppFailure('原图已改变，请重新打开照片。');
      }
      final cleanup = quickSourceSha == sha && quickCleanup != null
          ? quickCleanup!
          : await widget.state.core.call('media.cleanupAnalyze', {
              'owner': owner,
              'path': widget.photo.path,
              'regionId': '',
              'recipe': base.data,
            }, id);
      if (!current()) return;
      var local = base.data['localData'] as String? ?? '';
      if (style == 3) {
        final prepared =
            quickPortrait ??
            await widget.state.core.call('media.retouchAnalyze', {
              'owner': owner,
              'path': widget.photo.path,
              'recipe': base.data,
              'localData': local,
              'expectedSourceSha': sha,
              'mode': 'skin',
            }, id);
        if (!current()) return;
        final applied = await widget.state.core.call('media.retouchChange', {
          'owner': owner,
          'path': widget.photo.path,
          'recipe': base.data,
          'localData': prepared['localData'],
          'expectedSourceSha': sha,
          'action': 'skin',
          'value': {'NATURAL': strength},
        }, id);
        if (!current()) return;
        local = applied['localData'] as String;
        quickPortrait = prepared;
      }
      final verified = await widget.state.core.call('source.inspect', {
        'owner': owner,
        'path': widget.photo.path,
        'expectedSourceSha': sha,
      });
      if (!current()) return;
      if (verified['sourceSha'] != sha) {
        throw const AppFailure('原图已改变，请重新打开照片。');
      }
      final next = editorQuickRecipe(
        base: base.data,
        parameters: (widget.state.core.schema['parameters'] as List)
            .map(object)
            .toList(),
        style: style,
        amount: strength,
        cleanupData: cleanup['cleanupData'] as String,
        localData: local,
      );
      if (snapshot) checkpoint();
      refreshWorkspace(() {
        recipe = Recipe(data: next);
        quickBase = base;
        quickCleanup = cleanup;
        quickSourceSha = sha;
        quickAppliedFingerprint = jsonEncode(next);
        quickStyle = style;
        quickAmount = strength;
        compare = false;
        selectedRegionId = null;
      });
      await reloadLocalState();
      revision++;
      panelRevision.value++;
      unawaited(saveDraft().catchError((_) {}));
    } catch (failure) {
      if (current()) refreshWorkspace(() => error = '快速优化未完成：$failure');
    } finally {
      if (mounted && token == quickGeneration) {
        quickJob = null;
        refreshWorkspace(() => analyzingCleanup = false);
        panelRevision.value++;
        unawaited(render());
      }
    }
  }

  Widget quickDock() => EditorQuickPanel(
    style: quickStyle,
    amount: quickAmount,
    busy: analyzingCleanup,
    thumbnail: preview,
    onStyle: (value) => unawaited(chooseQuick(value)),
    onCancel: cancelQuick,
    onStart: () {
      checkpoint();
    },
    onChanged: (value) {
      refreshWorkspace(() => quickAmount = value);
    },
    onEnd: () => unawaited(
      chooseQuick(quickStyle, amount: quickAmount, snapshot: false),
    ),
  );
}
