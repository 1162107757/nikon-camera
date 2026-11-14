part of 'editor.dart';

const _editorYellow = Color(0xffffe335);
const _editorWhite = Color(0xfff4f5f7);
const _editorMuted = Color(0xffc8cdca);

extension _LegacyWorkspace on _EditorPageState {
  Future<void> openRetouch({bool patch = false}) async {
    if (!toolsEnabled) return;
    debounce?.cancel();
    revision++;
    refreshWorkspace(() => managingTools = true);
    try {
      await settleLocalAdjustments();
      if (activeJob != null) await widget.state.core.cancel(activeJob!);
      if (!mounted || !sameOwner) return;
      final frozen = recipe.clone().data, fingerprint = jsonEncode(recipe.data);
      final targetRegion = selectedRegionId;
      final targetName = selectedRegion?['name'] as String?;
      bool current() =>
          mounted &&
          sameOwner &&
          jsonEncode(recipe.data) == fingerprint &&
          selectedRegionId == targetRegion;
      final result = await hueRootPage<Json>(
        context,
        MaterialPageRoute(
          builder: (_) => RetouchWorkspace(
            state: widget.state,
            photo: widget.photo,
            owner: owner,
            recipe: frozen,
            isCurrent: current,
            patch: patch,
            regionId: patch ? null : targetRegion,
            regionName: patch ? null : targetName,
          ),
        ),
      );
      if (result == null || !current()) return;
      if (result['localData'] != (recipe.data['localData'] ?? '')) checkpoint();
      refreshWorkspace(() {
        recipe.data['localData'] = result['localData'];
        if (result['regionId'] is String &&
            (result['regionId'] as String).isNotEmpty) {
          selectedRegionId = result['regionId'] as String;
        }
        installLocalState(result);
        compare = false;
      });
      panelRevision.value++;
      unawaited(saveDraft().catchError((_) {}));
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) {
        refreshWorkspace(() => managingTools = false);
        unawaited(render());
      }
    }
  }

  bool get toolsEnabled =>
      restored &&
      sameOwner &&
      !leaving &&
      !exporting &&
      !managingTools &&
      !preparingFilter &&
      !analyzingCleanup;

  Widget compositionDock(double scale, bool compact) {
    final geometry = object(recipe.data['geometry'] ?? {});
    final left = geometry['left'] as int? ?? 0,
        top = geometry['top'] as int? ?? 0,
        right = geometry['right'] as int? ?? 1000000,
        bottom = geometry['bottom'] as int? ?? 1000000,
        turns = geometry['turns'] as int? ?? 0;
    var frameRatio = compositionFrame?.aspectRatio ?? 1.0;
    if ((turns - compositionFrameTurns).isOdd) frameRatio = 1 / frameRatio;
    final actual = frameRatio * (right - left) / (bottom - top);
    const choices = [
      ('原比例', 0.0),
      ('1:1', 1.0),
      ('2:3', 2 / 3),
      ('3:2', 1.5),
      ('9:16', 9 / 16),
      ('2.35:1', 2.35),
    ];
    double? selected;
    for (final c in choices) {
      if ((actual - (c.$2 == 0 ? frameRatio : c.$2)).abs() < .01) {
        selected = c.$2;
        break;
      }
    }
    final neutral =
        turns == 0 &&
        (geometry['angle'] ?? 0) == 0 &&
        (geometry['horizontalPerspective'] ?? 0) == 0 &&
        (geometry['verticalPerspective'] ?? 0) == 0 &&
        geometry['mirrored'] != true &&
        left == 0 &&
        top == 0 &&
        right == 1000000 &&
        bottom == 1000000;
    Widget action(
      String label,
      HueIconKind icon,
      VoidCallback run, {
      bool enabled = true,
    }) => Expanded(
      child: Opacity(
        opacity: toolsEnabled && enabled ? 1 : .3,
        child: TextButton(
          onPressed: toolsEnabled && enabled ? run : null,
          style: TextButton.styleFrom(
            foregroundColor: _editorWhite,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            minimumSize: const Size(0, 48),
            textStyle: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HueIcon(icon, size: 17, color: _editorWhite),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, bounds) {
              final width = bounds.maxWidth / 6 < 56
                  ? 56.0
                  : bounds.maxWidth / 6;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final c in choices)
                      SizedBox(
                        width: width,
                        height: compact ? 64 : 76 * scale,
                        child: TextButton(
                          onPressed: toolsEnabled
                              ? () => openCrop(initialRatio: c.$2)
                              : null,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.only(top: 7),
                            foregroundColor: selected == c.$2
                                ? _editorYellow
                                : const Color(0xc9ffffff),
                            textStyle: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CropRatioIcon(
                                c.$2,
                                color: selected == c.$2
                                    ? _editorYellow
                                    : const Color(0xc9ffffff),
                              ),
                              const SizedBox(height: 5),
                              Text(c.$1, maxLines: 1),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          Row(
            children: [
              action(
                '旋转 90°',
                HueIconKind.rotate,
                () => change(() {
                  geometry.addAll({
                    'turns': (turns + 1) % 4,
                    'left': 0,
                    'top': 0,
                    'right': 1000000,
                    'bottom': 1000000,
                  });
                  if (selected != null && selected > 0) {
                    final normalized = selected * frameRatio;
                    final w = normalized < 1 ? normalized : 1.0,
                        h = (normalized < 1 ? normalized : 1.0) / normalized;
                    geometry.addAll({
                      'left': ((1 - w) * 500000).round(),
                      'top': ((1 - h) * 500000).round(),
                      'right': ((1 + w) * 500000).round(),
                      'bottom': ((1 + h) * 500000).round(),
                    });
                  }
                  recipe.data['geometry'] = geometry;
                }),
              ),
              action(
                '水平翻转',
                HueIconKind.flipHorizontal,
                () => change(() {
                  geometry.addAll({
                    'mirrored': geometry['mirrored'] != true,
                    'left': 1000000 - right,
                    'right': 1000000 - left,
                  });
                  recipe.data['geometry'] = geometry;
                }),
              ),
              action(
                '重置',
                HueIconKind.refresh,
                () => change(() => recipe.data.remove('geometry')),
                enabled: !neutral,
              ),
            ],
          ),
          SizedBox(
            height: 40 * scale,
            width: double.infinity,
            child: Tooltip(
              message: '切换比例预览居中裁切，点击打开精细裁切、拉直与透视',
              child: InkWell(
                onTap: toolsEnabled ? openCrop : null,
                child: const Center(
                  child: Text(
                    '选择比例，拖动选框或双指缩放',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: Color(0xbdffffff)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> loadAtmosphere(String image) async {
    atmosphereLoading = true;
    String? original;
    try {
      final neutral = await widget.state.core.call('media.originalPreview', {
        'path': widget.photo.path,
        'owner': owner,
      });
      original = neutral['path'] as String;
      final result = await widget.state.core.call('media.atmosphere', {
        'path': original,
        'owner': owner,
      });
      if (!mounted) {
        await discardPreview(result['path']);
      } else {
        refreshWorkspace(() => atmosphere = result['path'] as String);
      }
    } catch (_) {
      // The bounded atmosphere is decorative; the photograph remains usable.
    } finally {
      if (original != null && original != preview) {
        await discardPreview(original);
      }
      atmosphereLoading = false;
    }
  }

  Widget backdrop() => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: Color(0xff242b27)),
      if (atmosphere != null)
        Image.file(
          File(atmosphere!),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => const SizedBox(),
        ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x8917221e), Color(0x2b15211d), Color(0x9e131b1b)],
            stops: [0, .48, 1],
          ),
        ),
      ),
    ],
  );

  Widget editorButton(
    HueIconKind kind,
    String label,
    VoidCallback? action, {
    bool disk = true,
  }) => Semantics(
    button: true,
    label: label,
    enabled: action != null,
    child: Tooltip(
      message: label,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: Material(
            color: disk ? const Color(0x9c101412) : Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: action,
              child: SizedBox(
                width: disk ? 36 : 48,
                height: disk ? 36 : 48,
                child: Center(
                  child: HueIcon(
                    kind,
                    size: 19,
                    color: action == null
                        ? _editorWhite.withValues(alpha: .3)
                        : _editorWhite,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> history(bool forward) async {
    if (!toolsEnabled || (forward ? redo : undo).isEmpty) return;
    debounce?.cancel();
    revision++;
    refreshWorkspace(() => managingTools = true);
    try {
      await settleLocalAdjustments();
      if (!mounted || !sameOwner) return;
      final source = forward ? redo : undo;
      (forward ? undo : redo).add(recipe.clone());
      final next = source.removeLast();
      refreshWorkspace(() {
        recipe = next;
        compare = false;
      });
      await reloadLocalState();
      panelRevision.value++;
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) {
        refreshWorkspace(() => managingTools = false);
        unawaited(render());
      }
    }
  }

  Future<void> openLinkedRaw() async {
    if (!toolsEnabled) return;
    debounce?.cancel();
    revision++;
    refreshWorkspace(() => managingTools = true);
    try {
      await settleLocalAdjustments();
      if (activeJob != null) await widget.state.core.cancel(activeJob!);
      if (!mounted || !sameOwner) return;
      await saveDraft();
      if (!mounted || !sameOwner) return;
      final source = widget.photo.info['rawSource'];
      if (source is! String || source.isEmpty) {
        throw const AppFailure('原始 RAW 来源不可用，请返回相册重新选择。');
      }
      final expected = widget.photo.info['rawSourceSha'];
      final inspected = await widget.state.core.call('source.inspect', {
        'owner': owner,
        'path': source,
        if (expected is String && expected.isNotEmpty)
          'expectedSourceSha': expected,
      });
      if (!mounted || !sameOwner) return;
      if (!const {
            'NEF',
            'NRW',
            'DNG',
            'ARW',
            'CR2',
            'CR3',
            'RAF',
            'RW2',
            'ORF',
            'PEF',
            'SRW',
          }.contains(inspected['format']) ||
          (expected is String &&
              expected.isNotEmpty &&
              inspected['sourceSha'] != expected)) {
        throw const AppFailure('原始 RAW 已改变或不可用，请返回相册重新核对。');
      }
      final matches = widget.state.photos.where(
        (photo) => photo.path == source,
      );
      final raw = matches.isNotEmpty
          ? matches.first
          : Photo(source, p.basename(source), {'raw': true});
      bool current() =>
          mounted && sameOwner && widget.photo.info['rawSource'] == source;
      await hueRootPage<void>(
        context,
        MaterialPageRoute(
          builder: (_) => RawDevelopPage(
            state: widget.state,
            photo: raw,
            isCurrent: current,
          ),
        ),
      );
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) {
        refreshWorkspace(() => managingTools = false);
        unawaited(render());
      }
    }
  }

  Widget editorHeader() => SizedBox(
    height:
        56 + (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 1) * 16,
    child: Padding(
      padding: const EdgeInsets.only(left: 14, right: 19),
      child: Row(
        children: [
          EditorHeaderButton(
            icon: HueIconKind.close,
            label: '返回相册',
            onPressed: leaveEditor,
          ),
          Builder(
            builder: (anchor) => EditorHeaderButton(
              icon: HueIconKind.more,
              label: '更多照片操作和重置',
              onPressed: toolsEnabled ? () => editorOptions(anchor) : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Builder(
              builder: (anchor) => GestureDetector(
                onTap: toolsEnabled ? () => editorOptions(anchor) : null,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    EditorMiddleTitle(
                      sameOwner ? widget.photo.name : '账号已改变',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _editorWhite,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sameOwner
                          ? photoEditorFormatLabel(
                              filePath: widget.photo.path,
                              name: widget.photo.name,
                              rawSourcePath:
                                  widget.photo.info['rawSource'] as String?,
                            )
                          : '请返回相册',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xbeffffff),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: _editorYellow,
                  foregroundColor: const Color(0xff191e17),
                  disabledBackgroundColor: _editorYellow.withValues(alpha: .4),
                  minimumSize: Size.zero,
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onPressed: toolsEnabled && preview != null ? export : null,
                child: const Text('导出'),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget photoViewport({
    String? heldComparison,
    bool showCompareButton = true,
  }) => Stack(
    fit: StackFit.expand,
    children: [
      if (preview != null)
        SplitCompare(
          effect: heldComparison ?? preview!,
          original: comparison,
          enabled: heldComparison == null && compare,
          warning:
              histogram.visible &&
                  histogram.warningCurrent &&
                  !histogram.updating &&
                  displayedRevision == revision
              ? histogram.warning
              : null,
          warningRect: histogramContentRect,
          warningCorner:
              (object(recipe.data['border'] ?? {})['template'] as int? ?? 0) < 3
              ? .025 *
                    (object(recipe.data['border'] ?? {})['corner'] as num? ??
                        100) /
                    100
              : 0,
          selection: regionLayer,
          selectionSize:
              displayedOverlay == null ||
                  displayedOverlay!['outputWidth'] is! num ||
                  displayedOverlay!['outputHeight'] is! num
              ? null
              : Size(
                  (displayedOverlay!['outputWidth'] as num).toDouble(),
                  (displayedOverlay!['outputHeight'] as num).toDouble(),
                ),
          onRetry: render,
        )
      else if (sameOwner)
        const Center(child: CircularProgressIndicator(color: _editorYellow)),
      if (canShowRegionLayer)
        Positioned(
          right: 72,
          bottom: 12,
          child: WorkspaceTool(
            icon: 'eye',
            selected: regionLayerVisible,
            tooltip: regionLayerVisible ? '隐藏选区，保留调整' : '显示选区',
            onPressed: () {
              refreshWorkspace(() => regionLayerVisible = !regionLayerVisible);
              unawaited(refreshRegionLayer());
            },
          ),
        ),
      if (showCompareButton)
        Positioned(
          top: 9,
          right: 9,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Material(
              color: const Color(0x9c101412),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: compare ? '显示效果' : '对比原图',
                onPressed: toolsEnabled && widget.photo.info['raw'] != true
                    ? () {
                        refreshWorkspace(() => compare = !compare);
                        revision++;
                        debounce?.cancel();
                        unawaited(render());
                      }
                    : null,
                icon: const HueIcon(
                  HueIconKind.splitCompare,
                  size: 21,
                  color: _editorWhite,
                ),
              ),
            ),
          ),
        ),
      if (rendering || exporting || analyzingCleanup)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: LinearProgressIndicator(
            value: progress > 0 ? progress : null,
            minHeight: 2,
            color: _editorYellow,
            backgroundColor: Colors.transparent,
          ),
        ),
      if (error != null)
        Positioned(
          bottom: 6,
          left: 20,
          right: 20,
          child: Material(
            color: const Color(0xd9262925),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    error!,
                    style: const TextStyle(color: _editorWhite, fontSize: 12),
                  ),
                  TextButton(
                    onPressed: toolsEnabled ? render : null,
                    child: const Text('重试预览'),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Widget historyBar() => SizedBox(
    height: 48,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          editorButton(
            HueIconKind.undo,
            '撤销',
            toolsEnabled && undo.isNotEmpty ? () => history(false) : null,
            disk: false,
          ),
          editorButton(
            HueIconKind.redo,
            '重做',
            toolsEnabled && redo.isNotEmpty ? () => history(true) : null,
            disk: false,
          ),
          Expanded(
            child: Center(
              child: Text(
                recipe.data['presetId'] == ''
                    ? '原图'
                    : '${recipe.data['presetName']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _editorWhite, fontSize: 11),
              ),
            ),
          ),
          editorButton(
            HueIconKind.refresh,
            '恢复原图',
            toolsEnabled ? resetPhoto : null,
          ),
        ],
      ),
    ),
  );

  void selectWorkspaceMode(int next) {
    if (!toolsEnabled) return;
    if (next == 8) {
      unawaited(openRetouch());
      return;
    }
    refreshWorkspace(() => tab = next);
  }

  Widget modeStrip(double scale) => SizedBox(
    height: 67 * scale,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          for (final entry in [
            (0, '滤镜', HueIconKind.filter),
            (1, '调节', HueIconKind.adjust),
            (3, '裁切', HueIconKind.crop),
            (8, '人像', HueIconKind.person),
            (4, '边框', HueIconKind.frame),
          ])
            Expanded(
              child: Semantics(
                container: true,
                excludeSemantics: true,
                button: true,
                selected: tab == entry.$1,
                label: entry.$2,
                onTap: toolsEnabled
                    ? () => selectWorkspaceMode(entry.$1)
                    : null,
                child: InkWell(
                  onTap: toolsEnabled
                      ? () => selectWorkspaceMode(entry.$1)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Column(
                      children: [
                        Container(
                          width: 39,
                          height: 39,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: tab == entry.$1
                                ? const Color(0xe6111713)
                                : const Color(0x9c101412),
                          ),
                          child: Center(
                            child: HueIcon(
                              entry.$3,
                              size: 21,
                              color: tab == entry.$1
                                  ? _editorYellow
                                  : _editorWhite,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 20 * scale,
                          child: Center(
                            child: Transform.translate(
                              offset: const Offset(0, -1),
                              child: Text(
                                entry.$2,
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.17,
                                  color: tab == entry.$1
                                      ? _editorYellow
                                      : _editorWhite,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget adjustmentDock(double scale, bool compact) {
    final parameters = (widget.state.core.schema['parameters'] as List)
        .map(object)
        .toList();
    final parameter = parameters.firstWhere(
      (row) => row['index'] == parameterIndex,
    );
    final value = adjustmentRecipe.values[parameterIndex];
    final label = parameter['label'] as String;
    final readout = parameterIndex == 1
        ? '${value >= 0 ? '+' : ''}${(value / 10).toStringAsFixed(1)} EV'
        : '${value > 0 ? '+' : ''}$value';
    final ordered = [
      1,
      2,
      9,
      7,
      -5,
      -6,
      -2,
      -7,
      -8,
      -9,
      ...parameters
          .map((row) => row['index'] as int)
          .where((index) => ![1, 2, 9, 7].contains(index)),
    ];
    const special = {
      -5: '曲线',
      -6: 'HSL',
      -2: '调色盘',
      -7: '去灰',
      -8: '局部',
      -9: '修补',
    };
    return Column(
      children: [
        SizedBox(
          height: 30 * scale,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 21),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: toolsEnabled ? () => parameterHelp(parameter) : null,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        selectedRegionId == null
                            ? label
                            : '$label · $adjustmentScope',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _editorWhite,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: '点击输入数值，长按查看参数说明',
                  child: InkWell(
                    onTap: toolsEnabled
                        ? () => exactParameter(parameter)
                        : null,
                    onLongPress: toolsEnabled
                        ? () => parameterHelp(parameter)
                        : null,
                    child: Center(
                      child: Text(
                        readout,
                        style: const TextStyle(
                          fontSize: 12,
                          color: _editorYellow,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.only(left: 24, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      activeTrackColor: _editorYellow,
                      inactiveTrackColor: const Color(0x66ffffff),
                      thumbColor: Colors.white,
                      overlayColor: const Color(0x22ffe335),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                        elevation: 0,
                        pressedElevation: 0,
                      ),
                      trackShape: const RectangularSliderTrackShape(),
                      padding: EdgeInsets.zero,
                    ),
                    child: Slider(
                      min: (parameter['min'] as num).toDouble(),
                      max: (parameter['max'] as num).toDouble(),
                      value: value.toDouble(),
                      onChangeStart: toolsEnabled
                          ? (_) {
                              beginParameterGesture();
                              checkpoint();
                            }
                          : null,
                      onChangeEnd: (_) => endParameterGesture(),
                      onChanged: toolsEnabled
                          ? (next) => changeAdjustment(
                              () => adjustmentRecipe.setValue(
                                parameterIndex,
                                next.round(),
                              ),
                              snapshot: false,
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                KeyedSubtree(
                  key: scopeAnchor,
                  child: editorButton(
                    HueIconKind.brush,
                    '调节范围：$adjustmentScope',
                    toolsEnabled ? showRegionScope : null,
                    disk: false,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!compact) SizedBox(height: 12 * scale),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                for (final index in ordered)
                  SizedBox(
                    width: 98 * scale,
                    child: Semantics(
                      button: true,
                      selected: index == parameterIndex,
                      label: index < 0
                          ? special[index]
                          : parameters[index]['label'] as String,
                      child: InkWell(
                        onTap: toolsEnabled
                            ? () {
                                if (index < 0) {
                                  if (index == -8) {
                                    editSelection();
                                  } else if (index == -9) {
                                    unawaited(openRetouch(patch: true));
                                  } else {
                                    advancedTool(-index);
                                  }
                                } else {
                                  refreshWorkspace(
                                    () => parameterIndex = index,
                                  );
                                }
                              }
                            : null,
                        onLongPress: toolsEnabled && index >= 0
                            ? () => changeAdjustment(
                                () => adjustmentRecipe.setValue(index, 0),
                              )
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            children: [
                              HueIcon(
                                index < 0
                                    ? editorAdvancedToolIcon(index)
                                    : parameterIcon(
                                        parameters[index]['name'] as String,
                                      ),
                                size: 26,
                                color: index == parameterIndex
                                    ? _editorYellow
                                    : const Color(0x99ffffff),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                index < 0
                                    ? special[index]!
                                    : parameters[index]['label'] as String,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: index == parameterIndex
                                      ? _editorYellow
                                      : const Color(0x99ffffff),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(
          height: 22 * scale,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 21),
              child: Text(
                '长按参数图标，恢复此项',
                style: const TextStyle(fontSize: 10, color: _editorMuted),
              ),
            ),
          ),
        ),
      ],
    );
  }

  HueIconKind parameterIcon(String name) => editorParameterIcon(name);

  Future<void> advancedTool(int page) async {
    if (page == 0) {
      await openFilterPicker();
    } else if ({2, 5, 6, 7}.contains(page)) {
      await advancedColorTool(page);
    }
  }

  Widget borderDock() => BorderPanel(
    state: widget.state,
    photo: widget.photo,
    owner: owner,
    recipe: recipe.data,
    enabled: toolsEnabled,
    canUndo: undo.isNotEmpty,
    canRedo: redo.isNotEmpty,
    onUndo: () => history(false),
    onRedo: () => history(true),
    onDragStart: checkpoint,
    onChanged: (border, snapshot) =>
        change(() => recipe.data['border'] = border, snapshot: snapshot),
  );

  ThemeData get workspaceTheme =>
      hueviaTheme(Brightness.dark, home: false).copyWith(
        brightness: Brightness.dark,
        canvasColor: const Color(0xff292724),
        cardColor: const Color(0xff292724),
        iconTheme: const IconThemeData(color: _editorWhite),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _editorYellow,
            foregroundColor: const Color(0xff191e17),
            minimumSize: const Size(48, 48),
            shape: const StadiumBorder(),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _editorWhite,
            backgroundColor: const Color(0x9c101412),
            side: BorderSide.none,
            minimumSize: const Size(48, 48),
            shape: const StadiumBorder(),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: _editorWhite,
            minimumSize: const Size(48, 48),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xff33302c),
          labelStyle: const TextStyle(color: _editorMuted),
          hintStyle: const TextStyle(color: _editorMuted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xff4c4640)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xff4c4640)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _editorYellow),
          ),
        ),
        colorScheme: const ColorScheme.dark(
          primary: _editorYellow,
          onPrimary: Color(0xff191e17),
          surface: Color(0xff292724),
          onSurface: _editorWhite,
          secondary: _editorYellow,
        ),
        textTheme: Theme.of(context).textTheme
            .apply(bodyColor: _editorWhite, displayColor: _editorWhite),
        sliderTheme: SliderTheme.of(context).copyWith(
          activeTrackColor: _editorYellow,
          inactiveTrackColor: const Color(0x66ffffff),
          thumbColor: Colors.white,
          trackHeight: 2,
          thumbShape: const RoundSliderThumbShape(
            enabledThumbRadius: 7,
            elevation: 0,
            pressedElevation: 0,
          ),
        ),
        scaffoldBackgroundColor: Colors.transparent,
      );

  Widget legacyWorkspace(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final compact =
        MediaQuery.sizeOf(context).width < 600 &&
        MediaQuery.sizeOf(context).height < 720;
    final theme = workspaceTheme;
    return Theme(
      data: theme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              backdrop(),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    Widget dock() => SizedBox(
                      height: tab == 9
                          ? (compact ? 160.0 : 184 * scale)
                                .clamp(120 + 22 * scale, double.infinity)
                                .toDouble()
                          : compact
                          ? 160
                          : 184 * scale,
                      child: tab == 9
                          ? quickDock()
                          : tab == 1
                          ? adjustmentDock(scale, compact)
                          : tab == 0
                          ? filterDock()
                          : tab == 4
                          ? borderDock()
                          : tab == 3
                          ? compositionDock(scale, compact)
                          : SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: controls(),
                            ),
                    );
                    final horizontal = bounds.maxWidth > bounds.maxHeight;
                    return Column(
                      children: [
                        editorHeader(),
                        Expanded(
                          child: horizontal
                              ? Row(
                                  children: [
                                    Expanded(child: photoViewport()),
                                    SizedBox(
                                      width: bounds.maxWidth * .46,
                                      child: SingleChildScrollView(
                                        child: Column(
                                          children: [
                                            if (histogram.visible)
                                              histogramPanel(),
                                            historyBar(),
                                            modeStrip(scale),
                                            dock(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  children: [
                                    Expanded(child: photoViewport()),
                                    if (histogram.visible) histogramPanel(),
                                    historyBar(),
                                    modeStrip(scale),
                                    dock(),
                                  ],
                                ),
                        ),
                        if (exporting)
                          TextButton(
                            onPressed: () {
                              if (activeJob != null) {
                                widget.state.core.cancel(activeJob!);
                              }
                            },
                            child: Text('取消导出 ${(progress * 100).round()}%'),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
