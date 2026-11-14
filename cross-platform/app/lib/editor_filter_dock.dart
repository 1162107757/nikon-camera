part of 'editor.dart';

// PhotoFilterEditor / PhotoPresetSourceTabs: browsing never edits the recipe.
final _legacyFilterWindows = Expando<_LegacyFilterWindow>();

class _LegacyFilterWindow {
  bool open = false;
  double pickerOffset = 0;
}

extension _LegacyFilterWorkspace on _EditorPageState {
  Widget filterDock() => _LegacyFilterDock(editor: this);

  Future<void> openFilterPicker() async {
    if (!toolsEnabled) return;
    final window = _legacyFilterWindows[this] ??= _LegacyFilterWindow();
    if (window.open) return;
    window.open = true;
    ModalRoute<dynamic>? pickerRoute;
    try {
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: .35),
        builder: (context) {
          pickerRoute = ModalRoute.of(context);
          return _LegacyFilterPicker(editor: this, window: window);
        },
      );
      // A second opening must not share the outgoing route's listeners/owner.
      await pickerRoute?.completed;
    } finally {
      window.open = false;
    }
  }

  List<Preset> get _sourceFilters =>
      onlineFilters ? filters.online : widget.state.presets;

  String _filterCategoryLabel(Preset preset) =>
      preset.category.isEmpty ? '未分类' : preset.category;

  List<String> get _filterCategories {
    final present = _sourceFilters.map(_filterCategoryLabel).toSet();
    return [
      '',
      for (final name in ['人像', '风景', '胶片', '黑白', '日常', '夜景'])
        if (present.remove(name)) name,
      ...present.where((name) => name.isNotEmpty && name != '未分类'),
      if (present.contains('未分类')) '未分类',
    ];
  }

  String get _currentFilterCategory =>
      _filterCategories.contains(filterCategory) ? filterCategory : '';

  void _browseFilters({bool? online, String? category}) {
    if (!toolsEnabled) return;
    if (online == onlineFilters || category == filterCategory) return;
    _legacyFilterWindows[this]?.pickerOffset = 0;
    refreshWorkspace(() {
      if (online != null && online != onlineFilters) {
        onlineFilters = online;
        filterCategory = '';
      } else if (category != null) {
        filterCategory = category;
      }
    });
    panelRevision.value++;
  }

  String get _filterStatus => preparingFilter
      ? '准备'
      : onlineFilters && filters.loading
      ? '加载'
      : onlineFilters && filters.error != null
      ? '重试'
      : onlineFilters && filters.notice.isNotEmpty
      ? '缓存'
      : onlineFilters && filters.online.isEmpty
      ? '暂无'
      : '';

  String get _filterStatusDetail => preparingFilter
      ? '正在准备滤镜'
      : filters.loading
      ? '正在加载在线滤镜'
      : filters.error != null
      ? '在线滤镜加载失败：${filters.error}，轻点重试'
      : filters.notice.isEmpty && filters.online.isEmpty
      ? '在线暂无滤镜，轻点刷新'
      : filters.notice;

  Future<void> _exactFilterStrength() async {
    if (!toolsEnabled || (recipe.data['presetId'] as String).isEmpty) return;
    final input = TextEditingController(text: '${recipe.data['strength']}');
    int? parsed() {
      final value = int.tryParse(input.text.trim());
      return value != null && value >= 0 && value <= 100 ? value : null;
    }

    var answered = false;
    try {
      final value = await hueDialog<int>(
        context: context,
        builder: (dialog) {
          void finish([int? value]) {
            if (answered || ModalRoute.of(dialog)?.isCurrent != true) return;
            answered = true;
            Navigator.pop(dialog, value);
          }

          return AlertDialog(
            title: const Text('强度'),
            content: TextField(
              controller: input,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: '0–100'),
              onSubmitted: (_) {
                if (parsed() != null) finish(parsed());
              },
            ),
            actions: [
              TextButton(onPressed: finish, child: const Text('取消')),
              TextButton(
                onPressed: () {
                  if (parsed() != null) finish(parsed());
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      );
      if (value != null &&
          mounted &&
          toolsEnabled &&
          value != recipe.data['strength']) {
        change(() => recipe.data['strength'] = value);
      }
    } finally {
      input.dispose();
    }
  }
}

class _LegacyFilterDock extends StatefulWidget {
  const _LegacyFilterDock({required this.editor});
  final _EditorPageState editor;
  @override
  State<_LegacyFilterDock> createState() => _LegacyFilterDockState();
}

class _LegacyFilterDockState extends State<_LegacyFilterDock> {
  final strip = ScrollController();
  bool? lastSource;
  String? lastCategory;

  @override
  void dispose() {
    strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = widget.editor;
    final media = MediaQuery.of(context);
    final compact = media.size.width < 600 && media.size.height < 720;
    final scale = media.textScaler.scale(1).clamp(1.0, 2.0);
    final category = editor._currentFilterCategory;
    if (lastSource != editor.onlineFilters || lastCategory != category) {
      lastSource = editor.onlineFilters;
      lastCategory = category;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && strip.hasClients) strip.jumpTo(0);
      });
    }
    final available = editor._sourceFilters
        .where(
          (preset) =>
              category.isEmpty ||
              editor._filterCategoryLabel(preset) == category,
        )
        .toList();
    final rows = available.take(24).toList();
    final selected = editor.recipe.data['presetId'];
    if (available.length > 24 &&
        !rows.any((item) => editor.filters.identity(item) == selected)) {
      final chosen = available.where(
        (item) => editor.filters.identity(item) == selected,
      );
      if (chosen.isNotEmpty) rows[23] = chosen.first;
    }
    final base = editor.recipe.clone().data
      ..['presetId'] = ''
      ..['presetName'] = ''
      ..['strength'] = 0;
    final canAdjust = editor.toolsEnabled && (selected as String).isNotEmpty;
    return Column(
      key: const ValueKey('legacy-filter-dock'),
      children: [
        SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _LegacyFilterSources(
                  online: editor.onlineFilters,
                  enabled: editor.toolsEnabled,
                  onChanged: (online) => editor._browseFilters(online: online),
                ),
                SizedBox(
                  width:
                      editor._filterStatus.isNotEmpty &&
                          media.orientation == Orientation.portrait
                      ? 42
                      : 0,
                  child:
                      editor._filterStatus.isNotEmpty &&
                          media.orientation == Orientation.portrait
                      ? _LegacyFilterStatus(editor: editor)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _LegacyFilterCategories(
                    categories: editor._filterCategories,
                    selected: category,
                    enabled: editor.toolsEnabled,
                    onChanged: (value) =>
                        editor._browseFilters(category: value),
                  ),
                ),
                Tooltip(
                  message: '查看全部滤镜',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const ValueKey('filter-view-all'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: editor.toolsEnabled
                          ? editor.openFilterPicker
                          : null,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0x33ffffff),
                              ),
                            ),
                            child: const Center(
                              child: HueIcon(
                                HueIconKind.presets,
                                size: 19,
                                color: _editorWhite,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, bounds) {
              final desired = compact ? 59.0 : 83 * scale;
              final cardHeight = desired.clamp(0.0, bounds.maxHeight);
              return ListView.builder(
                key: ValueKey('filter-strip-${editor.onlineFilters}-$category'),
                controller: strip,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: rows.length + 1,
                itemBuilder: (context, index) {
                  final preset = index == 0 ? null : rows[index - 1];
                  return Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Center(
                      child: SizedBox(
                        width: compact ? 66 : 66 * scale,
                        height: cardHeight,
                        child: _LegacyFilterCard(
                          editor: editor,
                          preset: preset,
                          recipe: base,
                          large: false,
                          compact: compact,
                          onTap: editor.toolsEnabled
                              ? () => editor.selectFilter(preset)
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const SizedBox(
                  width: 38,
                  child: Text(
                    '强度',
                    style: TextStyle(fontSize: 11, color: _editorWhite),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: _editorYellow,
                      inactiveTrackColor: const Color(0x66ffffff),
                      thumbColor: Colors.white,
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 16,
                      ),
                    ),
                    // A disabled Slider changes its internal render ancestry.
                    // Recreate that state rather than reparenting it underneath
                    // a blocking route (Flutter issue #193706).
                    child: KeyedSubtree(
                      key: ValueKey('filter-strength-enabled-$canAdjust'),
                      child: Slider(
                        key: const ValueKey('filter-strength'),
                        min: 0,
                        max: 100,
                        value: (editor.recipe.data['strength'] as num)
                            .toDouble()
                            .clamp(0, 100),
                        onChangeStart: canAdjust
                            ? (_) {
                                editor.beginParameterGesture();
                                editor.checkpoint();
                              }
                            : null,
                        onChanged: canAdjust
                            ? (value) => editor.change(
                                () => editor.recipe.data['strength'] = value
                                    .round(),
                                snapshot: false,
                              )
                            : null,
                        onChangeEnd: (_) => editor.endParameterGesture(),
                      ),
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: '强度，${editor.recipe.data['strength']}，点击输入数值',
                  child: InkWell(
                    onTap: canAdjust ? editor._exactFilterStrength : null,
                    child: SizedBox(
                      width: 46,
                      height: 48,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${editor.recipe.data['strength']}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: _editorWhite,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LegacyFilterSources extends StatelessWidget {
  const _LegacyFilterSources({
    required this.online,
    required this.enabled,
    required this.onChanged,
  });
  final bool online, enabled;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final width = 104 * (scale / 1.3).clamp(1.0, 2.0);
    final trackHeight = (12 * scale + 16).clamp(32.0, 46.0);
    return SizedBox(
      key: const ValueKey('filter-source-tabs'),
      width: width,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: trackHeight,
            decoration: BoxDecoration(
              color: const Color(0x18ffffff),
              border: Border.all(color: const Color(0x66ffffff)),
              borderRadius: BorderRadius.circular(trackHeight / 2),
            ),
          ),
          Positioned(
            left: online ? width / 2 : 3,
            right: online ? 3 : width / 2,
            top: (48 - trackHeight) / 2 + 3,
            bottom: (48 - trackHeight) / 2 + 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _editorWhite,
                borderRadius: BorderRadius.circular((trackHeight - 6) / 2),
              ),
            ),
          ),
          Row(
            children: [
              for (final source in [(false, '我的'), (true, '在线')])
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: online == source.$1,
                    label: '${source.$2}滤镜${online == source.$1 ? '，已选择' : ''}',
                    child: InkWell(
                      key: ValueKey(
                        'filter-source-${source.$1 ? 'online' : 'mine'}',
                      ),
                      borderRadius: BorderRadius.circular(24),
                      onTap: enabled ? () => onChanged(source.$1) : null,
                      child: SizedBox(
                        height: 48,
                        child: Center(
                          child: Text(
                            source.$2,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1,
                              leadingDistribution: TextLeadingDistribution.even,
                              fontWeight: online == source.$1
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                              color: online == source.$1
                                  ? const Color(0xff191e17)
                                  : _editorMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegacyFilterPickerSources extends StatelessWidget {
  const _LegacyFilterPickerSources({
    required this.online,
    required this.enabled,
    required this.onChanged,
    required this.compact,
  });
  final bool online, enabled, compact;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: compact ? 114 : double.infinity,
    height: 48,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0x12ffffff),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Row(
            children: [
              for (final source in [(true, '在线'), (false, '我的')])
                Expanded(
                  child: Semantics(
                    selected: online == source.$1,
                    button: true,
                    child: InkWell(
                      key: ValueKey(
                        'filter-source-${source.$1 ? 'online' : 'mine'}',
                      ),
                      onTap: enabled ? () => onChanged(source.$1) : null,
                      child: SizedBox(
                        height: 48,
                        child: Center(
                          child: Container(
                            height: 28,
                            width: double.infinity,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: online == source.$1
                                  ? _editorYellow
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              source.$2,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: online == source.$1
                                    ? const Color(0xff2a1c12)
                                    : const Color(0xadffffff),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _LegacyFilterCategories extends StatelessWidget {
  const _LegacyFilterCategories({
    required this.categories,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });
  final List<String> categories;
  final String selected;
  final bool enabled;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final category in categories)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Semantics(
              button: true,
              selected: category == selected,
              child: InkWell(
                key: ValueKey('filter-category-$category'),
                onTap: enabled ? () => onChanged(category) : null,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 48),
                  child: SizedBox(
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          child: Text(
                            category.isEmpty ? '全部' : category,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1,
                              leadingDistribution: TextLeadingDistribution.even,
                              fontWeight: FontWeight.w500,
                              color: category == selected
                                  ? _editorWhite
                                  : const Color(0x99ffffff),
                            ),
                          ),
                        ),
                        if (category == selected)
                          Positioned(
                            bottom: 5,
                            child: Container(
                              width: 18,
                              height: 2,
                              color: _editorYellow,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _LegacyFilterStatus extends StatelessWidget {
  const _LegacyFilterStatus({required this.editor});
  final _EditorPageState editor;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: editor._filterStatusDetail,
    child: InkWell(
      key: const ValueKey('filter-catalog-status'),
      onTap: editor.toolsEnabled && !editor.filters.loading
          ? editor.filters.load
          : null,
      child: SizedBox(
        width: 42,
        height: 48,
        child: Center(
          child: Text(
            editor._filterStatus,
            maxLines: 1,
            style: const TextStyle(fontSize: 10, color: _editorMuted),
          ),
        ),
      ),
    ),
  );
}

class _LegacyFilterCard extends StatelessWidget {
  const _LegacyFilterCard({
    required this.editor,
    required this.preset,
    required this.recipe,
    required this.large,
    required this.compact,
    required this.onTap,
    this.pending = false,
  });
  final _EditorPageState editor;
  final Preset? preset;
  final Json recipe;
  final bool large, compact, pending;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final id = preset == null ? '' : editor.filters.identity(preset!);
    final selected = editor.recipe.data['presetId'] == id;
    final captionHeight = large
        ? 26.0
        : (compact
              ? 20.0
              : 21 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0));
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${preset?.name ?? '原图'}${selected ? '，已选择' : ''}${pending ? '，正在准备' : ''}',
      child: Material(
        key: ValueKey('${large ? 'picker' : 'strip'}-filter-$id'),
        color: large ? Colors.transparent : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(large ? 12 : 7),
          side: selected
              ? const BorderSide(color: Color(0xffbbb9a1))
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (editor.restored && editor.sameOwner)
                      Opacity(
                        opacity: selected ? .8 : 1,
                        child: EditorPresetThumbnail(
                          key: ValueKey(id),
                          catalog: editor.filters,
                          preset: preset,
                          recipe: recipe,
                        ),
                      ),
                    if (selected)
                      IgnorePointer(
                        child: Align(
                          alignment: large
                              ? Alignment.bottomRight
                              : Alignment.center,
                          child: Padding(
                            padding: EdgeInsets.all(large ? 5 : 0),
                            child: Container(
                              width: large ? 22 : 27,
                              height: large ? 22 : 27,
                              decoration: BoxDecoration(
                                color: const Color(0x99121c17),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                Icons.check_rounded,
                                color: Colors.white,
                                size: large ? 17 : 21,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (pending)
                      const IgnorePointer(
                        child: Center(
                          child: SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: _editorYellow,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                color: large ? Colors.transparent : Colors.white,
                height: captionHeight,
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  preset?.name ?? '原图',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: large ? 12 : 10.5,
                    color: large ? _editorWhite : const Color(0xff1f2b29),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegacyFilterPicker extends StatefulWidget {
  const _LegacyFilterPicker({required this.editor, required this.window});
  final _EditorPageState editor;
  final _LegacyFilterWindow window;
  @override
  State<_LegacyFilterPicker> createState() => _LegacyFilterPickerState();
}

class _LegacyFilterPickerState extends State<_LegacyFilterPicker> {
  final search = TextEditingController();
  late final ScrollController grid;
  bool closing = false, invalid = false;
  String? pendingId, failure;
  ModalRoute<dynamic>? route;
  _EditorPageState get editor => widget.editor;
  bool get current =>
      mounted &&
      editor.mounted &&
      editor.sameOwner &&
      !editor.leaving &&
      editor.filters.valid &&
      !closing &&
      !invalid;

  @override
  void initState() {
    super.initState();
    grid = ScrollController(initialScrollOffset: widget.window.pickerOffset);
    editor.panelRevision.addListener(refresh);
    editor.widget.state.addListener(refresh);
    editor.filters.addListener(refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    route = ModalRoute.of(context);
  }

  void refresh() {
    if (!mounted || closing) return;
    if (!editor.mounted ||
        !editor.sameOwner ||
        editor.leaving ||
        !editor.filters.valid) {
      setState(() => invalid = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => close());
    } else {
      setState(() {});
    }
  }

  void close() {
    if (!mounted || closing) return;
    closing = true;
    final ownRoute = route;
    if (ownRoute == null || !ownRoute.isActive) return;
    if (ownRoute.isCurrent) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).removeRoute(ownRoute);
    }
  }

  void resetPosition() {
    widget.window.pickerOffset = 0;
    if (grid.hasClients) grid.jumpTo(0);
  }

  void browse({bool? online, String? category}) {
    if (!current || !editor.toolsEnabled) return;
    if (online == editor.onlineFilters || category == editor.filterCategory) {
      return;
    }
    if (online != null && online != editor.onlineFilters) search.clear();
    editor._browseFilters(online: online, category: category);
    resetPosition();
    setState(() => failure = null);
  }

  Future<void> choose(Preset? preset) async {
    if (!current || !editor.toolsEnabled || pendingId != null) return;
    final target = editor;
    final expectedRevision = target.revision;
    final expectedPath = target.widget.photo.path;
    final identity = preset == null ? '' : editor.filters.identity(preset);
    setState(() {
      pendingId = identity;
      failure = null;
    });
    try {
      final id = preset == null ? '' : await editor.filters.prepare(preset);
      if (!current || route?.isCurrent != true) return;
      if (target.revision != expectedRevision) return;
      final completed = route!.completed;
      close();
      // Unblock the editor before changing Slider enabled state. A completed
      // preparation still cannot apply after cancel, owner or photo changes.
      await completed;
      if (!target.mounted ||
          !target.toolsEnabled ||
          !target.filters.valid ||
          target.revision != expectedRevision ||
          target.widget.photo.path != expectedPath) {
        return;
      }
      target.change(() {
        target.recipe.data['presetId'] = id;
        target.recipe.data['presetName'] = preset?.name ?? '无滤镜';
        target.recipe.data['strength'] = preset == null ? 0 : 100;
      });
    } catch (error) {
      if (current) setState(() => failure = '滤镜准备失败：$error，轻点滤镜重试');
    } finally {
      if (mounted) setState(() => pendingId = null);
    }
  }

  @override
  void dispose() {
    closing = true;
    if (search.text.isEmpty && grid.hasClients) {
      widget.window.pickerOffset = grid.offset;
    }
    editor.panelRevision.removeListener(refresh);
    editor.widget.state.removeListener(refresh);
    editor.filters.removeListener(refresh);
    search.dispose();
    grid.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final landscape = media.orientation == Orientation.landscape;
    final availableHeight =
        media.size.height - media.viewInsets.bottom - media.padding.top;
    final desired = landscape
        ? (media.size.height * .9).clamp(322.0, media.size.height)
        : media.size.height * .72;
    final height = desired.clamp(0.0, availableHeight);
    final query = search.text.trim().toLowerCase();
    final category = editor._currentFilterCategory;
    final rows = editor._sourceFilters
        .where(
          (preset) =>
              (category.isEmpty ||
                  editor._filterCategoryLabel(preset) == category) &&
              (query.isEmpty ||
                  '${preset.name} ${editor._filterCategoryLabel(preset)}'
                      .toLowerCase()
                      .contains(query)),
        )
        .toList();
    final originals = query.isEmpty ? 1 : 0;
    final base = editor.recipe.clone().data
      ..['presetId'] = ''
      ..['presetName'] = ''
      ..['strength'] = 0;
    final enabled = current && editor.toolsEnabled && pendingId == null;
    final status =
        failure ??
        (pendingId != null
            ? '正在准备滤镜'
            : editor._filterStatus.isNotEmpty
            ? editor._filterStatusDetail
            : '');
    final sources = _LegacyFilterPickerSources(
      online: editor.onlineFilters,
      enabled: enabled,
      compact: landscape,
      onChanged: (online) => browse(online: online),
    );
    final categories = _LegacyFilterCategories(
      categories: editor._filterCategories,
      selected: category,
      enabled: enabled,
      onChanged: (value) => browse(category: value),
    );
    final searchField = TextField(
      key: const ValueKey('filter-picker-search'),
      controller: search,
      readOnly: !enabled,
      style: const TextStyle(fontSize: 13, color: _editorWhite),
      decoration: InputDecoration(
        hintText: '搜索名称或分类',
        hintStyle: const TextStyle(color: _editorMuted),
        filled: true,
        fillColor: const Color(0x50121c17),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      onChanged: (_) {
        resetPosition();
        setState(() {});
      },
    );
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) closing = true;
      },
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SizedBox(
          key: const ValueKey('legacy-filter-picker'),
          height: height,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Material(
                color: const Color(0xe5232b26),
                child: invalid
                    ? const SizedBox.expand()
                    : SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          child: Column(
                            children: [
                              Container(
                                width: 32,
                                height: 3,
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xff657080),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              SizedBox(
                                height: 48,
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        '滤镜',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: _editorWhite,
                                        ),
                                      ),
                                    ),
                                    if (landscape) sources,
                                    SizedBox(
                                      width: 42,
                                      child: Text(
                                        '${rows.length}款',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: _editorMuted,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      key: const ValueKey(
                                        'filter-picker-close',
                                      ),
                                      tooltip: '关闭滤镜',
                                      onPressed: close,
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        color: _editorWhite,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!landscape)
                                SizedBox(
                                  height: 48,
                                  child: Center(child: sources),
                                ),
                              if (landscape)
                                SizedBox(
                                  height: 48,
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: (media.size.width * .32).clamp(
                                          176.0,
                                          260.0,
                                        ),
                                        child: searchField,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(child: categories),
                                    ],
                                  ),
                                )
                              else ...[
                                SizedBox(height: 48, child: searchField),
                                SizedBox(height: 48, child: categories),
                              ],
                              SizedBox(
                                height: status.isNotEmpty
                                    ? (landscape
                                          ? 24
                                          : 22 * media.textScaler.scale(1) + 12)
                                    : 0,
                                child: status.isNotEmpty
                                    ? InkWell(
                                        onTap:
                                            enabled && !editor.filters.loading
                                            ? editor.filters.load
                                            : null,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 6,
                                          ),
                                          child: Text(
                                            status,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: _editorMuted,
                                            ),
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              Expanded(
                                key: const ValueKey('filter-picker-results'),
                                child: rows.isEmpty && originals == 0
                                    ? Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text(
                                              '无匹配滤镜',
                                              style: TextStyle(
                                                color: _editorMuted,
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () {
                                                search.clear();
                                                resetPosition();
                                                setState(() {});
                                              },
                                              child: const Text(
                                                '清空搜索',
                                                style: TextStyle(
                                                  color: _editorYellow,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : GridView.builder(
                                        key: const ValueKey(
                                          'filter-picker-grid',
                                        ),
                                        controller: grid,
                                        padding: const EdgeInsets.only(
                                          top: 8,
                                          bottom: 12,
                                        ),
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 3,
                                              crossAxisSpacing: 8,
                                              mainAxisSpacing: 10,
                                              mainAxisExtent: 112,
                                            ),
                                        itemCount: rows.length + originals,
                                        itemBuilder: (context, index) {
                                          final preset = index < originals
                                              ? null
                                              : rows[index - originals];
                                          final id = preset == null
                                              ? ''
                                              : editor.filters.identity(preset);
                                          return _LegacyFilterCard(
                                            editor: editor,
                                            preset: preset,
                                            recipe: base,
                                            large: true,
                                            compact: false,
                                            pending: pendingId == id,
                                            onTap: enabled
                                                ? () => choose(preset)
                                                : null,
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
