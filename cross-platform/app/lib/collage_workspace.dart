import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'collage_composition.dart';
import 'collage_viewport.dart';
import 'collage_chrome.dart';
import 'collage_thumbnail.dart';

const _muted = collageUiMuted;
const _panel = collageUiSurface;
const _ink = collageUiInk;

class CollageWorkspace extends StatefulWidget {
  const CollageWorkspace({
    super.key,
    required this.paths,
    required this.sizes,
    required this.transforms,
    required this.style,
    required this.tool,
    required this.selectedPhoto,
    required this.busy,
    required this.enabled,
    required this.error,
    required this.onClose,
    required this.onEdit,
    required this.onDownload,
    required this.onAdd,
    required this.onStyle,
    required this.onTool,
    required this.onSelected,
    required this.onTransform,
    required this.onMove,
    required this.onRemove,
    required this.onReplace,
  });
  final List<String> paths;
  final List<Size> sizes;
  final List<CollageTransform> transforms;
  final CollageStyle style;
  final CollageTool tool;
  final int? selectedPhoto;
  final bool busy, enabled;
  final String? error;
  final VoidCallback onClose;
  final Future<void> Function() onEdit, onDownload, onAdd;
  final ValueChanged<CollageStyle> onStyle;
  final ValueChanged<CollageTool> onTool;
  final ValueChanged<int?> onSelected;
  final void Function(int, CollageTransform) onTransform;
  final void Function(int, int) onMove;
  final ValueChanged<int> onRemove;
  final Future<void> Function(int) onReplace;
  @override
  State<CollageWorkspace> createState() => _CollageWorkspaceState();
}

class _CollageWorkspaceState extends State<CollageWorkspace> {
  final text = TextEditingController();
  final thumbnails = CollageThumbnailCache();
  @override
  void initState() {
    super.initState();
    thumbnails.load(widget.paths);
  }

  @override
  void didUpdateWidget(CollageWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paths.join('\n') != widget.paths.join('\n')) {
      thumbnails.load(widget.paths);
    }
  }

  final previewKey = GlobalKey<CollageViewportState>();
  double panelFraction = .42, dragHeight = 0;
  bool editingPhoto = false, movingText = false;
  bool get active => widget.enabled && !widget.busy;
  CollageStyle get style => widget.style;
  @override
  void dispose() {
    thumbnails.dispose();
    text.dispose();
    super.dispose();
  }

  void setText(CollageText value) =>
      widget.onStyle(style.copyWith(texts: [value]));
  CollageText get currentText => style.texts.firstOrNull ?? const CollageText();

  ThemeData get workspaceTheme {
    final inherited = Theme.of(context);
    return ThemeData(
      brightness: Brightness.light,
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: collageUiAccent,
        onPrimary: Colors.white,
        secondary: collageUiAccent,
        surface: _panel,
        onSurface: _ink,
        outline: collageUiOutline,
      ),
      scaffoldBackgroundColor: _panel,
      textTheme: inherited.textTheme.apply(bodyColor: _ink, displayColor: _ink),
      iconTheme: const IconThemeData(color: _ink),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _ink,
          disabledForegroundColor: _muted.withValues(alpha: .45),
        ),
      ),
      sliderTheme: const SliderThemeData(
        trackHeight: 2,
        activeTrackColor: collageUiAccent,
        inactiveTrackColor: collageUiOutline,
        thumbColor: collageUiAccent,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? Colors.white : _muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? collageUiAccent
              : collageUiContainer,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : _muted,
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: _muted),
        counterStyle: TextStyle(color: _muted),
      ),
    );
  }

  void help() => showDialog<void>(
    context: context,
    builder: (context) => Theme(
      data: workspaceTheme,
      child: AlertDialog(
        backgroundColor: _panel,
        title: const Text('拼图帮助'),
        content: const SingleChildScrollView(
          child: Text(
            '选择 2–9 张照片，切换画布比例和布局。\n\n拖动、双指缩放可查看整张拼图，点「适应画布」恢复完整视图。点击照片，再点「调整照片」可拖动和缩放单张照片的裁切，也可替换、旋转或翻转。点预览右下角的照片图标可添加、移除或拖动排序。\n\n「长图拼接」按照片原比例横向或纵向连接；「滤镜」「调节」「文字」会一起保存。点「移动文字」后可在预览中拖动文字。上下拖动工具面板顶部，或点箭头，可展开、收起工具。\n\n下载保存到手机相册，「去修图」生成独立图片继续编辑；原图保留。输出最长边 4096 像素。RAW 请先显影。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    ),
  );

  Future<void> photos() async {
    var paths = List<String>.from(widget.paths);
    var working = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      showDragHandle: true,
      builder: (sheet) => Theme(
        data: workspaceTheme,
        child: StatefulBuilder(
          builder: (sheet, update) => SafeArea(
            top: false,
            child: SizedBox(
              height: math.min(480, MediaQuery.sizeOf(sheet).height * .65),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '照片 ${paths.length}/9',
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: !active || working || paths.length >= 9
                              ? null
                              : () async {
                                  if (working || !active) return;
                                  update(() => working = true);
                                  await widget.onAdd();
                                  if (sheet.mounted) {
                                    update(() {
                                      working = false;
                                      paths = List.from(widget.paths);
                                    });
                                  }
                                },
                          icon: const Icon(Icons.add, size: 20),
                          label: const Text('添加照片'),
                        ),
                        IconButton(
                          tooltip: '关闭照片管理',
                          onPressed: () => Navigator.pop(sheet),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '拖动右侧手柄调整照片顺序',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: paths.length,
                      onReorderItem: (old, next) {
                        if (!active || working) return;
                        widget.onMove(old, next);
                        update(() => paths.insert(next, paths.removeAt(old)));
                      },
                      itemBuilder: (context, i) => ListTile(
                        key: ValueKey('collage-photo-$i-${paths[i]}'),
                        leading: SizedBox.square(
                          dimension: 46,
                          child: Image.file(
                            File(paths[i]),
                            fit: BoxFit.cover,
                            cacheWidth: 96,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                        title: Text(
                          '照片 ${i + 1}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        onTap: !active
                            ? null
                            : () async {
                                if (working || !active) return;
                                update(() => working = true);
                                await widget.onReplace(i);
                                if (sheet.mounted) {
                                  update(() {
                                    working = false;
                                    paths = List.from(widget.paths);
                                  });
                                }
                              },
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '移除第 ${i + 1} 张',
                              onPressed: !active
                                  ? null
                                  : () {
                                      if (working || !active) return;
                                      widget.onRemove(i);
                                      update(() => paths.removeAt(i));
                                    },
                              icon: const Icon(Icons.close, size: 21),
                            ),
                            ReorderableDragStartListener(
                              index: i,
                              enabled: active,
                              child: const SizedBox.square(
                                dimension: 48,
                                child: Icon(Icons.drag_handle, color: _muted),
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
          ),
        ),
      ),
    );
  }

  Widget preview() {
    if (widget.paths.length < 2) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.busy
                  ? Icons.hourglass_empty
                  : Icons.add_photo_alternate_outlined,
              color: Colors.white70,
              size: 34,
            ),
            const SizedBox(height: 12),
            Text(
              widget.busy ? '正在准备照片…' : '选择 2–9 张照片开始拼图',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (!widget.busy)
              TextButton(
                onPressed: active ? widget.onAdd : null,
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('添加照片'),
              ),
          ],
        ),
      );
    }
    return ColoredBox(
      color: collageUiPreview,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
              child: CollageViewport(
                key: previewKey,
                paths: widget.paths,
                sizes: widget.sizes,
                transforms: widget.transforms,
                style: style,
                selected: widget.selectedPhoto,
                enabled: active,
                photoEditing: editingPhoto && widget.selectedPhoto != null,
                textEditing: movingText,
                onSelected: (index) {
                  setState(() => editingPhoto = false);
                  widget.onSelected(index);
                },
                onTransform: widget.onTransform,
                onStyle: widget.onStyle,
              ),
            ),
          ),
          if (widget.selectedPhoto case final index?
              when index < widget.paths.length)
            Positioned(
              left: 6,
              right: 52,
              bottom: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .8),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: TextButtonTheme(
                  data: TextButtonThemeData(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        TextButton(
                          key: const ValueKey('collage-edit-photo'),
                          onPressed: active
                              ? () {
                                  setState(() {
                                    editingPhoto = !editingPhoto;
                                    movingText = false;
                                  });
                                  previewKey.currentState?.fit();
                                }
                              : null,
                          child: Text(editingPhoto ? '完成调整' : '调整照片'),
                        ),
                        TextButton(
                          onPressed: active
                              ? () => widget.onReplace(index)
                              : null,
                          child: const Text('替换'),
                        ),
                        TextButton(
                          onPressed: active
                              ? () => widget.onTransform(
                                  index,
                                  widget.transforms[index].copyWith(
                                    turns:
                                        (widget.transforms[index].turns + 1) %
                                        4,
                                  ),
                                )
                              : null,
                          child: const Text('旋转'),
                        ),
                        TextButton(
                          onPressed: active
                              ? () => widget.onTransform(
                                  index,
                                  widget.transforms[index].copyWith(
                                    mirror: !widget.transforms[index].mirror,
                                  ),
                                )
                              : null,
                          child: const Text('翻转'),
                        ),
                        TextButton(
                          onPressed: active
                              ? () => widget.onTransform(
                                  index,
                                  const CollageTransform(),
                                )
                              : null,
                          child: const Text('重置'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 6,
            top: 6,
            child: IconButton(
              key: const ValueKey('collage-fit'),
              tooltip: '适应画布',
              onPressed: active ? () => previewKey.currentState?.fit() : null,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.fit_screen, size: 22),
            ),
          ),
          if (editingPhoto || movingText)
            Positioned(
              left: 8,
              top: 8,
              right: 62,
              child: IgnorePointer(
                child: Text(
                  movingText ? '拖动文字调整位置' : '拖动、双指缩放调整这张照片',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    backgroundColor: Colors.black87,
                  ),
                ),
              ),
            ),
          Positioned(
            right: 4,
            bottom: 3,
            child: IconButton(
              tooltip: '管理拼图照片',
              onPressed: active ? photos : null,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.photo_library_outlined, size: 21),
            ),
          ),
        ],
      ),
    );
  }

  Widget modes() => SizedBox(
    height: 48,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final mode in CollageMode.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                key: ValueKey('collage-mode-${mode.name}'),
                onPressed: active
                    ? () => widget.onStyle(style.copyWith(mode: mode))
                    : null,
                style: TextButton.styleFrom(
                  minimumSize: const Size(60, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  shape: const RoundedRectangleBorder(),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      ['拼图', '模板', '长图拼接'][mode.index],
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.2,
                        fontWeight: style.mode == mode
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: style.mode == mode ? collageUiAccent : _ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 28,
                      height: 2,
                      decoration: BoxDecoration(
                        color: style.mode == mode
                            ? collageUiAccent
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget layouts() {
    if (style.mode == CollageMode.longImage) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('拼接方向', style: TextStyle(fontSize: 14, color: _muted)),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final horizontal in [false, true])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: OutlinedButton.icon(
                        onPressed: active
                            ? () => widget.onStyle(
                                style.copyWith(horizontal: horizontal),
                              )
                            : null,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: style.horizontal == horizontal
                              ? collageUiAccent
                              : _muted,
                          side: BorderSide(
                            color: style.horizontal == horizontal
                                ? collageUiAccent
                                : collageUiOutline,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                        icon: Icon(
                          horizontal
                              ? Icons.view_column_outlined
                              : Icons.table_rows_outlined,
                        ),
                        label: Text(horizontal ? '横向长图' : '纵向长图'),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '保留每张照片的原始比例，按照片顺序拼接。',
              style: TextStyle(fontSize: 13, color: _muted, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: active ? photos : null,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('调整照片顺序'),
            ),
          ],
        ),
      );
    }
    if (style.mode == CollageMode.template) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 18,
          crossAxisSpacing: 14,
          childAspectRatio: .9,
        ),
        itemCount: collageTemplateLabels.length,
        itemBuilder: (context, i) => InkWell(
          key: ValueKey('collage-template-$i'),
          onTap: active ? () => widget.onStyle(style.applyTemplate(i)) : null,
          child: Column(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: style.template == i
                          ? collageUiAccent
                          : collageUiOutline,
                      width: style.template == i ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: CollageThumbnail(
                      cache: thumbnails,
                      paths: widget.paths,
                      sizes: widget.sizes,
                      transforms: widget.transforms,
                      style: style.applyTemplate(i),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                collageTemplateLabels[i],
                style: TextStyle(
                  fontSize: 12,
                  color: style.template == i ? collageUiAccent : _muted,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final patterns = collagePatterns(widget.paths.length.clamp(2, 9));
    return Column(
      children: [
        SizedBox(
          height: 58,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            itemCount: collageRatios.length,
            separatorBuilder: (_, _) => const SizedBox(width: 0),
            itemBuilder: (context, i) => Semantics(
              selected: style.ratio == i,
              button: true,
              label: '画布比例 ${collageRatioLabels[i]}',
              child: InkWell(
                key: ValueKey('collage-ratio-$i'),
                onTap: active
                    ? () => widget.onStyle(style.copyWith(ratio: i))
                    : null,
                child: SizedBox(
                  width: ((MediaQuery.sizeOf(context).width - 6) / 8).clamp(
                    48.0,
                    66.0,
                  ),
                  height: 48,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: style.ratio == i
                            ? collageUiTint
                            : collageUiContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        collageRatioLabels[i],
                        style: TextStyle(
                          fontSize: 12,
                          height: 1,
                          fontWeight: style.ratio == i
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: style.ratio == i ? collageUiOnTint : _ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            key: const ValueKey('collage-layout-grid'),
            padding: const EdgeInsets.fromLTRB(13, 6, 13, 12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 10,
              crossAxisSpacing: 8,
              mainAxisExtent: math
                  .max(
                    56.0,
                    ((math.min(MediaQuery.sizeOf(context).width, 620) - 58) /
                                5) /
                            collageRatios[style.ratio] +
                        8,
                  )
                  .clamp(56.0, 140.0),
            ),
            itemCount: patterns.length,
            itemBuilder: (context, i) => Semantics(
              selected: style.pattern % patterns.length == i,
              button: true,
              label: '拼图布局 ${i + 1}',
              child: InkWell(
                key: ValueKey('collage-pattern-$i'),
                onTap: active
                    ? () => widget.onStyle(style.copyWith(pattern: i))
                    : null,
                child: Container(
                  margin: const EdgeInsets.all(1),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: style.pattern % patterns.length == i
                        ? collageUiTint
                        : collageUiContainer,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: style.pattern % patterns.length == i
                          ? collageUiAccent
                          : collageUiOutline,
                      width: style.pattern % patterns.length == i ? 1.5 : .5,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: CollageThumbnail(
                      cache: thumbnails,
                      paths: widget.paths,
                      sizes: widget.sizes,
                      transforms: widget.transforms,
                      style: style.copyWith(pattern: i),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget filters() => ListView(
    key: const ValueKey('collage-filter-list'),
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
    children: [
      const Text('滤镜', style: TextStyle(fontSize: 14, color: _muted)),
      const SizedBox(height: 18),
      Wrap(
        spacing: 14,
        runSpacing: 20,
        children: [
          for (var i = 0; i < collageFilterLabels.length; i++)
            InkWell(
              key: ValueKey('collage-filter-$i'),
              onTap: active
                  ? () => widget.onStyle(style.copyWith(filter: i))
                  : null,
              child: SizedBox(
                width: 76,
                child: Column(
                  children: [
                    Container(
                      height: 82,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: style.filter == i
                              ? collageUiAccent
                              : Colors.transparent,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: widget.paths.isEmpty
                            ? const ColoredBox(
                                color: collageUiContainer,
                                child: Center(
                                  child: Icon(Icons.photo_outlined),
                                ),
                              )
                            : ColorFiltered(
                                colorFilter: ColorFilter.matrix(
                                  collageColorMatrix(style.copyWith(filter: i)),
                                ),
                                child: Image.file(
                                  File(widget.paths.first),
                                  fit: BoxFit.cover,
                                  cacheWidth: 160,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      collageFilterLabels[i],
                      style: TextStyle(
                        fontSize: 12,
                        color: style.filter == i ? collageUiAccent : _muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 24),
      const Text(
        '滤镜同时作用于整张拼图，保留每张照片已有的编辑。',
        style: TextStyle(fontSize: 12, color: _muted, height: 1.5),
      ),
    ],
  );

  Widget slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            '${(value.abs() <= 1 && min < 0 ? value * 100 : value).round()}',
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        ],
      ),
      Slider(
        value: value,
        min: min,
        max: max,
        onChanged: active ? onChanged : null,
      ),
    ],
  );

  Widget adjustments() => ListView(
    key: const ValueKey('collage-adjust-list'),
    padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
    children: [
      Row(
        children: [
          const Expanded(
            child: Text('画布与照片', style: TextStyle(fontSize: 14, color: _muted)),
          ),
          TextButton(
            onPressed: active
                ? () => widget.onStyle(
                    style.copyWith(
                      gap: 0,
                      brightness: 0,
                      contrast: 0,
                      saturation: 0,
                      warmth: 0,
                      radius: 0,
                      contain: false,
                      background: Colors.white,
                    ),
                  )
                : null,
            child: const Text('重置'),
          ),
        ],
      ),
      slider(
        '间距',
        style.gap,
        0,
        40,
        (v) => widget.onStyle(style.copyWith(gap: v)),
      ),
      Row(
        children: [
          const Expanded(child: Text('底色', style: TextStyle(fontSize: 13))),
          for (final color in [
            Colors.white,
            Colors.black,
            const Color(0xffeee6d5),
            const Color(0xffdadada),
            const Color(0xffd9e5d2),
          ])
            Semantics(
              key: ValueKey('collage-background-${color.toARGB32()}'),
              label: '选择底色 ${color.toARGB32().toRadixString(16)}',
              button: true,
              selected: style.background == color,
              child: InkWell(
                onTap: active
                    ? () => widget.onStyle(style.copyWith(background: color))
                    : null,
                child: SizedBox.square(
                  dimension: 48,
                  child: Center(
                    child: Container(
                      width: 23,
                      height: 23,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: style.background == color
                              ? collageUiAccent
                              : const Color(0xff8d857d),
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('完整显示照片', style: TextStyle(fontSize: 13)),
        value: style.contain,
        onChanged: active
            ? (v) => widget.onStyle(style.copyWith(contain: v))
            : null,
      ),
      slider(
        '圆角',
        style.radius,
        0,
        24,
        (v) => widget.onStyle(style.copyWith(radius: v)),
      ),
      slider(
        '亮度',
        style.brightness,
        -1,
        1,
        (v) => widget.onStyle(style.copyWith(brightness: v)),
      ),
      slider(
        '对比度',
        style.contrast,
        -1,
        1,
        (v) => widget.onStyle(style.copyWith(contrast: v)),
      ),
      slider(
        '饱和度',
        style.saturation,
        -1,
        1,
        (v) => widget.onStyle(style.copyWith(saturation: v)),
      ),
      slider(
        '冷暖',
        style.warmth,
        -1,
        1,
        (v) => widget.onStyle(style.copyWith(warmth: v)),
      ),
    ],
  );

  Widget texts() => ListView(
    key: const ValueKey('collage-text-list'),
    padding: const EdgeInsets.fromLTRB(22, 18, 22, 24),
    children: [
      const Text(
        '输入文字，点击「移动文字」调整位置',
        style: TextStyle(fontSize: 12, color: _muted),
      ),
      const SizedBox(height: 14),
      TextField(
        key: const ValueKey('collage-text-input'),
        controller: text,
        maxLength: 60,
        minLines: 1,
        maxLines: 2,
        enabled: active,
        style: const TextStyle(color: _ink, fontSize: 16),
        decoration: const InputDecoration(
          hintText: '输入文字',
          filled: true,
          fillColor: collageUiContainer,
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        onChanged: (v) => setText(currentText.copyWith(value: v)),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const ValueKey('collage-move-text'),
          onPressed:
              active && (movingText || currentText.value.trim().isNotEmpty)
              ? () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  setState(() {
                    movingText = !movingText;
                    editingPhoto = false;
                  });
                  previewKey.currentState?.fit();
                }
              : null,
          icon: Icon(movingText ? Icons.check : Icons.open_with, size: 20),
          label: Text(movingText ? '完成移动' : '移动文字'),
        ),
      ),
      slider(
        '字号',
        currentText.size,
        12,
        64,
        (v) => setText(currentText.copyWith(size: v)),
      ),
      Row(
        children: [
          const Text('颜色', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 12),
          for (final color in [
            Colors.white,
            Colors.black,
            collageAccent,
            const Color(0xffffc88d),
          ])
            InkWell(
              key: ValueKey('collage-text-color-${color.toARGB32()}'),
              onTap: active
                  ? () => setText(currentText.copyWith(color: color))
                  : null,
              child: SizedBox.square(
                dimension: 48,
                child: Center(
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: currentText.color == color
                            ? collageUiAccent
                            : const Color(0xff8d857d),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('加粗', style: TextStyle(fontSize: 13)),
        value: currentText.bold,
        onChanged: active
            ? (v) => setText(currentText.copyWith(bold: v))
            : null,
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: active && style.texts.isNotEmpty
              ? () {
                  text.clear();
                  widget.onStyle(style.copyWith(texts: []));
                }
              : null,
          icon: const Icon(Icons.delete_outline, size: 20),
          label: const Text('删除文字'),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = workspaceTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: _panel,
        systemNavigationBarColor: _panel,
      ),
      child: Theme(
        data: theme,
        child: Builder(
          builder: (context) => Scaffold(
            resizeToAvoidBottomInset: true,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          IconButton(
                            key: widget.busy
                                ? const Key('cancel-collage')
                                : const Key('close-collage'),
                            tooltip: widget.busy ? '取消处理' : '关闭拼图',
                            onPressed: widget.onClose,
                            icon: const Icon(Icons.close, size: 29),
                          ),
                          IconButton(
                            tooltip: '拼图帮助',
                            onPressed: help,
                            icon: const Icon(Icons.help_outline, size: 25),
                          ),
                          const Spacer(),
                          OutlinedButton(
                            key: const Key('save-collage'),
                            onPressed: active && widget.paths.length >= 2
                                ? widget.onEdit
                                : null,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: collageUiAccent,
                              side: const BorderSide(color: collageUiAccent),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              minimumSize: const Size(62, 32),
                            ),
                            child: const Text(
                              '去修图',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            key: const Key('download-collage'),
                            tooltip: '保存拼图到手机相册',
                            onPressed: active && widget.paths.length >= 2
                                ? widget.onDownload
                                : null,
                            icon: const Icon(
                              Icons.file_download_outlined,
                              size: 31,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.busy) const LinearProgressIndicator(minHeight: 2),
                  if (widget.error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Text(
                        widget.error!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xffb3261e),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, bounds) {
                        const minimum = 68.0;
                        final maximum = math.max(
                          minimum,
                          bounds.maxHeight - 120,
                        );
                        final height = (bounds.maxHeight * panelFraction).clamp(
                          minimum,
                          maximum,
                        );
                        final showContent = height >= 156;
                        void toggle() => setState(
                          () => panelFraction = showContent ? 0 : .42,
                        );
                        return ColoredBox(
                          color: collageUiPreview,
                          child: Column(
                            children: [
                              Expanded(
                                child: ColoredBox(
                                  color: collageUiPreview,
                                  child: preview(),
                                ),
                              ),
                              SizedBox(
                                key: const ValueKey('collage-tool-panel'),
                                height: height,
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(15),
                                  ),
                                  child: Material(
                                    color: _panel,
                                    child: Column(
                                      children: [
                                        GestureDetector(
                                          key: const ValueKey(
                                            'collage-panel-handle',
                                          ),
                                          behavior: HitTestBehavior.opaque,
                                          onVerticalDragStart: (_) =>
                                              dragHeight = height,
                                          onVerticalDragUpdate: (event) =>
                                              setState(() {
                                                dragHeight =
                                                    (dragHeight -
                                                            event.delta.dy)
                                                        .clamp(
                                                          minimum,
                                                          maximum,
                                                        );
                                                panelFraction =
                                                    dragHeight /
                                                    bounds.maxHeight;
                                              }),
                                          onVerticalDragEnd: (event) => setState(() {
                                            final velocity =
                                                event.primaryVelocity ?? 0;
                                            if (velocity > 500) {
                                              panelFraction = 0;
                                            } else if (velocity < -500) {
                                              panelFraction = .75;
                                            } else {
                                              panelFraction = [0.0, .42, .75]
                                                  .reduce(
                                                    (a, b) =>
                                                        (a - panelFraction)
                                                                .abs() <
                                                            (b - panelFraction)
                                                                .abs()
                                                        ? a
                                                        : b,
                                                  );
                                            }
                                          }),
                                          child: Column(
                                            children: [
                                              SizedBox(
                                                height: 19,
                                                child: Center(
                                                  child: Container(
                                                    width: 28,
                                                    height: 4,
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xffb6b0aa,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            2,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Row(
                                                children: [
                                                  Expanded(child: modes()),
                                                  IconButton(
                                                    key: const ValueKey(
                                                      'collage-panel-toggle',
                                                    ),
                                                    tooltip: showContent
                                                        ? '收起工具面板'
                                                        : '展开工具面板',
                                                    onPressed: toggle,
                                                    icon: Icon(
                                                      showContent
                                                          ? Icons
                                                                .keyboard_arrow_down
                                                          : Icons
                                                                .keyboard_arrow_up,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Divider(
                                          height: 1,
                                          thickness: .5,
                                          color: collageUiOutline,
                                        ),
                                        if (showContent)
                                          Expanded(
                                            child: Center(
                                              child: ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                      maxWidth: 620,
                                                    ),
                                                child: switch (widget.tool) {
                                                  CollageTool.layout =>
                                                    layouts(),
                                                  CollageTool.filter =>
                                                    filters(),
                                                  CollageTool.adjust =>
                                                    adjustments(),
                                                  CollageTool.text => texts(),
                                                },
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(
                    height: .5,
                    thickness: .5,
                    color: collageUiOutline,
                  ),
                  Material(
                    color: _panel,
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        height: 64,
                        child: Row(
                          children: [
                            for (final item in CollageTool.values)
                              Expanded(
                                child: SizedBox(
                                  height: 64,
                                  child: Semantics(
                                    selected: widget.tool == item,
                                    button: true,
                                    child: InkWell(
                                      key: ValueKey(
                                        'collage-tool-${item.name}',
                                      ),
                                      onTap: !active
                                          ? null
                                          : () {
                                              if (item == CollageTool.text) {
                                                text.text = currentText.value;
                                              }
                                              FocusManager.instance.primaryFocus
                                                  ?.unfocus();
                                              setState(() {
                                                editingPhoto = movingText =
                                                    false;
                                                if (panelFraction < .2) {
                                                  panelFraction = .42;
                                                }
                                              });
                                              widget.onTool(item);
                                            },
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            [
                                              Icons.window_outlined,
                                              Icons.bubble_chart_outlined,
                                              Icons.tune,
                                              Icons.title,
                                            ][item.index],
                                            size: 22,
                                            color: widget.tool == item
                                                ? collageUiAccent
                                                : _ink,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            [
                                              '布局',
                                              '滤镜',
                                              '调节',
                                              '文字',
                                            ][item.index],
                                            style: TextStyle(
                                              fontSize: 12,
                                              height: 1.1,
                                              color: widget.tool == item
                                                  ? collageUiAccent
                                                  : _ink,
                                              fontWeight: widget.tool == item
                                                  ? FontWeight.w500
                                                  : FontWeight.w400,
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
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
