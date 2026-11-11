import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'hue_icons.dart';

/// The native session owns real encoded pixels. Flutter decodes only bounded
/// viewports, including at 100%, rather than two full-resolution photographs.
class ExportPreviewPage extends StatefulWidget {
  const ExportPreviewPage({
    super.key,
    required this.state,
    required this.photo,
    required this.recipe,
    required this.owner,
    required this.options,
  });
  final AppState state;
  final Photo photo;
  final Json recipe, options;
  final String owner;
  @override
  State<ExportPreviewPage> createState() => _ExportPreviewPageState();
}

class _ExportPreviewPageState extends State<ExportPreviewPage> {
  Json? session, frame;
  String? error, activeJob;
  bool creating = true, committing = false, rendering = false, pending = false;
  bool before = false, accountChanged = false;
  double cx = .5, cy = .5, scale = 0, startScale = 1;
  Size viewport = Size.zero;
  double deviceScale = 1;
  int revision = 0;
  Timer? debounce;
  HueviaCore get core => widget.state.core;
  @override
  void initState() {
    super.initState();
    widget.state.addListener(checkAccount);
    unawaited(create());
  }

  void checkAccount() {
    if ((widget.state.session['user']?['id'] as String? ?? '') ==
        widget.owner) {
      return;
    }
    if (!accountChanged && mounted) {
      revision++;
      final old = frame;
      setState(() {
        accountChanged = true;
        frame = null;
        error = '账号已改变，请重新打开成品预览。';
      });
      unawaited(discard(old));
      if (activeJob != null) unawaited(core.cancel(activeJob!));
      if (session != null) unawaited(close(session!['id'] as String));
    }
  }

  Future<void> close(String id) async {
    try {
      await core.call('media.exportPreviewClose', {'id': id});
    } catch (_) {
      /* App startup also removes abandoned preview sessions. */
    }
  }

  Future<void> discard(Json? value) async {
    if (value == null) return;
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    for (final key in ['before', 'jpeg']) {
      final path = value[key];
      if (path is! String || !p.isWithin(p.join(core.root, 'previews'), path)) {
        continue;
      }
      try {
        await FileImage(File(path)).evict();
        await File(path).delete();
      } on FileSystemException {
        /* The native session may already be closed. */
      }
    }
  }

  @override
  void dispose() {
    revision++;
    debounce?.cancel();
    widget.state.removeListener(checkAccount);
    if (activeJob != null) unawaited(core.cancel(activeJob!));
    unawaited(discard(frame));
    unawaited(discard({'jpeg': session?['overview']}));
    if (session != null) unawaited(close(session!['id'] as String));
    super.dispose();
  }

  Future<void> create() async {
    final serial = ++revision;
    final job = 'export-preview-${DateTime.now().microsecondsSinceEpoch}';
    activeJob = job;
    setState(() {
      creating = true;
      error = null;
    });
    try {
      final result = await core.call('media.exportPreview', {
        'path': widget.photo.path,
        'owner': widget.owner,
        'recipe': widget.recipe,
        ...widget.options,
      }, job);
      if (!mounted || serial != revision || accountChanged) {
        await close(result['id'] as String);
        return;
      }
      setState(() {
        session = result;
        creating = false;
        scale = 0;
      });
      queueFrame();
    } catch (failure) {
      if (mounted && serial == revision) {
        setState(() {
          error = '$failure';
          creating = false;
        });
      }
    } finally {
      if (activeJob == job) activeJob = null;
    }
  }

  double get fit => session == null || viewport.isEmpty
      ? 1
      : math.min(
          8,
          math.min(
            viewport.width * deviceScale / (session!['width'] as num),
            viewport.height * deviceScale / (session!['height'] as num),
          ),
        );
  double get effectiveScale => scale == 0 ? fit : scale;
  void queueFrame() {
    debounce?.cancel();
    debounce = Timer(
      const Duration(milliseconds: 80),
      () => unawaited(renderFrame()),
    );
  }

  Future<void> renderFrame() async {
    if (session == null || viewport.isEmpty || accountChanged || committing) {
      return;
    }
    if (rendering) {
      pending = true;
      return;
    }
    final serial = revision,
        job = 'export-frame-${DateTime.now().microsecondsSinceEpoch}';
    final width = (viewport.width * deviceScale).round().clamp(1, 4096),
        height = (viewport.height * deviceScale).round().clamp(1, 4096);
    activeJob = job;
    setState(() => rendering = true);
    try {
      final result = await core.call('media.exportPreviewFrame', {
        'id': session!['id'],
        'width': width,
        'height': height,
        'scale': effectiveScale,
        'cx': cx,
        'cy': cy,
      }, job);
      if (!mounted || serial != revision) {
        await discard(result);
        return;
      }
      final old = frame;
      setState(() {
        frame = result;
        error = null;
      });
      unawaited(discard(old));
    } catch (failure) {
      if (mounted && serial == revision) setState(() => error = '$failure');
    } finally {
      if (activeJob == job) activeJob = null;
      if (mounted) {
        setState(() => rendering = false);
        if (pending) {
          pending = false;
          unawaited(renderFrame());
        }
      }
    }
  }

  Future<void> commit() async {
    if (session == null || committing || accountChanged || creating) return;
    debounce?.cancel();
    // Keep the frame queue drained before committing its owning session.
    if (rendering) {
      setState(() => error = '预览正在更新，请稍候再导出。');
      return;
    }
    final job = 'export-confirm-${DateTime.now().microsecondsSinceEpoch}';
    activeJob = job;
    setState(() => committing = true);
    try {
      final result = await core.call('media.exportPreviewCommit', {
        'id': session!['id'],
      }, job);
      if (mounted) Navigator.pop(context, result);
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (activeJob == job) activeJob = null;
      if (mounted) setState(() => committing = false);
    }
  }

  Widget glass(Widget child, {double radius = 24}) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xc022211f),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: const Color(0x33ffffff)),
        ),
        child: child,
      ),
    ),
  );

  Widget segment(String label, bool selected, VoidCallback? action) => Padding(
    padding: const EdgeInsets.all(4),
    child: TextButton(
      onPressed: action,
      style: TextButton.styleFrom(
        foregroundColor: selected
            ? const Color(0xff2a1c12)
            : const Color(0xfff6f1eb),
        backgroundColor: selected
            ? const Color(0xffffe335)
            : Colors.transparent,
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        shape: const StadiumBorder(),
      ),
      child: Text(label),
    ),
  );

  void zoom(double value, [Offset? focus]) {
    final old = effectiveScale;
    final point = focus ?? viewport.center(Offset.zero);
    setState(() {
      scale = value;
      if (value == 0) {
        cx = .5;
        cy = .5;
      } else if (session != null) {
        cx =
            (cx +
                    (point.dx - viewport.width / 2) *
                        deviceScale *
                        (1 / old - 1 / value) /
                        (session!['width'] as num))
                .clamp(0.0, 1.0);
        cy =
            (cy +
                    (point.dy - viewport.height / 2) *
                        deviceScale *
                        (1 / old - 1 / value) /
                        (session!['height'] as num))
                .clamp(0.0, 1.0);
      }
    });
    queueFrame();
  }

  double anchorX = .5, anchorY = .5;
  Offset doubleTapPoint = Offset.zero;
  Widget canvas() => LayoutBuilder(
    builder: (context, box) {
      final dpr = MediaQuery.devicePixelRatioOf(context),
          raw = box.maxWidth * box.maxHeight * dpr * dpr,
          ratio = math.min(
            dpr,
            math.min(
              4096 / math.max(box.maxWidth, box.maxHeight),
              math.sqrt(12000000 / math.max(1, raw)) * dpr,
            ),
          );
      if (viewport != box.biggest || deviceScale != ratio) {
        viewport = box.biggest;
        deviceScale = ratio;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) queueFrame();
        });
      }
      final enabled = !committing && !accountChanged && session != null;
      return GestureDetector(
        key: const ValueKey('export-preview-viewport'),
        behavior: HitTestBehavior.opaque,
        onDoubleTapDown: enabled
            ? (d) => doubleTapPoint = d.localPosition
            : null,
        onDoubleTap: enabled
            ? () => zoom(scale == 0 ? 1 : 0, doubleTapPoint)
            : null,
        onScaleStart: enabled
            ? (d) {
                startScale = effectiveScale;
                anchorX =
                    cx +
                    (d.localFocalPoint.dx - viewport.width / 2) *
                        deviceScale /
                        (startScale * (session!['width'] as num));
                anchorY =
                    cy +
                    (d.localFocalPoint.dy - viewport.height / 2) *
                        deviceScale /
                        (startScale * (session!['height'] as num));
              }
            : null,
        onScaleUpdate: enabled
            ? (d) {
                setState(() {
                  scale = (startScale * d.scale).clamp(math.min(fit, 1), 8.0);
                  cx =
                      (anchorX -
                              (d.localFocalPoint.dx - viewport.width / 2) *
                                  deviceScale /
                                  (scale * (session!['width'] as num)))
                          .clamp(0.0, 1.0);
                  cy =
                      (anchorY -
                              (d.localFocalPoint.dy - viewport.height / 2) *
                                  deviceScale /
                                  (scale * (session!['height'] as num)))
                          .clamp(0.0, 1.0);
                });
                queueFrame();
              }
            : null,
        child: Semantics(
          image: true,
          label: before ? '编码前的实际像素' : '实际 JPEG 解码像素',
          child: frame == null
              ? const SizedBox.expand()
              : Image.file(
                  File(frame![before ? 'before' : 'jpeg'] as String),
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => Center(
                    child: TextButton(
                      onPressed: queueFrame,
                      child: const Text('重试预览'),
                    ),
                  ),
                ),
        ),
      );
    },
  );

  Widget locator() {
    final iw = (session!['width'] as num).toDouble(),
        ih = (session!['height'] as num).toDouble();
    final factor = math.min(82 / iw, 108 / ih),
        width = iw * factor,
        height = ih * factor;
    final l = (cx - viewport.width * deviceScale / (2 * effectiveScale * iw))
            .clamp(0.0, 1.0),
        r = (cx + viewport.width * deviceScale / (2 * effectiveScale * iw))
            .clamp(0.0, 1.0),
        t = (cy - viewport.height * deviceScale / (2 * effectiveScale * ih))
            .clamp(0.0, 1.0),
        b = (cy + viewport.height * deviceScale / (2 * effectiveScale * ih))
            .clamp(0.0, 1.0);
    return IgnorePointer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x88ffffff)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(session!['overview'] as String),
              fit: BoxFit.fill,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const SizedBox(),
            ),
            Positioned.fromRect(
              rect: Rect.fromLTRB(l * width, t * height, r * width, b * height),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: const Color(0xffffe335),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        session != null && !creating && !committing && !accountChanged;
    final headerHeight = math.max(
      52.0,
      MediaQuery.textScalerOf(context).scale(30) + 20,
    );
    return PopScope(
      canPop: !committing,
      child: Theme(
        data: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Roboto'),
          colorScheme: const ColorScheme.dark(primary: Color(0xffffe335)),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontSize: 12),
              minimumSize: const Size(48, 48),
            ),
          ),
        ),
        child: Scaffold(
          backgroundColor: const Color(0xff0a0908),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  Positioned.fill(child: canvas()),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: headerHeight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x99000000), Colors.transparent],
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: IconButton(
                              tooltip: '返回导出设置',
                              onPressed: committing
                                  ? null
                                  : () => Navigator.pop(context),
                              icon: const HueIcon(
                                HueIconKind.back,
                                color: Color(0xfff6f1eb),
                                size: 22,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  '成品预览',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  widget.photo.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xddffffff),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 52,
                            height: 48,
                            child: Tooltip(
                              message: '导出并分享',
                              child: TextButton(
                                onPressed: enabled ? commit : null,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                ),
                                child: const Text('导出'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: headerHeight + 6,
                    left: (box.maxWidth - math.min(220, box.maxWidth - 24)) / 2,
                    width: math.min(220, box.maxWidth - 24),
                    height: 48,
                    child: glass(
                      Row(
                        children: [
                          Expanded(
                            child: segment(
                              'JPEG',
                              !before,
                              () => setState(() => before = false),
                            ),
                          ),
                          Expanded(
                            child: segment(
                              '编码前',
                              before,
                              () => setState(() => before = true),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (session != null)
                    Positioned(
                      top: headerHeight + 64,
                      right: 12,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: box.maxWidth - 24,
                        ),
                        child: glass(
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            child: Text(
                              '${session!['width']}×${session!['height']} · JPEG ${session!['quality']} · ${((session!['bytes'] as num) / 1024).toStringAsFixed(1)} KB',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          radius: 12,
                        ),
                      ),
                    ),
                  Positioned(
                    left: 12,
                    bottom: 12,
                    width: math.min(222, box.maxWidth - 24),
                    height: 48,
                    child: glass(
                      Row(
                        children: [
                          Expanded(
                            child: segment(
                              '适应',
                              scale == 0,
                              enabled ? () => zoom(0) : null,
                            ),
                          ),
                          Expanded(
                            child: segment(
                              '100%',
                              scale != 0 && (scale - 1).abs() < .005,
                              enabled ? () => zoom(1) : null,
                            ),
                          ),
                          Expanded(
                            child: segment(
                              '200%',
                              scale != 0 && (scale - 2).abs() < .005,
                              enabled ? () => zoom(2) : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (session?['overview'] is String &&
                      !accountChanged &&
                      effectiveScale > fit + .0001)
                    Positioned(
                      right: 12,
                      bottom: box.maxWidth < 360 ? 84 : 12,
                      child: locator(),
                    ),
                  if (creating ||
                      error != null ||
                      (frame == null && !accountChanged))
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: glass(
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 280),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    error ?? '生成中…',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: error == null
                                          ? Colors.white
                                          : Colors.orangeAccent,
                                    ),
                                  ),
                                  if (!creating &&
                                      !accountChanged &&
                                      session == null)
                                    TextButton(
                                      onPressed: create,
                                      child: const Text('重试生成成品'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          radius: 14,
                        ),
                      ),
                    ),
                  if (creating || rendering || committing)
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(minHeight: 2),
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
