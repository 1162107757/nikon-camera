part of 'retouch_workspace.dart';

// Layout, labels and dimensions follow PhotoPortraitDialog / PhotoWorkspaceUi.
extension _OriginalPortraitWorkspace on _RetouchWorkspaceState {
  String get currentOverlayKey =>
      '${data?['localData']}|$selected|${tab == 1 && (skinParameter != 'tone' || tonePerFace != true)}|${widget.regionId ?? ''}';
  void clearPortraitOverlay() {
    portraitOverlayRevision++;
    if (portraitOverlayJob != null) {
      unawaited(widget.state.core.cancel(portraitOverlayJob!));
    }
    portraitOverlayJob = null;
    final old = portraitOverlay;
    portraitOverlay = null;
    portraitOverlayKey = null;
    old?.dispose();
  }

  Future<void> refreshPortraitOverlay() async {
    if (!current ||
        widget.patch ||
        !showOverlay ||
        tab == 2 ||
        photoSampling ||
        comparing ||
        data == null) {
      clearPortraitOverlay();
      return;
    }
    final key = currentOverlayKey;
    if (portraitOverlayKey == key && portraitOverlay != null) return;
    clearPortraitOverlay();
    final token = portraitOverlayRevision;
    final id =
        'retouch-overlay-$token-${DateTime.now().microsecondsSinceEpoch}';
    portraitOverlayJob = id;
    ui.Image? image;
    try {
      final response = await widget.state.core.call('media.retouchAnalyze', {
        'path': widget.photo.path,
        'owner': widget.owner,
        'localData': data!['localData'],
        if (widget.regionId?.isNotEmpty == true) 'regionId': widget.regionId,
        if (tonePerFace != null) 'tonePerFace': tonePerFace,
        'mode': 'overlay',
        'index': faces.isEmpty ? -1 : selected,
        'global': tab == 1 && (skinParameter != 'tone' || tonePerFace != true),
      }, id);
      if (!current ||
          token != portraitOverlayRevision ||
          key != currentOverlayKey) {
        return;
      }
      if ((response['regionId'] as String? ?? '') != (widget.regionId ?? '')) {
        throw const AppFailure('选区范围已变化。');
      }
      final raw = response['selectionOverlay'];
      if (raw == null) return;
      final rgba = object(raw),
          w = rgba['width'] as int,
          h = rgba['height'] as int;
      if (w < 1 || h < 1 || w > 240 || h > 320) {
        throw const AppFailure('选区显示大小无效。');
      }
      final bytes = base64Decode(rgba['rgba'] as String);
      if (bytes.length != w * h * 4) throw const AppFailure('选区显示数据无效。');
      final ready = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        bytes,
        w,
        h,
        ui.PixelFormat.rgba8888,
        ready.complete,
      );
      image = await ready.future;
      if (!current ||
          token != portraitOverlayRevision ||
          key != currentOverlayKey) {
        image.dispose();
        return;
      }
      refreshPortrait(() {
        portraitOverlay = image;
        portraitOverlayKey = key;
      });
      image = null;
    } catch (_) {
      image?.dispose();
    } finally {
      if (portraitOverlayJob == id) portraitOverlayJob = null;
    }
  }

  void beginBrushSizing() {
    if (busy || !current) return;
    brushEditing.value = false;
    comparing = compareWanted = false;
    cancelOriginalPhotoGesture();
    originalGestureLocal = null;
    refreshPortrait(() => brushRadiusStart = radius);
  }

  void updateBrushSizing(double value) {
    if (!current || brushRadiusStart == null) return;
    refreshPortrait(() => radius = value / 1000);
  }

  void endBrushSizing(double value) {
    if (!current || brushRadiusStart == null) return;
    refreshPortrait(() {
      radius = value / 1000;
      brushRadiusStart = null;
    });
    brushEditing.value = !comparing && !compareWanted;
  }

  void cancelBrushSizing() {
    if (brushRadiusStart == null) return;
    refreshPortrait(() {
      radius = brushRadiusStart!;
      brushRadiusStart = null;
      brushSizeGeneration++;
    });
    brushEditing.value = !comparing && !compareWanted;
  }

  Widget originalBrushSlider({bool patch = false}) {
    final epoch = operationEpoch;
    return RetouchOriginalSlider(
      key: ValueKey(
        '${patch ? 'repair-size' : 'portrait-size'}-$brushSizeGeneration',
      ),
      label: patch ? '画笔大小' : '大小',
      labelWidth: patch ? 80 : 44,
      value: radius * 1000,
      min: patch ? 5 : 2,
      max: patch ? 100 : 120,
      formatValue: (v) => '${(v / 10).toStringAsFixed(1)}%',
      onChangeStart: (_) {
        if (operationCurrent(epoch)) beginBrushSizing();
      },
      onChanged: busy || !current
          ? null
          : (v) {
              if (operationCurrent(epoch)) updateBrushSizing(v);
            },
      onChangeEnd: (v) {
        if (operationCurrent(epoch)) endBrushSizing(v);
      },
      onChangeCancel: () {
        if (operationCurrent(epoch)) cancelBrushSizing();
      },
    );
  }

  Widget brushPreview({bool patch = false}) {
    final shown = comparing && comparisonFrame != null
        ? comparisonFrame
        : frame;
    return RetouchBrushPreview(
      imageWidth: (shown?['width'] as num?)?.toDouble() ?? 1,
      imageHeight: (shown?['height'] as num?)?.toDouble() ?? 1,
      controller: viewport,
      radius: radius,
      center: brushPreviewCenter,
      keepVisible: true,
      visible: brushRadiusStart != null && !busy && !comparing,
      reserveBars: !patch && tab == 2 && !choosingGroup,
    );
  }

  Future<void> openOriginalPatch() async {
    if (brushRadiusStart != null) cancelBrushSizing();
    if (widget.patch ||
        widget.regionId?.isNotEmpty == true ||
        busy ||
        !current ||
        data == null ||
        patchChildOpen) {
      return;
    }
    await cancelTonePreview();
    if (!mounted || !current || data == null) return;
    final epoch = operationEpoch,
        staged = data!,
        fingerprint = data!['localData'];
    bool valid() =>
        operationCurrent(epoch) && data?['localData'] == fingerprint;
    patchChildOpen = true;
    try {
      final result = await hueRootPage<Json>(
        context,
        MaterialPageRoute(
          builder: (_) => RetouchWorkspace(
            state: widget.state,
            photo: widget.photo,
            owner: widget.owner,
            recipe: {...widget.recipe, 'localData': fingerprint},
            isCurrent: valid,
            patch: true,
          ),
        ),
      );
      if (result == null || !valid() || result['localData'] == fingerprint) {
        return;
      }
      refreshPortrait(() {
        busy = true;
        stopped = false;
        error = null;
      });
      final next = await call('media.retouchDescribe', {
        'localData': result['localData'],
      });
      final image = await render(next);
      if (valid()) {
        refreshPortrait(() {
          undo.add(staged);
          if (undo.length > 32) undo.removeAt(0);
          redo.clear();
          data = next;
          frame = image;
        });
      }
    } catch (failure) {
      if (operationCurrent(epoch)) refreshPortrait(() => error = '$failure');
    } finally {
      if (operationCurrent(epoch)) {
        patchChildOpen = false;
        refreshPortrait(() => busy = false);
      }
    }
    unawaited(refreshPortraitOverlay());
  }

  bool beginPatchStroke(Offset at, Size renderedSize) {
    if (busy ||
        !current ||
        data == null ||
        brushRadiusStart != null ||
        comparing) {
      return false;
    }
    originalGestureLocal = data!['localData'] as String;
    originalGestureRadius = radius;
    refreshPortrait(() {
      points
        ..clear()
        ..add(at);
      brushPreviewCenter = at;
    });
    return true;
  }

  void updatePatchStroke(Offset at) {
    if (!current ||
        data?['localData'] != originalGestureLocal ||
        brushRadiusStart != null) {
      return;
    }
    if (points.length < 512 &&
        (points.isEmpty || (at - points.last).distance > .001)) {
      refreshPortrait(() {
        points.add(at);
        brushPreviewCenter = at;
      });
    }
  }

  Future<void> endPatchStroke() async {
    final stroke = List<Offset>.of(points),
        size = originalGestureRadius,
        local = originalGestureLocal;
    cancelOriginalPhotoGesture();
    originalGestureLocal = null;
    if (stroke.isEmpty ||
        !current ||
        busy ||
        data?['localData'] != local ||
        brushRadiusStart != null) {
      return;
    }
    await perform('media.retouchPatch', {
      'points': stroke.expand((p) => [p.dx, p.dy]).toList(),
      'radius': size,
    });
  }

  void cancelPatchStroke() {
    cancelOriginalPhotoGesture();
    originalGestureLocal = null;
  }

  Widget originalPatchPhoto() {
    final shown = comparing ? patchEntryFrame : frame;
    return Stack(
      fit: StackFit.expand,
      children: [
        RetouchOriginalPhotoStage(
          imageWidth: (shown?['width'] as num?)?.toDouble() ?? 1,
          imageHeight: (shown?['height'] as num?)?.toDouble() ?? 1,
          controller: viewport,
          editingEnabled: photoEditingEnabled,
          editingSignal: brushEditing,
          drawing: !busy && current && !comparing && brushRadiusStart == null,
          onStart: beginPatchStroke,
          onUpdate: updatePatchStroke,
          onEnd: () => unawaited(endPatchStroke()),
          onCancel: cancelPatchStroke,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (shown != null)
                Image.file(
                  File(shown['path'] as String),
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  semanticLabel: '修补照片：${widget.photo.name}',
                ),
              if (!comparing)
                IgnorePointer(
                  child: CustomPaint(
                    painter: _RetouchOverlay(
                      faces: const [],
                      selected: -1,
                      points: points.toList(),
                      radius: originalGestureRadius,
                      originalPortrait: true,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Positioned.fill(child: brushPreview(patch: true)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 48,
          child: Row(
            children: [
              RetouchOriginalUtilityButton(
                icon: 'undo',
                semanticLabel: '撤销修补',
                onPressed: busy || undo.isEmpty
                    ? null
                    : () {
                        cancelPatchStroke();
                        unawaited(history(false));
                      },
              ),
              RetouchOriginalUtilityButton(
                icon: 'redo',
                semanticLabel: '重做修补',
                onPressed: busy || redo.isEmpty
                    ? null
                    : () {
                        cancelPatchStroke();
                        unawaited(history(true));
                      },
              ),
              const Spacer(),
              RetouchOriginalUtilityButton(
                icon: 'fit',
                semanticLabel: '适应照片',
                onPressed: busy
                    ? null
                    : () {
                        cancelPatchStroke();
                        cancelBrushSizing();
                        viewport.value = Matrix4.identity();
                      },
              ),
              RetouchOriginalUtilityButton(
                icon: 'compare',
                semanticLabel: '按住对比进入修补前的照片',
                selected: comparing,
                onCompare: (v) {
                  if (current && (!v || !busy)) {
                    cancelBrushSizing();
                    cancelPatchStroke();
                    compareWanted = v;
                    brushEditing.value = !v && brushRadiusStart == null;
                    refreshPortrait(() => comparing = v);
                  }
                },
              ),
            ],
          ),
        ),
        if (error != null || busy)
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: RetouchOriginalStatus(error ?? '正在修补…'),
          ),
      ],
    );
  }

  Widget originalPatchLayout(BuildContext context) => Theme(
    data: hueviaTheme(Brightness.dark, home: false),
    child: PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) cancelWorkspace(pop: false);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          PhotoAtmosphere(image: atmosphere),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              toolbarHeight: 52,
              leadingWidth: 52,
              backgroundColor: Colors.transparent,
              foregroundColor: retouchOriginalText,
              title: Text(
                '修补${data?['sourcePositioning'] == true ? ' · 塑形前定位' : ''}',
                style: const TextStyle(fontSize: 16),
              ),
              centerTitle: true,
              leading: IconButton(
                tooltip: '取消修补',
                onPressed: exitRequested ? null : cancelWorkspace,
                icon: const RetouchOriginalGlyph('close'),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
                  child: SizedBox(
                    width: 64,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: retouchOriginalAccent,
                        foregroundColor: const Color(0xff211812),
                        textStyle: const TextStyle(fontSize: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed:
                          busy ||
                              !current ||
                              data == null ||
                              brushRadiusStart != null ||
                              points.isNotEmpty
                          ? null
                          : () => Navigator.pop(context, data),
                      child: const Text('应用'),
                    ),
                  ),
                ),
              ],
            ),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final dock = RetouchOriginalDock(
                    choosingGroup: false,
                    entries: const [],
                    controls: [
                      const SizedBox(
                        height: 48,
                        child: Center(
                          child: Text(
                            '涂抹需要移除的小范围，松手后自动寻找附近干净纹理。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: retouchOriginalMuted,
                            ),
                          ),
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
                    ],
                  );
                  final side =
                      bounds.maxWidth > bounds.maxHeight &&
                      bounds.maxWidth >= 480;
                  return side
                      ? Row(
                          children: [
                            Expanded(child: originalPatchPhoto()),
                            SizedBox(
                              width: math.min(320, bounds.maxWidth * .44),
                              child: dock,
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(child: originalPatchPhoto()),
                            SizedBox(
                              height: math.min(180, bounds.maxHeight / 2),
                              child: dock,
                            ),
                          ],
                        );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget originalPhoto() {
    final shown = comparing && comparisonFrame != null
        ? comparisonFrame
        : frame;
    return RetouchOriginalPhotoStage(
      imageWidth: (shown?['width'] as num?)?.toDouble() ?? 1,
      imageHeight: (shown?['height'] as num?)?.toDouble() ?? 1,
      controller: viewport,
      editingEnabled: photoEditingEnabled,
      editingSignal: brushEditing,
      reserveBars: tab == 2 && !choosingGroup,
      singleFingerPan: tab == 2 && !choosingGroup,
      navigationEnabled: !photoSampling,
      drawing:
          brushRadiusStart == null &&
          !busy &&
          !choosingGroup &&
          (manual ||
              (tab == 0 && faceMode == 1 && selectionBrush > 0) ||
              (tab == 2 && showOverlay)),
      tapSlop: photoSampling
          ? 24
          : healMode
          ? 20
          : double.infinity,
      onStart: beginOriginalPhotoGesture,
      onUpdate: updateOriginalPhotoGesture,
      onEnd: () => unawaited(endOriginalPhotoGesture()),
      onCancel: cancelOriginalPhotoGesture,
      onTap: tapOriginalPhoto,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (shown != null)
            Image.file(
              File(shown['path'] as String),
              fit: BoxFit.fill,
              gaplessPlayback: true,
              semanticLabel: comparing
                  ? '处理前照片：${widget.photo.name}'
                  : '待编辑照片：${widget.photo.name}',
            ),
          if (portraitOverlay != null &&
              portraitOverlayKey == currentOverlayKey &&
              showOverlay &&
              !busy &&
              !comparing &&
              !photoSampling &&
              points.isEmpty &&
              lightStart == null &&
              scalarStart == null)
            IgnorePointer(
              child: RawImage(
                image: portraitOverlay,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.low,
              ),
            ),
          IgnorePointer(
            child: CustomPaint(
              painter: _RetouchOverlay(
                faces:
                    showOverlay &&
                        !comparing &&
                        !photoSampling &&
                        !choosingGroup &&
                        (tab == 0 || tonePerFace == true)
                    ? faces
                    : [],
                selected: selected,
                points: points.toList(),
                radius: radius,
                body: tab == 2 && showOverlay && !comparing
                    ? bodyGestureDraft ?? area
                    : null,
                originalPortrait: true,
                addingFace: manual,
                erasing: selectionBrush == 2,
                bodyTool: bodyTool,
                singleLeg: portrait['singleLeg'] == true,
                heals: healMode && showOverlay && !comparing && !photoSampling
                    ? (portrait['heals'] as List? ?? []).map(object).toList()
                    : [],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool beginOriginalPhotoGesture(Offset at, Size renderedSize) {
    if (busy ||
        !current ||
        data == null ||
        comparing ||
        choosingGroup ||
        brushRadiusStart != null) {
      return false;
    }
    originalGestureDown = at;
    brushPreviewCenter = at;
    originalGestureLocal = data!['localData'] as String;
    originalGestureFace = selected;
    originalGestureTool = bodyTool;
    originalGestureRadius = radius;
    if (manual || (tab == 0 && faceMode == 1 && selectionBrush > 0)) {
      refreshPortrait(() {
        points.clear();
        points.add(at);
      });
      return true;
    }
    if (tab == 2 && showOverlay && area['left'] is num) {
      final a = area;
      final l = (a['left'] as num).toDouble(),
          r = (a['right'] as num).toDouble(),
          t = (a['top'] as num).toDouble(),
          b = (a['bottom'] as num).toDouble();
      final xs = [l, r, l, r, (l + r) / 2, (l + r) / 2, l, r],
          ys = [t, t, b, b, t, b, (t + b) / 2, (t + b) / 2];
      var distance = 24.0;
      bodyHandle = -1;
      for (var i = 0; i < 8; i++) {
        final d = math.sqrt(
          math.pow((at.dx - xs[i]) * renderedSize.width, 2) +
              math.pow((at.dy - ys[i]) * renderedSize.height, 2),
        );
        if (d < distance) {
          bodyHandle = i;
          distance = d;
        }
      }
      if (bodyHandle < 0 && Rect.fromLTRB(l, t, r, b).contains(at)) {
        bodyHandle = 8;
      }
      if (bodyHandle >= 0) {
        bodyGestureArea = Map.of(a);
        bodyGestureDraft = Map.of(a);
        beginOriginalScalar('body-drag-$originalGestureTool');
        return true;
      }
    }
    return false;
  }

  void updateOriginalPhotoGesture(Offset at) {
    if (!current ||
        brushRadiusStart != null ||
        (data?['localData'] != originalGestureLocal &&
            scalarKey != 'body-drag-$originalGestureTool')) {
      return;
    }
    if (bodyGestureArea != null && originalGestureDown != null) {
      final a = bodyGestureArea!, maxB = originalGestureTool == 2 ? .97 : 1.0;
      var l = (a['left'] as num).toDouble(),
          r = (a['right'] as num).toDouble(),
          t = (a['top'] as num).toDouble(),
          b = (a['bottom'] as num).toDouble();
      var dx = at.dx - originalGestureDown!.dx,
          dy = at.dy - originalGestureDown!.dy;
      if (bodyHandle == 8) {
        dx = dx.clamp(-l, 1 - r);
        dy = dy.clamp(-t, maxB - b);
        l += dx;
        r += dx;
        t += dy;
        b += dy;
      } else {
        if ([0, 2, 6].contains(bodyHandle)) l = (l + dx).clamp(0, r - .08);
        if ([1, 3, 7].contains(bodyHandle)) r = (r + dx).clamp(l + .08, 1);
        if ([0, 1, 4].contains(bodyHandle)) t = (t + dy).clamp(0, b - .10);
        if ([2, 3, 5].contains(bodyHandle)) b = (b + dy).clamp(t + .10, maxB);
      }
      refreshPortrait(
        () => bodyGestureDraft = {
          ...a,
          'left': l,
          'top': t,
          'right': r,
          'bottom': b,
        },
      );
      updateOriginalScalar('body-drag-$originalGestureTool', {
        'action': 'body',
        'value': {...bodyGestureDraft!, 'tool': originalGestureTool},
      });
    } else if (points.length < 512 &&
        (points.isEmpty || (at - points.last).distance > .001)) {
      refreshPortrait(() {
        points.add(at);
        brushPreviewCenter = at;
      });
    }
  }

  void cancelOriginalPhotoGesture({bool rollback = true}) {
    if (rollback && scalarKey == 'body-drag-$originalGestureTool') {
      endOriginalScalar(cancel: true);
    }
    if (mounted) {
      refreshPortrait(() {
        points.clear();
        bodyGestureArea = null;
        bodyGestureDraft = null;
        originalGestureDown = null;
      });
    }
  }

  Future<void> endOriginalPhotoGesture() async {
    if (!current ||
        brushRadiusStart != null ||
        (data?['localData'] != originalGestureLocal &&
            scalarKey != 'body-drag-$originalGestureTool')) {
      cancelOriginalPhotoGesture();
      return;
    }
    final path = List<Offset>.of(points), body = bodyGestureDraft;
    final adding = manual;
    cancelOriginalPhotoGesture(rollback: false);
    if (body != null) {
      updateOriginalScalar('body-drag-$originalGestureTool', {
        'action': 'body',
        'value': {...body, 'tool': originalGestureTool},
      });
      endOriginalScalar();
      return;
    }
    if (adding && path.isNotEmpty) {
      final start = path.first, end = path.last;
      var cx = (start.dx + end.dx) / 2,
          cy = (start.dy + end.dy) / 2,
          rx = (start.dx - end.dx).abs() / 2,
          ry = (start.dy - end.dy).abs() / 2;
      if (rx < .008 || ry < .008) {
        cx = end.dx;
        cy = end.dy;
        rx = .12;
        ry = .17;
      }
      await perform('media.retouchChange', {
        'action': 'manualFace',
        'value': {'cx': cx, 'cy': cy, 'rx': rx, 'ry': ry},
      });
    } else if (path.isNotEmpty &&
        selected == originalGestureFace &&
        faceMode == 1 &&
        selectionBrush > 0) {
      await perform('media.retouchChange', {
        'action': 'faceStroke',
        'index': originalGestureFace,
        'value': {
          'points': path.expand((p) => [p.dx, p.dy]).toList(),
          'radius': originalGestureRadius,
          'erase': selectionBrush == 2,
        },
      });
    }
  }

  void tapOriginalPhoto(Offset at) {
    if (busy ||
        !current ||
        data == null ||
        comparing ||
        compareWanted ||
        brushRadiusStart != null) {
      return;
    }
    if (photoSampling) {
      unawaited(sampleTone(at));
      return;
    }
    if (choosingGroup) return;
    if (manual) {
      unawaited(
        perform('media.retouchChange', {
          'action': 'manualFace',
          'value': {'cx': at.dx, 'cy': at.dy, 'rx': .12, 'ry': .17},
        }),
      );
      return;
    }
    if (healMode && tab == 0) {
      brushPreviewCenter = at;
      unawaited(
        perform('media.retouchHeal', {
          'x': at.dx,
          'y': at.dy,
          'radius': radius,
        }),
      );
      return;
    }
    if (tab == 2 ||
        (tab == 1 && (tonePerFace != true || skinParameter != 'tone'))) {
      return;
    }
    final local = data!['localData'],
        face = selected,
        revision = ++faceHitRevision;
    unawaited(() async {
      try {
        final response = await call('media.retouchAnalyze', {
          'localData': local,
          'mode': 'hitFace',
          'x': at.dx,
          'y': at.dy,
        });
        if (!current ||
            busy ||
            data?['localData'] != local ||
            revision != faceHitRevision ||
            selected != face) {
          return;
        }
        final hit = response['hitFace'] as int? ?? -1;
        if (hit >= 0 && hit < faces.length) await selectFace(hit);
      } catch (failure) {
        if (current) refreshPortrait(() => error = '$failure');
      }
    }());
  }

  void beginOriginalLight() {
    if (busy || !current || chosen['enabled'] == false || data == null) return;
    lightStart = data;
    lightTarget = selected;
    lightEnded = lightCancelled = false;
  }

  void updateOriginalLight(Offset value) {
    if (!current || lightStart == null || selected != lightTarget) return;
    lightPending = value;
    if (!lightRunning) unawaited(drainOriginalLight());
  }

  Future<void> drainOriginalLight() async {
    final epoch = operationEpoch;
    if (lightRunning) return;
    lightRunning = true;
    try {
      while (lightPending != null &&
          operationCurrent(epoch) &&
          !lightCancelled &&
          selected == lightTarget) {
        final value = lightPending!;
        lightPending = null;
        await perform('media.retouchChange', {
          'action': 'face',
          'index': lightTarget,
          'value': {'LIGHT_X': value.dx.round(), 'LIGHT_Y': value.dy.round()},
        }, remember: false);
        if (!operationCurrent(epoch)) break;
        if (error != null) {
          lightCancelled = true;
          lightPending = null;
        }
      }
    } finally {
      if (operationCurrent(epoch)) {
        lightRunning = false;
        if (lightEnded || lightCancelled) await completeOriginalLight();
      }
    }
  }

  void endOriginalLight({bool cancel = false}) {
    lightEnded = true;
    lightCancelled = cancel;
    if (cancel) lightPending = null;
    if (!lightRunning) unawaited(completeOriginalLight());
  }

  Future<void> completeOriginalLight() async {
    final epoch = operationEpoch;
    final before = lightStart;
    lightStart = null;
    lightPending = null;
    if (before == null || !operationCurrent(epoch)) return;
    if (lightCancelled) {
      refreshPortrait(() {
        busy = true;
        stopped = false;
      });
      try {
        final image = await render(before);
        if (operationCurrent(epoch)) {
          refreshPortrait(() {
            data = before;
            frame = image;
          });
        }
      } catch (failure) {
        if (operationCurrent(epoch)) refreshPortrait(() => error = '$failure');
      } finally {
        if (operationCurrent(epoch)) refreshPortrait(() => busy = false);
      }
    } else if (before['localData'] != data?['localData']) {
      refreshPortrait(() {
        undo.add(before);
        if (undo.length > 32) undo.removeAt(0);
        redo.clear();
      });
    }
    unawaited(refreshPortraitOverlay());
  }

  Future<void> loadPortraitAtmosphere(String source) async {
    if (!current || atmosphere != null) return;
    try {
      final result = await widget.state.core.call('media.atmosphere', {
        'path': source,
        'owner': widget.owner,
      });
      final path = result['path'] as String;
      temporary.add(path);
      if (!current) {
        await remove(path);
        return;
      }
      refreshPortrait(() => atmosphere = path);
    } catch (_) {
      // The original sampled background is decorative; editing remains usable.
    }
  }

  Future<void> paintOriginalPortrait() async {
    if (brushRadiusStart != null) cancelBrushSizing();
    final epoch = operationEpoch;
    if (busy || !operationCurrent(epoch) || data == null) return;
    await cancelTonePreview();
    if (!mounted || !operationCurrent(epoch)) return;
    final staged = data!, fingerprint = data!['localData'];
    bool valid() =>
        operationCurrent(epoch) && data?['localData'] == fingerprint;
    String? owned;
    refreshPortrait(() {
      busy = true;
      stopped = false;
    });
    try {
      final base = await call('local.describe', {'localData': fingerprint});
      Json region;
      if (widget.regionId?.isNotEmpty == true) {
        final matches = (base['regions'] as List? ?? [])
            .map(object)
            .where((r) => r['id'] == widget.regionId)
            .toList();
        if (matches.length != 1) throw const AppFailure('当前局部区域已变化，请重新打开。');
        region = matches.single;
      } else {
        region = object(
          (await call('local.seedRegion', {'localData': fingerprint}))['seed'],
        );
      }
      final before = await call('media.retouchChange', {
        'localData': fingerprint,
        'action': 'beforeBody',
      });
      final paintRecipe = {
        ...widget.recipe,
        'localData': before['localData'],
        'geometry': <String, dynamic>{},
        'border': <String, dynamic>{},
      };
      final image = await call('media.localPreview', {
        'recipe': paintRecipe,
        'maxEdge': 1280,
      });
      owned = image['path'] as String;
      if (!mounted || !valid() || !operationCurrent(epoch)) return;
      refreshPortrait(() => busy = false);
      final page = SelectionWorkspace(
        state: widget.state,
        photo: widget.photo,
        owner: widget.owner,
        region: region,
        localState: base,
        frame: image,
        isCurrent: valid,
      );
      owned =
          null; // SelectionWorkspace owns this bounded frame until it closes.
      final selection = await hueRootPage<SelectionResult>(
        context,
        MaterialPageRoute(builder: (_) => page),
      );
      if (!mounted ||
          selection == null ||
          !valid() ||
          !operationCurrent(epoch)) {
        return;
      }
      if (widget.regionId?.isNotEmpty == true) {
        refreshPortrait(() => busy = true);
        final next = await call('media.retouchDescribe', {
          'localData': selection.localState['localData'],
        });
        final image = await render(next);
        if (valid()) {
          refreshPortrait(() {
            undo.add(staged);
            redo.clear();
            data = next;
            frame = image;
          });
        }
      } else {
        final target = selection.regionId;
        final result = await hueRootPage<Json>(
          context,
          MaterialPageRoute(
            builder: (_) => RetouchWorkspace(
              state: widget.state,
              photo: widget.photo,
              owner: widget.owner,
              recipe: {
                ...widget.recipe,
                'localData': selection.localState['localData'],
              },
              isCurrent: valid,
              regionId: target,
              regionName:
                  object(
                        (selection.localState['regions'] as List).firstWhere(
                          (r) => object(r)['id'] == target,
                        ),
                      )['name']
                      as String?,
            ),
          ),
        );
        if (mounted && result != null && valid() && operationCurrent(epoch)) {
          Navigator.pop(context, result);
        }
      }
    } catch (failure) {
      if (operationCurrent(epoch)) refreshPortrait(() => error = '$failure');
    } finally {
      if (owned != null) await remove(owned);
      if (operationCurrent(epoch)) refreshPortrait(() => busy = false);
    }
  }

  Future<void> originalAutoBlemishes() async {
    final epoch = operationEpoch;
    if (busy || !operationCurrent(epoch) || data == null) return;
    await cancelTonePreview();
    if (!operationCurrent(epoch) || data == null) return;
    final before = data!, fingerprint = data!['localData'];
    bool valid() =>
        operationCurrent(epoch) && data?['localData'] == fingerprint;
    refreshPortrait(() {
      busy = true;
      stopped = false;
      error = null;
    });
    try {
      var staged = before;
      if (object(staged['portrait'])['hasSkinMask'] != true) {
        staged = await call('media.retouchAnalyze', {
          'localData': staged['localData'],
          'mode': 'skin',
        });
      }
      final result = await call('media.retouchAnalyze', {
        'localData': staged['localData'],
        'mode': 'autoBlemish',
      });
      if (!valid()) return;
      final candidates = (result['healCandidates'] as List? ?? [])
          .map(object)
          .toList();
      if (candidates.isEmpty) {
        refreshPortrait(() => notice = '未发现需要修复的小瑕疵。');
        return;
      }
      refreshPortrait(() => busy = false);
      if (!mounted || !operationCurrent(epoch)) return;
      final selection = await showRetouchBlemishCandidates(
        context,
        candidates: [
          for (final (i, row) in candidates.indexed)
            RetouchHealEntry(
              index: i,
              x: (row['tx'] as num).toDouble(),
              y: (row['ty'] as num).toDouble(),
            ),
        ],
      );
      if (!valid() || selection == null || selection.isEmpty) return;
      refreshPortrait(() => busy = true);
      final next = await call('media.retouchChange', {
        'localData': staged['localData'],
        'action': 'addHeals',
        'value': {
          'heals': [for (final i in selection) candidates[i]],
        },
      });
      final image = await render(next);
      if (valid()) {
        refreshPortrait(() {
          undo.add(before);
          if (undo.length > 32) undo.removeAt(0);
          redo.clear();
          data = next;
          frame = image;
        });
      }
    } catch (failure) {
      if (operationCurrent(epoch)) refreshPortrait(() => error = '$failure');
    } finally {
      if (operationCurrent(epoch)) refreshPortrait(() => busy = false);
    }
    unawaited(refreshPortraitOverlay());
  }

  Future<void> originalNatural() async {
    final epoch = operationEpoch;
    if (busy || !operationCurrent(epoch) || data == null) return;
    await cancelTonePreview();
    if (!operationCurrent(epoch) || data == null) return;
    final before = data!;
    refreshPortrait(() {
      busy = true;
      stopped = false;
      error = null;
    });
    try {
      var next = before;
      if (object(next['portrait'])['hasSkinMask'] != true) {
        next = await call('media.retouchAnalyze', {
          'localData': next['localData'],
          'mode': 'skin',
        });
      }
      if ((object(next['portrait'])['faces'] as List? ?? []).isEmpty) {
        next = await call('media.retouchAnalyze', {
          'localData': next['localData'],
          'mode': 'face',
        });
      }
      final amount =
          (object(object(next['portrait'])['skin'])['NATURAL'] as num?)
              ?.toInt() ??
          0;
      next = await call('media.retouchChange', {
        'localData': next['localData'],
        'action': 'skin',
        'value': {'NATURAL': amount > 0 ? amount : 50},
      });
      final image = await render(next);
      if (operationCurrent(epoch) &&
          data?['localData'] == before['localData']) {
        refreshPortrait(() {
          undo.add(before);
          if (undo.length > 32) undo.removeAt(0);
          redo.clear();
          data = next;
          frame = image;
        });
      }
    } catch (failure) {
      if (operationCurrent(epoch)) refreshPortrait(() => error = '$failure');
    } finally {
      if (operationCurrent(epoch)) refreshPortrait(() => busy = false);
    }
    unawaited(refreshPortraitOverlay());
  }

  Future<void> detectFaces() async {
    if (busy || !current) return;
    if (faces.isNotEmpty) {
      final accepted = await confirmRetouchOriginalAction(
        context,
        title: '重新识别人脸？',
        message: '会替换已有的人脸选区和对应调节，保留祛痘。可撤销。',
        positive: '重新识别',
      );
      if (!accepted || !current) return;
    }
    await perform('media.retouchAnalyze', {'mode': 'face'});
  }

  Future<void> chooseOriginalFace(BuildContext anchor) async {
    if (busy || !current || faces.isEmpty) return;
    final index = await showRetouchOriginalPopupChoices(
      anchor,
      items: [
        for (var i = 0; i < faces.length; i++)
          '人脸 ${i + 1}${faces[i]['enabled'] == false ? ' · 停用' : ''}',
      ],
      selected: selected,
    );
    if (index != null && current) await selectFace(index);
  }

  Future<void> originalToneBody(bool value) async {
    final epoch = operationEpoch;
    if (!canEditTone || tonePerFace != true || data == null) return;
    final before = data!, target = selected;
    refreshPortrait(() {
      busy = true;
      stopped = false;
      error = null;
    });
    try {
      var staged = before;
      if (value && chosen['hasBodySkinMask'] != true) {
        staged = await call('media.retouchAnalyze', {
          'localData': before['localData'],
          'mode': 'faceBody',
        });
      }
      final next = await call('media.retouchChange', {
        'localData': staged['localData'],
        'action': 'face',
        'index': target,
        'value': {'toneBody': value},
      });
      final image = await render(next);
      if (operationCurrent(epoch) &&
          selected == target &&
          data?['localData'] == before['localData']) {
        refreshPortrait(() {
          undo.add(before);
          if (undo.length > 32) undo.removeAt(0);
          redo.clear();
          data = next;
          frame = image;
        });
      }
    } catch (failure) {
      if (operationCurrent(epoch)) refreshPortrait(() => error = '$failure');
    } finally {
      if (operationCurrent(epoch)) refreshPortrait(() => busy = false);
    }
    unawaited(refreshPortraitOverlay());
  }

  Future<void> refreshOriginalModeFrame() async {
    final epoch = operationEpoch;
    if (!operationCurrent(epoch) || data == null || busy) return;
    refreshPortrait(() {
      busy = true;
      stopped = false;
    });
    try {
      final image = await render(data!);
      if (operationCurrent(epoch)) refreshPortrait(() => frame = image);
    } catch (failure) {
      if (operationCurrent(epoch)) refreshPortrait(() => error = '$failure');
    } finally {
      if (operationCurrent(epoch)) refreshPortrait(() => busy = false);
    }
    unawaited(refreshPortraitOverlay());
  }

  Future<void> originalGroups() async {
    final epoch = operationEpoch;
    if (busy || !operationCurrent(epoch)) return;
    await cancelTonePreview();
    if (bodyStart != null) await finishOriginalBody(false);
    if (!mounted || !operationCurrent(epoch)) return;
    refreshPortrait(() {
      choosingGroup = true;
      photoSampling = manual = healMode = false;
      notice = null;
    });
    await refreshOriginalModeFrame();
  }

  Future<void> originalSection(int section, {bool natural = false}) async {
    if (brushRadiusStart != null) cancelBrushSizing();
    final epoch = operationEpoch;
    if (busy || !operationCurrent(epoch) || data == null) return;
    await cancelTonePreview();
    if (!mounted || !operationCurrent(epoch)) return;
    refreshPortrait(() {
      choosingGroup = false;
      if (section == 2) bodyTabBefore = tab;
      tab = section;
      photoSampling = manual = healMode = false;
      notice = null;
      if (natural) {
        skinParameter = 'NATURAL';
      } else if (section == 1) {
        skinParameter = 'tone';
      }
      if (section == 2) {
        bodyComparisonBefore = comparisonFrame;
        comparisonFrame = null;
        comparing = compareWanted = false;
        bodyViewportBefore = viewport.value.clone();
        bodyOverlayBefore = showOverlay;
        showOverlay = true;
        viewport.value = Matrix4.identity();
        bodyFrameBefore = frame;
        bodyStart = data;
        bodyUndoBefore = List.of(undo);
        bodyRedoBefore = List.of(redo);
        undo.clear();
        redo.clear();
      }
    });
    await refreshOriginalModeFrame();
    if (section == 1) {
      try {
        await toneCardRequest('toneCards.list');
      } catch (failure) {
        if (operationCurrent(epoch)) refreshPortrait(() => error = '$failure');
      }
      if (natural) {
        await originalNatural();
      } else if (operationCurrent(epoch) && portrait['hasSkinMask'] != true) {
        await perform('media.retouchAnalyze', {
          'mode': 'skin',
        }, remember: false);
      }
    } else if (section == 0 && faces.isEmpty) {
      await detectFaces();
    }
  }

  Future<void> finishOriginalBody(bool apply) async {
    final epoch = operationEpoch;
    if (busy || !operationCurrent(epoch) || bodyStart == null) return;
    final start = bodyStart!;
    final oldUndo = bodyUndoBefore!, oldRedo = bodyRedoBefore!;
    if (!apply) {
      refreshPortrait(() {
        busy = true;
        stopped = false;
      });
      try {
        final image = await render(start);
        if (!mounted || !operationCurrent(epoch)) return;
        refreshPortrait(() {
          data = start;
          frame = image;
        });
      } catch (failure) {
        if (operationCurrent(epoch)) refreshPortrait(() => error = '$failure');
        return;
      } finally {
        if (operationCurrent(epoch)) refreshPortrait(() => busy = false);
      }
    }
    if (!mounted || !operationCurrent(epoch)) return;
    refreshPortrait(() {
      undo
        ..clear()
        ..addAll(oldUndo);
      redo
        ..clear()
        ..addAll(oldRedo);
      if (apply && start['localData'] != data?['localData']) {
        undo.add(start);
        if (undo.length > 32) undo.removeAt(0);
        redo.clear();
      }
      if (bodyViewportBefore != null) viewport.value = bodyViewportBefore!;
      if (bodyOverlayBefore != null) showOverlay = bodyOverlayBefore!;
      comparisonFrame = bodyComparisonBefore;
      bodyComparisonBefore = null;
      comparing = compareWanted = false;
      if (bodyTabBefore != null) tab = bodyTabBefore!;
      bodyTabBefore = null;
      bodyViewportBefore = null;
      bodyOverlayBefore = null;
      bodyStart = bodyFrameBefore = null;
      bodyUndoBefore = bodyRedoBefore = null;
      choosingGroup = true;
    });
    unawaited(refreshPortraitOverlay());
  }

  Future<void> originalCompare(bool value) async {
    if (brushRadiusStart != null) cancelBrushSizing();
    final epoch = operationEpoch;
    compareWanted = value;
    brushEditing.value = !value && brushRadiusStart == null;
    if (!value) {
      if (operationCurrent(epoch)) refreshPortrait(() => comparing = false);
      return;
    }
    if (busy || !operationCurrent(epoch) || data == null) return;
    if (comparisonFrame != null) {
      refreshPortrait(() => comparing = true);
      return;
    }
    refreshPortrait(() {
      busy = true;
      stopped = false;
    });
    try {
      final base = await call('media.retouchChange', {
        'localData': data!['localData'],
        'action': bodyStart == null ? 'clearPortrait' : 'beforeBody',
      });
      final image = await render(base);
      if (operationCurrent(epoch)) {
        refreshPortrait(() {
          comparisonFrame = image;
          comparing = compareWanted;
        });
      }
    } catch (failure) {
      if (operationCurrent(epoch)) refreshPortrait(() => error = '$failure');
    } finally {
      if (operationCurrent(epoch)) refreshPortrait(() => busy = false);
    }
  }

  Widget originalAction(
    String label,
    VoidCallback? onPressed, {
    bool selected = false,
  }) => RetouchOriginalTextButton(
    label,
    onPressed == null
        ? null
        : () {
            cancelBrushSizing();
            onPressed();
          },
    selected: selected,
  );

  Widget originalRail(List<Widget> entries) => SizedBox(
    height: MediaQuery.textScalerOf(context).scale(10) >= 12 ? 84 : 72,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: entries),
    ),
  );

  void beginOriginalScalar(String key) {
    if (busy || !current || data == null || scalarStart != null) return;
    scalarStart = data;
    scalarRemember = tonePreviewStart == null;
    scalarKey = key;
    scalarEnded = scalarCancelled = false;
  }

  void updateOriginalScalar(String key, Json request) {
    if (!current || scalarStart == null || scalarKey != key) return;
    scalarPending = request;
    if (!scalarRunning) unawaited(drainOriginalScalar());
  }

  Future<void> drainOriginalScalar() async {
    final epoch = operationEpoch;
    if (scalarRunning) return;
    scalarRunning = true;
    try {
      while (scalarPending != null &&
          operationCurrent(epoch) &&
          !scalarCancelled) {
        final request = scalarPending!;
        scalarPending = null;
        await perform('media.retouchChange', request, remember: false);
        if (!operationCurrent(epoch)) break;
        if (error != null) {
          scalarCancelled = true;
          scalarPending = null;
        }
      }
    } finally {
      if (operationCurrent(epoch)) {
        scalarRunning = false;
        if (scalarEnded || scalarCancelled) await completeOriginalScalar();
      }
    }
  }

  void endOriginalScalar({bool cancel = false}) {
    scalarEnded = true;
    scalarCancelled = cancel;
    if (cancel) scalarPending = null;
    if (!scalarRunning) unawaited(completeOriginalScalar());
  }

  Future<void> completeOriginalScalar() async {
    final epoch = operationEpoch;
    final before = scalarStart;
    scalarStart = scalarPending = null;
    scalarKey = null;
    if (before == null || !operationCurrent(epoch)) return;
    if (scalarCancelled) {
      refreshPortrait(() {
        busy = true;
        stopped = false;
      });
      try {
        final image = await render(before);
        if (operationCurrent(epoch)) {
          refreshPortrait(() {
            data = before;
            frame = image;
          });
        }
      } catch (failure) {
        if (operationCurrent(epoch)) refreshPortrait(() => error = '$failure');
      } finally {
        if (operationCurrent(epoch)) refreshPortrait(() => busy = false);
      }
    } else if (scalarRemember && before['localData'] != data?['localData']) {
      refreshPortrait(() {
        undo.add(before);
        if (undo.length > (bodyStart == null ? 32 : 48)) undo.removeAt(0);
        redo.clear();
      });
    }
    unawaited(refreshPortraitOverlay());
  }

  Widget originalValue(
    String label,
    String key,
    Json source, {
    required String action,
    double min = 0,
    double max = 100,
    bool fraction = false,
    bool permitted = true,
  }) {
    final epoch = operationEpoch;
    final identity = '$action-$key-$selected-$bodyTool';
    final enabled =
        permitted &&
        current &&
        (!busy || scalarKey == identity) &&
        (scalarStart == null || scalarKey == identity) &&
        (action != 'face' || (faces.isNotEmpty && chosen['enabled'] != false));
    final value =
        (((source[key] as num?)?.toDouble() ?? 0) * (fraction ? 100 : 1)).clamp(
          min,
          max,
        );
    Json request(double v) => {
      'action': action,
      if (action == 'face') 'index': selected,
      'value': {
        if (action == 'body') 'tool': bodyTool,
        key: fraction ? v / 100 : v.round(),
      },
    };
    return RetouchOriginalSlider(
      key: ValueKey('original-$identity'),
      label: label,
      value: value,
      min: min,
      max: max,
      onChangeStart: (_) {
        if (operationCurrent(epoch)) beginOriginalScalar(identity);
      },
      onChanged: enabled
          ? (v) {
              if (operationCurrent(epoch)) {
                updateOriginalScalar(identity, request(v));
              }
            }
          : null,
      onChangeEnd: (v) {
        if (!operationCurrent(epoch)) return;
        updateOriginalScalar(identity, request(v));
        endOriginalScalar();
      },
      onChangeCancel: () {
        if (operationCurrent(epoch)) endOriginalScalar(cancel: true);
      },
    );
  }

  List<(String, String, String, double, double, bool)> get originalFaceFields =>
      [
        ('提亮', 'brightness', 'brightness', -100, 100, false),
        ('冷暖', 'warmth', 'warmth', -100, 100, false),
        ('红润', 'redness', 'redness', -100, 100, false),
        ('柔肤', 'smoothing', 'smooth', 0, 100, false),
        ('纹理', 'texture', 'texture', 0, 100, false),
        ('光照', 'light', 'light', -100, 100, false),
        ('眼下阴影', 'shadows', 'shadows', 0, 100, false),
        ('眼神清晰', 'EYE_DETAIL', 'eye', 0, 100, false),
        ('眼白净化', 'EYE_WHITE', 'eye-clean', 0, 100, false),
        ('牙齿去黄', 'TEETH', 'teeth', 0, 100, false),
        ('眼下修复', 'UNDER_EYE', 'under-eye', 0, 100, false),
        ('柔光补光', 'FILL', 'light', 0, 100, false),
        ('光源左右', 'LIGHT_X', 'light', -100, 100, false),
        ('光源上下', 'LIGHT_Y', 'light', -100, 100, false),
      ];

  List<Widget> originalFaceControls() => [
    if (faceMode == 0)
      for (final f in originalFaceFields.where((f) => f.$2 == faceParameter))
        originalValue(
          f.$1,
          f.$2,
          chosen,
          action: 'face',
          min: f.$4,
          max: f.$5,
          fraction: f.$6,
          permitted:
              ![
                'EYE_DETAIL',
                'EYE_WHITE',
                'TEETH',
                'UNDER_EYE',
              ].contains(f.$2) ||
              chosen['hasLandmarks'] == true,
        ),
    if (faceMode == 0 &&
        ['FILL', 'LIGHT_X', 'LIGHT_Y'].contains(faceParameter)) ...[
      RetouchOriginalLightPad(
        x: (chosen['LIGHT_X'] as num?)?.toDouble() ?? 0,
        y: (chosen['LIGHT_Y'] as num?)?.toDouble() ?? 0,
        onChanged:
            !current ||
                faces.isEmpty ||
                chosen['enabled'] == false ||
                (busy && !lightRunning)
            ? null
            : updateOriginalLight,
        onChangeStart: beginOriginalLight,
        onChangeEnd: () => endOriginalLight(),
        onCancel: () => endOriginalLight(cancel: true),
      ),
      Row(
        children: [
          for (final f in [('光源左右', 'LIGHT_X'), ('光源上下', 'LIGHT_Y')])
            Expanded(
              child: originalAction(
                f.$1,
                busy ? null : () => refreshPortrait(() => faceParameter = f.$2),
                selected: faceParameter == f.$2,
              ),
            ),
        ],
      ),
    ],
    if (faceMode == 1)
      Row(
        children: [
          for (final f in [(0, '选脸'), (1, '补选'), (2, '擦除')])
            Expanded(
              child: originalAction(
                f.$2,
                busy || (f.$1 > 0 && faces.isEmpty)
                    ? null
                    : () => refreshPortrait(() => selectionBrush = f.$1),
                selected: selectionBrush == f.$1,
              ),
            ),
        ],
      ),
    if (faceMode == 1 && selectionBrush == 0)
      SizedBox(
        height: 48,
        child: Center(
          child: Text(
            manual
                ? '在照片上拖出人脸范围，松手确认'
                : faces.isEmpty
                ? '先自动选脸，或点 + 手动添加'
                : '点按人脸切换人物 · 双指缩放和移动',
            style: const TextStyle(fontSize: 12, color: retouchOriginalMuted),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    if (faceMode == 2 || (faceMode == 1 && selectionBrush > 0))
      originalBrushSlider(),
    originalRail([
      for (final f in originalFaceFields.where(
        (f) => !['LIGHT_X', 'LIGHT_Y'].contains(f.$2),
      ))
        RetouchOriginalToolButton(
          label: f.$1,
          icon: f.$3,
          selected: faceMode == 0 && faceParameter == f.$2,
          onPressed: busy
              ? null
              : () async {
                  cancelBrushSizing();
                  cancelOriginalPhotoGesture();
                  originalGestureLocal = null;
                  refreshPortrait(() {
                    faceMode = 0;
                    faceParameter = f.$2;
                    healMode = false;
                  });
                  if ([
                        'EYE_DETAIL',
                        'EYE_WHITE',
                        'TEETH',
                        'UNDER_EYE',
                      ].contains(f.$2) &&
                      chosen['hasLandmarks'] != true) {
                    await perform('media.retouchAnalyze', {'mode': 'face'});
                  }
                },
        ),
      RetouchOriginalToolButton(
        label: '祛痘',
        icon: 'heal',
        selected: faceMode == 2,
        onPressed: busy
            ? null
            : () => refreshPortrait(() {
                cancelBrushSizing();
                faceMode = 2;
                healMode = true;
                manual = false;
              }),
      ),
      RetouchOriginalToolButton(
        label: '选区',
        icon: 'face',
        selected: faceMode == 1,
        onPressed: busy
            ? null
            : () => refreshPortrait(() {
                cancelBrushSizing();
                faceMode = 1;
                healMode = false;
                manual = false;
              }),
      ),
    ]),
  ];

  Widget originalToneRail() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final value in data?['tones'] as List? ?? [])
          RetouchToneCardButton(
            name: object(value)['name'] as String,
            rgb: object(value)['color'] as int,
            original: object(value)['id'] == 0,
            selected: editedTone['toneId'] == object(value)['id'],
            onTap: !canEditTone
                ? null
                : () => unawaited(previewTone({'toneId': object(value)['id']})),
          ),
        if (pickerSeed != null)
          RetouchToneCardButton(
            name: '自定义',
            rgb: editedTone['toneId'] == 10
                ? editedTone['toneRgb'] as int
                : pickerSeed!,
            selected: editedTone['toneId'] == 10,
            onTap: !canEditTone
                ? null
                : () => unawaited(customTone(pickerSeed!)),
          ),
        for (final card in toneCards)
          RetouchToneCardButton(
            name: card.name,
            rgb: card.rgb,
            selected:
                editedTone['toneId'] == 10 && editedTone['toneRgb'] == card.rgb,
            onTap: !canEditTone
                ? null
                : () => unawaited(previewTone({'toneRgb': card.rgb})),
            onLongPress: busy ? null : () => unawaited(deleteToneCard(card)),
          ),
      ],
    ),
  );

  List<Widget> originalSkinControls() => [
    if (skinParameter == 'tone') ...[
      if (tonePreviewStart == null && !photoSampling) ...[
        Row(
          children: [
            Expanded(
              child: originalAction(
                tonePerFace == true ? '仅脸部' : '全部露出皮肤',
                tonePerFace != true || !canEditTone
                    ? null
                    : () => unawaited(originalToneBody(false)),
                selected: tonePerFace != true || chosen['toneBody'] != true,
              ),
            ),
            Expanded(
              child: originalAction(
                tonePerFace == true ? '全身皮肤' : '重新识别',
                !canEditTone
                    ? null
                    : () => tonePerFace == true
                          ? unawaited(originalToneBody(true))
                          : unawaited(
                              perform('media.retouchAnalyze', {'mode': 'skin'}),
                            ),
                selected: tonePerFace == true && chosen['toneBody'] == true,
              ),
            ),
            if (tonePerFace == true)
              SizedBox(
                width: 80,
                child: originalAction(
                  '管理色卡',
                  busy || toneCards.isEmpty
                      ? null
                      : () => unawaited(
                          showRetouchToneCards(
                            context,
                            cards: toneCards,
                            onDelete: (id) =>
                                toneCardRequest('toneCards.remove', {'id': id}),
                          ),
                        ),
                ),
              ),
            if (tonePerFace != true)
              Builder(
                builder: (anchor) => SizedBox(
                  width: 48,
                  child: RetouchOriginalUtilityButton(
                    icon: 'more',
                    semanticLabel: '更多肤色选项',
                    onPressed: busy
                        ? null
                        : () => unawaited(morePortrait(anchor)),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: 88, child: originalToneRail()),
      ],
      if (tonePreviewStart != null && !photoSampling)
        Row(
          children: [
            Expanded(
              child: originalAction(
                '继续选色',
                busy || pickerSeed == null
                    ? null
                    : () => unawaited(customTone(pickerSeed!)),
              ),
            ),
            Expanded(
              child: originalAction(
                '取消',
                busy ? null : () => unawaited(cancelTonePreview()),
              ),
            ),
            Expanded(
              child: originalAction(
                '使用此色',
                busy ? null : confirmTonePreview,
                selected: true,
              ),
            ),
          ],
        ),
      if (photoSampling)
        originalAction(
          '点按照片取色 · 点此取消取色',
          busy
              ? null
              : () {
                  refreshPortrait(() => photoSampling = false);
                  if (sampleSeed != null) unawaited(customTone(sampleSeed!));
                },
        ),
      if (editedTone['toneId'] != 0 && !photoSampling)
        originalValue(
          '强度',
          'toneAmount',
          editedTone,
          action: toneAction,
          fraction: true,
          permitted:
              editedTone['toneId'] != 0 &&
              !photoSampling &&
              (tonePerFace != true
                  ? portrait['hasSkinMask'] == true
                  : faces.isNotEmpty && chosen['enabled'] != false),
        ),
    ] else
      originalValue(
        {
          'smoothing': '磨皮',
          'EVENNESS': '匀肤',
          'SHINE': '去油光',
          'TEXTURE': '纹理保留',
          'NATURAL': '自然精修',
          'region-brightness': '提亮',
          'region-warmth': '冷暖',
          'region-redness': '红润',
          'region-smoothing': '磨皮',
          'region-texture': '纹理',
        }[skinParameter]!,
        skinParameter.replaceFirst('region-', ''),
        skinParameter.startsWith('region-')
            ? object(portrait['regionSkin'] ?? {})
            : skin,
        action: skinParameter.startsWith('region-') ? 'regionSkin' : 'skin',
        min:
            [
              'region-brightness',
              'region-warmth',
              'region-redness',
            ].contains(skinParameter)
            ? -100
            : 0,
        permitted: portrait['hasSkinMask'] == true,
      ),
    originalRail([
      for (final f in [
        ('自然精修', 'NATURAL', 'face'),
        ('肤色', 'tone', 'color'),
        if (widget.regionId?.isNotEmpty != true) ('磨皮', 'smoothing', 'smooth'),
        if (widget.regionId?.isNotEmpty == true) ...[
          ('提亮', 'region-brightness', 'brightness'),
          ('冷暖', 'region-warmth', 'warmth'),
          ('红润', 'region-redness', 'redness'),
          ('磨皮', 'region-smoothing', 'smooth'),
          ('纹理', 'region-texture', 'texture'),
        ],
        if (widget.regionId?.isNotEmpty != true) ('纹理保留', 'TEXTURE', 'texture'),
        ('匀肤', 'EVENNESS', 'skin-even'),
        ('去油光', 'SHINE', 'shine-control'),
      ])
        RetouchOriginalToolButton(
          label: f.$1,
          icon: f.$3,
          selected: skinParameter == f.$2,
          onPressed: busy
              ? null
              : () => unawaited(selectOriginalSkinTool(f.$2)),
        ),
      RetouchOriginalToolButton(
        label: '自动祛痘',
        icon: 'heal',
        onPressed: busy ? null : () => unawaited(originalAutoBlemishes()),
      ),
    ]),
  ];

  Future<void> selectOriginalSkinTool(String key) async {
    if (busy || !current) return;
    await cancelTonePreview();
    if (current) {
      refreshPortrait(() => skinParameter = key);
      unawaited(refreshPortraitOverlay());
    }
    if (key == 'NATURAL') await originalNatural();
  }

  Json originalBodyAxis(int axis, double n) {
    final original = scalarStart == null
        ? area
        : object((object(scalarStart!['portrait'])['body'] as List)[bodyTool]);
    var l = (original['left'] as num).toDouble(),
        t = (original['top'] as num).toDouble(),
        w = (original['right'] as num).toDouble() - l,
        h = (original['bottom'] as num).toDouble() - t;
    final bottom = bodyTool == 2 ? .97 : 1.0;
    n = n.clamp(0, 1);
    switch (axis) {
      case 0:
        l = math.min(n, 1 - w);
      case 1:
        t = math.min(n, bottom - h);
      case 2:
        w = math.max(math.min(.08, 1 - l), math.min(n, 1 - l));
      case 3:
        h = math.max(math.min(.10, bottom - t), math.min(n, bottom - t));
    }
    return {
      'action': 'body',
      'value': {
        'tool': bodyTool,
        'left': l,
        'top': t,
        'right': l + w,
        'bottom': t + h,
      },
    };
  }

  Future<void> originalBodyAnalysis(bool locate) async {
    final epoch = operationEpoch;
    if (busy || !operationCurrent(epoch) || data == null) return;
    final before = data!, fingerprint = data!['localData'];
    bool valid() =>
        operationCurrent(epoch) && data?['localData'] == fingerprint;
    refreshPortrait(() {
      busy = true;
      stopped = false;
      error = null;
      notice = locate ? '正在识别人物轮廓…' : '正在分析背景直线…';
    });
    try {
      var next = await call('media.retouchAnalyze', {
        'localData': fingerprint,
        'mode': 'body',
        'locate': false,
        'protection': 100,
      });
      if (!valid()) return;
      if (locate) {
        final found = (next['people'] as List? ?? []).map(object).toList();
        if (found.isEmpty) {
          refreshPortrait(() => notice = '未识别到完整人物轮廓，请手动调整。');
          return;
        }
        var person = 0;
        if (found.length > 1) {
          refreshPortrait(() => busy = false);
          if (!mounted || !operationCurrent(epoch)) return;
          final choice = await showRetouchOriginalChoices(
            context,
            title: '选择要塑形的人物',
            items: [
              for (final (i, p) in found.indexed)
                '人物 ${i + 1} · 画面${(((p['left'] as num) + (p['right'] as num)) * 50).round()}% 处',
            ],
          );
          if (choice == null || !valid()) return;
          person = choice;
          refreshPortrait(() => busy = true);
        }
        next = await call('media.retouchAnalyze', {
          'localData': fingerprint,
          'mode': 'body',
          'locate': true,
          'person': person,
          'protection': 100,
        });
      }
      final image = await render(next);
      if (valid()) {
        refreshPortrait(() {
          undo.add(before);
          if (undo.length > 48) undo.removeAt(0);
          redo.clear();
          data = next;
          frame = image;
          if (locate) showOverlay = true;
          notice = locate ? '已按人物轮廓定位 · 请检查腰腿位置' : '背景直线保护已开启';
        });
      }
    } catch (failure) {
      if (operationCurrent(epoch)) refreshPortrait(() => error = '$failure');
    } finally {
      if (operationCurrent(epoch)) refreshPortrait(() => busy = false);
    }
  }

  Future<void> originalBodyProtection() async {
    if (busy || !current) return;
    if (portrait['hasBodyMask'] != true) {
      await originalBodyAnalysis(false);
      return;
    }
    await change('body', {
      'tool': bodyTool,
      'protection': (portrait['protection'] as num? ?? 0) == 0 ? 100 : 0,
    });
  }

  void resetOriginalBody() {
    final values = [
      [.25, .25, .75, .90],
      [.30, .50, .70, .94],
      [.23, .48, .77, .90],
    ][bodyTool];
    unawaited(
      change('body', {
        'tool': bodyTool,
        'left': values[0],
        'top': values[1],
        'right': values[2],
        'bottom': values[3],
        'amount': 0,
        if (bodyTool == 1) 'singleLeg': false,
      }),
    );
  }

  List<Widget> originalBodyControls() {
    final epoch = operationEpoch;
    final free = !busy && scalarStart == null && lightStart == null && current;
    final strengthKey = 'body-amount-$bodyTool';
    return [
      RetouchOriginalBodyControls(
        tool: bodyTool,
        area: area,
        protection: (portrait['protection'] as num?)?.toInt() ?? 0,
        singleLeg: portrait['singleLeg'] == true,
        expanded: bodyExpanded,
        busy: busy && scalarStart == null,
        onTool: !free
            ? null
            : (v) => refreshPortrait(() {
                bodyTool = v;
                showOverlay = true;
              }),
        onExpanded: !free
            ? null
            : (v) => refreshPortrait(() => bodyExpanded = v),
        onLocate: !free ? null : () => unawaited(originalBodyAnalysis(true)),
        onProtection: !free ? null : () => unawaited(originalBodyProtection()),
        onSingleLeg: !free
            ? null
            : () => unawaited(
                change('body', {
                  'tool': bodyTool,
                  'singleLeg': portrait['singleLeg'] != true,
                }),
              ),
        onReset: !free ? null : resetOriginalBody,
        onExact: !free
            ? null
            : (v) => unawaited(change('body', {'tool': bodyTool, 'amount': v})),
        onStart: () {
          if (operationCurrent(epoch)) beginOriginalScalar(strengthKey);
        },
        onChanged: !current || (busy && scalarKey != strengthKey)
            ? null
            : (v) {
                if (operationCurrent(epoch)) {
                  updateOriginalScalar(strengthKey, {
                    'action': 'body',
                    'value': {'tool': bodyTool, 'amount': v.round()},
                  });
                }
              },
        onEnd: () {
          if (operationCurrent(epoch)) endOriginalScalar();
        },
        onCancel: () {
          if (operationCurrent(epoch)) endOriginalScalar(cancel: true);
        },
        onAxisStart: (i) {
          if (operationCurrent(epoch)) {
            beginOriginalScalar('body-axis-$bodyTool-$i');
          }
        },
        onAxis: (i, v) {
          if (operationCurrent(epoch)) {
            updateOriginalScalar(
              'body-axis-$bodyTool-$i',
              originalBodyAxis(i, v),
            );
          }
        },
        onAxisEnd: (i) {
          if (operationCurrent(epoch)) endOriginalScalar();
        },
        onAxisCancel: (i) {
          if (operationCurrent(epoch)) endOriginalScalar(cancel: true);
        },
      ),
    ];
  }

  Widget originalUtilities() => LayoutBuilder(
    builder: (context, bounds) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: math.max(
          !choosingGroup && bodyStart == null ? 304 : 256,
          bounds.maxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              RetouchOriginalUtilityButton(
                icon: 'undo',
                semanticLabel: bodyStart == null ? '撤销' : '撤销塑形',
                onPressed: busy || undo.isEmpty
                    ? null
                    : () => unawaited(history(false)),
              ),
              RetouchOriginalUtilityButton(
                icon: 'redo',
                semanticLabel: bodyStart == null ? '重做' : '重做塑形',
                onPressed: busy || redo.isEmpty
                    ? null
                    : () => unawaited(history(true)),
              ),
              const Spacer(),
              if (!choosingGroup && bodyStart == null)
                RetouchOriginalUtilityButton(
                  icon: 'brush',
                  semanticLabel: '涂抹范围',
                  onPressed: busy || scalarStart != null || lightStart != null
                      ? null
                      : () => unawaited(paintOriginalPortrait()),
                ),
              RetouchOriginalUtilityButton(
                icon: 'eye',
                semanticLabel: bodyStart == null ? '显示或隐藏选区' : '显示或隐藏塑形范围',
                selected: showOverlay,
                onPressed: busy || scalarStart != null || lightStart != null
                    ? null
                    : () {
                        cancelBrushSizing();
                        refreshPortrait(() => showOverlay = !showOverlay);
                        unawaited(refreshPortraitOverlay());
                      },
              ),
              RetouchOriginalUtilityButton(
                icon: 'fit',
                semanticLabel: '适应照片',
                onPressed: busy || scalarStart != null || lightStart != null
                    ? null
                    : () {
                        cancelOriginalPhotoGesture();
                        originalGestureLocal = null;
                        cancelBrushSizing();
                        viewport.value = Matrix4.identity();
                      },
              ),
              RetouchOriginalUtilityButton(
                icon: 'compare',
                bodyCompareTransient: bodyStart != null,
                semanticLabel: bodyStart == null
                    ? '按住查看处理前；辅助功能点击切换'
                    : '按住对比进入塑形前的照片',
                selected: comparing,
                onCompare: (value) => unawaited(originalCompare(value)),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget originalStage() => Stack(
    children: [
      Positioned.fill(child: originalPhoto()),
      Positioned.fill(child: brushPreview()),
      if (bodyStart != null)
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            height: 48,
            color: const Color(0x7017221e),
            alignment: Alignment.center,
            child: Text(
              bodyTool == 2
                  ? '上边对齐大腿根，底边对齐脚底 · 脚下需留白'
                  : bodyTool == 1
                  ? (portrait['singleLeg'] == true
                        ? '将范围框贴合一条腿 · 双指缩放查看'
                        : '将范围框贴合双腿 · 中线放在两腿之间')
                  : '将范围框放在肩部以下 · 拖动边角调整',
              maxLines: 2,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: retouchOriginalMuted),
            ),
          ),
        ),
      if (!choosingGroup &&
          (tab == 0 ||
              (tab == 1 && skinParameter == 'tone' && tonePerFace == true)))
        Align(
          alignment: Alignment.topCenter,
          child: RetouchOriginalFaceBar(
            selectionLabel: faces.isEmpty
                ? '选择人脸'
                : '人脸 ${selected + 1}${chosen['enabled'] == false ? ' · 已停用' : ''}',
            onSelectAnchor: busy || faces.isEmpty
                ? null
                : (anchor) => unawaited(chooseOriginalFace(anchor)),
            onDetect: busy ? null : () => unawaited(detectFaces()),
            onAdd: busy
                ? null
                : () => refreshPortrait(() {
                    manual = true;
                    faceMode = 1;
                    selectionBrush = 0;
                    showOverlay = true;
                    healMode = false;
                    notice = null;
                  }),
            onMore: busy || data == null
                ? null
                : (anchor) => unawaited(morePortrait(anchor)),
          ),
        ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 48,
        child: originalUtilities(),
      ),
      if (error != null || notice != null || photoSampling || busy)
        Positioned(
          left: 0,
          right: 0,
          bottom: 48,
          child: RetouchOriginalStatus(
            error ??
                (photoSampling
                    ? '点按照片取色'
                    : busy
                    ? '正在处理…'
                    : notice ?? ''),
            onTap: photoSampling && !busy
                ? () {
                    refreshPortrait(() => photoSampling = false);
                    if (sampleSeed != null) unawaited(customTone(sampleSeed!));
                  }
                : null,
          ),
        ),
    ],
  );

  Widget originalPortraitLayout(BuildContext context) => Theme(
    data: hueviaTheme(Brightness.dark, home: false),
    child: PopScope(
      canPop:
          exitRequested ||
          (bodyStart == null &&
              (busy || scalarStart != null || lightStart != null)) ||
          (!busy && choosingGroup && scalarStart == null && lightStart == null),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          cancelWorkspace(pop: false);
        } else {
          requestExit();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          PhotoAtmosphere(image: atmosphere),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              foregroundColor: const Color(0xfff4f5f7),
              toolbarHeight: 52,
              leadingWidth: bodyStart == null ? 52 : 56,
              centerTitle: true,
              titleTextStyle: const TextStyle(
                color: Color(0xfff4f5f7),
                fontSize: 16,
              ),
              leading: IconButton(
                tooltip: bodyStart != null
                    ? '取消塑形并返回人像'
                    : busy ||
                          scalarStart != null ||
                          lightStart != null ||
                          choosingGroup
                    ? '取消人像精修'
                    : '返回人像工具',
                onPressed: exitRequested ? null : requestExit,
                icon: RetouchOriginalGlyph(
                  bodyStart == null &&
                          (busy ||
                              scalarStart != null ||
                              lightStart != null ||
                              choosingGroup)
                      ? 'close'
                      : 'back',
                ),
              ),
              title: Text(
                '${choosingGroup
                    ? '人像'
                    : tab == 2
                    ? '塑形'
                    : tab == 1
                    ? '皮肤'
                    : '面部'}${!choosingGroup && tab != 2 && data?['sourcePositioning'] == true ? ' · 塑形前定位' : ''}${widget.regionId?.isNotEmpty == true ? ' · ${widget.regionName ?? '局部区域'}' : ''}',
              ),
              actions: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    4,
                    8,
                    bodyStart == null ? 12 : 4,
                    8,
                  ),
                  child: SizedBox(
                    width: 64,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: const Color(0xffffe335),
                        foregroundColor: const Color(0xff211812),
                        textStyle: const TextStyle(fontSize: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed:
                          busy ||
                              data == null ||
                              !current ||
                              !originalPortraitReady ||
                              tonePreviewStart != null ||
                              photoSampling ||
                              scalarStart != null ||
                              lightStart != null ||
                              originalGestureDown != null
                          ? null
                          : () {
                              if (bodyStart != null) {
                                unawaited(finishOriginalBody(true));
                              } else {
                                Navigator.pop(context, data);
                              }
                            },
                      child: const Text('应用'),
                    ),
                  ),
                ),
              ],
            ),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final metrics = RetouchOriginalMetrics.resolve(
                    Size(bounds.maxWidth, bounds.maxHeight),
                    MediaQuery.textScalerOf(context).scale(10) / 10,
                    mode: tab == 1
                        ? (skinParameter == 'tone' ? 3 : 4)
                        : faceMode == 1
                        ? 2
                        : faceMode == 2
                        ? 1
                        : 0,
                    choosingGroup: choosingGroup,
                    hasSliderSelection: tab == 1
                        ? (skinParameter != 'tone' ||
                              (editedTone['toneId'] != 0 && !photoSampling))
                        : (faceMode == 0 && faceParameter != null),
                    lighting:
                        tab == 0 &&
                        faceMode == 0 &&
                        ['FILL', 'LIGHT_X', 'LIGHT_Y'].contains(faceParameter),
                    photoSampling: photoSampling,
                    tonePreviewing: tonePreviewStart != null,
                  );
                  final dock = RetouchOriginalDock(
                    choosingGroup: choosingGroup,
                    controls: tab == 0
                        ? originalFaceControls()
                        : tab == 1
                        ? originalSkinControls()
                        : originalBodyControls(),
                    entries: [
                      for (final f in [
                        (1, '皮肤', 'skin'),
                        (0, '面部', 'face'),
                        if (widget.regionId?.isNotEmpty != true)
                          (2, '塑形', 'body'),
                        (3, '自然精修', 'natural'),
                        if (widget.regionId?.isNotEmpty != true)
                          (4, '修补', 'heal'),
                      ])
                        RetouchOriginalToolButton(
                          label: f.$2,
                          icon: f.$3,
                          entry: true,
                          onPressed: busy || data == null
                              ? null
                              : () => unawaited(
                                  f.$1 == 4
                                      ? openOriginalPatch()
                                      : originalSection(
                                          f.$1 == 3 ? 1 : f.$1,
                                          natural: f.$1 == 3,
                                        ),
                                ),
                        ),
                    ],
                  );
                  if (metrics.side) {
                    return Row(
                      children: [
                        Expanded(child: originalStage()),
                        SizedBox(width: metrics.dockWidth, child: dock),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(child: originalStage()),
                      SizedBox(
                        height: !choosingGroup && tab == 2
                            ? retouchOriginalBodyDockHeight(
                                Size(bounds.maxWidth, bounds.maxHeight),
                                MediaQuery.textScalerOf(context).scale(10) / 10,
                                expanded: bodyExpanded,
                              )
                            : metrics.dockHeight,
                        child: dock,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
