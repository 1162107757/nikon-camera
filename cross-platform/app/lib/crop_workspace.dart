import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'editing_detail_preview.dart';
import 'editing_viewport.dart';
import 'hue_icons.dart';
import 'photo_workspace_chrome.dart';
import 'workspace_tools.dart';

const _yellow = Color(0xffffe335), _white = Color(0xfff4f5f7);

/// Coordinates are fractions of the oriented, rotated full frame, as in
/// PhotoGeometry. The tentative workspace never writes the photo's draft.
class CropWorkspace extends StatefulWidget {
  const CropWorkspace({
    super.key,
    required this.core,
    required this.photo,
    required this.owner,
    required this.recipe,
    this.initialRatio = -1,
    this.isCurrent,
    this.invalidation,
    this.viewportState,
    this.embedded = false,
    this.onFinished,
    this.onBackReady,
    this.initialFrame,
    this.embeddedLayoutBuilder,
  });
  final HueviaCore core;
  final Photo photo;
  final String owner;
  final Json recipe;
  final double initialRatio;
  final bool Function()? isCurrent;
  final Listenable? invalidation;
  final EditingViewportState? viewportState;
  final bool embedded;
  final ValueChanged<Json?>? onFinished;
  final ValueChanged<VoidCallback?>? onBackReady;
  final Json? initialFrame;
  final EditingWorkspaceLayoutBuilder? embeddedLayoutBuilder;
  @override
  State<CropWorkspace> createState() => _CropWorkspaceState();
}

class _CropWorkspaceState extends State<CropWorkspace> {
  late Json geometry = {...object(widget.recipe['geometry'] ?? {})};
  late Rect crop = Rect.fromLTRB(
    (geometry['left'] as num? ?? 0) / 1000000,
    (geometry['top'] as num? ?? 0) / 1000000,
    (geometry['right'] as num? ?? 1000000) / 1000000,
    (geometry['bottom'] as num? ?? 1000000) / 1000000,
  );
  String? image, atmosphere, error, job;
  Size pixels = const Size(1, 1);
  Size sourcePixels = const Size(1, 1);
  bool busy = true;
  bool fitPending = true;
  int generation = 0;
  int atmosphereGeneration = 0;
  bool stale = false, closing = false;
  final canvasKey = GlobalKey<_CropCanvasState>();
  Json? displayedRecipe;
  String? borrowedFrame;
  EditingViewportPlane get displayedPlane {
    final initial = widget.initialFrame;
    final content = image == borrowedFrame && initial != null
        ? initial['_viewportContentRect']
        : null;
    final rect = content is Map
        ? Rect.fromLTRB(
            (content['left'] as num).toDouble(),
            (content['top'] as num).toDouble(),
            (content['right'] as num).toDouble(),
            (content['bottom'] as num).toDouble(),
          )
        : const Rect.fromLTWH(0, 0, 1, 1);
    return EditingViewportPlane.fromRecipe(
      displayedRecipe ?? widget.recipe,
      sourceSize: sourcePixels,
      contentRect: rect,
    );
  }

  late final detail = EditingDetailPreviewController(
    core: widget.core,
    owner: widget.owner,
    sourcePath: widget.photo.path,
    isCurrent: () => current,
    maxTileEdge: 2048,
  );
  bool get current =>
      mounted && !stale && !closing && (widget.isCurrent?.call() ?? true);
  late double ratio = widget.initialRatio;
  String transform = 'angle';
  Timer? debounce;
  String get ratioName =>
      <double, String>{
        -1: '自由',
        0: '原图',
        1: '1:1',
        4 / 3: '4:3',
        2 / 3: '2:3',
        1.5: '3:2',
        9 / 16: '9:16',
        2.35: '电影 · 2.35:1',
      }[ratio] ??
      '自由';
  @override
  void initState() {
    super.initState();
    final initial = widget.initialFrame;
    if (initial != null && initial['path'] is String) {
      final width = initial['width'], height = initial['height'];
      if (width is num &&
          height is num &&
          width > 0 &&
          height > 0 &&
          width.isFinite &&
          height.isFinite) {
        image = borrowedFrame = initial['path'] as String;
        pixels = Size(width.toDouble(), height.toDouble());
        sourcePixels = Size(
          (initial['sourceWidth'] as num? ??
                  widget.photo.info['width'] as num? ??
                  width)
              .toDouble(),
          (initial['sourceHeight'] as num? ??
                  widget.photo.info['height'] as num? ??
                  height)
              .toDouble(),
        );
        displayedRecipe = initial['recipe'] is Map
            ? object(initial['recipe'])
            : widget.recipe;
      }
    }
    widget.invalidation?.addListener(ownerChanged);
    publishBack();
    unawaited(render());
  }

  void publishBack() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) widget.onBackReady?.call(() => finish());
  });

  @override
  void didUpdateWidget(CropWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onBackReady != widget.onBackReady) {
      oldWidget.onBackReady?.call(null);
      publishBack();
    }
  }

  void ownerChanged() {
    if (current || !mounted || stale) return;
    generation++;
    atmosphereGeneration++;
    debounce?.cancel();
    detail.invalidate();
    if (job != null) unawaited(widget.core.cancel(job!));
    final old = image, oldAtmosphere = atmosphere;
    setState(() {
      stale = true;
      image = atmosphere = null;
      busy = false;
      error = '照片或账号已改变，请返回后重新打开。';
    });
    unawaited(discard(old));
    unawaited(discard(oldAtmosphere));
  }

  void finish([Json? result]) {
    if (!mounted || closing || (result != null && !current)) return;
    closing = true;
    detail.invalidate();
    if (widget.embedded) {
      widget.onFinished?.call(result);
    } else {
      Navigator.pop(context, result);
    }
  }

  Future<void> discard(String? value) async {
    if (value == null ||
        value == borrowedFrame ||
        !p.isWithin(p.join(widget.core.root, 'previews'), value)) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      await FileImage(File(value)).evict();
      await File(value).delete();
    } on FileSystemException {
      /* Disposable owned preview. */
    }
  }

  @override
  void dispose() {
    widget.onBackReady?.call(null);
    widget.invalidation?.removeListener(ownerChanged);
    detail.dispose();
    generation++;
    atmosphereGeneration++;
    debounce?.cancel();
    if (job != null) unawaited(widget.core.cancel(job!));
    unawaited(discard(image));
    unawaited(discard(atmosphere));
    super.dispose();
  }

  Future<void> render() async {
    if (!current) return;
    detail.setEnabled(false);
    final serial = ++generation, previous = job;
    final identity = 'crop-${DateTime.now().microsecondsSinceEpoch}';
    job = identity;
    setState(() {
      busy = true;
      error = null;
    });
    final profile = <String, dynamic>{
      ...widget.recipe,
      'border': <String, dynamic>{},
      'geometry': {
        ...geometry,
        'left': 0,
        'top': 0,
        'right': 1000000,
        'bottom': 1000000,
      },
    };
    try {
      if (previous != null) await widget.core.cancel(previous);
      final result = await widget.core.call('media.preview', {
        'path': widget.photo.path,
        'owner': widget.owner,
        'recipe': profile,
      }, identity);
      if (!mounted || !current || serial != generation) {
        await discard(result['path'] as String);
        return;
      }
      Object? decodeFailure;
      await precacheImage(
        FileImage(File(result['path'] as String)),
        context,
        onError: (failure, stack) => decodeFailure = failure,
      );
      if (!current || serial != generation || decodeFailure != null) {
        await discard(result['path'] as String);
        if (decodeFailure != null && current && serial == generation) {
          throw const AppFailure('无法读取裁剪预览，请重试。');
        }
        return;
      }
      final old = image;
      setState(() {
        image = result['path'] as String;
        displayedRecipe = profile;
        pixels = Size(
          ((result['geometryWidth'] ?? result['width']) as num).toDouble(),
          ((result['geometryHeight'] ?? result['height']) as num).toDouble(),
        );
        sourcePixels = Size(
          (result['sourceWidth'] as num? ?? pixels.width).toDouble(),
          (result['sourceHeight'] as num? ?? pixels.height).toDouble(),
        );
        if (fitPending) {
          fitRatio();
          fitPending = false;
        }
      });
      detail.configure(
        recipe: profile,
        revision: serial,
        frameIdentity: image!,
        outputSize: Size(
          (result['width'] as num).toDouble(),
          (result['height'] as num).toDouble(),
        ),
      );
      unawaited(discard(old));
      if (atmosphere == null) unawaited(loadAtmosphere(image!));
    } catch (failure) {
      if (mounted && serial == generation) setState(() => error = '$failure');
    } finally {
      if (current && serial == generation) {
        setState(() {
          busy = false;
          job = null;
        });
        detail.setEnabled(error == null);
      }
    }
  }

  Future<void> loadAtmosphere(String source) async {
    final serial = ++atmosphereGeneration;
    try {
      final result = await widget.core.call('media.atmosphere', {
        'path': source,
        'owner': widget.owner,
      });
      final path = result['path'] as String;
      if (!current || serial != atmosphereGeneration) {
        unawaited(discard(path));
        return;
      }
      final old = atmosphere;
      setState(() => atmosphere = path);
      unawaited(discard(old));
    } catch (_) {
      // The crop remains usable if its decorative sample cannot be created.
    }
  }

  void fitRatio() {
    if (ratio < 0) return;
    final normalized = ratio == 0 ? 1.0 : ratio / pixels.aspectRatio;
    final w = math.min(1.0, normalized), h = w / normalized;
    final l = (crop.center.dx - w / 2).clamp(0.0, 1 - w),
        t = (crop.center.dy - h / 2).clamp(0.0, 1 - h);
    crop = Rect.fromLTWH(l, t, w, h);
  }

  void mutate(VoidCallback action, {bool refit = false}) {
    if (!current) return;
    detail.setEnabled(false);
    setState(() {
      action();
      fitPending |= refit;
    });
    debounce?.cancel();
    // Disable applying/hit testing until the new geometry has been rendered.
    generation++;
    setState(() => busy = true);
    debounce = Timer(
      const Duration(milliseconds: 180),
      () => unawaited(render()),
    );
  }

  Widget controls() => SingleChildScrollView(
    child: Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in const [
                ('原图', 0.0),
                ('自由', -1.0),
                ('1:1', 1.0),
                ('4:3', 4 / 3),
                ('2:3', 2 / 3),
                ('3:2', 1.5),
                ('9:16', 9 / 16),
                ('电影 · 2.35:1', 2.35),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            ratio = entry.$2;
                            fitRatio();
                          }),
                    style: TextButton.styleFrom(
                      foregroundColor: ratio == entry.$2
                          ? const Color(0xff2a1c12)
                          : const Color(0xccffffff),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 48),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Container(
                      height: 34,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: ratio == entry.$2
                            ? _yellow
                            : const Color(0x0dffffff),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: ratio == entry.$2
                              ? _yellow
                              : const Color(0x33ffffff),
                        ),
                      ),
                      child: Text(entry.$1),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Row(
          children: [
            SizedBox(
              width: 72,
              child: DropdownButton<String>(
                value: transform,
                isExpanded: true,
                dropdownColor: const Color(0xff292724),
                style: const TextStyle(
                  color: _white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                underline: const SizedBox(),
                icon: const HueIcon(HueIconKind.down, size: 12, color: _white),
                alignment: Alignment.center,
                items: const [
                  DropdownMenuItem(
                    value: 'angle',
                    alignment: Alignment.center,
                    child: Text('拉直'),
                  ),
                  DropdownMenuItem(
                    value: 'horizontalPerspective',
                    alignment: Alignment.center,
                    child: Text('水平'),
                  ),
                  DropdownMenuItem(
                    value: 'verticalPerspective',
                    alignment: Alignment.center,
                    child: Text('垂直'),
                  ),
                ],
                onChanged: (value) => setState(() => transform = value!),
              ),
            ),
            Expanded(
              child: Slider(
                value: (geometry[transform] as num? ?? 0).toDouble(),
                min: transform == 'angle' ? -450 : -100,
                max: transform == 'angle' ? 450 : 100,
                activeColor: _yellow,
                thumbColor: Colors.white,
                label: transform == 'angle'
                    ? '${((geometry[transform] as num? ?? 0) / 10).toStringAsFixed(1)}°'
                    : '${geometry[transform] ?? 0}',
                onChanged: (value) =>
                    mutate(() => geometry[transform] = value.round()),
              ),
            ),
            SizedBox(
              width: 60,
              child: Text(
                transform == 'angle'
                    ? '${((geometry[transform] as num? ?? 0) / 10).toStringAsFixed(1)}°'
                    : '${(geometry[transform] as num? ?? 0) >= 0 ? "+" : ""}${geometry[transform] ?? 0}',
                textAlign: TextAlign.end,
                style: const TextStyle(color: _white, fontSize: 12),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: busy
                    ? null
                    : () => mutate(() {
                        geometry['turns'] =
                            ((geometry['turns'] as int? ?? 0) + 1) % 4;
                        crop = const Rect.fromLTRB(0, 0, 1, 1);
                      }, refit: true),
                child: const Text('旋转 90°'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: busy
                    ? null
                    : () => mutate(() {
                        geometry = {};
                        crop = const Rect.fromLTRB(0, 0, 1, 1);
                        ratio = -1;
                        transform = 'angle';
                      }),
                child: const Text('重置'),
              ),
            ),
          ],
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 22),
          child: Text(
            '$ratioName · 保留${(crop.width * crop.height * 100).round()}%${(geometry['horizontalPerspective'] ?? 0) != 0 || (geometry['verticalPerspective'] ?? 0) != 0 ? " · 透视" : ""}',
            style: const TextStyle(color: _white, fontSize: 11),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              error!,
              style: const TextStyle(color: Colors.orangeAccent),
            ),
          ),
        if (error != null)
          TextButton(
            onPressed: () => unawaited(render()),
            child: const Text('重试预览'),
          ),
      ],
    ),
  );

  Widget header() => Container(
    height: 54,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x88000000), Colors.transparent],
      ),
    ),
    alignment: Alignment.topCenter,
    child: Row(
      children: [
        SizedBox(
          width: 64,
          height: 48,
          child: Stack(
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0x6e0e1513),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Positioned.fill(
                child: IconButton(
                  tooltip: '返回编辑照片',
                  onPressed: finish,
                  icon: const HueIcon(
                    HueIconKind.back,
                    size: 20,
                    color: _white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Expanded(
          child: Center(
            child: Text('构图', style: TextStyle(fontSize: 13, color: _white)),
          ),
        ),
        SizedBox(
          width: 64,
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: _yellow,
                foregroundColor: const Color(0xff191e17),
                minimumSize: Size.zero,
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                shape: const StadiumBorder(),
              ),
              onPressed: !current || busy || error != null
                  ? null
                  : () => finish({
                      ...geometry,
                      'left': (crop.left * 1000000).round(),
                      'top': (crop.top * 1000000).round(),
                      'right': (crop.right * 1000000).round(),
                      'bottom': (crop.bottom * 1000000).round(),
                    }),
              child: const Text('应用'),
            ),
          ),
        ),
      ],
    ),
  );
  Widget embeddedBody(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final photo = Stack(
        fit: StackFit.expand,
        children: [
          if (image == null)
            const Center(child: CircularProgressIndicator())
          else
            CropCanvas(
              key: canvasKey,
              image: image!,
              pixels: pixels,
              crop: crop,
              enabled: !busy && current && image != borrowedFrame,
              detail: detail,
              viewportState: widget.viewportState,
              plane: displayedPlane,
              embedded: true,
              showCropOverlay: image != borrowedFrame,
              aspect: ratio < 0
                  ? null
                  : ratio == 0
                  ? pixels.aspectRatio
                  : ratio,
              onChanged: (value) => setState(() => crop = value),
              onRetry: () => unawaited(render()),
            ),
        ],
      );
      final panel = SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            header(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => canvasKey.currentState?.fitPhoto(),
                  child: const Text('适应照片'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => canvasKey.currentState?.actualPixels(),
                  child: const Text('1:1像素'),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: controls(),
            ),
          ],
        ),
      );
      return widget.embeddedLayoutBuilder?.call(context, photo, panel) ??
          Column(
            children: [
              Expanded(child: photo),
              SizedBox(
                height: math.min(300, box.maxHeight * .46),
                child: panel,
              ),
            ],
          );
    },
  );

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context).textTheme
              .apply(fontFamily: 'Roboto', bodyColor: _white),
          colorScheme: const ColorScheme.dark(primary: _yellow),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: _white,
              minimumSize: const Size(48, 48),
            ),
          ),
        ),
        child: Builder(builder: embeddedBody),
      );
    }
    return PhotoWorkspaceSystemBars(
      color: const Color(0xff211f1b),
      child: Theme(
        data: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
          colorScheme: const ColorScheme.dark(primary: _yellow),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              foregroundColor: _white,
              minimumSize: const Size(48, 48),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          sliderTheme: const SliderThemeData(
            trackHeight: 2,
            trackShape: RectangularSliderTrackShape(),
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: 7,
              elevation: 0,
              pressedElevation: 0,
            ),
            overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
            thumbColor: Colors.white,
            inactiveTrackColor: Color(0x66ffffff),
          ),
        ),
        child: Scaffold(
          backgroundColor: const Color(0xff0a0908),
          body: Stack(
            fit: StackFit.expand,
            children: [
              PhotoAtmosphere(image: atmosphere),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final canvas = Stack(
                      children: [
                        Positioned.fill(
                          child: image == null
                              ? const Center(child: CircularProgressIndicator())
                              : CropCanvas(
                                  key: canvasKey,
                                  image: image!,
                                  pixels: pixels,
                                  crop: crop,
                                  enabled:
                                      !busy &&
                                      current &&
                                      image != borrowedFrame,
                                  detail: detail,
                                  viewportState: widget.viewportState,
                                  plane: displayedPlane,
                                  showCropOverlay: image != borrowedFrame,
                                  aspect: ratio < 0
                                      ? null
                                      : ratio == 0
                                      ? pixels.aspectRatio
                                      : ratio,
                                  onChanged: (value) =>
                                      setState(() => crop = value),
                                  onRetry: () => unawaited(render()),
                                ),
                        ),
                        if (busy)
                          const Align(
                            alignment: Alignment.bottomCenter,
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        Positioned(top: 0, left: 0, right: 0, child: header()),
                      ],
                    );
                    return box.maxWidth > box.maxHeight
                        ? Row(
                            children: [
                              Expanded(child: canvas),
                              SizedBox(
                                width: math.min(300, box.maxWidth * .45),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    0,
                                    10,
                                    8,
                                  ),
                                  child: controls(),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              Expanded(child: canvas),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: box.maxHeight * .48,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    0,
                                    10,
                                    8,
                                  ),
                                  child: controls(),
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
      ),
    );
  }
}

class CropCanvas extends StatefulWidget {
  const CropCanvas({
    super.key,
    required this.image,
    required this.pixels,
    required this.crop,
    required this.onChanged,
    this.aspect,
    this.enabled = true,
    this.onRetry,
    this.detail,
    this.viewportState,
    this.plane,
    this.embedded = false,
    this.showCropOverlay = true,
  });
  final String image;
  final Size pixels;
  final Rect crop;
  final ValueChanged<Rect> onChanged;
  final double? aspect;
  final bool enabled;
  final VoidCallback? onRetry;
  final EditingDetailPreviewController? detail;
  final EditingViewportState? viewportState;
  final EditingViewportPlane? plane;
  final bool embedded;
  final bool showCropOverlay;
  @override
  State<CropCanvas> createState() => _CropCanvasState();
}

class _CropCanvasState extends State<CropCanvas> {
  final navigation = TransformationController();
  EditingViewportBinding? viewportBinding;
  Rect frame = Rect.zero, start = Rect.zero;
  Rect fitFrame = Rect.zero, photoClip = Rect.zero, gestureCrop = Rect.zero;
  Offset down = Offset.zero;
  Offset pan = Offset.zero, startPan = Offset.zero, startFocal = Offset.zero;
  double zoom = 1, startZoom = 1;
  int edges = 0, pointers = 0;
  double scaleStart = 1;
  bool multiTouch = false, navigationStarted = false;
  int viewportGeneration = 0;
  static const left = 1, top = 2, right = 4, bottom = 8;
  @override
  void initState() {
    super.initState();
    bindViewport();
  }

  void bindViewport() {
    viewportBinding?.dispose();
    viewportBinding = widget.viewportState == null
        ? null
        : EditingViewportBinding(
            shared: widget.viewportState!,
            transform: navigation,
          );
  }

  @override
  void didUpdateWidget(CropCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewportState != widget.viewportState) bindViewport();
  }

  @override
  void dispose() {
    viewportBinding?.dispose();
    navigation.dispose();
    super.dispose();
  }

  void writeNavigation() {
    if (fitFrame.isEmpty || photoClip.isEmpty) return;
    final center = fitFrame.center - photoClip.topLeft;
    navigation.value = Matrix4.identity()
      ..setEntry(0, 0, zoom)
      ..setEntry(1, 1, zoom)
      ..setEntry(0, 3, center.dx * (1 - zoom) + pan.dx)
      ..setEntry(1, 3, center.dy * (1 - zoom) + pan.dy);
  }

  Rect get actual => Rect.fromLTRB(
    frame.left + widget.crop.left * frame.width,
    frame.top + widget.crop.top * frame.height,
    frame.left + widget.crop.right * frame.width,
    frame.top + widget.crop.bottom * frame.height,
  );
  void begin(Offset p) {
    final r = actual;
    edges = (p.dx - r.left).abs() <= 24
        ? left
        : (p.dx - r.right).abs() <= 24
        ? right
        : 0;
    if ((p.dy - r.top).abs() <= 24) edges |= top;
    if ((p.dy - r.bottom).abs() <= 24) edges |= bottom;
    var nearest = 30.0;
    for (final corner in [
      (r.topLeft, left | top),
      (r.topRight, right | top),
      (r.bottomLeft, left | bottom),
      (r.bottomRight, right | bottom),
    ]) {
      final distance = (p - corner.$1).distance;
      if (distance < nearest) {
        nearest = distance;
        edges = corner.$2;
      }
    }
    if (!r.inflate(30).contains(p)) edges = -1;
    start = widget.crop;
    down = p;
  }

  void update(Offset p) {
    if (edges < 0 || frame.isEmpty) return;
    final dx = (p.dx - down.dx) / frame.width,
        dy = (p.dy - down.dy) / frame.height;
    if (edges == 0) {
      final x = (start.left + dx).clamp(0.0, 1 - start.width),
          y = (start.top + dy).clamp(0.0, 1 - start.height);
      widget.onChanged(Rect.fromLTWH(x, y, start.width, start.height));
      return;
    }
    double l = start.left, t = start.top, r = start.right, b = start.bottom;
    final minW = math.min(.1, 48 / frame.width),
        minH = math.min(.1, 48 / frame.height);
    if (edges & left != 0) l = (l + dx).clamp(0.0, r - math.min(r, minW));
    if (edges & right != 0) r = (r + dx).clamp(l + math.min(1 - l, minW), 1.0);
    if (edges & top != 0) t = (t + dy).clamp(0.0, b - math.min(b, minH));
    if (edges & bottom != 0) b = (b + dy).clamp(t + math.min(1 - t, minH), 1.0);
    final aspect = widget.aspect;
    if (aspect != null) {
      final normalized = aspect / widget.pixels.aspectRatio;
      // Anchor the opposite corner. Constrain both dimensions together so
      // dragging against an edge cannot silently break the selected ratio.
      final anchor = Offset(
        edges & left != 0 ? start.right : start.left,
        edges & top != 0 ? start.bottom : start.top,
      );
      final growLeft = edges & left != 0, growUp = edges & top != 0;
      final limitW = growLeft ? anchor.dx : 1 - anchor.dx,
          limitH = growUp ? anchor.dy : 1 - anchor.dy;
      final horizontal = edges & (left | right) != 0,
          vertical = edges & (top | bottom) != 0;
      final desired = horizontal && vertical
          ? math.max(r - l, (b - t) * normalized)
          : horizontal
          ? r - l
          : (b - t) * normalized;
      final minimum = math.max(
        math.min(limitW, minW),
        math.min(limitH, minH) * normalized,
      );
      final w = math.min(
            math.min(limitW, limitH * normalized),
            math.max(minimum, desired),
          ),
          h = w / normalized;
      l = growLeft ? anchor.dx - w : anchor.dx;
      r = l + w;
      t = growUp ? anchor.dy - h : anchor.dy;
      b = t + h;
    }
    widget.onChanged(Rect.fromLTRB(l, t, r, b));
  }

  Rect shifted(double dx, double dy, {double resize = 0}) {
    final r = widget.crop;
    final w = (r.width + resize).clamp(.05, 1.0),
        h = widget.aspect == null
            ? (r.height + resize).clamp(.05, 1.0)
            : math.min(1.0, w * widget.pixels.aspectRatio / widget.aspect!);
    final width = widget.aspect == null
        ? w
        : h * widget.aspect! / widget.pixels.aspectRatio;
    final x = (r.center.dx + dx - width / 2).clamp(0.0, 1 - width),
        y = (r.center.dy + dy - h / 2).clamp(0.0, 1 - h);
    return Rect.fromLTWH(x, y, width, h);
  }

  void nudge(double dx, double dy, {double resize = 0}) =>
      widget.onChanged(shifted(dx, dy, resize: resize));

  void scale(ScaleUpdateDetails details) {
    if (frame.isEmpty) return;
    pointers = details.pointerCount;
    if (pointers < 2) {
      if (!multiTouch) update(details.localFocalPoint);
      return;
    }
    if (!navigationStarted) {
      if (!multiTouch && widget.crop != gestureCrop) {
        widget.onChanged(gestureCrop);
      }
      multiTouch = navigationStarted = true;
      startZoom = zoom;
      scaleStart = details.scale;
      startPan = clampPan(pan);
      startFocal = details.localFocalPoint;
      return;
    }
    final next = (startZoom * details.scale / scaleStart).clamp(1.0, 32.0);
    final ratio = next / startZoom, center = fitFrame.center;
    setState(() {
      zoom = next;
      pan = clampPan(
        details.localFocalPoint -
            center -
            (startFocal - center - startPan) * ratio,
      );
      writeNavigation();
    });
  }

  Offset clampPan(Offset value) {
    final x = math.max(0.0, (fitFrame.width * zoom - photoClip.width) / 2);
    final y = math.max(0.0, (fitFrame.height * zoom - photoClip.height) / 2);
    return Offset(value.dx.clamp(-x, x), value.dy.clamp(-y, y));
  }

  void fitPhoto() => setState(() {
    zoom = 1;
    pan = Offset.zero;
    writeNavigation();
  });

  void actualPixels() {
    if (fitFrame.isEmpty) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    setState(() {
      zoom = (widget.pixels.width / (fitFrame.width * dpr)).clamp(1.0, 32.0);
      pan = Offset.zero;
      writeNavigation();
    });
  }

  String label(Rect r) =>
      '${(r.width * 100).round()}% × ${(r.height * 100).round()}%';

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = applyBoxFit(
        BoxFit.contain,
        widget.pixels,
        widget.embedded
            ? box.biggest
            : Size(
                math.max(1, box.maxWidth - 24),
                math.max(1, box.maxHeight - 90),
              ),
      ).destination;
      photoClip = widget.embedded
          ? Offset.zero & box.biggest
          : Rect.fromLTWH(0, 78, box.maxWidth, math.max(1, box.maxHeight - 90));
      fitFrame = Alignment.center.inscribe(size, photoClip);
      final localFit = fitFrame.shift(-photoClip.topLeft);
      if (viewportBinding != null) {
        viewportBinding!.layout(
          viewport: photoClip.size,
          imageRect: localFit,
          plane: widget.plane,
        );
        zoom = navigation.value.getMaxScaleOnAxis();
        pan =
            MatrixUtils.transformPoint(navigation.value, localFit.center) -
            localFit.center;
      } else {
        pan = clampPan(pan);
        writeNavigation();
      }
      frame = MatrixUtils.transformRect(
        navigation.value,
        localFit,
      ).shift(photoClip.topLeft);
      final detail = widget.detail,
          visible = frame.intersect(photoClip),
          report = ++viewportGeneration;
      final region = editingDetailVisibleRegion(frame, photoClip),
          dpr = MediaQuery.devicePixelRatioOf(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            report != viewportGeneration ||
            detail != widget.detail) {
          return;
        }
        detail?.setViewport(
          visibleRegion: region,
          zoom: zoom,
          viewportPixelSize: Size(visible.width * dpr, visible.height * dpr),
        );
      });
      return Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (!widget.enabled || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft) {
            nudge(-.01, 0);
          } else if (key == LogicalKeyboardKey.arrowRight) {
            nudge(.01, 0);
          } else if (key == LogicalKeyboardKey.arrowUp) {
            nudge(0, -.01);
          } else if (key == LogicalKeyboardKey.arrowDown) {
            nudge(0, .01);
          } else {
            return KeyEventResult.ignored;
          }
          return KeyEventResult.handled;
        },
        child: Semantics(
          label: '裁切范围，单指拖动边框或内部调整，双指缩放和移动照片查看细节',
          value: '${label(widget.crop)} · 查看 ${(zoom * 100).round()}%',
          increasedValue: widget.enabled
              ? label(shifted(0, 0, resize: .05))
              : null,
          decreasedValue: widget.enabled
              ? label(shifted(0, 0, resize: -.05))
              : null,
          onIncrease: widget.enabled ? () => nudge(0, 0, resize: .05) : null,
          onDecrease: widget.enabled ? () => nudge(0, 0, resize: -.05) : null,
          child: GestureDetector(
            dragStartBehavior: DragStartBehavior.down,
            key: const ValueKey('crop-canvas'),
            behavior: HitTestBehavior.opaque,
            onScaleStart: widget.enabled
                ? (details) {
                    begin(details.localFocalPoint);
                    pointers = details.pointerCount;
                    scaleStart = 1;
                    multiTouch = pointers > 1;
                    gestureCrop = widget.crop;
                    navigationStarted = false;
                  }
                : null,
            onScaleUpdate: widget.enabled ? scale : null,
            onScaleEnd: (_) {
              pointers = 0;
              navigationStarted = false;
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRect(
                    clipper: _CropPhotoClip(photoClip),
                    child: Stack(
                      children: [
                        Positioned.fromRect(
                          rect: frame,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                File(widget.image),
                                key: const ValueKey('crop-image-plane'),
                                fit: BoxFit.fill,
                                excludeFromSemantics: true,
                                errorBuilder: (_, _, _) => Center(
                                  child: TextButton(
                                    onPressed: widget.onRetry,
                                    child: const Text('重试预览'),
                                  ),
                                ),
                              ),
                              if (detail != null)
                                EditingDetailTileLayer(controller: detail),
                            ],
                          ),
                        ),
                        if (widget.showCropOverlay)
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _CropOverlay(frame, actual),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!widget.embedded)
                  Positioned(
                    right: 8,
                    top: 48,
                    child: Row(
                      children: [
                        WorkspaceTool(
                          icon: 'fit',
                          tooltip: '适应照片',
                          onPressed: widget.enabled ? fitPhoto : null,
                        ),
                        TextButton(
                          onPressed: widget.enabled ? actualPixels : null,
                          child: const Text('1:1像素'),
                        ),
                      ],
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

class _CropPhotoClip extends CustomClipper<Rect> {
  const _CropPhotoClip(this.rect);
  final Rect rect;
  @override
  Rect getClip(Size size) => rect;
  @override
  bool shouldReclip(_CropPhotoClip oldClipper) => rect != oldClipper.rect;
}

class _CropOverlay extends CustomPainter {
  _CropOverlay(this.frame, this.crop);
  final Rect frame, crop;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(frame)
        ..addRect(crop),
      Paint()..color = const Color(0x99000000),
    );
    final paint = Paint()
      ..color = const Color(0xccffffff)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(crop, paint);
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(crop.left + crop.width * i / 3, crop.top),
        Offset(crop.left + crop.width * i / 3, crop.bottom),
        paint..color = const Color(0x66ffffff),
      );
      canvas.drawLine(
        Offset(crop.left, crop.top + crop.height * i / 3),
        Offset(crop.right, crop.top + crop.height * i / 3),
        paint,
      );
    }
    for (final p in [
      crop.topLeft,
      crop.topRight,
      crop.bottomLeft,
      crop.bottomRight,
    ]) {
      final x = p.dx == crop.left ? 1.0 : -1.0,
          y = p.dy == crop.top ? 1.0 : -1.0;
      canvas.drawPath(
        Path()
          ..moveTo(p.dx, p.dy + y * 18)
          ..lineTo(p.dx, p.dy)
          ..lineTo(p.dx + x * 18, p.dy),
        paint
          ..color = Colors.white
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(_CropOverlay old) =>
      old.crop != crop || old.frame != frame;
}
