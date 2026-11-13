import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'theme.dart';

enum EditorDetailsResult { raw }

/// A read-only full-resolution viewer. Native detailRender never saves a version.
class EditorDetailsPage extends StatefulWidget {
  const EditorDetailsPage({
    super.key,
    required this.state,
    required this.photo,
    required this.owner,
    required this.recipe,
    required this.expectedSourceSha,
    required this.isCurrent,
    this.hasRaw = false,
  });
  final AppState state;
  final Photo photo;
  final String owner, expectedSourceSha;
  final Json recipe;
  final bool Function() isCurrent;
  final bool hasRaw;
  @override
  State<EditorDetailsPage> createState() => _EditorDetailsPageState();
}

class _EditorDetailsPageState extends State<EditorDetailsPage> {
  final transform = TransformationController();
  final owned = <String>{};
  ImageProvider? provider;
  String? path, job, error, failedDecode;
  bool before = false, loading = true, closed = false;
  bool routeClosing = false;
  int generation = 0, width = 0, height = 0;
  Size viewport = Size.zero;
  bool get current =>
      mounted &&
      !closed &&
      widget.isCurrent() &&
      widget.state.session['logoutPending'] != true &&
      (widget.state.session['user']?['id'] as String? ?? '') == widget.owner;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(ownerChanged);
    unawaited(load(false));
  }

  void ownerChanged() {
    if (current || !mounted) return;
    closed = true;
    generation++;
    final active = job;
    job = null;
    if (active != null) unawaited(widget.state.core.cancel(active));
    setState(() {
      path = null;
      error = '照片或账号已变化，请关闭细节预览。';
    });
    unawaited(evictCurrent());
  }

  Future<void> evictCurrent() async {
    final old = provider;
    provider = null;
    if (old != null) await old.evict();
  }

  bool ownedPath(String value) {
    final directory = p.normalize(p.join(widget.state.core.root, 'previews'));
    final file = p.normalize(value);
    return p.isWithin(directory, file) &&
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png)$',
          caseSensitive: false,
        ).hasMatch(p.basename(file));
  }

  Future<void> removeOwned(String value) async {
    if (!owned.contains(value) || !ownedPath(value)) return;
    for (var attempt = 0; attempt < 12; attempt++) {
      try {
        final type = await FileSystemEntity.type(value, followLinks: false);
        if (type == FileSystemEntityType.notFound) {
          owned.remove(value);
          return;
        }
        if (type != FileSystemEntityType.file) return;
        final resolved = await File(value).resolveSymbolicLinks();
        if (!p.equals(p.normalize(value), p.normalize(resolved))) return;
        await File(value).delete();
        owned.remove(value);
        return;
      } on FileSystemException {
        // A decoder can release its read mapping just after the route's last frame.
        if (attempt < 11) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
    }
  }

  Future<void> load(bool original) async {
    if (!current) return;
    final token = ++generation, previous = job;
    final oldPath = path;
    setState(() {
      before = original;
      loading = true;
      error = null;
      path = null;
    });
    if (previous != null) unawaited(widget.state.core.cancel(previous));
    // Release the previous full bitmap before the renderer or decoder allocates another.
    await WidgetsBinding.instance.endOfFrame;
    await evictCurrent();
    if (oldPath != null && owned.contains(oldPath)) await removeOwned(oldPath);
    final rejected = failedDecode;
    if (rejected != null) {
      await removeOwned(rejected);
      if (owned.contains(rejected)) {
        if (current && token == generation) {
          setState(() {
            error = '临时细节文件仍在使用，请关闭后重新打开。';
            loading = false;
          });
        }
        return;
      }
      failedDecode = null;
    }
    if (!current || token != generation) return;
    final id = 'photo-detail-${DateTime.now().microsecondsSinceEpoch}';
    job = id;
    try {
      final inspected = await widget.state.core.call('source.inspect', {
        'path': widget.photo.path,
        'owner': widget.owner,
        'expectedSourceSha': widget.expectedSourceSha,
      }, id);
      if (inspected['sourceSha'] != widget.expectedSourceSha) {
        throw const AppFailure('原图已改变，请重新打开照片。');
      }
      if (!current || token != generation) return;
      final geometry = object(widget.recipe['geometry'] ?? {});
      final raw =
          widget.photo.info['raw'] == true ||
          const [
            'nef',
            'nrw',
            'arw',
            'cr2',
            'cr3',
            'dng',
            'raf',
            'rw2',
            'orf',
            'pef',
            'srw',
          ].contains(
            p.extension(widget.photo.path).replaceFirst('.', '').toLowerCase(),
          );
      String shown;
      int? declaredWidth, declaredHeight;
      if (original && geometry.isEmpty && !raw) {
        shown = widget.photo.path;
      } else {
        final recipe = original
            ? Recipe().data
            : Recipe(data: widget.recipe).data;
        if (original && geometry.isNotEmpty) recipe['geometry'] = geometry;
        recipe['border'] = <String, dynamic>{};
        final result = await widget.state.core.call('media.detailRender', {
          'path': widget.photo.path,
          'owner': widget.owner,
          'recipe': recipe,
          'expectedSourceSha': widget.expectedSourceSha,
        }, id);
        final output = result['path'];
        if (output is String && ownedPath(output)) owned.add(output);
        if (result['sourceSha'] != widget.expectedSourceSha ||
            result['temporary'] != true ||
            result['fullResolution'] != true ||
            output is! String ||
            !owned.contains(output) ||
            result['width'] is! int ||
            result['height'] is! int ||
            (result['width'] as int) < 1 ||
            (result['height'] as int) < 1) {
          if (output is String) await removeOwned(output);
          throw const AppFailure('未取得有效的全尺寸细节文件。');
        }
        if (!current || token != generation) {
          await removeOwned(output);
          return;
        }
        shown = output;
        declaredWidth = result['width'] as int;
        declaredHeight = result['height'] as int;
      }
      if (!current || token != generation) return;
      final next = FileImage(File(shown));
      final stream = next.resolve(const ImageConfiguration());
      final dimensions = Completer<Size>();
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          final size = Size(
            info.image.width.toDouble(),
            info.image.height.toDouble(),
          );
          info.dispose();
          stream.removeListener(listener);
          if (!dimensions.isCompleted) dimensions.complete(size);
        },
        onError: (Object failure, StackTrace? trace) {
          stream.removeListener(listener);
          if (!dimensions.isCompleted) dimensions.completeError(failure, trace);
        },
      );
      stream.addListener(listener);
      late final Size size;
      try {
        size = await dimensions.future;
      } catch (_) {
        // This provider has not been installed in the page. Release its cache
        // and its own full-size file before exposing the retry action.
        await next.evict();
        await removeOwned(shown);
        if (owned.contains(shown)) failedDecode = shown;
        rethrow;
      }
      if (!current || token != generation) {
        await next.evict();
        await removeOwned(shown);
        return;
      }
      if (declaredWidth != null &&
          (size.width != declaredWidth || size.height != declaredHeight)) {
        await next.evict();
        await removeOwned(shown);
        throw const AppFailure('细节文件的实际尺寸与渲染结果不符。');
      }
      try {
        final checked = await widget.state.core.call('source.inspect', {
          'owner': widget.owner,
          'path': widget.photo.path,
          'expectedSourceSha': widget.expectedSourceSha,
        }, id);
        if (checked['sourceSha'] != widget.expectedSourceSha) {
          throw const AppFailure('原图已改变，请重新打开照片。');
        }
      } catch (_) {
        await next.evict();
        await removeOwned(shown);
        rethrow;
      }
      if (!current || token != generation) {
        await next.evict();
        await removeOwned(shown);
        return;
      }
      setState(() {
        provider = next;
        path = shown;
        width = size.width.round();
        height = size.height.round();
        loading = false;
        transform.value = Matrix4.identity();
      });
    } catch (failure) {
      if (current && token == generation) {
        setState(() {
          error = '$failure';
          loading = false;
        });
      }
    } finally {
      if (job == id) job = null;
    }
  }

  void close([EditorDetailsResult? result]) {
    if (!mounted || routeClosing || ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    routeClosing = true;
    closed = true;
    generation++;
    final active = job;
    job = null;
    if (active != null) unawaited(widget.state.core.cancel(active));
    Navigator.pop(context, result);
  }

  double get actualScale {
    if (width < 1 || height < 1 || viewport.isEmpty) return 1;
    final fit = math.min(viewport.width / width, viewport.height / height);
    return 1 / (fit * MediaQuery.devicePixelRatioOf(context));
  }

  void zoom(double? factor) {
    final scale = factor == null ? 1.0 : actualScale * factor;
    setState(
      () => transform.value = Matrix4.identity()
        ..translateByDouble(
          viewport.width * (1 - scale) / 2,
          viewport.height * (1 - scale) / 2,
          0,
          1,
        )
        ..scaleByDouble(scale, scale, 1, 1),
    );
  }

  Future<void> information() async {
    final raw = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: const Color(0xff19211d),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('细节说明', style: TextStyle(fontSize: 16)),
        content: Text(
          '${widget.photo.name}\n\n${width > 0 ? '$width×$height px\n' : ''}${path == widget.photo.path ? '调色前直接读取原文件像素。' : '当前效果使用全尺寸临时渲染文件。JPEG 为有损处理效果，不等同原文件字节。'}\n\n100% 为一张照片像素对应一个屏幕物理像素，双指可缩放、拖动可查看局部。关闭不写入版本、草稿或系统相册。',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          if (widget.hasRaw)
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('RAW 显影'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
    if (mounted && current && raw == true) close(EditorDetailsResult.raw);
  }

  Widget paletteButton(
    String label,
    VoidCallback? action, {
    bool selected = false,
    bool comparing = false,
  }) => Expanded(
    child: SizedBox(
      height: 48,
      child: Semantics(
        button: true,
        selected: selected,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (selected)
              Positioned(
                left: 0,
                right: 0,
                top: comparing ? 8 : 4,
                bottom: comparing ? 8 : 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xffffe335),
                    borderRadius: BorderRadius.circular(comparing ? 16 : 14),
                  ),
                ),
              ),
            TextButton(
              onPressed: action,
              style: TextButton.styleFrom(
                foregroundColor: selected
                    ? const Color(0xff2a1c12)
                    : const Color(0xbdffffff),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(comparing ? 16 : 14),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    ),
  );
  Widget glass(Widget child, {double radius = 18}) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ui.ImageFilter.blur(sigmaX: 6.1, sigmaY: 6.1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xa6201e1c),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0x45ffffff), width: .5),
        ),
        child: child,
      ),
    ),
  );
  Widget detailHeader() => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x76000000), Colors.transparent],
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              tooltip: '返回照片编辑',
              onPressed: close,
              icon: const HueIcon(
                HueIconKind.back,
                size: 22,
                color: Color(0xfff6f1eb),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: information,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    '细节预览',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    widget.photo.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xccffffff),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 64,
            height: 48,
            child: TextButton(
              onPressed: close,
              child: const Text(
                '完成',
                style: TextStyle(fontSize: 13, color: Color(0xffffe335)),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  Widget comparisonPalette() => Stack(
    fit: StackFit.expand,
    children: [
      Positioned(
        left: 0,
        right: 0,
        top: 4,
        bottom: 4,
        child: glass(const SizedBox.expand(), radius: 20),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            paletteButton(
              '当前',
              current && !loading ? () => unawaited(load(false)) : null,
              selected: !before,
              comparing: true,
            ),
            paletteButton(
              '调色前',
              current && !loading ? () => unawaited(load(true)) : null,
              selected: before,
              comparing: true,
            ),
          ],
        ),
      ),
    ],
  );
  Widget pixelMetric() => InkWell(
    onTap: information,
    child: Align(
      alignment: Alignment.topRight,
      child: glass(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: ValueListenableBuilder<Matrix4>(
            valueListenable: transform,
            builder: (_, matrix, _) => SizedBox(
              height: 26,
              child: Center(
                child: Text(
                  '$width×$height px · ${(matrix.getMaxScaleOnAxis() / actualScale * 100).round()}%',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xe0ffffff),
                  ),
                ),
              ),
            ),
          ),
        ),
        radius: 9,
      ),
    ),
  );
  Widget loadFeedback() => Center(
    child: glass(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                error ?? '载入中…',
                maxLines: 3,
                style: TextStyle(
                  fontSize: 11,
                  color: error != null
                      ? const Color(0xffffb4a7)
                      : const Color(0xe0ffffff),
                ),
              ),
            ),
            if (error != null)
              SizedBox(
                width: 56,
                height: 48,
                child: TextButton(
                  onPressed: current ? () => unawaited(load(before)) : null,
                  child: const Text(
                    '重试',
                    style: TextStyle(fontSize: 12, color: Color(0xffffe335)),
                  ),
                ),
              ),
          ],
        ),
      ),
      radius: 16,
    ),
  );
  Widget zoomPalette() => glass(
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ValueListenableBuilder<Matrix4>(
        valueListenable: transform,
        builder: (_, matrix, _) => Row(
          children: [
            paletteButton(
              '适应',
              provider == null ? null : () => zoom(null),
              selected: matrix == Matrix4.identity(),
            ),
            paletteButton(
              '100%',
              provider == null ? null : () => zoom(1),
              selected: (matrix.getMaxScaleOnAxis() - actualScale).abs() < .005,
            ),
            paletteButton(
              '200%',
              provider == null ? null : () => zoom(2),
              selected:
                  (matrix.getMaxScaleOnAxis() - actualScale * 2).abs() < .005,
            ),
          ],
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: hueviaTheme(Brightness.dark, home: false),
    child: PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          routeClosing = true;
          closed = true;
          generation++;
          if (job != null) unawaited(widget.state.core.cancel(job!));
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xff0a0908),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, bounds) {
              viewport = Size(bounds.maxWidth, bounds.maxHeight);
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (provider != null && !loading && error == null)
                    InteractiveViewer(
                      transformationController: transform,
                      minScale: math.min(1, actualScale),
                      maxScale: math.max(8, actualScale * 2),
                      child: SizedBox.expand(
                        child: Image(
                          image: provider!,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.none,
                          gaplessPlayback: false,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 52,
                    child: detailHeader(),
                  ),
                  Positioned(
                    top: 54,
                    left: math.max(12, (bounds.maxWidth - 184) / 2),
                    width: math.min(184, bounds.maxWidth - 24),
                    height: 48,
                    child: comparisonPalette(),
                  ),
                  if (width > 0)
                    Positioned(
                      right: 12,
                      top: 106,
                      height: 48,
                      child: pixelMetric(),
                    ),
                  if (loading || error != null)
                    Positioned(
                      top: 150,
                      left: 20,
                      right: 20,
                      child: loadFeedback(),
                    ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    width: math.min(
                      MediaQuery.textScalerOf(context).scale(1) >= 1.2
                          ? 232
                          : 216,
                      bounds.maxWidth - 24,
                    ),
                    height: 48,
                    child: zoomPalette(),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    closed = true;
    generation++;
    widget.state.removeListener(ownerChanged);
    if (job != null) unawaited(widget.state.core.cancel(job!));
    final files = List<String>.of(owned);
    unawaited(
      evictCurrent().then((_) async {
        for (final file in files) {
          await removeOwned(file);
        }
      }),
    );
    transform.dispose();
    super.dispose();
  }
}
