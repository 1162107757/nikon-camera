import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'editing_detail_preview.dart';
import 'photo_workspace_chrome.dart';
import 'selection_editor.dart';
import 'selection_mask.dart';
import 'theme.dart';
import 'workspace_tools.dart';

class SelectionResult {
  const SelectionResult(this.localState, this.regionId);
  final Json localState;
  final String regionId;
}

/// Owns the bounded frame/atmosphere supplied by the parent, and returns only
/// a validated tentative recipe. Saving remains the editor's explicit action.
class SelectionWorkspace extends StatelessWidget {
  const SelectionWorkspace({
    super.key,
    required this.state,
    required this.photo,
    required this.owner,
    required this.region,
    required this.localState,
    required this.frame,
    this.atmosphere,
    this.isCurrent,
    this.maskBuilder,
    this.recipe,
    this.expectedSourceSha = '',
  });
  final AppState state;
  final Photo photo;
  final String owner;
  final Json region, localState, frame;
  final String? atmosphere;
  final bool Function()? isCurrent;
  final Future<Json> Function(Json input)? maskBuilder;
  final Json? recipe;
  final String expectedSourceSha;
  @override
  Widget build(BuildContext context) => Theme(
    data: hueviaTheme(Brightness.dark, home: false),
    child: _SelectionBody(config: this),
  );
}

class _SelectionBody extends StatefulWidget {
  const _SelectionBody({required this.config});
  final SelectionWorkspace config;
  @override
  State<_SelectionBody> createState() => _SelectionBodyState();
}

class _SelectionBodyState extends State<_SelectionBody> {
  SelectionWorkspace get config => widget.config;
  late final base = selectionCopy(config.localState);
  late final sourceSize = Size(
    (config.frame['geometryWidth'] as num? ?? config.frame['width'] as num)
        .toDouble(),
    (config.frame['geometryHeight'] as num? ?? config.frame['height'] as num)
        .toDouble(),
  );
  late final editor = SelectionEditor(config.region, sourceSize: sourceSize);
  final stage = GlobalKey<_SelectionStageState>();
  final moreAnchor = GlobalKey();
  final discarded = <String>{};
  ui.Image? mask;
  bool stale = false,
      closing = false,
      committing = false,
      maskBusy = false,
      hasCoverage = false,
      imageFailed = false;
  Json? pendingMask;
  String requestedMask = '', acceptedMask = '';
  String? error, commitJob;
  int maskGeneration = 0;
  EditingDetailPreviewController? detail;
  HueviaCore get core => config.state.core;
  String get currentOwner => config.state.session['logoutPending'] == true
      ? ''
      : config.state.session['user']?['id'] as String? ?? '';
  bool get current =>
      mounted &&
      !stale &&
      !closing &&
      currentOwner == config.owner &&
      (config.isCurrent?.call() ?? true);
  String get framePath => config.frame['path'] as String;
  bool get ready => current && !committing && !imageFailed;

  @override
  void initState() {
    super.initState();
    if (!_owned(framePath)) {
      imageFailed = true;
      error = '选区预览文件无效，请重新打开。';
    }
    if (!sourceSize.width.isFinite ||
        !sourceSize.height.isFinite ||
        sourceSize.width < 1 ||
        sourceSize.height < 1 ||
        sourceSize.width > 65535 ||
        sourceSize.height > 65535) {
      imageFailed = true;
      error = '选区照片尺寸无效，请重新打开。';
    }
    config.state.addListener(accountChanged);
    if (!imageFailed && config.recipe != null) {
      detail =
          EditingDetailPreviewController(
            core: core,
            owner: config.owner,
            sourcePath: config.photo.path,
            isCurrent: () =>
                current && config.state.session['logoutPending'] != true,
            maxTileEdge: 2048,
          )..configure(
            recipe: config.recipe!,
            revision: 0,
            frameIdentity: framePath,
            outputSize: Size(
              (config.frame['width'] as num).toDouble(),
              (config.frame['height'] as num).toDouble(),
            ),
            expectedSourceSha: config.expectedSourceSha,
            viewMode: 'local',
          );
    }
    editor.addListener(changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) changed();
    });
  }

  bool _owned(String path) =>
      p.isAbsolute(path) &&
      p.isWithin(p.join(core.root, 'previews'), p.normalize(path));
  Future<void> discard(String? path) async {
    if (path == null || !_owned(path) || !discarded.add(path)) return;
    await WidgetsBinding.instance.endOfFrame;
    try {
      await ResizeImage(FileImage(File(path)), width: 1280).evict();
      await FileImage(File(path)).evict();
      if (await File(path).exists()) await File(path).delete();
    } on FileSystemException {
      /* The original photo is never a preview path. */
    }
  }

  void releaseMask(ui.Image? value) {
    if (value == null) return;
    unawaited(WidgetsBinding.instance.endOfFrame.then((_) => value.dispose()));
  }

  void accountChanged() {
    if (config.state.session['logoutPending'] != true &&
        currentOwner == config.owner &&
        (config.isCurrent?.call() ?? true)) {
      return;
    }
    if (!mounted || stale) return;
    detail?.invalidate();
    editor.cancel();
    editor.removeListener(changed);
    if (commitJob != null) unawaited(core.cancel(commitJob!));
    maskGeneration++;
    pendingMask = null;
    final old = mask;
    setState(() {
      stale = true;
      mask = null;
      maskBusy = false;
      hasCoverage = false;
      error = null;
    });
    editor.region = {};
    editor.undo.clear();
    editor.redo.clear();
    releaseMask(old);
    unawaited(discard(framePath));
    unawaited(discard(config.atmosphere));
  }

  @override
  void dispose() {
    detail?.dispose();
    config.state.removeListener(accountChanged);
    editor.removeListener(changed);
    editor.dispose();
    if (commitJob != null) unawaited(core.cancel(commitJob!));
    maskGeneration++;
    pendingMask = null;
    releaseMask(mask);
    unawaited(discard(framePath));
    unawaited(discard(config.atmosphere));
    super.dispose();
  }

  void changed() {
    if (!current) return;
    final visible = editor.displayRegion;
    final selection = {
      'strokes': visible['strokes'] ?? [],
      'shapes': visible['shapes'] ?? [],
      'inverted': visible['inverted'] == true,
    };
    final key = jsonEncode(selection);
    if (key != requestedMask) {
      requestedMask = key;
      maskGeneration++;
      pendingMask = {
        'region': selectionCopy(selection),
        'width': sourceSize.width,
        'height': sourceSize.height,
        'generation': maskGeneration,
        'key': key,
      };
      if (!maskBusy) {
        maskBusy = true;
        unawaited(renderMasks());
      }
    }
    setState(() {});
  }

  Future<void> renderMasks() async {
    try {
      while (current && pendingMask != null) {
        final input = pendingMask!;
        pendingMask = null;
        final generation = input['generation'] as int;
        ui.Image? image;
        try {
          final data =
              await (config.maskBuilder?.call(input) ??
                  compute(buildSelectionMask, input));
          if (!current || generation != maskGeneration) continue;
          final completer = Completer<ui.Image>();
          ui.decodeImageFromPixels(
            data['bytes'] as Uint8List,
            data['width'] as int,
            data['height'] as int,
            ui.PixelFormat.rgba8888,
            completer.complete,
          );
          image = await completer.future;
          if (!current || generation != maskGeneration) {
            releaseMask(image);
            continue;
          }
          final old = mask;
          setState(() {
            mask = image;
            acceptedMask = input['key'] as String;
            hasCoverage = data['hasCoverage'] == true;
            error = null;
          });
          releaseMask(old);
        } catch (failure) {
          if (image != null && image != mask) releaseMask(image);
          if (current && generation == maskGeneration && !editor.tracking) {
            setState(() => error = '选区预览失败，请点击提示重试。');
          }
        }
      }
    } finally {
      if (mounted) setState(() => maskBusy = false);
    }
  }

  void retryMask() {
    requestedMask = '';
    changed();
  }

  void close() {
    if (closing) return;
    setState(() => closing = true);
    detail?.invalidate();
    if (commitJob != null) unawaited(core.cancel(commitJob!));
    Navigator.pop(context);
  }

  Future<void> complete() async {
    if (!ready ||
        maskBusy ||
        acceptedMask != requestedMask ||
        !editor.canComplete(hasCoverage)) {
      return;
    }
    editor.cancel();
    setState(() {
      committing = true;
      error = null;
    });
    final id = editor.region['id'] as String;
    final exists = (base['regions'] as List? ?? []).any(
      (r) => object(r)['id'] == id,
    );
    final job = 'selection-commit-${DateTime.now().microsecondsSinceEpoch}';
    commitJob = job;
    try {
      final result = await core.call('local.change', {
        'localData': base['localData'] ?? '',
        'expectedSha': base['sha256'],
        'action': exists ? 'setRegion' : 'addRegion',
        'regionId': id,
        'value': selectionCopy(editor.region),
      }, job);
      if (!mounted || !current) return;
      closing = true;
      detail?.invalidate();
      Navigator.pop(context, SelectionResult(result, id));
    } catch (failure) {
      if (current) setState(() => error = '$failure');
    } finally {
      if (commitJob == job) commitJob = null;
      if (mounted && !closing) setState(() => committing = false);
    }
  }

  Future<void> more() async {
    if (!ready) return;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final anchor = moreAnchor.currentContext!.findRenderObject()! as RenderBox;
    final origin = anchor.localToGlobal(Offset.zero, ancestor: overlay);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          origin.dx,
          origin.dy + anchor.size.height,
          anchor.size.width,
          0,
        ),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'fit', child: Text('适应照片')),
        PopupMenuItem(value: 'clear', child: Text('清空当前选区')),
      ],
    );
    if (!ready) return;
    if (value == 'fit') stage.currentState?.fit();
    if (value == 'clear') editor.clear();
  }

  Widget header() => SizedBox(
    height: 52,
    child: Padding(
      padding: const EdgeInsets.only(left: 4, right: 8),
      child: Row(
        children: [
          WorkspaceTool(
            icon: 'close',
            tooltip: '取消本次选区编辑',
            height: 52,
            onPressed: closing ? null : close,
          ),
          Expanded(
            child: Text(
              stale ? '选区编辑已关闭' : '编辑选区 · ${editor.region['name']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.normal,
                color: workspaceWhite,
              ),
            ),
          ),
          SizedBox(
            width: 76,
            height: 52,
            child: FilledButton(
              onPressed:
                  ready &&
                      !maskBusy &&
                      editor.canComplete(hasCoverage) &&
                      acceptedMask == requestedMask
                  ? complete
                  : null,
              style:
                  FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: const Color(0xff191e17),
                    disabledBackgroundColor: Colors.transparent,
                    disabledForegroundColor: const Color(0xff191e17),
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.normal,
                    ),
                  ).copyWith(
                    splashFactory: NoSplash.splashFactory,
                    overlayColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                  ),
              child: Container(
                width: double.infinity,
                height: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                decoration: BoxDecoration(
                  color: workspaceYellow,
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: const Text('完成'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Widget modeButton(
    String label,
    VoidCallback? action, {
    bool selected = false,
    bool invert = false,
  }) => SizedBox(
    height: 48,
    child: TextButton(
      onPressed: action,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: Size.zero,
        foregroundColor: invert
            ? editor.inverted
                  ? workspaceYellow
                  : workspaceWhite
            : selected
            ? workspaceWhite
            : workspaceMuted,
        disabledForegroundColor: invert ? workspaceWhite : workspaceMuted,
        backgroundColor: !invert && selected
            ? const Color(0x18d9dcc5)
            : Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
      ),
      child: Text(label),
    ),
  );
  Widget slider(bool feather, double scale, double available) {
    final value = feather ? editor.feather * 100 : editor.radius * 1000 - 1;
    final label = feather ? '羽化' : '大小';
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: math.min(44 * scale, available * .22),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: const TextStyle(color: workspaceMuted, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                trackShape: const RectangularSliderTrackShape(),
                activeTrackColor: workspaceYellow,
                inactiveTrackColor: const Color(0x66ffffff),
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                  elevation: 0,
                  pressedElevation: 0,
                ),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: Slider(
                semanticFormatterCallback: (_) => feather
                    ? '${editor.feather * 100}%'
                    : '${(editor.radius * 100).toStringAsFixed(1)}%',
                value: value.clamp(0.0, feather ? 100.0 : 119.0),
                min: 0,
                max: feather ? 100 : 119,
                onChangeStart: ready ? (_) => editor.beginSlider() : null,
                onChanged: ready
                    ? (value) {
                        if (feather) {
                          editor.setFeather(value.round() / 100);
                        } else {
                          editor.setRadius((value.round() + 1) / 1000);
                        }
                      }
                    : null,
                onChangeEnd: ready ? (_) => editor.endSlider() : null,
              ),
            ),
          ),
          SizedBox(
            width: math.min(48 * scale, available * .32),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                feather
                    ? '${(editor.feather * 100).round()}%'
                    : '${(editor.radius * 100).toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: const TextStyle(color: workspaceMuted, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget controls(double scale) => LayoutBuilder(
    builder: (context, box) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  WorkspaceTool(
                    icon: 'undo',
                    tooltip: '撤销选区操作',
                    onPressed: ready && editor.undo.isNotEmpty
                        ? () => editor.history(false)
                        : null,
                  ),
                  WorkspaceTool(
                    icon: 'redo',
                    tooltip: '重做选区操作',
                    onPressed: ready && editor.redo.isNotEmpty
                        ? () => editor.history(true)
                        : null,
                  ),
                  const Spacer(),
                  WorkspaceTool(
                    icon: 'eye',
                    tooltip: editor.showSelection ? '隐藏选区，保留调整' : '显示选区',
                    selected: editor.showSelection,
                    onPressed: ready ? editor.toggleOverlay : null,
                  ),
                  SizedBox(
                    width: math.min(
                      64 * scale,
                      math.max(0, box.maxWidth - 216),
                    ),
                    child: GestureDetector(
                      onTap: ready ? editor.toggleOverlay : null,
                      child: ExcludeSemantics(
                        child: Text(
                          editor.showSelection ? '隐藏选区' : '显示选区',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: const TextStyle(
                            color: workspaceWhite,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                  WorkspaceTool(
                    key: moreAnchor,
                    icon: 'more',
                    tooltip: '更多选区操作',
                    onPressed: ready ? more : null,
                  ),
                ],
              ),
            ),
            Row(
              children: [
                for (final (index, label, icon) in const [
                  (0, '画笔', 'brush'),
                  (1, '圆形', 'selection-circle'),
                  (2, '矩形', 'selection-rectangle'),
                ])
                  Expanded(
                    child: WorkspaceTool(
                      icon: icon,
                      tooltip: label,
                      label: label,
                      width: double.infinity,
                      height: 72 * scale,
                      selected: editor.tool == index,
                      onPressed: ready ? () => editor.chooseTool(index) : null,
                    ),
                  ),
              ],
            ),
            Row(
              children: [
                for (final (index, label) in const [
                  (0, '替换'),
                  (1, '添加'),
                  (2, '减去'),
                ])
                  Expanded(
                    child: modeButton(
                      label,
                      ready ? () => editor.chooseOperation(index) : null,
                      selected: editor.operation == index,
                    ),
                  ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 60,
                  child: modeButton(
                    '反选',
                    ready && selectionHasContent(editor.region)
                        ? editor.toggleInverted
                        : null,
                    invert: true,
                  ),
                ),
              ],
            ),
            slider(true, scale, box.maxWidth - 24),
            if (editor.tool == 0) slider(false, scale, box.maxWidth - 24),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final page = PhotoWorkspaceSystemBars(
      color: const Color(0xff201f1d),
      child: Scaffold(
        backgroundColor: const Color(0xff242b27),
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
                        if (stale) {
                          return const Center(
                            child: Text(
                              '账号或照片已改变，请返回后重新打开。',
                              style: TextStyle(color: workspaceWhite),
                            ),
                          );
                        }
                        if (imageFailed) {
                          return Center(
                            child: Text(
                              error ?? '预览读取失败，请返回后重试。',
                              style: const TextStyle(color: workspaceWhite),
                            ),
                          );
                        }
                        final scale = MediaQuery.textScalerOf(context)
                            .scale(1)
                            .clamp(1.0, 3.2);
                        final side =
                            box.maxWidth > box.maxHeight && box.maxWidth >= 480;
                        final photo = _SelectionStage(
                          key: stage,
                          editor: editor,
                          framePath: framePath,
                          sourceSize: sourceSize,
                          mask: mask,
                          enabled: ready && !editor.adjusting,
                          detail: detail,
                          onImageFailed: () {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && !imageFailed) {
                                setState(() => imageFailed = true);
                              }
                            });
                          },
                          hint:
                              error ??
                              editor.error ??
                              (base['hasBodyShape'] == true
                                  ? '按原图定位选区 · 调整后保留照片构图'
                                  : editor.tool == 0
                                  ? '单指涂抹 · 双指缩放和移动'
                                  : '拖动创建 · 拖动选区移动 · 拉角点调整大小'),
                          retry: error != null && !committing
                              ? retryMask
                              : null,
                        );
                        if (side) {
                          return Row(
                            children: [
                              Expanded(child: photo),
                              SizedBox(
                                width: math.min(320, box.maxWidth * .44),
                                child: controls(scale),
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            Expanded(child: photo),
                            SizedBox(
                              height: math.min(
                                (editor.tool == 0 ? 264 : 216) +
                                    48 * (scale - 1),
                                box.maxHeight / 2,
                              ),
                              child: controls(scale),
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
    return PopScope<SelectionResult>(
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) return;
        closing = true;
        if (commitJob != null) unawaited(core.cancel(commitJob!));
      },
      child: page,
    );
  }
}

// Stage implementation follows below; image/selection coordinates always use
// the same fitted source rectangle, independently of the editor's composition.
class _SelectionStage extends StatefulWidget {
  const _SelectionStage({
    super.key,
    required this.editor,
    required this.framePath,
    required this.sourceSize,
    required this.mask,
    required this.enabled,
    required this.hint,
    required this.onImageFailed,
    this.retry,
    this.detail,
  });
  final SelectionEditor editor;
  final String framePath, hint;
  final Size sourceSize;
  final ui.Image? mask;
  final bool enabled;
  final VoidCallback onImageFailed;
  final VoidCallback? retry;
  final EditingDetailPreviewController? detail;
  @override
  State<_SelectionStage> createState() => _SelectionStageState();
}

class _SelectionStageState extends State<_SelectionStage> {
  final pointers = <int>{};
  double zoom = 1, startZoom = 1, startScale = 1;
  Offset pan = Offset.zero,
      startPan = Offset.zero,
      startFocal = Offset.zero,
      downPosition = Offset.zero;
  Size viewport = Size.zero;
  bool multiple = false, navigationStarted = false;
  int viewportGeneration = 0;
  SelectionEditor get editor => widget.editor;
  Size get fitted {
    final scale = math.min(
      viewport.width / widget.sourceSize.width,
      viewport.height / widget.sourceSize.height,
    );
    return Size(
      widget.sourceSize.width * scale * zoom,
      widget.sourceSize.height * scale * zoom,
    );
  }

  Offset clampPan(Offset value) {
    final size = fitted,
        x = math.max(0.0, (size.width - viewport.width) / 2),
        y = math.max(0.0, (size.height - viewport.height) / 2);
    return Offset(value.dx.clamp(-x, x), value.dy.clamp(-y, y));
  }

  Rect get frame => Rect.fromCenter(
    center: viewport.center(Offset.zero) + clampPan(pan),
    width: fitted.width,
    height: fitted.height,
  );
  Offset normalized(Offset value) {
    final rect = frame;
    return Offset(
      ((value.dx - rect.left) / rect.width).clamp(0.0, 1.0),
      ((value.dy - rect.top) / rect.height).clamp(0.0, 1.0),
    );
  }

  void fit() {
    editor.cancel();
    setState(() {
      zoom = 1;
      pan = Offset.zero;
    });
  }

  void pointerDown(PointerDownEvent event) {
    if (pointers.isEmpty) {
      downPosition = event.localPosition;
      multiple = false;
      navigationStarted = false;
    }
    pointers.add(event.pointer);
    if (pointers.length > 1) {
      multiple = true;
      editor.cancel();
      navigationStarted = false;
    } else {
      beginDrawing(downPosition);
    }
  }

  void pointerMove(PointerMoveEvent event) {
    if (widget.enabled &&
        !multiple &&
        pointers.length == 1 &&
        editor.tracking) {
      editor.move(normalized(event.localPosition));
    }
  }

  void pointerEnd(PointerEvent event, {bool cancelled = false}) {
    if (cancelled) {
      editor.cancel();
    } else if (!multiple && pointers.length == 1 && editor.tracking) {
      editor.end(point: normalized(event.localPosition));
    }
    pointers.remove(event.pointer);
    if (pointers.isEmpty) navigationStarted = false;
  }

  (int, int) hitShape(Offset point) {
    if (editor.tool == 0 || editor.operation != 0) return (-1, -1);
    final values = editor.shapes, rect = frame;
    for (var i = values.length - 1; i >= 0; i--) {
      final shape = values[i];
      if ((editor.tool == 1) != (shape['kind'] == 'ellipse')) continue;
      final box = Rect.fromLTRB(
        rect.left + (shape['left'] as num) * rect.width,
        rect.top + (shape['top'] as num) * rect.height,
        rect.left + (shape['right'] as num) * rect.width,
        rect.top + (shape['bottom'] as num) * rect.height,
      );
      final corners = [
        box.topLeft,
        box.topRight,
        box.bottomLeft,
        box.bottomRight,
      ];
      for (var corner = 0; corner < 4; corner++) {
        if ((point - corners[corner]).distance <= 24) return (i, corner);
      }
      if (box.contains(point)) return (i, 4);
    }
    return (-1, -1);
  }

  void beginDrawing(Offset point) {
    if (!widget.enabled || !frame.contains(point)) return;
    final (index, handle) = hitShape(point);
    editor.begin(normalized(point), shapeIndex: index, handle: handle);
  }

  void scaleStart(ScaleStartDetails details) {
    if (details.pointerCount > 1 || multiple) {
      multiple = true;
      editor.cancel();
      navigationStarted = false;
      return;
    }
  }

  void scaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount > 1 || multiple) {
      if (!multiple) {
        multiple = true;
        editor.cancel();
      }
      if (details.pointerCount < 2) return;
      if (!navigationStarted) {
        navigationStarted = true;
        startZoom = zoom;
        startScale = details.scale;
        startPan = clampPan(pan);
        startFocal = details.localFocalPoint;
      }
      final next = (startZoom * details.scale / startScale).clamp(1.0, 32.0),
          ratio = next / startZoom,
          center = viewport.center(Offset.zero),
          focus = details.localFocalPoint - center,
          original = startFocal - center;
      setState(() {
        zoom = next;
        pan = clampPan(focus - (original - startPan) * ratio);
      });
    }
  }

  void scaleEnd(ScaleEndDetails details) {
    navigationStarted = false;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (viewport != Size.zero && viewport != box.biggest && editor.tracking) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) editor.cancel();
        });
      }
      viewport = box.biggest;
      final rect = frame;
      final detail = widget.detail, report = ++viewportGeneration;
      final clip = Offset.zero & viewport, visible = rect.intersect(clip);
      final region = editingDetailVisibleRegion(rect, clip),
          dpr = MediaQuery.devicePixelRatioOf(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            report != viewportGeneration ||
            detail != widget.detail) {
          return;
        }
        detail?.setEnabled(widget.enabled);
        detail?.setViewport(
          visibleRegion: region,
          zoom: zoom,
          viewportPixelSize: Size(visible.width * dpr, visible.height * dpr),
        );
      });
      return Stack(
        children: [
          Positioned.fill(
            child: Semantics(
              key: const ValueKey('selection-canvas'),
              label: '选区照片，单指绘制或调整选区，双指缩放和移动',
              value: '${(zoom * 100).round()}%',
              child: Listener(
                onPointerDown: widget.enabled ? pointerDown : null,
                onPointerMove: widget.enabled ? pointerMove : null,
                onPointerUp: pointerEnd,
                onPointerCancel: (event) => pointerEnd(event, cancelled: true),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: widget.enabled ? scaleStart : null,
                  onScaleUpdate: widget.enabled ? scaleUpdate : null,
                  onScaleEnd: widget.enabled ? scaleEnd : null,
                  child: ClipRect(
                    child: Stack(
                      children: [
                        Positioned.fromRect(
                          rect: rect,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(widget.framePath),
                                key: const ValueKey('selection-image-plane'),
                                fit: BoxFit.fill,
                                cacheWidth: 1280,
                                excludeFromSemantics: true,
                                errorBuilder: (_, _, _) {
                                  widget.onImageFailed();
                                  return const Center(
                                    child: Text('预览读取失败，请返回后重试。'),
                                  );
                                },
                              ),
                              if (detail != null)
                                EditingDetailTileLayer(controller: detail),
                            ],
                          ),
                        ),
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _SelectionPaint(
                              rect,
                              widget.mask,
                              editor.showSelection && !editor.adjusting,
                              editor.tool > 0 ? editor.selectedShape : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Center(
              child: IgnorePointer(
                ignoring: widget.retry == null,
                child: GestureDetector(
                  onTap: widget.retry,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xb3191e17),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        widget.hint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: workspaceWhite,
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _SelectionPaint extends CustomPainter {
  const _SelectionPaint(this.frame, this.mask, this.show, this.shape);
  final Rect frame;
  final ui.Image? mask;
  final bool show;
  final Json? shape;
  @override
  void paint(Canvas canvas, Size size) {
    if (!show) return;
    canvas.save();
    canvas.clipRect(frame);
    final image = mask;
    if (image != null) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        frame,
        Paint()..filterQuality = FilterQuality.low,
      );
    }
    final value = shape;
    if (value != null) {
      final box = Rect.fromLTRB(
        frame.left + (value['left'] as num) * frame.width,
        frame.top + (value['top'] as num) * frame.height,
        frame.left + (value['right'] as num) * frame.width,
        frame.top + (value['bottom'] as num) * frame.height,
      );
      final ink = Paint()
        ..color = const Color(0xffdddcc8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      if (value['kind'] == 'ellipse') {
        canvas.drawOval(box, ink);
      } else {
        canvas.drawRect(box, ink);
      }
      ink
        ..color = workspaceWhite
        ..style = PaintingStyle.fill;
      for (final point in [
        box.topLeft,
        box.topRight,
        box.bottomLeft,
        box.bottomRight,
      ]) {
        canvas.drawCircle(point, 3, ink);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SelectionPaint old) =>
      old.frame != frame ||
      old.mask != mask ||
      old.show != show ||
      old.shape != shape;
}
