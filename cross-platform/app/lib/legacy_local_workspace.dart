import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'legacy_local_editor.dart';
import 'legacy_local_preview.dart';
import 'photo_workspace_chrome.dart';
import 'theme.dart';
import 'workspace_tools.dart';

/// Original PhotoLocalEditDialog: source coordinates before body/crop/frame.
/// The page owns bounded temporary previews; only Apply returns validated data.
class LegacyLocalWorkspace extends StatelessWidget {
  const LegacyLocalWorkspace({
    super.key,
    required this.state,
    required this.photo,
    required this.owner,
    required this.recipe,
    required this.localState,
    required this.frame,
    this.atmosphere,
    required this.isCurrent,
  });
  final AppState state;
  final Photo photo;
  final String owner;
  final Json recipe, localState, frame;
  final String? atmosphere;
  final bool Function() isCurrent;

  @override
  Widget build(BuildContext context) => Theme(
    data: hueviaTheme(Brightness.dark, home: false),
    child: _LegacyBody(config: this),
  );
}

class _LegacyBody extends StatefulWidget {
  const _LegacyBody({required this.config});
  final LegacyLocalWorkspace config;
  @override
  State<_LegacyBody> createState() => _LegacyBodyState();
}

class _LegacyBodyState extends State<_LegacyBody> {
  LegacyLocalWorkspace get config => widget.config;
  late final editor = LegacyLocalEditor(config.localState);
  late final preview = LegacyLocalPreview(
    core: config.state.core,
    photo: config.photo,
    owner: config.owner,
    recipe: config.recipe,
    localState: config.localState,
    initialFrame: config.frame,
    isCurrent: () => current,
    discard: discard,
  );
  final stage = GlobalKey<_LegacyStageState>();
  final chooserAnchor = GlobalKey(), moreAnchor = GlobalKey();
  final discarded = <String>{};
  bool stale = false, closing = false, overlay = true;
  String? failedImage;
  String get sessionOwner => config.state.session['logoutPending'] == true
      ? ''
      : config.state.session['user']?['id'] as String? ?? '';
  bool get current =>
      mounted &&
      !closing &&
      !stale &&
      sessionOwner == config.owner &&
      config.isCurrent();
  bool get editable => current && failedImage == null;

  @override
  void initState() {
    super.initState();
    editor.addListener(changed);
    preview.addListener(repaint);
    config.state.addListener(accountChanged);
  }

  bool owned(String path) =>
      p.isAbsolute(path) &&
      p.isWithin(p.join(config.state.core.root, 'previews'), p.normalize(path));
  Future<void> discard(String? path) async {
    if (path == null || !owned(path) || !discarded.add(path)) return;
    await WidgetsBinding.instance.endOfFrame;
    try {
      await ResizeImage(FileImage(File(path)), width: 1280).evict();
      await FileImage(File(path)).evict();
      if (await File(path).exists()) await File(path).delete();
    } on FileSystemException {
      // A decoded image can remain mapped until the next frame on Windows.
    }
  }

  void changed() {
    if (!current) return;
    preview.offer(
      editor.tools,
      interactive: editor.tracking || editor.adjusting,
    );
    setState(() {});
  }

  void repaint() {
    if (mounted) setState(() {});
  }

  void accountChanged() {
    if (sessionOwner == config.owner && config.isCurrent()) return;
    if (!mounted || stale) return;
    editor.removeListener(changed);
    editor.cancel();
    stale = true;
    editor.tools = {'masks': [], 'clones': []};
    editor.undo.clear();
    editor.redo.clear();
    preview.invalidate();
    unawaited(discard(config.atmosphere));
    setState(() {});
  }

  @override
  void dispose() {
    config.state.removeListener(accountChanged);
    editor.removeListener(changed);
    preview.removeListener(repaint);
    editor.dispose();
    preview.dispose();
    unawaited(discard(config.atmosphere));
    super.dispose();
  }

  String maskName(Json mask, int index) =>
      '${{'brush': '画笔', 'radial': '径向', 'linear': '渐变'}[mask['kind']]} ${index + 1}'
      '${mask['enabled'] == true ? '' : ' · 停用'}';
  String get selectionName => editor.mask != null
      ? maskName(editor.mask!, editor.selectedMask)
      : editor.clone != null
      ? '修复 ${editor.selectedClone + 1}'
            '${editor.clone!['enabled'] == true ? '' : ' · 停用'}'
      : '在照片上拖动新建';

  RelativeRect menuPosition(GlobalKey key) {
    final anchor = key.currentContext?.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final origin =
        anchor?.localToGlobal(Offset.zero, ancestor: overlay) ??
        const Offset(8, 52);
    return RelativeRect.fromRect(
      origin & (anchor?.size ?? const Size(48, 48)),
      Offset.zero & overlay.size,
    );
  }

  Future<void> choose() async {
    if (!editable || editor.tracking || editor.adjusting) return;
    final value = await showMenu<String>(
      context: context,
      position: menuPosition(chooserAnchor),
      items: [
        for (var i = 0; i < editor.masks.length; i++)
          PopupMenuItem(
            value: 'm$i',
            child: Text(maskName(editor.masks[i], i)),
          ),
        for (var i = 0; i < editor.clones.length; i++)
          PopupMenuItem(
            value: 'c$i',
            child: Text(
              '修复 ${i + 1}'
              '${editor.clones[i]['enabled'] == true ? '' : ' · 停用'}',
            ),
          ),
        if (editor.masks.isEmpty && editor.clones.isEmpty)
          const PopupMenuItem(enabled: false, child: Text('在照片上拖动新建')),
      ],
    );
    if (!current || value == null) return;
    if (value.startsWith('m')) {
      editor.chooseMask(int.parse(value.substring(1)));
    } else {
      editor.chooseClone(int.parse(value.substring(1)));
    }
  }

  Future<void> more() async {
    if (!editable || editor.tracking || editor.adjusting) return;
    final selected = editor.mask ?? editor.clone;
    final value = await showMenu<String>(
      context: context,
      position: menuPosition(moreAnchor),
      items: [
        PopupMenuItem(
          value: 'new',
          enabled: editor.canAdd,
          child: Text(editor.tool == 3 ? '新建修复' : '新建蒙版'),
        ),
        PopupMenuItem(
          value: 'enable',
          enabled: selected != null,
          child: Text(selected?['enabled'] == true ? '停用' : '启用'),
        ),
        CheckedPopupMenuItem(
          value: 'invert',
          enabled: editor.mask != null,
          checked: editor.mask?['inverted'] == true,
          child: const Text('反选蒙版'),
        ),
        PopupMenuItem(
          value: 'delete',
          enabled: selected != null,
          child: Text(editor.tool == 3 ? '删除修复' : '删除蒙版'),
        ),
      ],
    );
    if (!current) return;
    switch (value) {
      case 'new':
        editor.newSelection();
      case 'enable':
        editor.toggleEnabled();
      case 'invert':
        editor.invert();
      case 'delete':
        editor.remove();
    }
  }

  Widget header() => SizedBox(
    height: 52,
    child: Row(
      children: [
        WorkspaceTool(
          icon: 'close',
          tooltip: '取消',
          onPressed: () {
            closing = true;
            Navigator.of(context).pop();
          },
        ),
        Expanded(
          child: Text(
            config.localState['hasBodyShape'] == true ? '局部 · 塑形前定位' : '局部调整',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: config.localState['hasBodyShape'] == true ? 12 : 16,
              color: workspaceWhite,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          child: SizedBox(
            width: 64,
            height: 36,
            child: TextButton(
              key: const ValueKey('legacy-apply'),
              style: TextButton.styleFrom(
                backgroundColor: workspaceYellow,
                foregroundColor: const Color(0xff211812),
                disabledBackgroundColor: workspaceYellow.withValues(alpha: .45),
                disabledForegroundColor: const Color(0xff211812)
                    .withValues(alpha: .45),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: EdgeInsets.zero,
              ),
              onPressed:
                  editable &&
                      !editor.tracking &&
                      !editor.adjusting &&
                      preview.ready
                  ? () {
                      final result = preview.result;
                      closing = true;
                      Navigator.of(context).pop(result);
                    }
                  : null,
              child: const Text('应用', style: TextStyle(fontSize: 13)),
            ),
          ),
        ),
      ],
    ),
  );

  Widget controls(double scale) {
    final m = editor.mask, c = editor.clone, parameter = editor.parameter;
    final sizeMaximum = m?['kind'] == 'radial'
        ? 1000.0
        : (editor.tool == 3 ? 250.0 : 500.0);
    final maximum = parameter == 0
        ? 30.0
        : (parameter == 3 ? sizeMaximum : 100.0);
    final minimum = parameter < 3
        ? -maximum
        : parameter == 3
        ? 1.0
        : 0.0;
    final radius =
        (c?['radius'] as num?)?.toDouble() ??
        (m?[m['kind'] == 'radial' ? 'x1' : 'radius'] as num?)?.toDouble() ??
        editor.brushRadius;
    final value = parameter < 3
        ? (m?[['exposure', 'temperature', 'saturation'][parameter]] as num? ??
                  0)
              .toDouble()
        : parameter == 3
        ? radius * 1000
        : ((m?['feather'] ?? c?['feather']) as num? ?? editor.feather)
                  .toDouble() *
              100;
    final readout = parameter == 0
        ? '${value >= 0 ? '+' : ''}${(value / 10).toStringAsFixed(1)}'
        : parameter < 3
        ? '${value >= 0 ? '+' : ''}${value.round()}'
        : '${value.round()}';
    const labels = ['曝光', '冷暖', '饱和', '大小', '羽化'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < 5; i++)
                    if ((i >= 3 || m != null) && !(i == 3 && editor.tool == 2))
                      SizedBox(
                        width: 60 * math.min(1.4, scale),
                        height: 48,
                        child: TextButton(
                          onPressed: editable
                              ? () => editor.chooseParameter(i)
                              : null,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: i == parameter
                                ? workspaceYellow
                                : workspaceMuted,
                          ),
                          child: Text(
                            labels[i],
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    labels[parameter],
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: workspaceYellow,
                      inactiveTrackColor: const Color(0x66ffffff),
                      thumbColor: Colors.white,
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                    ),
                    child: Slider(
                      key: const ValueKey('legacy-slider'),
                      min: minimum,
                      max: maximum,
                      divisions: (maximum - minimum).round(),
                      value: value.clamp(minimum, maximum),
                      label: readout,
                      semanticFormatterCallback: (_) => readout,
                      onChangeStart: editable
                          ? (_) => editor.beginAdjustment()
                          : null,
                      onChanged: editable
                          ? (v) => editor.adjust(v.round())
                          : null,
                      onChangeEnd: editable
                          ? (_) => editor.endAdjustment()
                          : null,
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    readout,
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 72 + 28 * (scale - 1),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    WorkspaceTool(
                      icon: ['brush', 'radial', 'linear', 'clone'][i],
                      tooltip: ['画笔', '径向', '渐变', '修复'][i],
                      label: ['画笔', '径向', '渐变', '修复'][i],
                      width: 64,
                      height: 72 + 28 * (scale - 1),
                      selected: editor.tool == i,
                      onPressed: editable ? () => editor.selectTool(i) : null,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget imageStage() {
    final frame = preview.frame;
    final path = frame?['path'] as String?;
    final valid = path != null && owned(path);
    final size = Size(
      (config.frame['geometryWidth'] as num? ?? config.frame['width'] as num)
          .toDouble(),
      (config.frame['geometryHeight'] as num? ?? config.frame['height'] as num)
          .toDouble(),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: stale
              ? const SizedBox()
              : _LegacyStage(
                  key: stage,
                  editor: editor,
                  source: size,
                  enabled: editable && valid,
                  overlay: overlay,
                  path: valid ? path : null,
                  onImageError: () {
                    if (!current ||
                        preview.frame?['path'] != path ||
                        failedImage == path) {
                      return;
                    }
                    setState(() => failedImage = path);
                  },
                  onImageReady: () {
                    if (current &&
                        preview.frame?['path'] == path &&
                        failedImage != null) {
                      setState(() => failedImage = null);
                    }
                  },
                ),
        ),
        if (!stale)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xb30c0b0a),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: chooserAnchor,
                      onPressed: editable ? choose : null,
                      style: TextButton.styleFrom(
                        foregroundColor: workspaceWhite,
                      ),
                      child: Text(
                        selectionName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  WorkspaceTool(
                    icon: 'add',
                    tooltip: editor.tool == 3 ? '新建修复' : '新建蒙版',
                    onPressed: editable && editor.canAdd
                        ? editor.newSelection
                        : null,
                  ),
                  WorkspaceTool(
                    key: moreAnchor,
                    icon: 'more',
                    tooltip: '更多',
                    onPressed: editable ? more : null,
                  ),
                ],
              ),
            ),
          ),
        if (!stale)
          Positioned(
            left: 8,
            right: 208,
            bottom: 8,
            height: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                editor.tool == 3 && !editor.sourceSet
                    ? '点击选择取样位置'
                    : preview.busy
                    ? '预览中…'
                    : '双指缩放与移动',
                maxLines: 2,
                style: const TextStyle(fontSize: 12, color: workspaceMuted),
              ),
            ),
          ),
        if (!stale)
          Positioned(
            right: 8,
            bottom: 8,
            height: 48,
            child: Row(
              children: [
                WorkspaceTool(
                  icon: 'undo',
                  tooltip: '撤销',
                  onPressed: editable && editor.undo.isNotEmpty
                      ? () => editor.history(false)
                      : null,
                ),
                WorkspaceTool(
                  icon: 'redo',
                  tooltip: '重做',
                  onPressed: editable && editor.redo.isNotEmpty
                      ? () => editor.history(true)
                      : null,
                ),
                WorkspaceTool(
                  icon: 'fit',
                  tooltip: '适合屏幕',
                  onPressed: editable ? () => stage.currentState?.fit() : null,
                ),
                WorkspaceTool(
                  icon: 'eye',
                  tooltip: '显示蒙版',
                  selected: overlay,
                  onPressed: editable
                      ? () => setState(() => overlay = !overlay)
                      : null,
                ),
              ],
            ),
          ),
        if (stale) const Center(child: Text('账号已变更，请重新打开照片。')),
        if (!stale && (preview.error != null || failedImage != null || !valid))
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xdd201f1d),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('局部预览失败，请重试。'),
                  TextButton(
                    onPressed: current && !preview.busy
                        ? () {
                            failedImage = null;
                            preview.retry();
                          }
                        : null,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => PhotoWorkspaceSystemBars(
    color: const Color(0xff201f1d),
    child: Scaffold(
      backgroundColor: const Color(0xff201f1d),
      body: Stack(
        children: [
          Positioned.fill(
            child: PhotoAtmosphere(image: stale ? null : config.atmosphere),
          ),
          SafeArea(
            child: Column(
              children: [
                header(),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final scale = math.max(
                        1.0,
                        MediaQuery.textScalerOf(context).scale(13) / 13,
                      );
                      final tools = controls(scale);
                      if (box.maxWidth > box.maxHeight) {
                        final width = math.min(
                          math.min(300.0, box.maxWidth * .46),
                          math.max(240.0, box.maxWidth * .4),
                        );
                        return Row(
                          children: [
                            Expanded(child: imageStage()),
                            SizedBox(
                              width: width,
                              child: SingleChildScrollView(child: tools),
                            ),
                          ],
                        );
                      }
                      final essential = 168 + 28 * (scale - 1),
                          padding = (box.maxHeight * .4 - essential).clamp(
                            0.0,
                            16.0,
                          ),
                          height = math.min(
                            essential + padding,
                            box.maxHeight / 2,
                          );
                      return Column(
                        children: [
                          Expanded(child: imageStage()),
                          SizedBox(
                            height: height,
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: padding / 2,
                                ),
                                child: tools,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _LegacyStage extends StatefulWidget {
  const _LegacyStage({
    super.key,
    required this.editor,
    required this.source,
    required this.enabled,
    required this.overlay,
    this.path,
    required this.onImageError,
    required this.onImageReady,
  });
  final LegacyLocalEditor editor;
  final Size source;
  final bool enabled, overlay;
  final String? path;
  final VoidCallback onImageError, onImageReady;
  @override
  State<_LegacyStage> createState() => _LegacyStageState();
}

class _LegacyStageState extends State<_LegacyStage> {
  final pointers = <int>{};
  Size viewport = Size.zero;
  double zoom = 1, startZoom = 1, startScale = 1;
  Offset pan = Offset.zero, startPan = Offset.zero, startFocal = Offset.zero;
  bool multiple = false, navigationStarted = false;
  Rect get frame {
    final ratio =
        math.min(
          viewport.width / widget.source.width,
          viewport.height / widget.source.height,
        ) *
        zoom;
    return Rect.fromCenter(
      center: viewport.center(Offset.zero) + pan,
      width: widget.source.width * ratio,
      height: widget.source.height * ratio,
    );
  }

  Offset normalized(Offset value) => Offset(
    ((value.dx - frame.left) / frame.width).clamp(0.0, 1.0),
    ((value.dy - frame.top) / frame.height).clamp(0.0, 1.0),
  );
  Offset boundedPan(Offset value) {
    final x = math.max(0.0, (frame.width - viewport.width) / 2),
        y = math.max(0.0, (frame.height - viewport.height) / 2);
    return Offset(value.dx.clamp(-x, x), value.dy.clamp(-y, y));
  }

  void fit() {
    widget.editor.cancel();
    setState(() {
      zoom = 1;
      pan = Offset.zero;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      viewport = box.biggest;
      pan = boundedPan(pan);
      return ClipRect(
        child: Listener(
          key: const ValueKey('legacy-stage'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            if (pointers.isEmpty) {
              multiple = false;
              navigationStarted = false;
            }
            pointers.add(e.pointer);
            if (pointers.length > 1) {
              multiple = true;
              navigationStarted = false;
              widget.editor.cancel();
            } else if (widget.enabled && frame.contains(e.localPosition)) {
              widget.editor.begin(normalized(e.localPosition), frame.size);
            }
          },
          onPointerMove: (e) {
            if (widget.enabled &&
                !multiple &&
                pointers.length == 1 &&
                widget.editor.tracking) {
              widget.editor.move(normalized(e.localPosition));
            }
          },
          onPointerUp: (e) {
            pointers.remove(e.pointer);
            if (!multiple && widget.editor.tracking) widget.editor.end();
          },
          onPointerCancel: (e) {
            pointers.remove(e.pointer);
            widget.editor.cancel();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (d) {
              navigationStarted = false;
            },
            onScaleUpdate: (d) {
              if (!widget.enabled || d.pointerCount < 2) return;
              widget.editor.cancel();
              if (!navigationStarted) {
                navigationStarted = true;
                startZoom = zoom;
                startScale = d.scale;
                startPan = pan;
                startFocal = d.localFocalPoint;
              }
              final nextZoom = (startZoom * d.scale / startScale).clamp(
                1.0,
                8.0,
              );
              final ratio = nextZoom / startZoom;
              final center = viewport.center(Offset.zero);
              setState(() {
                zoom = nextZoom;
                pan = boundedPan(
                  d.localFocalPoint -
                      center -
                      (startFocal - center - startPan) * ratio,
                );
              });
            },
            onScaleEnd: (_) {
              navigationStarted = false;
            },
            child: Stack(
              children: [
                if (widget.path != null)
                  Positioned.fromRect(
                    rect: frame,
                    child: Image.file(
                      File(widget.path!),
                      key: ValueKey(widget.path),
                      fit: BoxFit.fill,
                      cacheWidth: 1280,
                      excludeFromSemantics: true,
                      filterQuality: FilterQuality.medium,
                      frameBuilder: (_, child, frame, synchronous) {
                        if (frame != null || synchronous) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) widget.onImageReady();
                          });
                        }
                        return child;
                      },
                      errorBuilder: (_, _, _) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) widget.onImageError();
                        });
                        return const SizedBox();
                      },
                    ),
                  ),
                if (widget.overlay && !widget.editor.tracking)
                  Positioned.fromRect(
                    rect: frame,
                    child: IgnorePointer(
                      child: CustomPaint(painter: _LocalOverlay(widget.editor)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _LocalOverlay extends CustomPainter {
  _LocalOverlay(LegacyLocalEditor editor)
    : mask = editor.mask == null ? null : toolsCopy(editor.mask!),
      clone = editor.clone == null ? null : toolsCopy(editor.clone!),
      source = editor.tool == 3 && editor.sourceSet && editor.clone == null
          ? Offset(editor.sourceX, editor.sourceY)
          : null;
  final Json? mask, clone;
  final Offset? source;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final ink = Paint()
      ..color = const Color(0xff79d5ef)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    Offset point(num x, num y) =>
        Offset(x.toDouble() * size.width, y.toDouble() * size.height);
    void cross(Offset p, double radius, Color color) {
      ink.color = color;
      canvas.drawLine(p - Offset(radius, 0), p + Offset(radius, 0), ink);
      canvas.drawLine(p - Offset(0, radius), p + Offset(0, radius), ink);
    }

    void shape(Path path, Color fill, bool inverted) {
      if (inverted) {
        path = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addPath(path, Offset.zero);
      }
      canvas.drawPath(path, Paint()..color = fill);
    }

    final m = mask;
    if (m != null) {
      final a = point(m['x0'] as num, m['y0'] as num),
          b = point(m['x1'] as num, m['y1'] as num),
          enabled = m['enabled'] == true,
          inverted = m['inverted'] == true;
      if (m['kind'] == 'radial') {
        final oval = Rect.fromCenter(
          center: a,
          width: b.dx * 2,
          height: b.dy * 2,
        );
        shape(
          Path()..addOval(oval),
          Color(enabled ? 0x3579d5ef : 0x1579d5ef),
          inverted,
        );
        canvas.drawOval(oval, ink);
        final feather = 1 - (m['feather'] as num).toDouble();
        canvas.drawOval(
          Rect.fromCenter(
            center: a,
            width: oval.width * feather,
            height: oval.height * feather,
          ),
          ink,
        );
        cross(a, 5, const Color(0xff79d5ef));
        canvas.drawCircle(
          Offset(
            (a.dx + b.dx).clamp(0.0, size.width),
            (a.dy + b.dy).clamp(0.0, size.height),
          ),
          6,
          ink,
        );
      } else if (m['kind'] == 'linear') {
        if ((a - b).distance > .001) {
          canvas.drawRect(
            Offset.zero & size,
            Paint()
              ..shader = ui.Gradient.linear(
                a,
                b,
                inverted
                    ? const [Color(0x5579d5ef), Color(0x0079d5ef)]
                    : const [Color(0x0079d5ef), Color(0x5579d5ef)],
              ),
          );
        }
        canvas.drawLine(a, b, ink);
        cross(a, 6, const Color(0xff79d5ef));
        cross(b, 6, const Color(0xff79d5ef));
      } else {
        final values = m['points'] as List;
        final radius = (m['radius'] as num).toDouble() * size.shortestSide;
        final path = Path();
        for (var i = 0; i + 1 < values.length; i += 2) {
          final p = point(values[i] as num, values[i + 1] as num);
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        if (values.length >= 2) {
          if (inverted) {
            var union = Path();
            for (var i = 0; i + 1 < values.length; i += 2) {
              final end = point(values[i] as num, values[i + 1] as num);
              final segment = Path()
                ..addOval(Rect.fromCircle(center: end, radius: radius));
              if (i > 0) {
                final start = point(values[i - 2] as num, values[i - 1] as num),
                    d = end - start;
                if (d.distance > .001) {
                  final n = Offset(-d.dy, d.dx) / d.distance * radius;
                  segment.addPolygon([
                    start + n,
                    end + n,
                    end - n,
                    start - n,
                  ], true);
                }
              }
              union = Path.combine(PathOperation.union, union, segment);
            }
            shape(union, Color(enabled ? 0x5579d5ef : 0x2279d5ef), true);
          } else {
            final brush = Paint()
              ..color = Color(enabled ? 0x5579d5ef : 0x2279d5ef)
              ..strokeWidth = radius * 2
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..style = PaintingStyle.stroke;
            if (values.length == 2) {
              canvas.drawCircle(
                point(values[0] as num, values[1] as num),
                radius,
                Paint()..color = brush.color,
              );
            } else {
              canvas.drawPath(path, brush);
            }
          }
          cross(point(values[0] as num, values[1] as num), 5, workspaceYellow);
        }
      }
    }
    final c = clone;
    if (c != null) {
      final a = point(c['sourceX'] as num, c['sourceY'] as num),
          b = point(c['targetX'] as num, c['targetY'] as num),
          radius = (c['radius'] as num).toDouble() * size.shortestSide;
      ink.color = const Color(0xaaffffff);
      canvas.drawLine(a, b, ink);
      ink.color = const Color(0xff79d5ef);
      canvas.drawCircle(a, radius, ink);
      ink.color = workspaceYellow;
      canvas.drawCircle(b, radius, ink);
      cross(a, 3, const Color(0xff79d5ef));
      cross(b, 3, workspaceYellow);
    } else if (source != null) {
      canvas.drawCircle(point(source!.dx, source!.dy), 10, ink);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LocalOverlay old) => true;
}
