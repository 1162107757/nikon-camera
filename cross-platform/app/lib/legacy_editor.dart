part of 'editor.dart';

const _editorYellow = Color(0xffffe335);
const _editorWhite = Color(0xfff4f5f7);
const _editorMuted = Color(0xffc8cdca);

extension _LegacyWorkspace on _EditorPageState {
  bool get toolsEnabled =>
      restored && !exporting && !managingTools && !analyzingCleanup;

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

  void history(bool forward) {
    if (!toolsEnabled || (forward ? redo : undo).isEmpty) return;
    final source = forward ? redo : undo;
    (forward ? undo : redo).add(recipe.clone());
    final next = source.removeLast();
    change(() => recipe = next, snapshot: false);
  }

  Future<void> editorOptions() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      backgroundColor: const Color(0xff292724),
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in [
              ('recipes', '我的配方'),
              ('copy', '复制当前调节'),
              ('versions', '成品版本'),
              if (widget.photo.info['rawSource'] is String) ('raw', 'RAW 显影'),
              ('reset', '恢复原图'),
            ])
              ListTile(
                title: Text(
                  entry.$2,
                  style: const TextStyle(color: _editorWhite),
                ),
                onTap: () => Navigator.pop(sheet, entry.$1),
              ),
          ],
        ),
      ),
    );
    if (!mounted || value == null) return;
    if (value == 'reset') {
      change(() => recipe = Recipe());
    } else if (value == 'raw') {
      final source = widget.photo.info['rawSource'] as String;
      final matches = widget.state.photos.where(
        (photo) => photo.path == source,
      );
      final raw = matches.isNotEmpty
          ? matches.first
          : Photo(source, p.basename(source), const {'raw': true});
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => RawDevelopPage(state: widget.state, photo: raw),
        ),
      );
    } else {
      await openTool(
        copying: value == 'copy',
        savedVersions: value == 'versions',
      );
    }
  }

  Widget editorHeader() => SizedBox(
    height:
        56 + (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(0, 1) * 16,
    child: Padding(
      padding: const EdgeInsets.only(left: 14, right: 19),
      child: Row(
        children: [
          editorButton(
            HueIconKind.close,
            '关闭编辑',
            () => Navigator.maybePop(context),
          ),
          editorButton(
            HueIconKind.more,
            '编辑选项',
            toolsEnabled ? editorOptions : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: toolsEnabled ? editorOptions : null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.photo.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _editorWhite,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${p.extension(widget.photo.info['rawSource'] as String? ?? widget.photo.name).replaceFirst('.', '').toUpperCase()} · 编辑照片',
                    style: const TextStyle(
                      fontSize: 10,
                      color: _editorMuted,
                      height: 1.3,
                    ),
                  ),
                ],
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
                  textStyle: const TextStyle(fontSize: 13),
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

  Widget photoViewport() => Stack(
    fit: StackFit.expand,
    children: [
      if (preview != null)
        SplitCompare(
          effect: preview!,
          original: comparison,
          enabled: compare,
          onRetry: render,
        )
      else
        const Center(child: CircularProgressIndicator(color: _editorYellow)),
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
            toolsEnabled ? () => change(() => recipe = Recipe()) : null,
          ),
        ],
      ),
    ),
  );

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
                    ? () => refreshWorkspace(() => tab = entry.$1)
                    : null,
                child: InkWell(
                  onTap: toolsEnabled
                      ? () => refreshWorkspace(() => tab = entry.$1)
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
    final value = recipe.values[parameterIndex];
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
      ...parameters
          .map((row) => row['index'] as int)
          .where((index) => ![1, 2, 9, 7].contains(index)),
    ];
    const special = {-5: '曲线', -6: 'HSL', -2: '调色盘', -7: '去灰'};
    return Column(
      children: [
        SizedBox(
          height: 30 * scale,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 21),
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: _editorWhite),
                ),
                const Spacer(),
                Text(
                  readout,
                  style: const TextStyle(
                    fontSize: 12,
                    color: _editorYellow,
                    fontWeight: FontWeight.bold,
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
                      onChangeStart: toolsEnabled ? (_) => checkpoint() : null,
                      onChanged: toolsEnabled
                          ? (next) => change(
                              () =>
                                  recipe.setValue(parameterIndex, next.round()),
                              snapshot: false,
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                editorButton(
                  HueIconKind.brush,
                  '$label说明',
                  () => showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(label),
                      content: Text(parameter['help'] as String),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('知道了'),
                        ),
                      ],
                    ),
                  ),
                  disk: false,
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
                                  advancedTool(-index);
                                } else {
                                  refreshWorkspace(
                                    () => parameterIndex = index,
                                  );
                                }
                              }
                            : null,
                        onLongPress: toolsEnabled && index >= 0
                            ? () => change(() => recipe.setValue(index, 0))
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            children: [
                              HueIcon(
                                index < 0
                                    ? {
                                        -5: HueIconKind.curve,
                                        -6: HueIconKind.saturation,
                                        -2: HueIconKind.palette,
                                        -7: HueIconKind.cleanup,
                                      }[index]!
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

  HueIconKind parameterIcon(String name) => switch (name) {
    'EXPOSURE' || 'BRIGHTNESS' => HueIconKind.exposure,
    'CONTRAST' || 'WHITES' || 'BLACKS' => HueIconKind.contrast,
    'SATURATION' => HueIconKind.saturation,
    'TEMPERATURE' => HueIconKind.temperature,
    _ => HueIconKind.adjust,
  };

  Future<void> advancedTool(int page) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xff292724),
      builder: (sheet) => Theme(
        data: workspaceTheme,
        child: ValueListenableBuilder<int>(
          valueListenable: panelRevision,
          builder: (_, _, _) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheet).height * .75,
              child: Column(
                children: [
                  ListTile(
                    title: Text(
                      {
                            0: '全部滤镜',
                            2: '调色盘',
                            5: '曲线',
                            6: 'HSL',
                            7: '自动去灰',
                          }[page] ??
                          '调节',
                      style: const TextStyle(color: _editorWhite),
                    ),
                    trailing: IconButton(
                      tooltip: '完成',
                      icon: const HueIcon(
                        HueIconKind.check,
                        color: _editorYellow,
                      ),
                      onPressed: () => Navigator.pop(sheet),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [controls(tool: page)],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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

  Widget filterDock() => Column(
    children: [
      SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Text(
                '我的',
                style: TextStyle(fontSize: 11, color: _editorYellow),
              ),
              const SizedBox(width: 18),
              const Text(
                '全部',
                style: TextStyle(fontSize: 11, color: _editorWhite),
              ),
              const Spacer(),
              editorButton(
                HueIconKind.presets,
                '查看全部滤镜',
                () => advancedTool(0),
                disk: false,
              ),
            ],
          ),
        ),
      ),
      Expanded(
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          children: [
            for (final preset in <Preset?>[null, ...widget.state.presets])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 68,
                  child: InkWell(
                    onTap: toolsEnabled
                        ? () => change(() {
                            recipe.data['presetId'] = preset?.id ?? '';
                            recipe.data['presetName'] = preset?.name ?? '无滤镜';
                            recipe.data['strength'] = 100;
                          })
                        : null,
                    child: Column(
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(9),
                              border:
                                  recipe.data['presetId'] == (preset?.id ?? '')
                                  ? Border.all(color: const Color(0xffbbb9a1))
                                  : null,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: preview == null
                                  ? const SizedBox.expand()
                                  : Image.file(
                                      File(preview!),
                                      width: 68,
                                      fit: BoxFit.cover,
                                      cacheWidth: 160,
                                      excludeFromSemantics: true,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          preset?.name ?? '原图',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: _editorWhite,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 21),
          child: Row(
            children: [
              const Text(
                '强度',
                style: TextStyle(fontSize: 11, color: _editorWhite),
              ),
              Expanded(
                child: Slider(
                  min: 0,
                  max: 100,
                  value: (recipe.data['strength'] as num).toDouble(),
                  onChangeStart: toolsEnabled ? (_) => checkpoint() : null,
                  onChanged: toolsEnabled
                      ? (value) => change(
                          () => recipe.data['strength'] = value.round(),
                          snapshot: false,
                        )
                      : null,
                ),
              ),
              Text(
                '${recipe.data['strength']}',
                style: const TextStyle(fontSize: 11, color: _editorWhite),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  ThemeData get workspaceTheme => Theme.of(context).copyWith(
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
                      height: compact ? 160 : 184 * scale,
                      child: tab == 1
                          ? adjustmentDock(scale, compact)
                          : tab == 0
                          ? filterDock()
                          : tab == 4
                          ? borderDock()
                          : SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: tab == 8
                                  ? const Padding(
                                      padding: EdgeInsets.only(top: 16),
                                      child: Text(
                                        '人像精修',
                                        style: TextStyle(color: _editorWhite),
                                      ),
                                    )
                                  : controls(),
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
