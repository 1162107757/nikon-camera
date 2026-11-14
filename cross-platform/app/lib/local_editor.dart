part of 'editor.dart';

extension _LocalWorkspace on _EditorPageState {
  bool get sameOwner =>
      widget.state.session['logoutPending'] != true &&
      (widget.state.session['user']?['id'] as String? ?? '') == owner;

  Json? get selectedRegion {
    for (final value in localState['regions'] as List? ?? const []) {
      final region = object(value);
      if (region['id'] == selectedRegionId) return region;
    }
    return null;
  }

  Recipe get adjustmentRecipe => regionAdjustments ?? recipe;
  String get adjustmentScope => selectedRegion?['name'] as String? ?? '全图';

  bool get canShowRegionLayer =>
      mounted &&
      sameOwner &&
      preview != null &&
      !compare &&
      selectedRegion != null &&
      displayedOverlay != null &&
      displayedOverlay!['sourceWidth'] is num &&
      displayedOverlay!['sourceHeight'] is num &&
      displayedOverlay!['outputWidth'] is num &&
      displayedOverlay!['outputHeight'] is num &&
      ((selectedRegion!['strokes'] as List? ?? const []).isNotEmpty ||
          (selectedRegion!['shapes'] as List? ?? const []).isNotEmpty) &&
      displayedRevision == revision;

  void clearRegionLayer() {
    regionLayerGeneration++;
    if (regionLayerJob != null) {
      unawaited(widget.state.core.cancel(regionLayerJob!));
    }
    regionLayerJob = null;
    final old = regionLayer;
    regionLayer = null;
    if (old != null) {
      unawaited(WidgetsBinding.instance.endOfFrame.then((_) => old.dispose()));
    }
  }

  Future<void> refreshRegionLayer() async {
    clearRegionLayer();
    if (!canShowRegionLayer || !regionLayerVisible || adjustingParameter) {
      return;
    }
    final generation = regionLayerGeneration;
    final job = 'selection-overlay-${DateTime.now().microsecondsSinceEpoch}';
    regionLayerJob = job;
    bool current() =>
        mounted &&
        sameOwner &&
        generation == regionLayerGeneration &&
        canShowRegionLayer &&
        regionLayerVisible &&
        !adjustingParameter;
    try {
      final result = await widget.state.core.call('local.overlay', {
        ...displayedOverlay!,
        'regionId': selectedRegionId,
      }, job);
      if (!current()) return;
      final width = result['width'] as int, height = result['height'] as int;
      final bytes = base64Decode(result['rgba'] as String);
      if (width < 1 ||
          height < 1 ||
          width > 320 ||
          height > 320 ||
          bytes.length != width * height * 4) {
        return;
      }
      final decoded = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        bytes,
        width,
        height,
        ui.PixelFormat.rgba8888,
        decoded.complete,
      );
      final image = await decoded.future;
      if (!current()) {
        image.dispose();
        return;
      }
      refreshWorkspace(() => regionLayer = image);
    } catch (_) {
      // A separate display layer never changes photo/export pixels.
    } finally {
      if (regionLayerJob == job) regionLayerJob = null;
    }
  }

  void beginParameterGesture() {
    if (!mounted || !toolsEnabled) return;
    clearRegionLayer();
    refreshWorkspace(() => adjustingParameter = true);
  }

  void endParameterGesture() {
    if (!mounted) return;
    refreshWorkspace(() => adjustingParameter = false);
    debounce?.cancel();
    unawaited(render());
    unawaited(refreshRegionLayer());
  }

  String parameterValue(Json parameter, int value) => parameter['index'] == 1
      ? '${value >= 0 ? '+' : ''}${(value / 10).toStringAsFixed(1)} EV'
      : '${value > 0 ? '+' : ''}$value';

  Future<T?> parameterDialog<T>(WidgetBuilder builder) async {
    final route = DialogRoute<T>(
      context: context,
      barrierColor: const Color.fromRGBO(0, 0, 0, .42),
      builder: (dialog) => Theme(
        data: hueviaTheme(Brightness.dark, home: false),
        child: AnimatedBuilder(
          animation: widget.state,
          builder: (context, _) => sameOwner
              ? builder(context)
              : AlertDialog(
                  title: const Text('账号已改变'),
                  content: const Text('请返回相册后重新打开照片。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialog),
                      child: const Text('返回'),
                    ),
                  ],
                ),
        ),
      ),
    );
    final result = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<T>(route);
    await route.completed;
    return result;
  }

  Future<void> parameterHelp(Json parameter) async {
    if (!toolsEnabled) return;
    await parameterDialog<void>(
      (dialog) => AlertDialog(
        title: Text(parameter['label'] as String),
        content: SingleChildScrollView(
          child: Text(
            '${parameter['help']}\n\n范围：${parameterValue(parameter, parameter['min'] as int)} 至 ${parameterValue(parameter, parameter['max'] as int)}；0 为不额外调节。\n点击滑杆旁的数值可精确输入。',
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

  Future<void> exactParameter(Json parameter) async {
    if (!toolsEnabled) return;
    final index = parameter['index'] as int, region = selectedRegionId;
    final before = adjustmentRecipe.values[index];
    final factor = index == 1 ? 10 : 1;
    final input = TextEditingController(
      text: index == 1 ? (before / 10).toStringAsFixed(1) : '$before',
    );
    input.selection = TextSelection(
      baseOffset: 0,
      extentOffset: input.text.length,
    );
    String? invalid;
    try {
      final next = await parameterDialog<int>(
        (dialog) => StatefulBuilder(
          builder: (context, refresh) {
            void apply() {
              if (!sameOwner || selectedRegionId != region) {
                Navigator.pop(dialog);
                return;
              }
              final parsed = double.tryParse(input.text.trim());
              final raw = parsed == null ? double.nan : parsed * factor;
              if (!raw.isFinite ||
                  (raw - raw.round()).abs() > .00001 ||
                  raw < (parameter['min'] as int) ||
                  raw > (parameter['max'] as int)) {
                refresh(
                  () =>
                      invalid = '请输入范围内的${index == 1 ? '数值，步长 0.1 EV' : '整数'}',
                );
                return;
              }
              Navigator.pop(dialog, raw.round());
            }

            return AlertDialog(
              title: Text(parameter['label'] as String),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '范围 ${parameterValue(parameter, parameter['min'] as int)} 至 ${parameterValue(parameter, parameter['max'] as int)}',
                    ),
                    TextField(
                      controller: input,
                      style: const TextStyle(fontSize: 13),
                      keyboardType: TextInputType.numberWithOptions(
                        signed: true,
                        decimal: index == 1,
                      ),
                      decoration: InputDecoration(
                        errorText: invalid,
                        errorMaxLines: 3,
                      ),
                      onSubmitted: (_) => apply(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog),
                  child: const Text('取消'),
                ),
                TextButton(onPressed: apply, child: const Text('确定')),
              ],
            );
          },
        ),
      );
      if (next != null &&
          mounted &&
          sameOwner &&
          toolsEnabled &&
          region == selectedRegionId &&
          next != before) {
        changeAdjustment(() => adjustmentRecipe.setValue(index, next));
      }
    } finally {
      input.dispose();
    }
  }

  Future<void> settleLocalAdjustments() async {
    final queue = localQueue;
    if (queue != null) await queue.settled;
  }

  Future<void> reloadLocalState() async {
    final frozen = recipe.data['localData'] as String? ?? '';
    final described = await widget.state.core.call('local.describe', {
      'localData': frozen,
    });
    if (!mounted ||
        !sameOwner ||
        frozen != (recipe.data['localData'] as String? ?? '')) {
      return;
    }
    installLocalState(described);
  }

  void installLocalState(Json value) {
    localQueue?.close();
    localState = value;
    selectRegion(selectedRegionId);
    late final LocalAdjustmentQueue queue;
    queue = LocalAdjustmentQueue(
      core: widget.state.core,
      initial: value,
      isCurrent: () => mounted && sameOwner && identical(localQueue, queue),
      onAccepted: (next) {
        recipe.data['localData'] = next['localData'];
        localState = next;
      },
    );
    localQueue = queue;
  }

  void selectRegion(String? id) {
    selectedRegionId = id;
    final region = selectedRegion;
    if (region == null) {
      selectedRegionId = null;
      regionAdjustments = null;
    } else {
      regionAdjustments = Recipe(data: object(region['adjustments']));
    }
    unawaited(refreshRegionLayer());
  }

  void changeAdjustment(VoidCallback mutation, {bool snapshot = true}) {
    if (!toolsEnabled) return;
    final id = selectedRegionId, queue = localQueue;
    change(mutation, snapshot: snapshot);
    if (id == null || queue == null) return;
    final settings = adjustmentRecipe.clone().data;
    settings.putIfAbsent('cleanupData', () => '');
    unawaited(
      queue.change(id, {'adjustments': settings}).catchError((Object failure) {
        if (mounted && identical(localQueue, queue)) {
          refreshWorkspace(() {
            installLocalState(queue.state);
            error = '$failure';
          });
          panelRevision.value++;
          report(context, failure);
        }
        return queue.state;
      }),
    );
  }

  Future<void> leaveEditor() async {
    if (quickJob != null) cancelQuick();
    if (leaving || exporting || managingTools || analyzingCleanup) return;
    leaving = true;
    try {
      if (restored && sameOwner) await saveDraft();
      if (!mounted) return;
      refreshWorkspace(() => allowPop = true);
      // PopScope registers the new disposition during the next frame.
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      leaving = false;
    }
  }

  Future<void> resetPhoto() async {
    if (!toolsEnabled) return;
    debounce?.cancel();
    revision++;
    refreshWorkspace(() => managingTools = true);
    try {
      await settleLocalAdjustments();
      if (!mounted || !sameOwner) return;
      checkpoint();
      refreshWorkspace(() {
        recipe = Recipe();
        compare = false;
        selectedRegionId = null;
      });
      await reloadLocalState();
      panelRevision.value++;
      await saveDraft();
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) {
        refreshWorkspace(() => managingTools = false);
        unawaited(render());
      }
    }
  }

  void editorOwnerChanged() {
    if (!mounted) return;
    if (sameOwner) {
      filtersChanged();
      return;
    }
    cancelQuick();
    histogram.invalidate();
    parkedDraft = quickBase = null;
    quickCleanup = quickPortrait = null;
    debounce?.cancel();
    clearRegionLayer();
    revision++;
    localQueue?.close();
    localQueue = null;
    if (activeJob != null) unawaited(widget.state.core.cancel(activeJob!));
    final discarded = [preview, comparison, atmosphere];
    refreshWorkspace(() {
      preview = comparison = atmosphere = activeJob = null;
      displayedOverlay = null;
      rendering = false;
      managingTools = analyzingCleanup = exporting = colorToolActive = false;
      localState = {};
      selectedRegionId = null;
      regionAdjustments = null;
      recipe = Recipe();
      undo.clear();
      redo.clear();
      error = '账号已改变，请返回相册后重新打开照片。';
    });
    panelRevision.value++;
    for (final path in discarded) {
      if (path != null) unawaited(discardPreview(path));
    }
  }

  Future<void> showRegionScope({BuildContext? anchorContext}) async {
    if (!toolsEnabled) return;
    try {
      await settleLocalAdjustments();
      if (!mounted || !sameOwner) return;
      final regions = (localState['regions'] as List? ?? const [])
          .map(object)
          .toList();
      final anchor =
          (anchorContext ?? scopeAnchor.currentContext)?.findRenderObject()
              as RenderBox?;
      final overlay =
          Overlay.of(context, rootOverlay: true).context.findRenderObject()
              as RenderBox;
      final origin =
          anchor?.localToGlobal(Offset.zero, ancestor: overlay) ?? Offset.zero;
      final choice = await showMenu<String>(
        context: context,
        useRootNavigator: true,
        position: RelativeRect.fromRect(
          origin & (anchor?.size ?? const Size(48, 48)),
          Offset.zero & overlay.size,
        ),
        items: [
          const PopupMenuItem(value: 'global', child: Text('全图')),
          for (final region in regions)
            PopupMenuItem(
              value: 'region:${region['id']}',
              child: Text(region['name'] as String),
            ),
          PopupMenuItem(
            value: 'add',
            enabled: regions.length < 16,
            child: const Text('新增选区'),
          ),
          PopupMenuItem(
            value: 'edit',
            enabled: selectedRegion != null,
            child: const Text('编辑当前选区'),
          ),
          PopupMenuItem(
            value: 'view',
            enabled: selectedRegion != null,
            child: const Text('查看选区'),
          ),
          PopupMenuItem(
            value: 'remove',
            enabled: selectedRegion != null,
            child: const Text('删除当前区域'),
          ),
          const PopupMenuItem(value: 'legacy', child: Text('渐变与取样修复')),
        ],
      );
      if (!mounted || choice == null || !sameOwner) return;
      if (choice == 'global' || choice.startsWith('region:')) {
        refreshWorkspace(
          () => selectRegion(choice == 'global' ? null : choice.substring(7)),
        );
        panelRevision.value++;
      } else if (choice == 'remove') {
        final next = await widget.state.core.call('local.change', {
          'localData': localState['localData'],
          'expectedSha': localState['sha256'],
          'action': 'removeRegion',
          'regionId': selectedRegionId,
        });
        if (!mounted || !sameOwner) return;
        change(() {
          recipe.data['localData'] = next['localData'];
          selectedRegionId = null;
          installLocalState(next);
        });
      } else if (choice == 'legacy') {
        await openLegacyTools();
      } else {
        await editSelection(existing: choice == 'edit' || choice == 'view');
      }
    } catch (failure) {
      if (mounted) report(context, failure);
    }
  }

  Future<void> editSelection({bool existing = false}) async {
    if (!toolsEnabled) return;
    debounce?.cancel();
    revision++;
    refreshWorkspace(() => managingTools = true);
    String? ownedFrame, ownedAtmosphere;
    final job = 'selection-frame-${DateTime.now().microsecondsSinceEpoch}';
    try {
      await settleLocalAdjustments();
      if (activeJob != null) await widget.state.core.cancel(activeJob!);
      if (!mounted || !sameOwner) return;
      final frozen = recipe.clone().data;
      final fingerprint = jsonEncode(frozen);
      bool current() =>
          mounted && sameOwner && jsonEncode(recipe.data) == fingerprint;
      final base = await widget.state.core.call('local.describe', {
        'localData': frozen['localData'] ?? '',
      });
      final region = existing
          ? selectedRegion
          : object(
              (await widget.state.core.call('local.seedRegion', {
                'localData': base['localData'],
              }))['seed'],
            );
      if (region == null || !current()) return;
      final frame = await widget.state.core.call('media.localPreview', {
        'path': widget.photo.path,
        'owner': owner,
        'recipe': frozen,
      }, job);
      ownedFrame = frame['path'] as String;
      if (!current()) return;
      try {
        final background = await widget.state.core.call('media.atmosphere', {
          'path': ownedFrame,
          'owner': owner,
        }, '$job-atmosphere');
        ownedAtmosphere = background['path'] as String;
      } catch (_) {
        // The source-coordinate editing surface remains usable without blur.
      }
      if (!mounted || !current()) return;
      await precacheImage(
        ResizeImage(FileImage(File(ownedFrame)), width: 1280),
        context,
      );
      if (!mounted || !current()) return;
      final page = SelectionWorkspace(
        state: widget.state,
        photo: widget.photo,
        owner: owner,
        region: region,
        localState: base,
        frame: frame,
        atmosphere: ownedAtmosphere,
        isCurrent: current,
      );
      // The pushed page now owns its bounded temporary images.
      ownedFrame = ownedAtmosphere = null;
      final result = await hueRootPage<SelectionResult>(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
      if (result == null || !current()) return;
      final next = result.localState;
      if (next['localData'] != (recipe.data['localData'] ?? '')) checkpoint();
      refreshWorkspace(() {
        recipe.data['localData'] = next['localData'];
        selectedRegionId = result.regionId;
        installLocalState(next);
        compare = false;
      });
      panelRevision.value++;
      unawaited(saveDraft().catchError((_) {}));
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (ownedFrame != null) await discardPreview(ownedFrame);
      if (ownedAtmosphere != null) await discardPreview(ownedAtmosphere);
      if (mounted) {
        refreshWorkspace(() => managingTools = false);
        unawaited(render());
      }
    }
  }

  Future<void> openLegacyTools() async {
    if (!toolsEnabled) return;
    debounce?.cancel();
    revision++;
    refreshWorkspace(() => managingTools = true);
    String? ownedFrame, ownedAtmosphere;
    final job = 'local-tools-frame-${DateTime.now().microsecondsSinceEpoch}';
    try {
      await settleLocalAdjustments();
      if (activeJob != null) await widget.state.core.cancel(activeJob!);
      if (!mounted || !sameOwner) return;
      final frozen = recipe.clone().data;
      final fingerprint = jsonEncode(frozen);
      bool current() =>
          mounted && sameOwner && jsonEncode(recipe.data) == fingerprint;
      final base = await widget.state.core.call('local.describe', {
        'localData': frozen['localData'] ?? '',
      });
      if (!current()) return;
      final frame = await widget.state.core.call('media.localPreview', {
        'path': widget.photo.path,
        'owner': owner,
        'recipe': frozen,
        'maxEdge': 1280,
      }, job);
      ownedFrame = frame['path'] as String;
      if (!current()) return;
      try {
        final background = await widget.state.core.call('media.atmosphere', {
          'path': ownedFrame,
          'owner': owner,
        }, '$job-atmosphere');
        ownedAtmosphere = background['path'] as String;
      } catch (_) {
        // Atmosphere is optional; the bounded source-coordinate frame is not.
      }
      if (!mounted || !current()) return;
      await precacheImage(
        ResizeImage(FileImage(File(ownedFrame)), width: 1280),
        context,
      );
      if (!mounted || !current()) return;
      final page = LegacyLocalWorkspace(
        state: widget.state,
        photo: widget.photo,
        owner: owner,
        recipe: frozen,
        localState: base,
        frame: frame,
        atmosphere: ownedAtmosphere,
        isCurrent: current,
      );
      ownedFrame = ownedAtmosphere = null;
      final result = await hueRootPage<Json>(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
      if (result == null || !current()) return;
      if (result['localData'] != (recipe.data['localData'] ?? '')) checkpoint();
      refreshWorkspace(() {
        recipe.data['localData'] = result['localData'];
        installLocalState(result);
        compare = false;
      });
      panelRevision.value++;
      unawaited(saveDraft().catchError((_) {}));
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (ownedFrame != null) await discardPreview(ownedFrame);
      if (ownedAtmosphere != null) await discardPreview(ownedAtmosphere);
      if (mounted) {
        refreshWorkspace(() => managingTools = false);
        unawaited(render());
      }
    }
  }
}
