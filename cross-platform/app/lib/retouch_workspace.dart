import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'retouch_more.dart';
import 'retouch_original_controls.dart';
import 'retouch_original_body.dart';
import 'retouch_brush_preview.dart';
import 'retouch_blemish_review.dart';
import 'selection_workspace.dart';
import 'photo_workspace_chrome.dart';
import 'widgets.dart';
import 'theme.dart';

part 'retouch_original_workspace.dart';

/// Tentative edits remain owned by this route until Apply returns localData.
class RetouchWorkspace extends StatefulWidget {
  const RetouchWorkspace({
    super.key,
    required this.state,
    required this.photo,
    required this.owner,
    required this.recipe,
    required this.isCurrent,
    this.patch = false,
    this.regionId,
    this.regionName,
  });
  final AppState state;
  final Photo photo;
  final String owner;
  final Json recipe;
  final bool Function() isCurrent;
  final bool patch;
  final String? regionId, regionName;
  @override
  State<RetouchWorkspace> createState() => _RetouchWorkspaceState();
}

class _RetouchWorkspaceState extends State<RetouchWorkspace> {
  Json? data, frame;
  final undo = <Json>[], redo = <Json>[];
  String? job, error;
  String? notice;
  bool busy = true, stopped = false, manual = false, healMode = false;
  bool exitRequested = false;
  int operationEpoch = 0;
  int selected = 0, tab = 0, bodyTool = 0;
  double radius = .025;
  double? brushRadiusStart;
  int brushSizeGeneration = 0;
  final brushEditing = ValueNotifier<bool>(true);
  bool get photoEditingEnabled =>
      current &&
      !comparing &&
      !compareWanted &&
      brushRadiusStart == null &&
      (!busy || bodyGestureArea != null);
  Offset? brushPreviewCenter;
  bool patchChildOpen = false;
  Json? patchEntryFrame;
  double targetX = .5, targetY = .5;
  final points = <Offset>[];
  List<Json> people = [];
  int bodyPerson = 0;
  bool? tonePerFace;
  List<RetouchToneCard> toneCards = [];
  Json? tonePreviewStart;
  bool photoSampling = false;
  int? sampleSeed;
  bool choosingGroup = true, showOverlay = true, comparing = false;
  bool compareWanted = false, bodyExpanded = false;
  Matrix4? bodyViewportBefore;
  bool? bodyOverlayBefore;
  int? bodyTabBefore;
  String? faceParameter;
  String skinParameter = 'tone', bodyParameter = 'amount';
  int faceMode = 0, selectionBrush = 0;
  Json? comparisonFrame, bodyStart, bodyComparisonBefore, bodyFrameBefore;
  List<Json>? bodyUndoBefore, bodyRedoBefore;
  final viewport = TransformationController();
  String? atmosphere;
  Json? scalarStart;
  Json? scalarFrameStart;
  Json? scalarPending;
  String? scalarKey;
  bool scalarRunning = false,
      scalarEnded = false,
      scalarCancelled = false,
      scalarRemember = true;
  Json? lightStart;
  Json? lightFrameStart;
  Offset? lightPending;
  bool lightRunning = false, lightEnded = false, lightCancelled = false;
  int lightTarget = 0;
  Offset? originalGestureDown;
  Json? bodyGestureArea, bodyGestureDraft;
  String? originalGestureLocal;
  int originalGestureFace = 0, bodyHandle = -1, originalGestureTool = 0;
  double originalGestureRadius = .022;
  ui.Image? portraitOverlay;
  String? portraitOverlayKey, portraitOverlayJob;
  int portraitOverlayRevision = 0, faceHitRevision = 0;
  ValueNotifier<bool>? blemishReview;
  void invalidateBlemishReview() => blemishReview?.value = false;
  void refreshPortrait(VoidCallback update) => setState(update);
  final temporary = <String>{};
  bool get current =>
      mounted &&
      !exitRequested &&
      widget.isCurrent() &&
      widget.state.session['logoutPending'] != true &&
      (widget.state.session['user']?['id'] as String? ?? '') == widget.owner;
  bool operationCurrent(int epoch) => current && epoch == operationEpoch;
  void cancelJob(String? id) {
    if (id != null) {
      unawaited(() async {
        try {
          await widget.state.core.cancel(id);
        } catch (_) {}
      }());
    }
  }

  void cancelWorkspace({bool pop = true}) {
    if (exitRequested) return;
    invalidateBlemishReview();
    final active = job;
    job = null;
    exitRequested = true;
    brushEditing.value = false;
    operationEpoch++;
    stopped = true;
    clearPortraitOverlay();
    cancelJob(active);
    if (pop && mounted) Navigator.of(context).pop();
  }

  void cancelBusyBody() {
    final before = bodyStart;
    if (before == null) return;
    final active = job;
    job = null;
    operationEpoch++;
    clearPortraitOverlay();
    cancelJob(active);
    setState(() {
      data = before;
      frame = bodyFrameBefore;
      undo
        ..clear()
        ..addAll(bodyUndoBefore ?? []);
      redo
        ..clear()
        ..addAll(bodyRedoBefore ?? []);
      scalarStart = scalarFrameStart = scalarPending = null;
      scalarKey = null;
      scalarRunning = false;
      scalarEnded = false;
      scalarCancelled = true;
      lightStart = lightFrameStart = null;
      lightPending = null;
      lightRunning = false;
      lightCancelled = true;
      points.clear();
      bodyGestureArea = bodyGestureDraft = null;
      originalGestureDown = null;
      originalGestureLocal = null;
      comparisonFrame = bodyComparisonBefore;
      bodyComparisonBefore = null;
      comparing = compareWanted = false;
      if (bodyTabBefore != null) tab = bodyTabBefore!;
      if (bodyOverlayBefore != null) showOverlay = bodyOverlayBefore!;
      if (bodyViewportBefore != null) viewport.value = bodyViewportBefore!;
      bodyStart = bodyFrameBefore = null;
      bodyUndoBefore = bodyRedoBefore = null;
      bodyTabBefore = null;
      bodyOverlayBefore = null;
      bodyViewportBefore = null;
      busy = false;
      stopped = false;
      error = notice = null;
      choosingGroup = true;
    });
    unawaited(refreshPortraitOverlay());
  }

  void requestExit() {
    if (exitRequested) return;
    if (brushRadiusStart != null) cancelBrushSizing();
    if (bodyStart != null &&
        (busy ||
            scalarStart != null ||
            lightStart != null ||
            originalGestureDown != null)) {
      cancelBusyBody();
      return;
    }
    if (busy || scalarStart != null || lightStart != null || choosingGroup) {
      cancelWorkspace();
      return;
    }
    unawaited(originalGroups());
  }

  Json get portrait => object(data?['portrait'] ?? {});
  List<Json> get faces =>
      (portrait['faces'] as List? ?? []).map(object).toList();
  Json get chosen =>
      faces.isEmpty ? {} : faces[selected.clamp(0, faces.length - 1)];
  Json get skin => object(portrait['skin'] ?? {});
  bool get originalPortraitReady {
    if (portrait['hasSkinMask'] == true) return true;
    if (((skin['smoothing'] as num?) ?? 0) != 0) return false;
    if ([
      'NATURAL',
      'EVENNESS',
      'SHINE',
    ].any((k) => ((skin[k] as num?) ?? 0) > 0)) {
      return false;
    }
    if (skin['toneId'] != 0 && ((skin['toneAmount'] as num?) ?? 0) != 0) {
      return false;
    }
    final regional = object(portrait['regionSkin'] ?? {});
    if (widget.regionId?.isNotEmpty == true &&
        regional.entries.any((e) => e.value != (e.key == 'texture' ? 70 : 0))) {
      return false;
    }
    return true;
  }

  Json get area => (portrait['body'] as List? ?? []).length == 3
      ? object((portrait['body'] as List)[bodyTool])
      : {};
  @override
  void initState() {
    super.initState();
    if (!widget.patch) {
      radius = .022;
      tab = 1; // Original PhotoPortraitDialog starts in mode 3 (skin tone).
    }
    widget.state.addListener(accountChanged);
    unawaited(load());
  }

  void accountChanged() {
    if (!current) {
      operationEpoch++;
      invalidateBlemishReview();
      unawaited(stop());
      if (mounted) setState(() => error = '账号已改变，请返回重新打开照片。');
      if (mounted) {
        setState(() {
          data = frame = null;
          undo.clear();
          redo.clear();
          toneCards = [];
          tonePreviewStart = null;
          photoSampling = false;
          atmosphere = null;
          lightPending = null;
          lightStart = lightFrameStart = null;
          scalarStart = scalarFrameStart = scalarPending = null;
          scalarKey = null;
          comparisonFrame = null;
          comparing = compareWanted = false;
          bodyStart = bodyGestureArea = bodyGestureDraft = null;
          bodyUndoBefore = bodyRedoBefore = null;
          points.clear();
        });
      }
      clearPortraitOverlay();
    }
  }

  Future<Json> call(String op, Json value) async {
    final epoch = operationEpoch;
    if (!operationCurrent(epoch) || stopped) throw const AppFailure('编辑计算已停止。');
    final id = 'retouch-${DateTime.now().microsecondsSinceEpoch}';
    job = id;
    try {
      final result = await widget.state.core.call(op, {
        'path': widget.photo.path,
        'owner': widget.owner,
        if (widget.regionId?.isNotEmpty == true) 'regionId': widget.regionId,
        if (tonePerFace != null) 'tonePerFace': tonePerFace,
        ...value,
      }, id);
      if (!operationCurrent(epoch) || stopped) {
        final path = result['path'];
        if (path is String) await remove(path);
        throw const AppFailure('编辑计算已停止。');
      }
      if (op.startsWith('media.retouch') &&
          (result['regionId'] as String? ?? '') != (widget.regionId ?? '')) {
        throw const AppFailure('人像编辑范围已变化，请重新打开。');
      }
      return result;
    } finally {
      if (job == id) job = null;
    }
  }

  Future<void> remove(String path) async {
    if (!p.isWithin(p.join(widget.state.core.root, 'previews'), path)) return;
    try {
      await FileImage(File(path)).evict();
      await File(path).delete();
    } on FileSystemException {
      /* disposable */
    }
  }

  Future<Json> render(Json next, {bool interactive = false}) async {
    final epoch = operationEpoch;
    final display =
        (widget.patch ||
            (tab != 2 &&
                (!choosingGroup ||
                    (widget.regionId?.isNotEmpty == true &&
                        next['sourcePositioning'] == true))))
        ? await call('media.retouchChange', {
            'localData': next['localData'],
            'action': 'beforeBody',
          })
        : next;
    final result = await call(
      widget.patch ? 'media.localPreview' : 'media.reviewPreview',
      {
        'recipe': {
          ...widget.recipe,
          'localData': display['localData'],
          'geometry': <String, dynamic>{},
          'border': <String, dynamic>{},
        },
        'maxEdge': interactive ? 640 : 1280,
      },
    );
    final path = result['path'] as String;
    if (!mounted || !operationCurrent(epoch) || stopped) {
      await remove(path);
      throw const AppFailure('编辑计算已停止。');
    }
    Object? decodeFailure;
    await precacheImage(
      FileImage(File(path)),
      context,
      onError: (failure, stack) => decodeFailure = failure,
    );
    // Do not expose/retire an image while FileImage still has a pending read.
    // If the route leaves during decoding, this task owns its late file until
    // decoding completes and can safely remove it without touching newer work.
    if (!operationCurrent(epoch) || stopped || decodeFailure != null) {
      await remove(path);
      throw AppFailure(decodeFailure == null ? '编辑计算已停止。' : '无法读取人像预览，请重试。');
    }
    temporary.add(path);
    return result;
  }

  Future<void> load() async {
    final epoch = operationEpoch;
    if (operationCurrent(epoch)) {
      setState(() {
        busy = true;
        stopped = false;
        error = null;
      });
    }
    try {
      final next = await call('media.retouchDescribe', {
        'localData': widget.recipe['localData'] ?? '',
      });
      final image = await render(next);
      if (operationCurrent(epoch)) {
        setState(() {
          data = next;
          tonePerFace =
              object(next['portrait'] ?? {})['tonePerFace'] as bool? ??
              tonePerFace;
          frame = image;
          if (widget.patch) patchEntryFrame = image;
          if (next['people'] is List) {
            people = (next['people'] as List).map(object).toList();
            bodyPerson = next['selectedPerson'] as int? ?? 0;
          }
        });
        unawaited(loadPortraitAtmosphere(image['path'] as String));
        unawaited(refreshPortraitOverlay());
      }
    } catch (failure) {
      if (operationCurrent(epoch)) setState(() => error = '$failure');
    } finally {
      if (operationCurrent(epoch)) setState(() => busy = false);
    }
    if (!widget.patch &&
        !choosingGroup &&
        operationCurrent(epoch) &&
        data != null &&
        faces.isEmpty) {
      unawaited(detectFaces());
    }
  }

  Future<void> perform(String op, Json payload, {bool remember = true}) async {
    if (brushRadiusStart != null) cancelBrushSizing();
    final epoch = operationEpoch;
    if (remember &&
        tonePreviewStart != null &&
        !busy &&
        operationCurrent(epoch)) {
      await cancelTonePreview();
    }
    if (busy || !operationCurrent(epoch) || data == null) return;
    final scalarGesture = !remember && scalarStart != null;
    final lightGesture = !remember && lightStart != null;
    final gesture = scalarGesture || lightGesture;
    bool cancelledGesture() =>
        gesture &&
        (scalarGesture && scalarCancelled ||
            lightGesture && lightCancelled ||
            stopped);
    setState(() {
      busy = true;
      stopped = false;
      error = null;
    });
    try {
      final next = await call(op, {
        'localData': data!['localData'],
        ...payload,
      });
      if (cancelledGesture()) return;
      if (op == 'media.retouchAnalyze' &&
          payload['mode'] == 'face' &&
          (object(next['portrait'])['faces'] as List? ?? []).isEmpty) {
        if (operationCurrent(epoch)) setState(() => notice = '未识别到清晰正脸，请手动添加。');
        return;
      }
      // A held body handle uses PhotoStage's current raster dimensions for its
      // pointer lease. Keep that raster size until all canvas pointers lift.
      final image = await render(
        next,
        interactive: gesture && bodyGestureArea == null,
      );
      if (cancelledGesture()) {
        await remove(image['path'] as String);
        return;
      }
      if (operationCurrent(epoch)) {
        setState(() {
          if (remember) {
            undo.add(data!);
            if (undo.length > (bodyStart == null ? 32 : 48)) undo.removeAt(0);
            redo.clear();
          }
          data = next;
          tonePerFace =
              object(next['portrait'] ?? {})['tonePerFace'] as bool? ??
              tonePerFace;
          frame = image;
          selected = selected.clamp(0, math.max(0, faces.length - 1));
          if (payload['action'] == 'manualFace') {
            selected = math.max(0, faces.length - 1);
            manual = false;
          }
          if (next['people'] is List) {
            people = (next['people'] as List).map(object).toList();
            bodyPerson = next['selectedPerson'] as int? ?? 0;
          }
        });
        if (!gesture) unawaited(refreshPortraitOverlay());
      }
    } catch (failure) {
      if (operationCurrent(epoch) && !stopped) {
        setState(() => error = '$failure');
      }
    } finally {
      if (operationCurrent(epoch)) {
        setState(() {
          busy = false;
          points.clear();
        });
      }
    }
  }

  Future<void> finishGesturePreview(
    Json before,
    Json? beforeFrame, {
    required bool Function() cancelled,
    required bool remember,
  }) async {
    final epoch = operationEpoch;
    if (!operationCurrent(epoch)) return;
    void rollback() {
      data = before;
      frame = beforeFrame;
    }

    if (cancelled() || stopped) {
      setState(rollback);
      return;
    }
    final candidate = data!;
    setState(() => busy = true);
    try {
      // Only a completed gesture gets the normal-size preview and one history
      // entry. Intermediate native changes are tentative route-owned values.
      final image = await render(candidate);
      if (!operationCurrent(epoch)) return;
      if (cancelled() || stopped) {
        await remove(image['path'] as String);
        if (operationCurrent(epoch)) setState(rollback);
        return;
      }
      setState(() {
        frame = image;
        if (remember && before['localData'] != candidate['localData']) {
          undo.add(before);
          if (undo.length > (bodyStart == null ? 32 : 48)) undo.removeAt(0);
          redo.clear();
        }
      });
    } catch (failure) {
      if (operationCurrent(epoch)) {
        setState(() {
          rollback();
          if (!stopped && !cancelled()) error = '$failure';
        });
      }
    } finally {
      if (operationCurrent(epoch)) setState(() => busy = false);
    }
  }

  Future<void> history(bool forward) async {
    if (brushRadiusStart != null) cancelBrushSizing();
    final epoch = operationEpoch;
    if (tonePreviewStart != null && !busy && operationCurrent(epoch)) {
      await cancelTonePreview();
    }
    final from = forward ? redo : undo, to = forward ? undo : redo;
    if (busy || from.isEmpty || !operationCurrent(epoch) || data == null) {
      return;
    }
    setState(() {
      busy = true;
      stopped = false;
      error = null;
    });
    try {
      final next = from.last;
      final image = await render(next);
      if (operationCurrent(epoch)) {
        setState(() {
          to.add(data!);
          from.removeLast();
          data = next;
          tonePerFace =
              object(next['portrait'] ?? {})['tonePerFace'] as bool? ??
              tonePerFace;
          frame = image;
          selected = selected.clamp(0, math.max(0, faces.length - 1));
        });
        unawaited(refreshPortraitOverlay());
      }
    } catch (failure) {
      if (operationCurrent(epoch) && !stopped) {
        setState(() => error = '$failure');
      }
    } finally {
      if (operationCurrent(epoch)) setState(() => busy = false);
    }
  }

  Future<void> stop() async {
    stopped = true;
    scalarCancelled = lightCancelled = true;
    scalarPending = null;
    lightPending = null;
    if (job != null) {
      try {
        await widget.state.core.cancel(job!);
      } catch (_) {
        /* The next result boundary also checks stopped. */
      }
    }
  }

  Future<void> change(String action, Json value) => perform(
    'media.retouchChange',
    {'action': action, 'index': selected, 'value': value},
  );

  List<RetouchHealEntry> get healingHistory => [
    for (final (index, value) in (portrait['heals'] as List? ?? []).indexed)
      RetouchHealEntry(
        index: index,
        x: (object(value)['tx'] as num).toDouble(),
        y: (object(value)['ty'] as num).toDouble(),
      ),
  ];

  Future<List<RetouchToneCard>> toneCardRequest(
    String operation, [
    Json extra = const {},
  ]) async {
    if (!current || stopped) throw const AppFailure('照片或账号已变化，请返回重新打开。');
    final result = await call(operation, extra);
    final cards = [
      for (final value in result['cards'] as List? ?? [])
        RetouchToneCard(
          id: object(value)['id'] as String,
          name: object(value)['name'] as String,
          rgb: object(value)['rgb'] as int,
        ),
    ];
    if (!current || stopped) throw const AppFailure('照片或账号已变化，请返回重新打开。');
    setState(() => toneCards = cards);
    return cards;
  }

  Future<void> morePortrait(BuildContext anchor) async {
    if (widget.patch || busy || !current || data == null) return;
    stopped = false;
    if (tonePreviewStart != null) await cancelTonePreview();
    if (!current || busy || data == null) return;
    final local = data!['localData'], face = faces.isEmpty ? null : selected;
    bool unchanged() =>
        current &&
        !busy &&
        data?['localData'] == local &&
        (faces.isEmpty ? null : selected) == face;
    try {
      if (tab == 1) {
        setState(() => busy = true);
        try {
          await toneCardRequest('toneCards.list');
        } finally {
          if (mounted) setState(() => busy = false);
        }
      }
      if (!mounted || !unchanged() || !anchor.mounted) return;
      final action = await showRetouchMoreMenu(
        anchor,
        state: RetouchMoreState(
          selectedFace: face,
          faceEnabled: chosen['enabled'] != false,
          heals: healingHistory,
          hasPortrait: true,
          skinMode: tab == 1 && skinParameter == 'tone',
          tonePerFace: tonePerFace ?? false,
          toneCardCount: toneCards.length,
        ),
      );
      if (!mounted || !unchanged() || action == null) return;
      switch (action) {
        case RetouchMoreAction.healHistory:
          final index = await showRetouchHealingHistory(
            context,
            heals: healingHistory,
          );
          if (!unchanged() || index == null) return;
          await perform('media.retouchChange', {
            'action': 'removeHeal',
            'index': index,
          });
        case RetouchMoreAction.manageToneCards:
          await showRetouchToneCards(
            context,
            cards: toneCards,
            onDelete: (id) => toneCardRequest('toneCards.remove', {'id': id}),
          );
        case RetouchMoreAction.toggleToneScope:
          await perform('media.retouchChange', {
            'action': 'toneScope',
            'index': face ?? -1,
            'value': {'perFace': !(tonePerFace ?? false)},
          });
        case RetouchMoreAction.toggleFace:
          if (face == null) return;
          await perform('media.retouchChange', {
            'action': 'face',
            'index': face,
            'value': {'enabled': chosen['enabled'] == false},
          });
        case RetouchMoreAction.deleteFace:
          if (face == null) return;
          await perform('media.retouchChange', {
            'action': 'removeFace',
            'index': face,
          });
        case RetouchMoreAction.undoLastHeal:
          if (healingHistory.isEmpty) return;
          await perform('media.retouchChange', {
            'action': 'removeHeal',
            'index': healingHistory.last.index,
          });
        case RetouchMoreAction.resetPortrait:
          final confirmed = await confirmRetouchReset(context);
          if (!unchanged() || !confirmed) return;
          await perform('media.retouchChange', {'action': 'clearPortrait'});
      }
    } catch (failure) {
      if (mounted && current) setState(() => error = '$failure');
    }
  }

  Json get editedTone => (tonePerFace ?? false) ? chosen : skin;
  String get toneAction => (tonePerFace ?? false) ? 'face' : 'skin';
  int? get pickerSeed {
    if (editedTone['toneId'] != 0 && editedTone['toneRgb'] is int) {
      return editedTone['toneRgb'] as int;
    }
    for (final value in data?['tones'] as List? ?? []) {
      final entry = object(value);
      if (entry['id'] == 1 && entry['color'] is int) {
        return entry['color'] as int;
      }
    }
    return null;
  }

  bool get canEditTone =>
      current &&
      !busy &&
      (!(tonePerFace ?? false) ||
          (faces.isNotEmpty && chosen['enabled'] != false));

  Future<void> previewTone(Json value) async {
    if (!canEditTone || data == null) return;
    tonePreviewStart ??= data;
    await perform('media.retouchChange', {
      'action': toneAction,
      'index': selected,
      'value': {
        'toneAmount': (editedTone['toneAmount'] as num?)?.toDouble() == 0
            ? .35
            : editedTone['toneAmount'],
        ...value,
      },
    }, remember: false);
  }

  void confirmTonePreview() {
    if (busy || !current || tonePreviewStart == null || data == null) return;
    setState(() {
      undo.add(tonePreviewStart!);
      if (undo.length > (bodyStart == null ? 32 : 48)) undo.removeAt(0);
      redo.clear();
      tonePreviewStart = null;
      photoSampling = false;
    });
  }

  Future<void> cancelTonePreview() async {
    final epoch = operationEpoch;
    if (busy || !operationCurrent(epoch) || tonePreviewStart == null) return;
    final before = tonePreviewStart!;
    setState(() {
      busy = true;
      stopped = false;
      photoSampling = false;
    });
    try {
      final image = await render(before);
      if (operationCurrent(epoch)) {
        setState(() {
          data = before;
          frame = image;
          tonePerFace =
              object(before['portrait'])['tonePerFace'] as bool? ?? tonePerFace;
          tonePreviewStart = null;
        });
      }
    } catch (failure) {
      if (operationCurrent(epoch)) setState(() => error = '$failure');
    } finally {
      if (operationCurrent(epoch)) setState(() => busy = false);
    }
  }

  Future<void> customTone(int rgb) async {
    if (!canEditTone) return;
    stopped = false;
    final local = data?['localData'], target = selected, perFace = tonePerFace;
    try {
      await toneCardRequest('toneCards.list');
      if (!mounted || !current || data?['localData'] != local) return;
      final result = await showRetouchCustomTone(
        context,
        rgb: rgb,
        cards: toneCards,
        onSave: (name, color) =>
            toneCardRequest('toneCards.save', {'name': name, 'rgb': color}),
      );
      if (!current ||
          target != selected ||
          tonePerFace != perFace ||
          data?['localData'] != local) {
        return;
      }
      if (result == null) {
        await cancelTonePreview();
      } else if (result.action == RetouchTonePickerAction.sample) {
        setState(() {
          photoSampling = true;
          sampleSeed = result.rgb;
        });
      } else {
        await previewTone({'toneRgb': result.rgb});
      }
    } catch (failure) {
      if (mounted && current) setState(() => error = '$failure');
    }
  }

  Future<void> sampleTone(Offset at) async {
    final epoch = operationEpoch;
    if (!photoSampling || !canEditTone || data == null) return;
    final local = data!['localData'], target = selected, perFace = tonePerFace;
    setState(() {
      busy = true;
      stopped = false;
    });
    ui.Codec? codec;
    ui.Image? image;
    String? path;
    int? rgb;
    try {
      // The original picker samples one real pixel from the portrait analysis
      // bitmap, before any portrait/body effect, using the displayed coordinates.
      final base = await call('media.retouchChange', {
        'localData': local,
        'action': 'clearPortrait',
      });
      final analysis = await render(base);
      path = analysis['path'] as String;
      codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
      image = (await codec.getNextFrame()).image;
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels == null) throw const AppFailure('照片取色失败，请重试。');
      final x = (at.dx * image.width).floor().clamp(0, image.width - 1);
      final y = (at.dy * image.height).floor().clamp(0, image.height - 1);
      final i = (y * image.width + x) * 4;
      rgb =
          (pixels.getUint8(i) << 16) |
          (pixels.getUint8(i + 1) << 8) |
          pixels.getUint8(i + 2);
    } catch (failure) {
      if (operationCurrent(epoch)) setState(() => error = '$failure');
    } finally {
      image?.dispose();
      codec?.dispose();
      if (path != null && path != frame?['path']) {
        temporary.remove(path);
        await remove(path);
      }
      if (operationCurrent(epoch)) {
        setState(() {
          busy = false;
          photoSampling = false;
        });
      }
    }
    if (rgb != null &&
        operationCurrent(epoch) &&
        data?['localData'] == local &&
        selected == target &&
        tonePerFace == perFace) {
      await customTone(rgb);
    }
  }

  Future<void> deleteToneCard(RetouchToneCard card) async {
    if (busy || !current) return;
    if (!await confirmRetouchDeleteToneCard(context, card: card) || !current) {
      return;
    }
    try {
      await toneCardRequest('toneCards.remove', {'id': card.id});
    } catch (failure) {
      if (mounted && current) setState(() => error = '$failure');
    }
  }

  Future<void> selectTab(int value) async {
    if (busy || !current) return;
    stopped = false;
    await cancelTonePreview();
    if (!current) return;
    setState(() {
      tab = value;
      manual = false;
      photoSampling = false;
    });
    if (value == 1) {
      try {
        await toneCardRequest('toneCards.list');
      } catch (failure) {
        if (mounted && current) setState(() => error = '$failure');
      }
    }
  }

  Future<void> selectFace(int value) async {
    if (busy || !current) return;
    await cancelTonePreview();
    if (current && value >= 0 && value < faces.length) {
      setState(() {
        selected = value;
        photoSampling = false;
        manual = false;
        showOverlay = true;
      });
      unawaited(refreshPortraitOverlay());
    }
  }

  Widget tones(Json source, String action) => Column(
    children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final row in data?['tones'] as List? ?? [])
              RetouchToneCardButton(
                name: object(row)['name'] as String,
                rgb: object(row)['color'] as int,
                original: object(row)['id'] == 0,
                selected: source['toneId'] == object(row)['id'],
                onTap: !canEditTone
                    ? null
                    : () =>
                          unawaited(previewTone({'toneId': object(row)['id']})),
              ),
            if ((data?['tones'] as List? ?? []).any(
              (v) => object(v)['id'] == 1,
            ))
              RetouchToneCardButton(
                name: '自定义',
                rgb: source['toneId'] == 10
                    ? source['toneRgb'] as int
                    : object(
                            (data!['tones'] as List).firstWhere(
                              (v) => object(v)['id'] == 1,
                            ),
                          )['color']
                          as int,
                selected: source['toneId'] == 10,
                onTap: !canEditTone
                    ? null
                    : () => unawaited(
                        customTone(
                          source['toneId'] == 10
                              ? source['toneRgb'] as int
                              : object(
                                      (data!['tones'] as List).firstWhere(
                                        (v) => object(v)['id'] == 1,
                                      ),
                                    )['color']
                                    as int,
                        ),
                      ),
              ),
            for (final card in toneCards)
              RetouchToneCardButton(
                name: card.name,
                rgb: card.rgb,
                selected:
                    source['toneId'] == 10 && source['toneRgb'] == card.rgb,
                onTap: !canEditTone
                    ? null
                    : () => unawaited(previewTone({'toneRgb': card.rgb})),
                onLongPress: busy || !current
                    ? null
                    : () => unawaited(deleteToneCard(card)),
              ),
          ],
        ),
      ),
      _RetouchSlider(
        key: ValueKey('tone-amount-$action-${data?['sha256']}'),
        label: '肤色强度',
        value: ((source['toneAmount'] as num?)?.toDouble() ?? 0) * 100,
        min: 0,
        max: 100,
        enabled: canEditTone,
        onEnd: (value) => tonePreviewStart == null
            ? change(action, {'toneAmount': value / 100})
            : unawaited(previewTone({'toneAmount': value / 100})),
      ),
    ],
  );
  Widget positionTool({required bool patch}) => ExpansionTile(
    title: const Text('精确定位'),
    children: [
      _RetouchSlider(
        label: '位置左右',
        value: targetX * 100,
        min: 0,
        max: 100,
        enabled: !busy,
        onEnd: (value) => setState(() => targetX = value / 100),
      ),
      _RetouchSlider(
        label: '位置上下',
        value: targetY * 100,
        min: 0,
        max: 100,
        enabled: !busy,
        onEnd: (value) => setState(() => targetY = value / 100),
      ),
      FilledButton.tonal(
        onPressed: busy
            ? null
            : () => unawaited(
                perform(
                  patch ? 'media.retouchPatch' : 'media.retouchHeal',
                  patch
                      ? {
                          'points': [targetX, targetY],
                          'radius': radius,
                        }
                      : {'x': targetX, 'y': targetY, 'radius': radius},
                ),
              ),
        child: Text(patch ? '修补此位置' : '修复此位置'),
      ),
    ],
  );
  Widget slider(
    String label,
    String key,
    Json source, {
    double min = 0,
    double max = 100,
    String? action,
  }) {
    final initial = ((source[key] as num?)?.toDouble() ?? 0).clamp(min, max);
    return StatefulBuilder(
      key: ValueKey('$key-${data?['sha256']}-$selected-$bodyTool'),
      builder: (context, update) {
        var value = initial;
        return _RetouchSlider(
          label: label,
          value: value,
          min: min,
          max: max,
          enabled: !busy && current,
          onEnd: (v) => change(
            action ??
                (tab == 0
                    ? 'face'
                    : tab == 1
                    ? 'skin'
                    : 'body'),
            {if (tab == 2) 'tool': bodyTool, key: v.round()},
          ),
        );
      },
    );
  }

  Widget controls() {
    if (widget.patch) {
      return Column(
        children: [
          const Text('涂抹需要移除的小范围，松手后自动寻找附近干净纹理。'),
          _RetouchSlider(
            label: '画笔大小',
            value: radius * 1000,
            min: 5,
            max: 100,
            enabled: !busy,
            onEnd: (v) => setState(() => radius = v / 1000),
          ),
          Text('已创建 ${data?['patchCount'] ?? 0} 个修补'),
          positionTool(patch: true),
          if ((data?['patchCount'] as int? ?? 0) > 0)
            TextButton(
              onPressed: busy
                  ? null
                  : () => unawaited(
                      perform('media.retouchChange', {
                        'action': 'removePatch',
                        'index': (data!['patchCount'] as int) - 1,
                      }),
                    ),
              child: const Text('移除最后一个修补'),
            ),
        ],
      );
    }
    return Column(
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('脸部')),
            ButtonSegment(value: 1, label: Text('皮肤')),
            ButtonSegment(value: 2, label: Text('身体')),
          ],
          selected: {tab},
          onSelectionChanged: busy
              ? null
              : (v) => unawaited(selectTab(v.single)),
        ),
        const SizedBox(height: 10),
        FilledButton.tonal(
          onPressed: busy
              ? null
              : () => unawaited(
                  perform('media.retouchAnalyze', {
                    'mode': ['face', 'skin', 'body'][tab],
                  }),
                ),
          child: Text(['自动选脸与五官分析', '分析皮肤范围', '自动定位身体'][tab]),
        ),
        if (tab == 0) ...[
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < faces.length; i++)
                ChoiceChip(
                  label: Text('人物 ${i + 1}'),
                  selected: selected == i,
                  onSelected: busy ? null : (_) => unawaited(selectFace(i)),
                ),
              FilterChip(
                label: const Text('手动添加人脸'),
                selected: manual,
                onSelected: busy
                    ? null
                    : (v) => setState(() {
                        manual = v;
                        if (v) healMode = false;
                      }),
              ),
              FilterChip(
                label: const Text('点按祛痘'),
                selected: healMode,
                onSelected: busy
                    ? null
                    : (value) => setState(() {
                        healMode = value;
                        manual = false;
                      }),
              ),
            ],
          ),
          if (faces.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('自动分析无人脸时，可点击“手动添加人脸”后在照片上点选脸部。'),
            ),
          if (manual)
            TextButton(
              onPressed: busy
                  ? null
                  : () => change('manualFace', {'cx': .5, 'cy': .4}),
              child: const Text('在中心添加人脸后调整范围'),
            ),
          if (faces.isNotEmpty) ...[
            ExpansionTile(
              title: const Text('调整脸部范围'),
              children: [
                for (final entry in [
                  ('中心左右', 'cx', 0.0, 100.0),
                  ('中心上下', 'cy', 0.0, 100.0),
                  ('脸部宽度', 'rx', 1.0, 50.0),
                  ('脸部高度', 'ry', 1.0, 50.0),
                ])
                  _RetouchSlider(
                    key: ValueKey('${data?['sha256']}-${entry.$2}-$selected'),
                    label: entry.$1,
                    value: (chosen[entry.$2] as num).toDouble() * 100,
                    min: entry.$3,
                    max: entry.$4,
                    enabled: !busy,
                    onEnd: (value) => change('face', {entry.$2: value / 100}),
                  ),
              ],
            ),
            slider('提亮', 'brightness', chosen, min: -100),
            slider('磨皮', 'smoothing', chosen),
            slider('纹理保留', 'texture', chosen),
            slider('肤色冷暖', 'warmth', chosen, min: -100),
            slider('红润', 'redness', chosen, min: -100),
            slider('柔光补光', 'FILL', chosen),
            slider('面部光影', 'light', chosen, min: -100),
            slider('阴影提亮', 'shadows', chosen),
            slider('眼下修复', 'UNDER_EYE', chosen),
            if (chosen['hasLandmarks'] == true) ...[
              slider('眼神清晰', 'EYE_DETAIL', chosen),
              slider('眼白净化', 'EYE_WHITE', chosen),
              slider('牙齿去黄', 'TEETH', chosen),
            ],
            slider('光源左右', 'LIGHT_X', chosen, min: -100),
            slider('光源上下', 'LIGHT_Y', chosen, min: -100),
            slider('自然精修', 'NATURAL', chosen),
            TextButton(
              onPressed: busy ? null : () => change('removeFace', {}),
              child: const Text('移除所选人脸'),
            ),
          ],
          if (healMode)
            _RetouchSlider(
              label: '祛痘半径',
              value: radius * 1000,
              min: 2,
              max: 100,
              enabled: !busy,
              onEnd: (value) => setState(() => radius = value / 1000),
            ),
          if (healMode) positionTool(patch: false),
        ],
        if (tab == 1) ...[
          Text(
            portrait['hasSkinMask'] == true
                ? ((portrait['skinPixels'] as int? ?? 0) >= 32
                      ? '皮肤范围已分析'
                      : '未找到可确认的皮肤范围，可重试或使用局部画笔。')
                : '先分析皮肤范围，再调节效果。',
          ),
          if (data?['analysisEngine'] == 'Vision')
            const Text('此设备以人物分割和脸部取样肤色范围选择皮肤。'),
          if (portrait['hasSkinMask'] == true &&
              (portrait['skinPixels'] as int? ?? 0) >= 32) ...[
            slider('全身磨皮', 'smoothing', skin),
            slider('匀肤', 'EVENNESS', skin),
            slider('去油光', 'SHINE', skin),
            slider('纹理保留', 'TEXTURE', skin),
          ],
          if (tonePerFace == true) ...[
            const Text('逐人肤色调节（高级）'),
            if (faces.isEmpty) const Text('请先自动选脸或手动选择人脸。'),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < faces.length; i++)
                  ChoiceChip(
                    label: Text('人物 ${i + 1}'),
                    selected: selected == i,
                    onSelected: busy ? null : (_) => unawaited(selectFace(i)),
                  ),
              ],
            ),
          ],
          tones(editedTone, toneAction),
        ],
        if (tab == 2) ...[
          if (people.length > 1)
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < people.length; i++)
                  ChoiceChip(
                    label: Text('人物 ${i + 1}'),
                    selected: bodyPerson == i,
                    onSelected: busy
                        ? null
                        : (_) => unawaited(
                            perform('media.retouchAnalyze', {
                              'mode': 'body',
                              'person': i,
                            }),
                          ),
                  ),
              ],
            ),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('瘦身')),
              ButtonSegment(value: 1, label: Text('瘦腿')),
              ButtonSegment(value: 2, label: Text('拉长')),
            ],
            selected: {bodyTool},
            onSelectionChanged: busy
                ? null
                : (v) => setState(() => bodyTool = v.single),
          ),
          slider('强度', 'amount', area),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('单腿模式'),
            value: portrait['singleLeg'] == true,
            onChanged: busy
                ? null
                : (value) =>
                      change('body', {'tool': bodyTool, 'singleLeg': value}),
          ),
          for (final entry in [
            ('左边界', 'left'),
            ('上边界', 'top'),
            ('右边界', 'right'),
            ('下边界', 'bottom'),
          ])
            _RetouchSlider(
              key: ValueKey('${data?['sha256']}-$bodyTool-${entry.$2}'),
              label: entry.$1,
              value: ((area[entry.$2] as num?)?.toDouble() ?? .5) * 100,
              min: 0,
              max: entry.$2 == 'bottom' ? 96 : 100,
              enabled: !busy,
              onEnd: (v) =>
                  change('body', {'tool': bodyTool, entry.$2: v / 100}),
            ),
          if (portrait['hasBodyMask'] == true)
            slider('背景保护', 'protection', portrait, action: 'body'),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => widget.patch
      ? originalPatchLayout(context)
      : originalPortraitLayout(context);
  @override
  void dispose() {
    invalidateBlemishReview();
    clearPortraitOverlay();
    viewport.dispose();
    brushEditing.dispose();
    widget.state.removeListener(accountChanged);
    unawaited(stop());
    for (final path in temporary) {
      unawaited(remove(path));
    }
    super.dispose();
  }
}

class _RetouchSlider extends StatefulWidget {
  const _RetouchSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onEnd,
  });
  final String label;
  final double value, min, max;
  final bool enabled;
  final ValueChanged<double> onEnd;
  @override
  State<_RetouchSlider> createState() => _RetouchSliderState();
}

class _RetouchSliderState extends State<_RetouchSlider> {
  double? pending;
  @override
  void didUpdateWidget(_RetouchSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) pending = null;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(widget.label)),
          Text('${(pending ?? widget.value).round()}'),
        ],
      ),
      Slider(
        semanticFormatterCallback: (value) =>
            '${widget.label} ${value.round()}',
        value: (pending ?? widget.value).clamp(widget.min, widget.max),
        min: widget.min,
        max: widget.max,
        divisions: (widget.max - widget.min).round(),
        onChanged: widget.enabled ? (v) => setState(() => pending = v) : null,
        onChangeEnd: widget.enabled ? widget.onEnd : null,
      ),
    ],
  );
}

class _RetouchOverlay extends CustomPainter {
  _RetouchOverlay({
    required this.faces,
    required this.selected,
    required this.points,
    required this.radius,
    this.body,
    this.originalPortrait = false,
    this.addingFace = false,
    this.erasing = false,
    this.bodyTool = 0,
    this.singleLeg = false,
    this.heals = const [],
  });
  final List<Json> faces;
  final int selected, bodyTool;
  final List<Offset> points;
  final double radius;
  final Json? body;
  final bool originalPortrait, addingFace, erasing, singleLeg;
  final List<Json> heals;
  void dashed(Canvas canvas, Path path, Paint pen) {
    for (final metric in path.computeMetrics()) {
      for (double at = 0; at < metric.length; at += 10) {
        canvas.drawPath(
          metric.extractPath(at, math.min(at + 5, metric.length)),
          pen,
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xffffe335);
    // Human selection uses the original native mask.weight overlay, not face ellipses.
    if (!originalPortrait) {
      for (var i = 0; i < faces.length; i++) {
        final f = faces[i];
        pen.color = i == selected ? const Color(0xffffe335) : Colors.white54;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(
              (f['cx'] as num) * size.width,
              (f['cy'] as num) * size.height,
            ),
            width: (f['rx'] as num) * size.width * 2,
            height: (f['ry'] as num) * size.height * 2,
          ),
          pen,
        );
      }
    }
    if (body != null && body!.isNotEmpty) {
      final box = Rect.fromLTRB(
        (body!['left'] as num) * size.width,
        (body!['top'] as num) * size.height,
        (body!['right'] as num) * size.width,
        (body!['bottom'] as num) * size.height,
      );
      if (originalPortrait) {
        pen
          ..color = const Color(0xaafff1e4)
          ..strokeWidth = 1;
        dashed(
          canvas,
          Path()
            ..addRRect(RRect.fromRectAndRadius(box, const Radius.circular(3))),
          pen,
        );
        if (bodyTool == 1 && !singleLeg) {
          dashed(
            canvas,
            Path()
              ..moveTo(box.center.dx, box.top)
              ..lineTo(box.center.dx, box.bottom),
            pen,
          );
        }
        pen
          ..color = const Color(0xffffe335)
          ..strokeWidth = 2;
        for (var i = 0; i < 4; i++) {
          final x = i.isEven ? box.left : box.right,
              y = i < 2 ? box.top : box.bottom;
          canvas.drawLine(
            Offset(x, y),
            Offset(x + (i.isEven ? 12 : -12), y),
            pen,
          );
          canvas.drawLine(Offset(x, y), Offset(x, y + (i < 2 ? 12 : -12)), pen);
        }
        canvas.drawLine(
          Offset(box.center.dx - 10, box.top),
          Offset(box.center.dx + 10, box.top),
          pen,
        );
        canvas.drawLine(
          Offset(box.center.dx - 10, box.bottom),
          Offset(box.center.dx + 10, box.bottom),
          pen,
        );
      } else {
        canvas.drawRect(box, pen);
      }
    }
    pen
      ..color = const Color(0xffffe335)
      ..strokeWidth = 1;
    for (final h in heals) {
      canvas.drawCircle(
        Offset((h['tx'] as num) * size.width, (h['ty'] as num) * size.height),
        ((h['radius'] as num?)?.toDouble() ?? radius) *
            math.min(size.width, size.height),
        pen,
      );
    }
    if (addingFace && originalPortrait) return;
    pen
      ..color = originalPortrait
          ? (erasing ? const Color(0xaaff9b8f) : const Color(0x66fff1e4))
          : const Color(0x88ffe335)
      ..strokeWidth = radius * math.min(size.width, size.height) * 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (points.isNotEmpty) {
      final path = Path()
        ..moveTo(points.first.dx * size.width, points.first.dy * size.height);
      for (final at in points.skip(1)) {
        path.lineTo(at.dx * size.width, at.dy * size.height);
      }
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(covariant _RetouchOverlay oldDelegate) => true;
}
