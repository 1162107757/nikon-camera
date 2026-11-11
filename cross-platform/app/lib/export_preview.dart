import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';

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
      setState(() {
        accountChanged = true;
        error = '账号已改变，请重新打开成品预览。';
      });
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
      await discard(old);
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !committing,
    child: Theme(
      data: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(primary: Color(0xffffe335)),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xff181d1b),
        appBar: AppBar(
          title: const Text('成品预览', style: TextStyle(fontSize: 14)),
          backgroundColor: Colors.transparent,
          actions: [
            TextButton(
              onPressed:
                  session == null || creating || committing || accountChanged
                  ? null
                  : commit,
              child: const Text('导出并分享'),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in const [
                      ('成品 JPEG', false),
                      ('编码前', true),
                    ])
                      TextButton(
                        onPressed: () => setState(() => before = entry.$2),
                        style: TextButton.styleFrom(
                          foregroundColor: before == entry.$2
                              ? const Color(0xffffe335)
                              : Colors.white,
                        ),
                        child: Text(entry.$1),
                      ),
                    TextButton(
                      onPressed: session == null
                          ? null
                          : () {
                              setState(() {
                                scale = 0;
                                cx = .5;
                                cy = .5;
                              });
                              queueFrame();
                            },
                      child: const Text('适应'),
                    ),
                    TextButton(
                      onPressed: session == null
                          ? null
                          : () {
                              setState(() => scale = 1);
                              queueFrame();
                            },
                      child: const Text('100%'),
                    ),
                    IconButton(
                      tooltip: '缩小',
                      onPressed: session == null
                          ? null
                          : () {
                              setState(
                                () => scale = math.max(fit, effectiveScale / 2),
                              );
                              queueFrame();
                            },
                      icon: const Icon(Icons.remove),
                    ),
                    IconButton(
                      tooltip: '放大',
                      onPressed: session == null
                          ? null
                          : () {
                              setState(
                                () => scale = math.min(8, effectiveScale * 2),
                              );
                              queueFrame();
                            },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              if (session != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: Text(
                    '${session!['width']} × ${session!['height']} · JPEG ${session!['quality']} · ${((session!['bytes'] as num) / 1024).toStringAsFixed(1)} KB',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final dpr = MediaQuery.devicePixelRatioOf(context),
                        raw = box.maxWidth * box.maxHeight * dpr * dpr;
                    final ratio = math.min(
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
                    return GestureDetector(
                      key: const ValueKey('export-preview-viewport'),
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: committing || accountChanged
                          ? null
                          : (_) => startScale = effectiveScale,
                      onScaleUpdate:
                          committing || accountChanged || session == null
                          ? null
                          : (details) {
                              setState(() {
                                scale = (startScale * details.scale).clamp(
                                  math.min(fit, 1),
                                  8.0,
                                );
                                cx =
                                    (cx -
                                            details.focalPointDelta.dx *
                                                deviceScale /
                                                (scale *
                                                    (session!['width'] as num)))
                                        .clamp(0.0, 1.0);
                                cy =
                                    (cy -
                                            details.focalPointDelta.dy *
                                                deviceScale /
                                                (scale *
                                                    (session!['height']
                                                        as num)))
                                        .clamp(0.0, 1.0);
                              });
                              queueFrame();
                            },
                      child: Semantics(
                        image: true,
                        label: before ? '编码前的实际像素' : '实际 JPEG 解码像素',
                        child: frame == null
                            ? const Center(child: CircularProgressIndicator())
                            : Image.file(
                                File(
                                  frame![before ? 'before' : 'jpeg'] as String,
                                ),
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
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
                ),
              ),
              // Loading must not resize the native viewport. Otherwise each
              // frame changes the viewport height and requests another frame.
              SizedBox(
                height: 2,
                child: creating || rendering || committing
                    ? const LinearProgressIndicator(minHeight: 2)
                    : null,
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
              if (!creating && session == null && !accountChanged)
                TextButton(onPressed: create, child: const Text('重试生成成品')),
            ],
          ),
        ),
      ),
    ),
  );
}
