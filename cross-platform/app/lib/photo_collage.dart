import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'editor.dart';
import 'theme.dart';

enum CollageLayout { horizontal, vertical, grid }

class CollagePlan {
  const CollagePlan(this.size, this.cells);
  final Size size;
  final List<Rect> cells;
}

/// One geometry plan serves both the preview and the saved image.
CollagePlan planCollage(
  List<Size> sources,
  CollageLayout layout,
  double gap,
  int edge,
) {
  if (sources.length < 2 ||
      sources.length > 9 ||
      gap < 0 ||
      gap > 40 ||
      edge < 256 ||
      edge > 4096 ||
      sources.any(
        (s) =>
            !s.width.isFinite ||
            !s.height.isFinite ||
            s.width <= 0 ||
            s.height <= 0,
      )) {
    throw const AppFailure('请选择 2–9 张有效照片。');
  }
  final space = gap * 4, cells = <Rect>[];
  double width, height;
  if (layout == CollageLayout.grid) {
    final columns = sources.length <= 4 ? 2 : 3,
        rows = (sources.length / (sources.length <= 4 ? 2 : 3)).ceil();
    width = columns * 1000 + (columns + 1) * space;
    height = rows * 1000 + (rows + 1) * space;
    for (var i = 0; i < sources.length; i++) {
      cells.add(
        Rect.fromLTWH(
          space + (i % columns) * (1000 + space),
          space + (i ~/ columns) * (1000 + space),
          1000,
          1000,
        ),
      );
    }
  } else {
    var cursor = space;
    for (final source in sources) {
      final ratio = (source.width / source.height).clamp(.05, 20.0);
      final w = layout == CollageLayout.horizontal ? 1000 * ratio : 1000.0;
      final h = layout == CollageLayout.vertical ? 1000 / ratio : 1000.0;
      cells.add(
        Rect.fromLTWH(
          layout == CollageLayout.horizontal ? cursor : space,
          layout == CollageLayout.vertical ? cursor : space,
          w,
          h,
        ),
      );
      cursor += (layout == CollageLayout.horizontal ? w : h) + space;
    }
    width = layout == CollageLayout.horizontal ? cursor : 1000 + space * 2;
    height = layout == CollageLayout.vertical ? cursor : 1000 + space * 2;
  }
  var scale = edge / math.max(width, height);
  if (width * height * scale * scale > 12000000) {
    scale = math.sqrt(12000000 / (width * height));
  }
  final size = Size(
    math.max(1, (width * scale).floor()).toDouble(),
    math.max(1, (height * scale).floor()).toDouble(),
  );
  return CollagePlan(
    size,
    cells
        .map(
          (r) => Rect.fromLTRB(
            r.left * scale,
            r.top * scale,
            math.min(size.width, r.right * scale),
            math.min(size.height, r.bottom * scale),
          ),
        )
        .toList(),
  );
}

Future<Uint8List> renderCollage(
  List<String> paths,
  CollagePlan plan, {
  required Color background,
  required bool contain,
}) async {
  if (paths.length != plan.cells.length) throw const AppFailure('拼接照片与布局不一致。');
  final recorder = ui.PictureRecorder(), retained = <ui.Image>[];
  final canvas = Canvas(recorder);
  ui.Picture? picture;
  ui.Image? output;
  try {
    canvas.drawColor(background, BlendMode.src);
    for (var i = 0; i < paths.length; i++) {
      final cell = plan.cells[i];
      final bytes = await File(paths[i]).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        final fitFactor =
            (contain
                    ? math.min(
                        cell.width / descriptor.width,
                        cell.height / descriptor.height,
                      )
                    : math.max(
                        cell.width / descriptor.width,
                        cell.height / descriptor.height,
                      ))
                .clamp(.000001, 1.0);
        // Cover can otherwise decode an entire wide panorama for one small
        // square. Bound all retained source bitmaps by the output pixel budget.
        final factor = math.min(fitFactor, math.sqrt(12000000 / paths.length / (descriptor.width * descriptor.height)));
        codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * factor).ceil()),
          targetHeight: math.max(1, (descriptor.height * factor).ceil()),
        );
        final image = (await codec.getNextFrame()).image;
        retained.add(image);
        final fitted = applyBoxFit(
          contain ? BoxFit.contain : BoxFit.cover,
          Size(image.width.toDouble(), image.height.toDouble()),
          cell.size,
        );
        canvas.save();
        canvas.clipRect(cell);
        canvas.drawImageRect(
          image,
          Alignment.center.inscribe(
            fitted.source,
            Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
          ),
          Alignment.center.inscribe(fitted.destination, cell),
          Paint()..filterQuality = FilterQuality.high,
        );
        canvas.restore();
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
      }
    }
    picture = recorder.endRecording();
    output = await picture.toImage(
      plan.size.width.toInt(),
      plan.size.height.toInt(),
    );
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw const AppFailure('拼接图片保存失败，请重试。');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    if (recorder.isRecording) recorder.endRecording().dispose();
    output?.dispose();
    picture?.dispose();
    for (final image in retained) {
      image.dispose();
    }
  }
}

class PhotoCollagePage extends StatefulWidget {
  const PhotoCollagePage({
    super.key,
    required this.state,
    this.rows = const [],
    this.phone = false,
  });
  final AppState state;
  final List<Json> rows;
  final bool phone;
  @override
  State<PhotoCollagePage> createState() => _PhotoCollagePageState();
}

class _CollageSource {
  const _CollageSource(
    this.photo,
    this.path,
    this.size,
    this.recipe,
    this.sourceSha,
  );
  final Photo photo;
  final String path;
  final Size size;
  final Json recipe;
  final String sourceSha;
}

class _PhotoCollagePageState extends State<PhotoCollagePage> {
  late final owner = widget.state.session['user']?['id'] as String? ?? '';
  final sources = <_CollageSource>[];
  CollageLayout layout = CollageLayout.grid;
  double gap = 12;
  bool black = false,
      contain = true,
      busy = false,
      rendering = false,
      changedWhileRendering = false;
  bool cancelled = false;
  Uint8List? preview;
  String? error, job;
  int revision = 0;
  Timer? debounce;
  bool get current =>
      mounted &&
      widget.state.session['logoutPending'] != true &&
      (widget.state.session['user']?['id'] as String? ?? '') == owner;
  CollagePlan plan(int edge) =>
      planCollage(sources.map((s) => s.size).toList(), layout, gap, edge);
  @override
  void initState() {
    super.initState();
    widget.state.addListener(accountChanged);
    if (widget.rows.isNotEmpty) unawaited(loadSelection());
  }

  void accountChanged() {
    if (mounted && !current) {
      revision++;
      debounce?.cancel();
      if (job != null) unawaited(widget.state.core.cancel(job!));
      setState(() {
        preview = null;
        error = '账号已改变，请返回后重新选择照片。';
      });
    }
  }

  Future<void> discard(String path) async {
    if (!p.isWithin(p.join(widget.state.core.root, 'previews'), path)) return;
    try {
      await File(path).delete();
    } on FileSystemException {
      /* disposable */
    }
  }

  @override
  void dispose() {
    cancelled = true;
    revision++;
    debounce?.cancel();
    widget.state.removeListener(accountChanged);
    if (job != null) unawaited(widget.state.core.cancel(job!));
    for (final source in sources) {
      unawaited(discard(source.path));
    }
    super.dispose();
  }

  void check() {
    if (!current || cancelled) throw const AppFailure('拼接已取消或账号已改变。');
  }

  void cancelWork() {
    cancelled = true;
    revision++;
    debounce?.cancel();
    if (job != null) unawaited(widget.state.core.cancel(job!));
    if (mounted) setState(() => error = '已取消拼接处理。');
  }

  Future<void> add(Photo photo) async {
    check();
    if (photo.info['raw'] == true) throw const AppFailure('请先将 RAW 显影为照片后再拼接。');
    final saved = await widget.state.core.call('draft.load', {
      'path': photo.path,
      'owner': owner,
    });
    check();
    job = 'collage-source-${DateTime.now().microsecondsSinceEpoch}';
    final recipe = Recipe(
      data: saved['recipe'] == null ? null : object(saved['recipe']),
    ).data;
    final value = await widget.state.core.call('media.reviewPreview', {
      'path': photo.path,
      'owner': owner,
      'recipe': recipe,
      'maxEdge': 1280,
    }, job);
    final path = value['path'] as String;
    if (!current || cancelled) {
      await discard(path);
      return;
    }
    setState(
      () => sources.add(
        _CollageSource(
          photo,
          path,
          Size(
            (value['width'] as num).toDouble(),
            (value['height'] as num).toDouble(),
          ),
          recipe,
          saved['sourceSha'] as String,
        ),
      ),
    );
  }

  Future<void> loadSelection() async {
    cancelled = false;
    setState(() => busy = true);
    try {
      if (widget.rows.length < 2 || widget.rows.length > 9) {
        throw const AppFailure('一次请选择 2–9 张照片进行拼接。');
      }
      if (widget.rows.any((r) => r['raw'] == true)) {
        throw const AppFailure('请先将 RAW 显影为照片后再拼接。');
      }
      for (final row in widget.rows) {
        check();
        Photo photo;
        if (widget.phone) {
          final imported = await widget.state.core.call('gallery.import', {
            'id': row['id'],
            'batchSelection': true,
          });
          check();
          final info = await widget.state.core.call('media.info', {
            'path': imported['path'],
          });
          check();
          photo = await widget.state.registerPhoto(
            imported['path'] as String,
            imported['name'] as String,
            info,
          );
        } else {
          photo = widget.state.photos.firstWhere(
            (v) => v.path == row['id'],
            orElse: () => throw const AppFailure('所选照片已不在相册中。'),
          );
        }
        await add(photo);
      }
    } catch (failure) {
      if (current) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
      job = null;
      schedule();
    }
  }

  Future<void> pick() async {
    if (busy || !current) return;
    cancelled = false;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final files = await openFiles(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: '照片',
            extensions: ['jpg', 'jpeg', 'png'],
            uniformTypeIdentifiers: ['public.jpeg', 'public.png'],
          ),
        ],
      );
      check();
      if (files.length + sources.length > 9) {
        throw const AppFailure('一次最多拼接 9 张照片。');
      }
      for (final file in files) {
        check();
        final photo = await widget.state.importPhoto(
          file,
          isCurrent: () => current && !cancelled,
        );
        await add(photo);
      }
    } catch (failure) {
      if (current) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
      job = null;
      schedule();
    }
  }

  void schedule() {
    revision++;
    debounce?.cancel();
    if (current && !cancelled && !busy && sources.length >= 2) {
      debounce = Timer(const Duration(milliseconds: 120), render);
    }
  }

  Future<void> render() async {
    if (!current || cancelled || busy || sources.length < 2) return;
    if (rendering) {
      changedWhileRendering = true;
      return;
    }
    final expected = revision;
    setState(() {
      rendering = true;
      changedWhileRendering = false;
    });
    try {
      final bytes = await renderCollage(
        sources.map((s) => s.path).toList(),
        plan(1024),
        background: black ? Colors.black : Colors.white,
        contain: contain,
      );
      if (current && expected == revision) {
        setState(() {
          preview = bytes;
          error = null;
        });
      }
    } catch (failure) {
      if (current && expected == revision) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => rendering = false);
      if (current && (changedWhileRendering || expected != revision)) {
        schedule();
      }
    }
  }

  Future<void> save() async {
    if (busy || !current || sources.length < 2) return;
    cancelled = false;
    final frozen = plan(4096), selected = List<_CollageSource>.from(sources);
    debounce?.cancel();
    revision++;
    setState(() {
      busy = true;
      error = null;
    });
    String? temporary;
    final fullPaths = <String>[];
    try {
      for (final source in selected) {
        check();
        job = 'collage-full-${DateTime.now().microsecondsSinceEpoch}';
        final full = await widget.state.core.call('media.detailRender', {
          'path': source.photo.path,
          'owner': owner,
          'recipe': source.recipe,
          'expectedSourceSha': source.sourceSha,
        }, job);
        final output = full['path'];
        if (output is String &&
            p.isWithin(p.join(widget.state.core.root, 'previews'), output)) {
          fullPaths.add(output);
        }
        check();
        if (fullPaths.isEmpty ||
            fullPaths.last != output ||
            full['sourceSha'] != source.sourceSha ||
            full['temporary'] != true ||
            full['fullResolution'] != true) {
          throw const AppFailure('照片已变化，请重新选择后拼接。');
        }
      }
      final bytes = await renderCollage(
        fullPaths,
        frozen,
        background: black ? Colors.black : Colors.white,
        contain: contain,
      );
      check();
      final directory = Directory(p.join(widget.state.core.root, 'previews'));
      await directory.create(recursive: true);
      temporary = p.join(
        directory.path,
        'collage-${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await File(temporary).writeAsBytes(bytes, flush: true);
      check();
      final photo = await widget.state.importPhoto(
        XFile(temporary),
        displayName: '拼接_${DateTime.now().millisecondsSinceEpoch}.png',
        isCurrent: () => current && !cancelled,
      );
      check();
      for (final path in fullPaths) {
        await discard(path);
      }
      fullPaths.clear();
      await discard(temporary);
      temporary = null;
      check();
      if (mounted) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => EditorPage(state: widget.state, photo: photo),
          ),
        );
      }
    } catch (failure) {
      if (current) setState(() => error = '$failure');
    } finally {
      job = null;
      for (final path in fullPaths) {
        await discard(path);
      }
      if (temporary != null) await discard(temporary);
      if (mounted) setState(() => busy = false);
    }
  }

  void change(VoidCallback update) {
    if (busy || !current) return;
    setState(update);
    schedule();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HuePalette.of(context);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) cancelWork();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('图片拼接'),
          actions: [
            if (busy)
              TextButton(
                key: const Key('cancel-collage'),
                onPressed: cancelled
                    ? null
                    : () {
                        cancelWork();
                        Navigator.of(context).maybePop();
                      },
                child: const Text('取消处理'),
              ),
            TextButton(
              key: const Key('save-collage'),
              onPressed: !current || busy || sources.length < 2 ? null : save,
              child: const Text('保存'),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Container(
                color: palette.container,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(16),
                child: preview == null
                    ? Center(child: Text(busy ? '正在准备照片…' : '选择 2–9 张照片开始拼接'))
                    : Image.memory(
                        preview!,
                        gaplessPlayback: true,
                        fit: BoxFit.contain,
                      ),
              ),
            ),
            if (busy || rendering) const LinearProgressIndicator(minHeight: 2),
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .48,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final item in CollageLayout.values)
                            ChoiceChip(
                              label: Text(const ['横向', '纵向', '网格'][item.index]),
                              selected: layout == item,
                              onSelected: busy
                                  ? null
                                  : (_) => change(() => layout = item),
                            ),
                        ],
                      ),
                      if (sources.isNotEmpty)
                        SizedBox(
                          height: 74,
                          child: ReorderableListView(
                            scrollDirection: Axis.horizontal,
                            onReorderItem: busy
                                ? (_, _) {}
                                : (old, next) => change(() {
                                    sources.insert(next, sources.removeAt(old));
                                  }),
                            children: [
                              for (var i = 0; i < sources.length; i++)
                                Padding(
                                  key: ValueKey(sources[i]),
                                  padding: const EdgeInsets.only(
                                    right: 8,
                                    top: 8,
                                  ),
                                  child: Stack(
                                    children: [
                                      SizedBox(
                                        width: 64,
                                        height: 64,
                                        child: Image.file(
                                          File(sources[i].path),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        child: ColoredBox(
                                          color: Colors.black54,
                                          child: Padding(
                                            padding: const EdgeInsets.all(2),
                                            child: Text(
                                              '${i + 1}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        child: SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: IconButton(
                                            tooltip: '移除第 ${i + 1} 张',
                                            icon: const Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              shadows: [Shadow(blurRadius: 2)],
                                            ),
                                            onPressed: busy
                                                ? null
                                                : () => change(() {
                                                    final removed = sources
                                                        .removeAt(i);
                                                    unawaited(
                                                      discard(removed.path),
                                                    );
                                                    if (sources.length < 2) {
                                                      preview = null;
                                                    }
                                                  }),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          const Text('间距'),
                          Expanded(
                            child: Slider(
                              value: gap,
                              min: 0,
                              max: 40,
                              divisions: 40,
                              label: gap.round().toString(),
                              onChanged: busy
                                  ? null
                                  : (v) => change(() => gap = v),
                            ),
                          ),
                          Text(gap.round().toString()),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => change(() => black = !black),
                            child: Text(black ? '黑色底' : '白色底'),
                          ),
                        ],
                      ),
                      if (layout == CollageLayout.grid)
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('完整显示照片'),
                          subtitle: const Text('关闭后居中裁切，填满每一格'),
                          value: contain,
                          onChanged: busy
                              ? null
                              : (v) => change(() => contain = v),
                        ),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: busy || sources.length >= 9
                                ? null
                                : pick,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: const Text('添加照片'),
                          ),
                          const Spacer(),
                          Text(
                            '${sources.length}/9 · 长按缩略图排序',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      if (sources.length >= 2)
                        Text(
                          '保存为 ${plan(4096).size.width.toInt()} × ${plan(4096).size.height.toInt()} 独立图片，可继续编辑和导出',
                          style: TextStyle(
                            fontSize: 12,
                            color: palette.secondary,
                          ),
                        ),
                      if (error != null)
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SafeArea(top: false, child: SizedBox(height: 4)),
          ],
        ),
      ),
    );
  }
}
