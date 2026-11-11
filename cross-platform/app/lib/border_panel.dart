import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'hue_icons.dart';
import 'widgets.dart';

const _text = Color(0xffffffff),
    _muted = Color(0x9effffff),
    _accent = Color(0xffffe335);
const borderTemplates = ['无边框', '模糊居中', '模糊侧栏', '白底信息'];
const _names = ['机型', '焦距', '光圈', '快门', 'ISO', '拍摄时间'];
const _logos = ['跟随模板', '彩色', '白色', '黑色'];

// The original PhotoBorderPanel model catalog and display aliases.
const _cameras = <String, List<String>>{
  'NIKON': [
    'NIKON Z 6_2',
    'NIKON Z 6_3',
    'NIKON Z f',
    'NIKON Z 8',
    'NIKON Z 9',
    'NIKON Z 5',
    'NIKON Z 7_2',
    'NIKON Z 50',
    'NIKON Z fc',
    'NIKON D850',
    'NIKON D750',
  ],
  'FUJIFILM': [
    'X-T20',
    'X-T30 II',
    'X-T4',
    'X-T5',
    'X-S20',
    'X100VI',
    'X-H2',
    'GFX100 II',
  ],
  'SONY': ['ILCE-7M3', 'ILCE-7M4', 'ILCE-7RM5', 'ILCE-7CM2', 'ILCE-6700'],
  'CANON': [
    'Canon EOS R5',
    'Canon EOS R6 Mark II',
    'Canon EOS R8',
    'Canon EOS R50',
  ],
};
String friendlyCamera(String value) => value
    .replaceFirst(RegExp(r'^NIKON\s+', caseSensitive: false), 'Nikon ')
    .replaceAll('Z 6_2', 'Z6 II')
    .replaceAll('Z 7_2', 'Z7 II')
    .replaceAll('Z 6_3', 'Z6 III')
    .replaceAll('Z f', 'Zf')
    .replaceAllMapped(RegExp(r'Z ([5789])'), (m) => 'Z${m[1]}');

class BorderPanel extends StatefulWidget {
  const BorderPanel({
    super.key,
    required this.state,
    required this.photo,
    required this.owner,
    required this.recipe,
    required this.enabled,
    required this.onChanged,
    required this.onDragStart,
    required this.onUndo,
    required this.onRedo,
    required this.canUndo,
    required this.canRedo,
  });
  final AppState state;
  final Photo photo;
  final String owner;
  final Json recipe;
  final bool enabled, canUndo, canRedo;
  final void Function(Json border, bool snapshot) onChanged;
  final VoidCallback onDragStart, onUndo, onRedo;
  @override
  State<BorderPanel> createState() => _BorderPanelState();
}

class _BorderPanelState extends State<BorderPanel> {
  late Json border = copy(object(widget.recipe['border'] ?? {}));
  Json capture = {};
  List<String> thumbnails = [];
  String? error, job;
  String thumbKey = '';
  Timer? debounce;
  int generation = 0, captureGeneration = 0;
  bool dragging = false, loading = true;
  final sheetRevision = ValueNotifier<int>(0);
  HueviaCore get core => widget.state.core;
  bool get ready =>
      mounted &&
      widget.enabled &&
      (widget.state.session['user']?['id'] as String? ?? '') == widget.owner;
  Json copy(Json data) => object(jsonDecode(jsonEncode(data)));
  Json get recipe => {...copy(widget.recipe), 'border': copy(border)};
  List<String> get fields =>
      List<String>.from(border['fields'] as List? ?? List.filled(5, ''));
  List<String> get originals =>
      List<String>.from(capture['fields'] as List? ?? List.filled(5, ''));
  String value(int index) => index == 0
      ? friendlyCamera(
          border['automatic'] == false
              ? border['model'] as String? ?? ''
              : capture['model'] as String? ?? '',
        )
      : fields[index - 1].isEmpty
      ? originals[index - 1]
      : fields[index - 1];
  bool shown(int index) =>
      ((border['visible'] as int? ?? 63) & (1 << index)) != 0;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(accountChanged);
    unawaited(loadCapture());
    schedule();
  }

  @override
  void didUpdateWidget(covariant BorderPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(accountChanged);
      widget.state.addListener(accountChanged);
    }
    border = copy(object(widget.recipe['border'] ?? {}));
    if (!dragging) schedule();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) sheetRevision.value++;
    });
  }

  void accountChanged() {
    if (!mounted) return;
    if (!ready) {
      generation++;
      captureGeneration++;
      debounce?.cancel();
      if (job != null) unawaited(core.cancel(job!));
      final old = thumbnails;
      setState(() {
        thumbnails = [];
        capture = {};
        loading = false;
      });
      unawaited(discard(old));
    }
    sheetRevision.value++;
  }

  Future<void> discard(List<String> paths) async {
    if (paths.isEmpty) return;
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    for (final path in paths) {
      if (!p.isWithin(p.join(core.root, 'previews'), path)) continue;
      try {
        await ResizeImage(FileImage(File(path)), width: 256).evict();
        await FileImage(File(path)).evict();
        if (await File(path).exists()) await File(path).delete();
      } on FileSystemException {
        /* An obsolete owned preview can be pruned later. */
      }
    }
  }

  @override
  void dispose() {
    generation++;
    captureGeneration++;
    debounce?.cancel();
    widget.state.removeListener(accountChanged);
    if (job != null) unawaited(core.cancel(job!));
    unawaited(discard(thumbnails));
    sheetRevision.dispose();
    super.dispose();
  }

  Future<void> loadCapture() async {
    final serial = ++captureGeneration;
    try {
      final result = await core.call('media.borderInfo', {
        'path': widget.photo.path,
        'owner': widget.owner,
      });
      if (!ready || serial != captureGeneration) return;
      setState(() => capture = result);
      sheetRevision.value++;
    } catch (failure) {
      if (ready && serial == captureGeneration) {
        setState(() => error = '$failure');
      }
    }
  }

  void schedule({bool force = false}) {
    if (!ready) return;
    final frozen = recipe, thumbBorder = object(frozenBorder(recipe));
    thumbBorder.remove('template');
    final key = jsonEncode({...frozen, 'border': thumbBorder});
    if (!force && key == thumbKey) return;
    thumbKey = key;
    debounce?.cancel();
    final serial = ++generation;
    if (job != null) unawaited(core.cancel(job!));
    debounce = Timer(
      const Duration(milliseconds: 240),
      () => unawaited(render(frozen, serial)),
    );
  }

  Json frozenBorder(Json value) => copy(object(value['border'] ?? {}));
  Future<void> render(Json frozen, int serial) async {
    if (!ready || serial != generation) return;
    final identity = 'border-${DateTime.now().microsecondsSinceEpoch}';
    String? activeJob;
    final results = <String>[];
    bool accepted = false;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      for (var i = 0; i < 4; i++) {
        activeJob = '$identity-$i';
        job = activeJob;
        final result = await core.call('media.preview', {
          'path': widget.photo.path,
          'owner': widget.owner,
          'maxEdge': 256,
          'recipe': {
            ...frozen,
            'border': {...frozenBorder(frozen), 'template': i},
          },
        }, activeJob);
        if (job == activeJob) job = null;
        results.add(result['path'] as String);
        if (!ready || serial != generation) return;
      }
      final old = thumbnails;
      setState(() {
        thumbnails = results;
        loading = false;
      });
      accepted = true;
      unawaited(discard(old));
    } catch (failure) {
      if (ready && serial == generation) {
        setState(() {
          error = '$failure';
          loading = false;
        });
      }
    } finally {
      if (job == activeJob) job = null;
      if (!accepted) unawaited(discard(results));
    }
  }

  void apply(Json next, {bool snapshot = true}) {
    if (!ready) return;
    setState(() => border = copy(next));
    widget.onChanged(copy(next), snapshot);
    sheetRevision.value++;
  }

  bool unchanged(String initial) {
    if (!ready || initial != jsonEncode(border)) {
      if (mounted) report(context, '照片或边框设置已变化，请重新打开。');
      return false;
    }
    return true;
  }

  Widget button(
    String label,
    VoidCallback? action, {
    bool selected = false,
    bool accent = false,
    bool muted = false,
  }) => TextButton(
    onPressed: action,
    style: TextButton.styleFrom(
      foregroundColor: selected || accent
          ? _accent
          : muted
          ? _muted
          : _text,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: TextStyle(
        fontSize: 12,
        fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
      ),
    ),
    child: Text(label),
  );

  Widget sliderFace(Widget child) => SizedBox(
    height: 48,
    child: SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        trackShape: const RectangularSliderTrackShape(),
        activeTrackColor: _accent,
        inactiveTrackColor: const Color(0xff565450),
        thumbColor: _accent,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 9,
          elevation: 0,
          pressedElevation: 0,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        showValueIndicator: ShowValueIndicator.never,
      ),
      child: child,
    ),
  );

  InputDecoration inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    counterText: '',
    filled: true,
    fillColor: const Color(0xff292724),
    hintStyle: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.normal,
      color: _muted,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );

  Widget cameraMode(String label, bool selected, VoidCallback action) =>
      SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: action,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                backgroundColor: selected ? _accent : const Color(0xff292724),
                foregroundColor: selected ? const Color(0xff352016) : _muted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: selected
                        ? Colors.transparent
                        : const Color(0x30ffffff),
                  ),
                ),
                textStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
              child: Text(label),
            ),
          ),
        ),
      );
  Widget row(int index, {bool checkbox = false}) {
    final display = value(index),
        custom = index == 0
            ? border['automatic'] == false
            : fields[index - 1].isNotEmpty;
    final origin = display.isEmpty
        ? '原图无此记录'
        : custom
        ? '自定义'
        : 'EXIF';
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label:
                '${_names[index]}，${display.isEmpty ? "未记录" : display}，$origin，${shown(index) ? "已显示" : "已隐藏"}，轻点编辑',
            excludeSemantics: true,
            child: InkWell(
              onTap: !ready
                  ? null
                  : () => index == 0 ? camera() : editField(index - 1),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: checkbox ? 48 : 38 * textScale,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 60 * textScale,
                      child: Text(
                        _names[index],
                        style: const TextStyle(color: _muted, fontSize: 11.5),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        display.isEmpty ? '未记录' : display,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          color: display.isEmpty ? _muted : _text,
                          fontSize: 11.5,
                          fontWeight: display.isEmpty
                              ? FontWeight.normal
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (checkbox)
          SizedBox(
            width: 48,
            height: 48,
            child: Checkbox(
              semanticLabel: '显示${_names[index]}',
              value: shown(index),
              onChanged: !ready
                  ? null
                  : (checked) {
                      final visible = border['visible'] as int? ?? 63;
                      apply({
                        ...border,
                        'visible': checked == true
                            ? visible | (1 << index)
                            : visible & ~(1 << index),
                      });
                    },
            ),
          ),
      ],
    );
  }

  double get textScale =>
      MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
  Widget primaryAction({
    required Widget child,
    required VoidCallback? onPressed,
  }) => SizedBox(
    height: 48,
    child: Center(
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: const Color(0xff352016),
            alignment: Alignment.centerLeft,
            minimumSize: const Size(48, 34),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          child: child,
        ),
      ),
    ),
  );

  Future<void> editField(int index) async {
    if (!ready) return;
    final initial = jsonEncode(border),
        input = TextEditingController(text: fields[index]);
    input.selection = TextSelection(
      baseOffset: 0,
      extentOffset: input.text.length,
    );
    final result = await hueDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(_names[index + 1]),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '原图值：${originals[index].isEmpty ? "未记录" : originals[index]}',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: input,
              autofocus: true,
              maxLength: 96,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.normal,
              ),
              decoration: inputDecoration('留空使用原图'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (input.text.length > 96) {
                report(dialog, '边框文字最多 96 个字符。');
                return;
              }
              Navigator.pop(dialog, input.text.trim());
            },
            child: const Text('应用'),
          ),
        ],
      ),
    );
    input.dispose();
    if (result != null && unchanged(initial)) {
      final next = fields;
      next[index] = result;
      apply({...border, 'fields': next});
    }
  }

  Future<void> logo() async {
    final initial = jsonEncode(border);
    final result = await hueDialog<int>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Logo 样式'),
        scrollable: true,
        content: SizedBox(
          width: 320,
          child: RadioGroup<int>(
            groupValue: border['logo'] as int? ?? 0,
            onChanged: (v) => Navigator.pop(dialog, v),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _logos.length; i++)
                  RadioListTile<int>(value: i, title: Text(_logos[i])),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (result != null && unchanged(initial)) {
      apply({...border, 'logo': result});
    }
  }

  Future<void> settings() async {
    if (!ready) return;
    var tab = 2;
    await hueBottomSheet<void>(
      context: context,
      builder: (sheet) => StatefulBuilder(
        builder: (context, refresh) => ValueListenableBuilder<int>(
          valueListenable: sheetRevision,
          builder: (context, _, _) => SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                height: math.min(
                  432,
                  MediaQuery.sizeOf(context).height -
                      MediaQuery.paddingOf(context).vertical -
                      40,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '边框设置',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭边框设置',
                          onPressed: () => Navigator.pop(sheet),
                          icon: const HueIcon(HueIconKind.close, color: _text),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < 3; i++)
                          Expanded(
                            child: Stack(
                              alignment: Alignment.bottomCenter,
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: button(
                                    ['样式', '信息', '外观'][i],
                                    () => refresh(() => tab = i),
                                    selected: tab == i,
                                    muted: tab != i,
                                  ),
                                ),
                                if (tab == i)
                                  Positioned(
                                    bottom: 5,
                                    child: Container(
                                      width: 18,
                                      height: 2,
                                      decoration: BoxDecoration(
                                        color: _accent,
                                        borderRadius: BorderRadius.circular(1),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        IconButton(
                          tooltip: '撤销边框调整',
                          onPressed: ready && widget.canUndo
                              ? widget.onUndo
                              : null,
                          icon: HueIcon(
                            HueIconKind.undo,
                            color: ready && widget.canUndo
                                ? _text
                                : _text.withValues(alpha: .35),
                          ),
                        ),
                        IconButton(
                          tooltip: '重做边框调整',
                          onPressed: ready && widget.canRedo
                              ? widget.onRedo
                              : null,
                          icon: HueIcon(
                            HueIconKind.redo,
                            color: ready && widget.canRedo
                                ? _text
                                : _text.withValues(alpha: .35),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: ListView(
                        key: ValueKey('border-settings-body-$tab'),
                        children: tab == 0
                            ? [
                                for (var i = 0; i < 4; i++)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: button(
                                      borderTemplates[i],
                                      !ready
                                          ? null
                                          : () => apply({
                                              ...border,
                                              'template': i,
                                            }),
                                      selected: (border['template'] ?? 0) == i,
                                    ),
                                  ),
                              ]
                            : tab == 1
                            ? [
                                for (var i = 0; i < 6; i++)
                                  row(i, checkbox: true),
                              ]
                            : [
                                for (final entry in const [
                                  ('margin', '边距', 50.0, 160.0),
                                  ('corner', '圆角', 0.0, 200.0),
                                  ('shadow', '阴影', 0.0, 150.0),
                                  ('blur', '模糊', 0.0, 200.0),
                                ])
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 66,
                                        child: Text(
                                          entry.$2,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        child: sliderFace(
                                          Slider(
                                            activeColor: _accent,
                                            key: ValueKey(
                                              'border-appearance-${entry.$1}',
                                            ),
                                            value:
                                                (border[entry.$1] as num? ??
                                                        100)
                                                    .toDouble(),
                                            min: entry.$3,
                                            max: entry.$4,
                                            semanticFormatterCallback: (v) =>
                                                '${v.round()}%',
                                            onChangeStart: !ready
                                                ? null
                                                : (_) {
                                                    dragging = true;
                                                    widget.onDragStart();
                                                  },
                                            onChanged: !ready
                                                ? null
                                                : (v) => apply({
                                                    ...border,
                                                    entry.$1: v.round(),
                                                  }, snapshot: false),
                                            onChangeEnd: !ready
                                                ? null
                                                : (_) {
                                                    dragging = false;
                                                    schedule();
                                                  },
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 44,
                                        child: Text(
                                          '${border[entry.$1] ?? 100}%',
                                          textAlign: TextAlign.end,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: _muted,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                button(
                                  'Logo · ${_logos[border['logo'] as int? ?? 0]}',
                                  ready ? logo : null,
                                  accent: true,
                                ),
                                button(
                                  '恢复默认',
                                  !ready
                                      ? null
                                      : () => apply({
                                          'template': border['template'] ?? 0,
                                        }),
                                  accent: true,
                                ),
                              ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    dragging = false;
  }

  double cameraHeight(BuildContext context, bool manual) {
    final screen = MediaQuery.sizeOf(context);
    final view = View.of(context);
    // The original dialog's display metrics exclude the system navigation bar.
    // Read the view inset because the sheet removes padding from its children.
    final height =
        screen.height - view.viewPadding.bottom / view.devicePixelRatio;
    return math.min(
      manual ? height * (screen.height < 520 ? .95 : .76) - 24 : 176.0,
      math.max(
        80.0,
        screen.height -
            MediaQuery.paddingOf(context).vertical -
            MediaQuery.viewInsetsOf(context).bottom -
            32,
      ),
    );
  }

  bool compactCamera(BuildContext context, bool manual) =>
      cameraHeight(context, manual) < (manual ? 440 * textScale : 190);

  Future<void> camera() async {
    if (!ready) return;
    final initial = jsonEncode(border), search = TextEditingController();
    var manual = border['automatic'] == false,
        brand = border['automatic'] == false
            ? border['brand'] as String? ?? 'NIKON'
            : capture['brand'] as String? ?? 'NIKON',
        model = border['automatic'] == false
            ? border['model'] as String? ?? ''
            : capture['model'] as String? ?? '';
    if (!_cameras.containsKey(brand)) brand = 'NIKON';
    final result = await hueBottomSheet<Json>(
      context: context,
      builder: (sheet) => StatefulBuilder(
        builder: (context, refresh) => ValueListenableBuilder<int>(
          valueListenable: sheetRevision,
          builder: (context, _, _) => SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                height: cameraHeight(context, manual),
                child: _CameraLayout(
                  compact: compactCamera(context, manual),
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '机型',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭机型选择',
                          onPressed: () => Navigator.pop(sheet),
                          icon: const HueIcon(HueIconKind.close, color: _text),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: cameraMode(
                            '自动',
                            !manual,
                            () => refresh(() => manual = false),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: cameraMode(
                            '手动',
                            manual,
                            () => refresh(() => manual = true),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 32,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          (capture['model'] as String? ?? '').isEmpty
                              ? '原图无机型信息'
                              : '识别：${friendlyCamera(capture['model'] as String)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: _muted),
                        ),
                      ),
                    ),
                    if (!manual) ...[
                      if (!compactCamera(context, manual)) const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: primaryAction(
                          onPressed: !ready
                              ? null
                              : () => Navigator.pop(sheet, {
                                  'automatic': true,
                                  'brand': '',
                                  'model': '',
                                }),
                          child: const Text('使用识别结果'),
                        ),
                      ),
                    ] else ...[
                      TextField(
                        controller: search,
                        maxLength: 96,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.normal,
                          color: _text,
                        ),
                        decoration: inputDecoration('搜索机型'),
                        onChanged: (_) => refresh(() {}),
                      ),
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final entry in const [
                              ('NIKON', '尼康'),
                              ('FUJIFILM', '富士'),
                              ('SONY', '索尼'),
                              ('CANON', '佳能'),
                            ])
                              SizedBox(
                                width: 72,
                                child: button(
                                  entry.$2,
                                  () => refresh(() {
                                    brand = entry.$1;
                                    model = '';
                                  }),
                                  selected: brand == entry.$1,
                                  muted: brand != entry.$1,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _CameraModels(
                        compact: compactCamera(context, manual),
                        child: ListView(
                          children: [
                            for (final m
                                in <String>{
                                  if (brand == capture['brand'] &&
                                      (capture['model'] as String? ?? '')
                                          .isNotEmpty)
                                    capture['model'] as String,
                                  if (model.isNotEmpty) model,
                                  ..._cameras[brand]!,
                                }.where(
                                  (m) => friendlyCamera(m)
                                      .toLowerCase()
                                      .contains(
                                        search.text.trim().toLowerCase(),
                                      ),
                                ))
                              ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                title: Text(
                                  friendlyCamera(m),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: model == m
                                        ? FontWeight.w500
                                        : FontWeight.normal,
                                    color: model == m ? _accent : _text,
                                  ),
                                ),
                                trailing: model == m
                                    ? const HueIcon(
                                        HueIconKind.check,
                                        color: _accent,
                                        size: 16,
                                      )
                                    : null,
                                onTap: () => refresh(() => model = m),
                              ),
                          ],
                        ),
                      ),
                      button(
                        '自定义机型',
                        !ready
                            ? null
                            : () async {
                                final input = TextEditingController(
                                  text: model,
                                );
                                final custom = await hueDialog<String>(
                                  context: context,
                                  builder: (dialog) => AlertDialog(
                                    title: const Text('自定义机型'),
                                    scrollable: true,
                                    content: TextField(
                                      controller: input,
                                      maxLength: 96,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.normal,
                                        color: _text,
                                      ),
                                      decoration: inputDecoration(
                                        '输入机型，最多 96 个字符',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dialog),
                                        child: const Text('取消'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          if (input.text.length > 96) {
                                            report(dialog, '边框文字最多 96 个字符。');
                                            return;
                                          }
                                          Navigator.pop(
                                            dialog,
                                            input.text.trim(),
                                          );
                                        },
                                        child: const Text('使用'),
                                      ),
                                    ],
                                  ),
                                );
                                input.dispose();
                                if (custom != null && ready && sheet.mounted) {
                                  model = custom;
                                  Navigator.pop(sheet, {
                                    'automatic': false,
                                    'brand': brand,
                                    'model': model,
                                  });
                                }
                              },
                        accent: true,
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: primaryAction(
                          onPressed: !ready
                              ? null
                              : () {
                                  if (model.isEmpty) {
                                    report(context, '请先选择机型，或输入自定义机型。');
                                    return;
                                  }
                                  Navigator.pop(sheet, {
                                    'automatic': false,
                                    'brand': brand,
                                    'model': model,
                                  });
                                },
                          child: const Text('使用机型'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    search.dispose();
    if (result != null && unchanged(initial)) apply({...border, ...result});
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final stripHeight = math.min(82 * textScale + 16, box.maxHeight * .6),
          labelHeight = math.min(20 * textScale, stripHeight / 2),
          imageHeight = math.max(12.0, stripHeight - 16 - labelHeight);
      return Column(
        children: [
          SizedBox(
            height: stripHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              itemCount: 4,
              separatorBuilder: (_, _) => const SizedBox(width: 9),
              itemBuilder: (context, i) {
                final selected = (border['template'] ?? 0) == i;
                return SizedBox(
                  width: 70 * textScale,
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: borderTemplates[i],
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: !ready
                          ? null
                          : () => apply({...border, 'template': i}),
                      borderRadius: BorderRadius.circular(10),
                      child: Column(
                        children: [
                          Container(
                            height: imageHeight,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: const Color(0xff1a1715),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? const Color(0xffbbb9a1)
                                    : Colors.transparent,
                              ),
                            ),
                            child: thumbnails.length == 4
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(thumbnails[i]),
                                      fit: BoxFit.contain,
                                      width: double.infinity,
                                      cacheWidth: 256,
                                      excludeFromSemantics: true,
                                      errorBuilder: (_, _, _) => const HueIcon(
                                        HueIconKind.frame,
                                        color: _muted,
                                      ),
                                    ),
                                  )
                                : const SizedBox.expand(),
                          ),
                          SizedBox(
                            height: labelHeight,
                            child: Center(
                              child: Text(
                                borderTemplates[i],
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: selected
                                      ? const Color(0xffe5e5d6)
                                      : const Color(0xa8ffffff),
                                  fontWeight: selected
                                      ? FontWeight.w500
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('border-information-list'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              children: [
                for (var i = 0; i < 6; i++)
                  DecoratedBox(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0x12ffffff), width: .5),
                      ),
                    ),
                    child: row(i),
                  ),
                InkWell(
                  onTap: ready ? settings : null,
                  child: SizedBox(
                    height: 38 * textScale,
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '设置',
                        style: TextStyle(fontSize: 11.5, color: _accent),
                      ),
                    ),
                  ),
                ),
                if (loading) const LinearProgressIndicator(minHeight: 2),
                if (error != null)
                  TextButton(
                    onPressed: () {
                      unawaited(loadCapture());
                      schedule(force: true);
                    },
                    child: Text(
                      '边框预览失败，重试：$error',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _CameraLayout extends StatelessWidget {
  const _CameraLayout({required this.compact, required this.children});
  final bool compact;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => compact
      ? SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        )
      : Column(children: children);
}

class _CameraModels extends StatelessWidget {
  const _CameraModels({required this.compact, required this.child});
  final bool compact;
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      compact ? SizedBox(height: 160, child: child) : Expanded(child: child);
}
