import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'photo_format.dart';
import 'curve_control.dart';
import 'legacy_color_controls.dart';
import 'recipes.dart';
import 'copy_adjustments.dart';
import 'versions.dart';
import 'widgets.dart';
import 'raw_develop.dart';
import 'crop_workspace.dart';
import 'split_compare.dart';
import 'export_settings.dart';
import 'export_settings_model.dart';
import 'border_panel.dart';
import 'photo_workspace_chrome.dart';
import 'local_adjustments.dart';
import 'selection_workspace.dart';
import 'legacy_local_workspace.dart';
import 'retouch_workspace.dart';
import 'theme.dart';
import 'workspace_tools.dart';
import 'editor_presets.dart';
import 'editor_parameter_icons.dart';
import 'editor_more.dart';
import 'editor_details.dart';
import 'editor_quick.dart';
import 'editor_histogram.dart';
import 'editor_histogram_controller.dart';
import 'album_operations.dart';
import 'latest_preview_queue.dart';
import 'editing_detail_preview.dart';

part 'legacy_editor.dart';
part 'editor_filter_dock.dart';
part 'editor_color_workspace.dart';
part 'editor_detail_preview.dart';
part 'local_editor.dart';
part 'editor_menu_actions.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.state, required this.photo});
  final AppState state;
  final Photo photo;
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPreviewRequest {
  _EditorPreviewRequest(
    this.recipe,
    this.revision,
    this.generation,
    this.splitting,
    this.readOnly,
    this.sourceSha,
    this.path,
  );
  final Recipe recipe;
  final int revision, generation;
  final bool splitting, readOnly;
  final String sourceSha, path;
}

class _EditorPreviewFrame {
  _EditorPreviewFrame(this.result, this.reference);
  final Json result;
  final String? reference;
}

class _EditorPageState extends State<EditorPage> {
  Recipe recipe = Recipe();
  Recipe? parkedDraft, quickBase;
  Json? quickCleanup, quickPortrait;
  String sourceSha = '', quickAppliedFingerprint = '', quickSourceSha = '';
  bool savingFavourite = false, photoDeleted = false;
  int quickStyle = -1, quickAmount = 55, quickGeneration = 0;
  String? quickJob;
  Timer? quickDebounce;
  late final EditorHistogramController histogram;
  final List<Recipe> undo = [], redo = [];
  Timer? debounce;
  int previewGeneration = 0, queuedPreviewRevision = -1;
  late final previewQueue =
      LatestPreviewQueue<_EditorPreviewRequest, _EditorPreviewFrame?>(
        render: renderPreview,
        isCurrent: previewRequestCurrent,
        onFrame: acceptPreview,
        onError: (request, failure, stack) {
          if (previewRequestCurrent(request)) {
            setState(() => error = '$failure');
          }
        },
        discard: discardPreviewFrame,
      );
  StreamSubscription<dynamic>? progressEvents;
  String? preview, comparison, error, activeJob, atmosphere;
  int parameterIndex = 1;
  bool atmosphereLoading = false;
  int atmosphereGeneration = 0;
  final panelRevision = ValueNotifier<int>(0);
  void refreshWorkspace(VoidCallback update) => setState(update);
  bool exporting = false, rendering = false, compare = false, restored = false;
  bool managingTools = false;
  bool colorToolActive = false;
  bool detailRefreshPending = false;
  EditingDetailPreviewController? effectDetails, comparisonDetails;
  bool analyzingCleanup = false;
  final scopeAnchor = GlobalKey();
  Json localState = {};
  String? selectedRegionId;
  Recipe? regionAdjustments;
  LocalAdjustmentQueue? localQueue;
  bool leaving = false, allowPop = false;
  Json? displayedOverlay;
  ui.Image? regionLayer;
  String? regionLayerJob;
  int regionLayerGeneration = 0;
  int displayedRevision = -1;
  bool regionLayerVisible = true, adjustingParameter = false;
  double progress = 0;
  Size? compositionFrame;
  int compositionFrameTurns = 0;
  int tab = 0, revision = 0, hslBand = 0;
  late final EditorPresets filters;
  bool onlineFilters = true, preparingFilter = false;
  String filterCategory = '';
  List<Preset> get filterRows =>
      (onlineFilters ? filters.online : widget.state.presets)
          .where(
            (preset) =>
                filterCategory.isEmpty || preset.category == filterCategory,
          )
          .toList();
  List<Preset> get allFilters => <String, Preset>{
    for (final preset in [...filters.online, ...widget.state.presets])
      filters.identity(preset): preset,
  }.values.toList();
  void filtersChanged() {
    if (!mounted) return;
    setState(() {});
    panelRevision.value++;
  }

  Future<void> selectFilter(Preset? preset) async {
    if (!toolsEnabled || preparingFilter) return;
    setState(() => preparingFilter = true);
    try {
      final id = preset == null ? '' : await filters.prepare(preset);
      if (!mounted || !sameOwner) return;
      change(() {
        recipe.data['presetId'] = id;
        recipe.data['presetName'] = preset?.name ?? '无滤镜';
        recipe.data['strength'] = preset == null ? 0 : 100;
      });
    } catch (failure) {
      if (mounted && sameOwner) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => preparingFilter = false);
    }
  }

  late final String owner =
      widget.state.session['user']?['id'] as String? ?? '';
  late final File legacyDraft = File(
    p.join(
      widget.state.core.root,
      'shared-drafts',
      owner.isEmpty ? 'guest' : owner,
      '${p.basenameWithoutExtension(widget.photo.path)}.json',
    ),
  );
  @override
  void initState() {
    super.initState();
    filters = EditorPresets(widget.state, widget.photo)
      ..addListener(filtersChanged);
    histogram = EditorHistogramController(
      core: widget.state.core,
      owner: owner,
      path: widget.photo.path,
      isCurrent: () => mounted && sameOwner && !leaving,
    )..addListener(histogramChanged);
    unawaited(filters.load());
    widget.state.addListener(editorOwnerChanged);
    progressEvents = HueviaCore.progress.listen((event) {
      final value = object(event);
      if (mounted && value['jobId'] == activeJob) {
        setState(() => progress = (value['progress'] as num).toDouble());
      }
    }, onError: (_) {});
    unawaited(restore());
  }

  Future<void> restore() async {
    try {
      final saved = await widget.state.core.call('draft.load', {
        'path': widget.photo.path,
        'owner': owner,
      });
      sourceSha = saved['sourceSha'] as String? ?? '';
      if (saved['recipe'] != null) {
        recipe = Recipe(data: object(saved['recipe']));
      } else if (await legacyDraft.exists()) {
        // Validate the old development draft through the original native format.
        final migrated = await widget.state.core.call('draft.save', {
          'path': widget.photo.path,
          'owner': owner,
          'recipe': object(jsonDecode(await legacyDraft.readAsString())),
        });
        recipe = Recipe(data: object(migrated['recipe']));
      }
      await reloadLocalState();
      if (mounted) {
        setState(() => restored = true);
        await render();
      }
    } catch (failure) {
      if (mounted) setState(() => error = '草稿未能打开：$failure');
    }
  }

  @override
  void dispose() {
    effectDetails?.dispose();
    comparisonDetails?.dispose();
    atmosphereGeneration++;
    atmosphereLoading = false;
    previewQueue.close();
    widget.state.removeListener(editorOwnerChanged);
    filters.removeListener(filtersChanged);
    filters.dispose();
    quickGeneration++;
    quickDebounce?.cancel();
    if (quickJob != null) unawaited(widget.state.core.cancel(quickJob!));
    histogram.removeListener(histogramChanged);
    histogram.dispose();
    clearRegionLayer();
    debounce?.cancel();
    if (restored && !exporting && !photoDeleted && !colorToolActive) {
      unawaited(saveDraft().catchError((_) {}));
    }
    unawaited(progressEvents?.cancel());
    if (activeJob != null) unawaited(widget.state.core.cancel(activeJob!));
    if (preview != null) unawaited(discardPreview(preview, force: true));
    if (comparison != null) unawaited(discardPreview(comparison, force: true));
    if (atmosphere != null) unawaited(discardPreview(atmosphere, force: true));
    panelRevision.dispose();
    super.dispose();
  }

  Future<void> saveDraft() async {
    await settleLocalAdjustments();
    if ((widget.state.session['user']?['id'] as String? ?? '') != owner) {
      throw const AppFailure('账号已改变，请重新打开照片。');
    }
    final saved = await widget.state.core.call('draft.save', {
      'path': widget.photo.path,
      'owner': owner,
      'recipe': recipe.clone().data,
    });
    if (sameOwner && saved['sourceSha'] is String) {
      sourceSha = saved['sourceSha'] as String;
    }
  }

  void checkpoint() {
    final snapshot = recipe.clone();
    localQueue?.fillSnapshot(snapshot);
    undo.add(snapshot);
    if (undo.length > 40) undo.removeAt(0);
    redo.clear();
  }

  void change(void Function() mutation, {bool snapshot = true}) {
    if (exporting ||
        managingTools ||
        analyzingCleanup ||
        !restored ||
        !sameOwner ||
        leaving) {
      return;
    }
    pauseEditorDetails();
    if (snapshot) checkpoint();
    clearRegionLayer();
    setState(() {
      compare = false;
      mutation();
      error = null;
    });
    revision++;
    panelRevision.value++;
    // Do not debounce the actual drag: a completed native frame is useful even
    // while the next parameter sample is waiting. The timer only refines the
    // last sample when an input control has no explicit gesture-end callback.
    unawaited(queuePreview(interactive: true));
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(render());
    });
  }

  bool previewRequestCurrent(_EditorPreviewRequest request) =>
      mounted &&
      sameOwner &&
      !leaving &&
      !managingTools &&
      !analyzingCleanup &&
      !exporting &&
      !exportWindowOpen &&
      request.path == widget.photo.path &&
      request.generation == previewGeneration &&
      queuedPreviewRevision == revision;

  Future<void> render({bool readOnly = false}) {
    pauseEditorDetails();
    debounce?.cancel();
    return queuePreview(interactive: false, readOnly: readOnly);
  }

  Future<void> queuePreview({
    required bool interactive,
    bool readOnly = false,
  }) {
    if (!mounted || managingTools || !sameOwner || leaving) {
      return Future.value();
    }
    // Modal tools, undo, compare and owner invalidation advance revision outside
    // change(). Retire their preceding scope before accepting another sample.
    if (queuedPreviewRevision != revision &&
        (!interactive || queuedPreviewRevision != revision - 1)) {
      previewGeneration++;
      previewQueue.reset();
    }
    queuedPreviewRevision = revision;
    clearRegionLayer();
    return previewQueue.offer(
      _EditorPreviewRequest(
        recipe.clone(),
        revision,
        previewGeneration,
        compare,
        readOnly || colorToolActive,
        sourceSha,
        widget.photo.path,
      ),
      interactive: interactive,
    );
  }

  Future<_EditorPreviewFrame?> renderPreview(
    _EditorPreviewRequest request,
    bool interactive,
  ) async {
    if (!previewRequestCurrent(request)) return null;
    histogram.markUpdating();
    final frozen = request.recipe;
    // The queue starts in a microtask, after changeAdjustment has enqueued the
    // matching local mutation. Await that position, not a moving stream of edits.
    final queue = localQueue;
    if (queue != null) {
      final local = await queue.settled;
      frozen.data['localData'] = local['localData'];
    }
    if (!previewRequestCurrent(request)) return null;
    final job = 'preview-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      rendering = true;
      activeJob = job;
      progress = 0;
    });
    try {
      final result = await widget.state.core.call(
        request.readOnly ? 'media.reviewPreview' : 'media.preview',
        {
          'path': request.path,
          'recipe': frozen.data,
          'owner': owner,
          'maxEdge': interactive ? 640 : 1280,
          if (request.readOnly) 'snapshot': true,
          if (request.readOnly) 'expectedSourceSha': request.sourceSha,
        },
        job,
      );
      if (!previewRequestCurrent(request) || activeJob != job) {
        unawaited(discardPreview(result['path']));
        return null;
      }
      String? reference;
      if (request.splitting) {
        final neutral = Recipe().data;
        for (final key in ['geometry', 'border']) {
          if (frozen.data[key] != null) neutral[key] = frozen.data[key];
        }
        late final Json before;
        try {
          before = await widget.state.core.call(
            request.readOnly ? 'media.reviewPreview' : 'media.preview',
            {
              'path': request.path,
              'recipe': neutral,
              'owner': owner,
              'maxEdge': interactive ? 640 : 1280,
              if (request.readOnly) 'snapshot': true,
              if (request.readOnly) 'expectedSourceSha': request.sourceSha,
            },
            job,
          );
        } catch (_) {
          unawaited(discardPreview(result['path']));
          rethrow;
        }
        reference = before['path'] as String;
        if (!previewRequestCurrent(request) || activeJob != job) {
          unawaited(discardPreview(reference));
          unawaited(discardPreview(result['path']));
          return null;
        }
      }
      return _EditorPreviewFrame(result, reference);
    } finally {
      if (mounted && activeJob == job) {
        setState(() {
          rendering = false;
          activeJob = null;
        });
      }
    }
  }

  void acceptPreview(
    _EditorPreviewRequest request,
    _EditorPreviewFrame? frame,
    bool interactive,
    bool latest,
  ) {
    if (frame == null) return;
    if (!interactive) detailRefreshPending = false;
    final result = frame.result, frozen = request.recipe;
    final reference = frame.reference;
    final old = preview, oldComparison = comparison;
    setState(() {
      preview = result['path'] as String;
      if (result['geometryWidth'] is num && result['geometryHeight'] is num) {
        compositionFrame = Size(
          (result['geometryWidth'] as num).toDouble(),
          (result['geometryHeight'] as num).toDouble(),
        );
        compositionFrameTurns =
            object(frozen.data['geometry'] ?? {})['turns'] as int? ?? 0;
      }
      comparison = reference;
      displayedOverlay = {
        'recipe': frozen.data,
        'sourceWidth': result['sourceWidth'],
        'sourceHeight': result['sourceHeight'],
        'outputWidth': result['width'],
        'outputHeight': result['height'],
      };
      displayedRevision = request.revision;
      error = null;
    });
    unawaited(refreshRegionLayer());
    // Avoid another full native render per intermediate drag frame. The
    // settled request refreshes histogram pixels at the normal final size.
    if (!interactive) {
      unawaited(histogram.update(frozen.data, request.sourceSha));
    }
    panelRevision.value++;
    if (oldComparison != null &&
        oldComparison != preview &&
        oldComparison != comparison) {
      unawaited(discardPreview(oldComparison));
    }
    if (atmosphere == null && !atmosphereLoading) {
      unawaited(loadAtmosphere(result['path'] as String));
    }
    if (old != null &&
        old != result['path'] &&
        p.isWithin(p.join(widget.state.core.root, 'previews'), old)) {
      unawaited(discardPreview(old));
    }
  }

  Future<void> discardPreviewFrame(_EditorPreviewFrame? frame) async {
    if (frame == null) return;
    // Decoding a retiring image must not hold up the next native render.
    unawaited(discardPreview(frame.result['path']));
    unawaited(discardPreview(frame.reference));
  }

  Future<void> discardPreview(Object? path, {bool force = false}) async {
    if (path is! String ||
        !p.isWithin(p.join(widget.state.core.root, 'previews'), path)) {
      return;
    }
    bool displayed() =>
        path == preview || path == comparison || path == atmosphere;
    if (!force && displayed()) return;
    try {
      final file = File(path);
      // A fast native frame may retire its predecessor before FileImage has
      // finished reading it. Join that same decoded-image stream before
      // removing its backing file; this never stalls the render queue.
      if (await file.exists()) {
        final read = Completer<void>();
        final stream = FileImage(file).resolve(const ImageConfiguration());
        final listener = ImageStreamListener(
          (image, synchronous) {
            image.dispose();
            if (!read.isCompleted) read.complete();
          },
          onError: (Object error, StackTrace? stack) {
            if (!read.isCompleted) read.complete();
          },
        );
        stream.addListener(listener);
        try {
          await read.future;
        } finally {
          stream.removeListener(listener);
        }
      }
      if (!force && displayed()) return;
      await ResizeImage(FileImage(file), width: 1280).evict();
      await FileImage(file).evict();
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A preview is disposable; cleanup failure never affects the original.
    }
  }

  Future<void> openCrop({double initialRatio = -1}) async {
    if (!toolsEnabled) return;
    pauseEditorDetails();
    debounce?.cancel();
    revision++;
    setState(() => managingTools = true);
    try {
      await settleLocalAdjustments();
      if (activeJob != null) await widget.state.core.cancel(activeJob!);
      if (!mounted) return;
      final result = await hueRootPage<Json>(
        context,
        MaterialPageRoute(
          builder: (_) => CropWorkspace(
            core: widget.state.core,
            photo: widget.photo,
            owner: owner,
            recipe: recipe.clone().data,
            isCurrent: () => mounted && sameOwner && !leaving,
            invalidation: widget.state,
            initialRatio: initialRatio,
          ),
        ),
      );
      if (result != null && mounted) {
        if ((widget.state.session['user']?['id'] as String? ?? '') != owner) {
          throw const AppFailure('账号已改变，请重新打开照片。');
        }
        checkpoint();
        setState(() {
          recipe.data['geometry'] = result;
          compare = false;
        });
        unawaited(saveDraft().catchError((_) {}));
      }
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) {
        setState(() => managingTools = false);
        unawaited(render());
      }
    }
  }

  Future<void> openTool({
    bool copying = false,
    bool savedVersions = false,
  }) async {
    if (!toolsEnabled) return;
    debounce?.cancel();
    revision++;
    setState(() => managingTools = true);
    try {
      await settleLocalAdjustments();
      if (activeJob != null) await widget.state.core.cancel(activeJob!);
      if (!mounted || !sameOwner) return;
      await saveDraft();
      if (!mounted || !sameOwner) return;
      final frozen = recipe.clone().data;
      final fingerprint = jsonEncode(frozen);
      bool current() =>
          mounted && sameOwner && jsonEncode(recipe.data) == fingerprint;
      final source = savedVersions
          ? await widget.state.core.call('draft.load', {
              'owner': owner,
              'path': widget.photo.path,
            })
          : const <String, dynamic>{};
      if (!mounted || !current()) return;
      final applied = await hueRootPage<Json>(
        context,
        MaterialPageRoute(
          builder: (_) => copying
              ? CopyAdjustmentsPage(
                  state: widget.state,
                  source: widget.photo,
                  recipe: frozen,
                  owner: owner,
                  isCurrent: current,
                )
              : savedVersions
              ? VersionsPage(
                  core: widget.state.core,
                  owner: owner,
                  path: widget.photo.path,
                  state: widget.state,
                  isCurrent: current,
                  expectedSourceSha: source['sourceSha'] as String?,
                )
              : RecipesPage(
                  core: widget.state.core,
                  owner: owner,
                  path: widget.photo.path,
                  current: frozen,
                  state: widget.state,
                  isCurrent: current,
                ),
        ),
      );
      if (!mounted || !current()) return;
      if (applied != null) {
        if (copying) {
          rememberCopy(applied);
          showCopyReceipt(
            context,
            widget.state.core,
            owner,
            applied,
            isCurrent: () => mounted && sameOwner,
          );
          return;
        }
        if (savedVersions) parkedDraft = Recipe(data: frozen);
        checkpoint();
        setState(() {
          compare = false;
          recipe = Recipe(data: applied);
        });
        await reloadLocalState();
        if (!mounted || !sameOwner) return;
        panelRevision.value++;
        await saveDraft();
      }
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) {
        setState(() => managingTools = false);
        unawaited(render());
      }
    }
  }

  Future<void> analyzeCleanup() async {
    if (exporting || managingTools || analyzingCleanup || !restored) return;
    pauseEditorDetails();
    debounce?.cancel();
    revision++;
    final job = 'cleanup-${DateTime.now().microsecondsSinceEpoch}';
    final oldJob = activeJob;
    var succeeded = false;
    setState(() {
      analyzingCleanup = true;
      activeJob = job;
      progress = 0;
      error = null;
    });
    panelRevision.value++;
    try {
      await settleLocalAdjustments();
      if (!mounted || !sameOwner || activeJob != job) return;
      final regionId = selectedRegionId;
      if (oldJob != null) await widget.state.core.cancel(oldJob);
      if (!mounted || !sameOwner || activeJob != job) return;
      final result = await widget.state.core.call('media.cleanupAnalyze', {
        'path': widget.photo.path,
        'owner': owner,
        'regionId': regionId ?? '',
        'recipe': recipe.clone().data,
      }, job);
      if (!mounted ||
          !sameOwner ||
          activeJob != job ||
          regionId != selectedRegionId) {
        return;
      }
      checkpoint();
      setState(() {
        compare = false;
        adjustmentRecipe.data['cleanupData'] = result['cleanupData'];
        adjustmentRecipe.data['cleanup'] = {
          'amount': 100,
          'haze': 100,
          'noise': 100,
        };
      });
      if (regionId != null) {
        await localQueue!.change(regionId, {
          'adjustments': adjustmentRecipe.clone().data,
        });
      }
      panelRevision.value++;
      succeeded = true;
    } catch (failure) {
      if (mounted && activeJob == job) setState(() => error = '$failure');
    } finally {
      if (mounted && activeJob == job) {
        setState(() {
          analyzingCleanup = false;
          rendering = false;
          activeJob = null;
        });
        panelRevision.value++;
        if (succeeded) unawaited(render());
      }
    }
  }

  bool exportWindowOpen = false;
  Future<void> export() async {
    if (!toolsEnabled || exportWindowOpen) return;
    pauseEditorDetails();
    exportWindowOpen = true;
    debounce?.cancel();
    final previousJob = activeJob;
    revision++;
    setState(() {
      rendering = false;
      activeJob = null;
    });
    ExportSettings? settings;
    try {
      await settleLocalAdjustments();
      if (previousJob != null) await widget.state.core.cancel(previousJob);
      if (!mounted || !sameOwner || leaving) return;
      settings = ExportSettings(
        state: widget.state,
        photo: widget.photo,
        owner: owner,
        recipe: recipe.clone().data,
        isCurrent: () => mounted && sameOwner && !leaving,
      );
      await showLegacyExport(context, settings, preview: preview);
    } catch (failure) {
      if (mounted && sameOwner) report(context, failure);
    } finally {
      settings?.dispose();
      exportWindowOpen = false;
      if (mounted) {
        setState(() {
          exporting = false;
          rendering = false;
          activeJob = null;
        });
      }
    }
  }

  Widget slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> changed, {
    String? display,
    VoidCallback? start,
  }) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            display ?? value.round().toString(),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      Row(
        children: [
          IconButton(
            tooltip: '减小$label',
            onPressed:
                exporting || managingTools || analyzingCleanup || value <= min
                ? null
                : () {
                    checkpoint();
                    changed((value - 1).clamp(min, max));
                  },
            icon: const Icon(Icons.remove_rounded),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChangeStart: exporting || managingTools || analyzingCleanup
                  ? null
                  : (_) {
                      beginParameterGesture();
                      (start ?? checkpoint)();
                    },
              onChangeEnd: (_) => endParameterGesture(),
              onChanged: exporting || managingTools || analyzingCleanup
                  ? null
                  : changed,
            ),
          ),
          IconButton(
            tooltip: '增大$label',
            onPressed:
                exporting || managingTools || analyzingCleanup || value >= max
                ? null
                : () {
                    checkpoint();
                    changed((value + 1).clamp(min, max));
                  },
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    ],
  );
  Widget controls({int? tool}) {
    switch (tool ?? tab) {
      case 7:
        return legacyColorControls(7);
      case 0:
        return Column(
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('preset-${recipe.data['presetId']}'),
              initialValue: recipe.data['presetId'] as String,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '滤镜预设'),
              items: [
                const DropdownMenuItem(value: '', child: Text('无滤镜')),
                if ((recipe.data['presetId'] as String).isNotEmpty &&
                    !allFilters.any(
                      (preset) =>
                          filters.identity(preset) == recipe.data['presetId'],
                    ))
                  DropdownMenuItem(
                    value: recipe.data['presetId'] as String,
                    child: Text('${recipe.data['presetName'] ?? '已保存滤镜'} · 草稿'),
                  ),
                ...allFilters.map(
                  (preset) => DropdownMenuItem(
                    value: filters.identity(preset),
                    child: Text(
                      preset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: !toolsEnabled
                  ? null
                  : (value) {
                      if (value == recipe.data['presetId']) return;
                      unawaited(
                        selectFilter(
                          value == null || value.isEmpty
                              ? null
                              : allFilters.firstWhere(
                                  (preset) => filters.identity(preset) == value,
                                ),
                        ),
                      );
                    },
            ),
            if (filters.loading) const LinearProgressIndicator(),
            if (filters.error != null)
              TextButton(
                onPressed: () => unawaited(filters.load()),
                child: const Text('在线滤镜加载失败，重试'),
              ),
            const SizedBox(height: 16),
            slider(
              '滤镜强度',
              (recipe.data['strength'] as int).toDouble(),
              0,
              100,
              (value) => change(
                () => recipe.data['strength'] = value.round(),
                snapshot: false,
              ),
            ),
          ],
        );
      case 1:
        return Column(
          children: [
            for (final raw in widget.state.core.schema['parameters'] as List)
              Builder(
                builder: (context) {
                  final parameter = object(raw),
                      index = parameter['index'] as int,
                      name = parameter['label'] as String,
                      value = adjustmentRecipe.values[index];
                  return Column(
                    children: [
                      slider(
                        name,
                        value.toDouble(),
                        (parameter['min'] as num).toDouble(),
                        (parameter['max'] as num).toDouble(),
                        (v) => changeAdjustment(
                          () => adjustmentRecipe.setValue(index, v.round()),
                          snapshot: false,
                        ),
                        display: index == 1
                            ? '${(value / 10).toStringAsFixed(1)} EV'
                            : '$value',
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => hueDialog<void>(
                            context: context,
                            builder: (dialog) => AlertDialog(
                              title: Text(name),
                              content: SingleChildScrollView(
                                child: Text(parameter['help'] as String),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog),
                                  child: const Text('知道了'),
                                ),
                              ],
                            ),
                          ),
                          child: Text('$name说明'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
          ],
        );
      case 2:
        return legacyColorControls(2);
      case 3:
        final geometry = object(recipe.data['geometry'] ?? {});
        return Column(
          children: [
            OutlinedButton.icon(
              onPressed: toolsEnabled ? openCrop : null,
              icon: const HueIcon(HueIconKind.crop),
              label: const Text('交互裁切与构图'),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.rotate_right_rounded),
                  label: const Text('旋转 90°'),
                  onPressed: exporting
                      ? null
                      : () => change(() {
                          geometry['turns'] =
                              ((geometry['turns'] as int? ?? 0) + 1) % 4;
                          geometry.addAll({
                            'left': 0,
                            'top': 0,
                            'right': 1000000,
                            'bottom': 1000000,
                          });
                          recipe.data['geometry'] = geometry;
                        }),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.flip_rounded),
                  label: const Text('水平翻转'),
                  onPressed: exporting
                      ? null
                      : () => change(() {
                          geometry['mirrored'] = geometry['mirrored'] != true;
                          final left = geometry['left'] as int? ?? 0;
                          geometry['left'] =
                              1000000 - (geometry['right'] as int? ?? 1000000);
                          geometry['right'] = 1000000 - left;
                          recipe.data['geometry'] = geometry;
                        }),
                ),
              ],
            ),
            const SizedBox(height: 16),
            slider(
              '拉直',
              (geometry['angle'] as int? ?? 0).toDouble(),
              -450,
              450,
              (value) => change(() {
                geometry['angle'] = value.round();
                recipe.data['geometry'] = geometry;
              }, snapshot: false),
              display:
                  '${((geometry['angle'] as int? ?? 0) / 10).toStringAsFixed(1)}°',
            ),
            for (final entry in [
              ('horizontalPerspective', '水平透视'),
              ('verticalPerspective', '垂直透视'),
            ])
              slider(
                entry.$2,
                (geometry[entry.$1] as int? ?? 0).toDouble(),
                -100,
                100,
                (value) => change(() {
                  geometry[entry.$1] = value.round();
                  recipe.data['geometry'] = geometry;
                }, snapshot: false),
              ),
            const SizedBox(height: 12),
            const Text('裁剪范围'),
            for (final entry in [
              ('left', '左侧', 0),
              ('top', '顶部', 0),
              ('right', '右侧', 1000000),
              ('bottom', '底部', 1000000),
            ])
              slider(
                entry.$2,
                (geometry[entry.$1] as int? ?? entry.$3) / 10000,
                0,
                100,
                (value) => change(() {
                  var next = (value * 10000).round();
                  final opposite = {
                    'left': 'right',
                    'right': 'left',
                    'top': 'bottom',
                    'bottom': 'top',
                  }[entry.$1]!;
                  if (entry.$3 == 0) {
                    next = next.clamp(
                      0,
                      (geometry[opposite] as int? ?? 1000000) - 1000,
                    );
                  } else {
                    next = next.clamp(
                      (geometry[opposite] as int? ?? 0) + 1000,
                      1000000,
                    );
                  }
                  geometry[entry.$1] = next;
                  recipe.data['geometry'] = geometry;
                }, snapshot: false),
                display:
                    '${((geometry[entry.$1] as int? ?? entry.$3) / 10000).toStringAsFixed(1)}%',
              ),
            TextButton(
              onPressed: exporting
                  ? null
                  : () => change(() => recipe.data.remove('geometry')),
              child: const Text('重置构图'),
            ),
          ],
        );
      case 5:
        return legacyColorControls(5);
      case 6:
        return legacyColorControls(6);
      default:
        return SizedBox(height: 280, child: borderDock());
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(leaveEditor());
    },
    child: legacyWorkspace(context),
  );
}
