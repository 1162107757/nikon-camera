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
import 'collage_composition.dart';
import 'collage_workspace.dart';
import 'export_save.dart';
import 'export_settings_model.dart';
export 'collage_composition.dart';

Future<Uint8List> renderCollage(
  List<String> paths,
  CollagePlan plan, {
  required Color background,
  required bool contain,
  CollageStyle style = const CollageStyle(),
  List<CollageTransform>? transforms,
}) async {
  if (paths.length != plan.cells.length ||
      (transforms != null && transforms.length != paths.length)) {
    throw const AppFailure('拼接照片与布局不一致。');
  }
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
        final transform = transforms?[i] ?? const CollageTransform();
        final width = transform.turns.isOdd
            ? descriptor.height
            : descriptor.width;
        final height = transform.turns.isOdd
            ? descriptor.width
            : descriptor.height;
        final fitFactor =
            (contain
                ? math.min(cell.width / width, cell.height / height)
                : math.max(cell.width / width, cell.height / height)) *
            transform.scale.clamp(1.0, 4.0);
        // Cover can otherwise decode an entire wide panorama for one small
        // square. Bound all retained source bitmaps by the output pixel budget.
        final factor = math.min(
          fitFactor.clamp(.000001, 1.0),
          math.sqrt(
            12000000 / paths.length / (descriptor.width * descriptor.height),
          ),
        );
        codec = await descriptor.instantiateCodec(
          targetWidth: math.max(1, (descriptor.width * factor).ceil()),
          targetHeight: math.max(1, (descriptor.height * factor).ceil()),
        );
        final image = (await codec.getNextFrame()).image;
        retained.add(image);
        paintCollageImage(
          canvas,
          image,
          cell,
          transforms?[i] ?? const CollageTransform(),
          contain: contain,
          matrix: collageColorMatrix(style),
          radius: style.radius * plan.size.width / 390,
        );
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
      }
    }
    paintCollageTexts(canvas, style.texts, plan.size);
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
  _CollageSource(this.photo, this.path, this.size, this.recipe, this.sourceSha);
  final Photo photo;
  final String path;
  final Size size;
  final Json recipe;
  final String sourceSha;
  CollageTransform transform = const CollageTransform();
}

class _PhotoCollagePageState extends State<PhotoCollagePage> {
  late final owner = widget.state.session['user']?['id'] as String? ?? '';
  final sources = <_CollageSource>[];
  CollageStyle style = const CollageStyle();
  CollageTool tool = CollageTool.layout;
  bool busy = false, cancelled = false;
  String? error, job;
  int revision = 0;
  int? selectedPhoto;
  ExportSave? exportTask;
  ExportSettings? preparingExport;
  int exportRevision = -1;
  bool get current =>
      mounted &&
      widget.state.session['logoutPending'] != true &&
      (widget.state.session['user']?['id'] as String? ?? '') == owner;
  CollagePlan plan(int edge) => composeCollage(
    sources.map((s) => s.size).toList(),
    style,
    edge,
    transforms: sources.map((s) => s.transform).toList(),
  );
  @override
  void initState() {
    super.initState();
    widget.state.addListener(accountChanged);
    if (widget.rows.isNotEmpty) unawaited(loadSelection());
  }

  void accountChanged() {
    if (mounted && !current) {
      revision++;
      if (job != null) unawaited(widget.state.core.cancel(job!));
      setState(() {
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
    widget.state.removeListener(accountChanged);
    exportTask?.dispose();
    preparingExport?.dispose();
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
    if (job != null) unawaited(widget.state.core.cancel(job!));
    unawaited(exportTask?.cancel());
    preparingExport?.dispose();
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
  }

  Future<void> save({bool edit = true}) async {
    if (busy || !current || sources.length < 2) return;
    cancelled = false;
    final frozen = plan(4096), selected = List<_CollageSource>.from(sources);
    final frozenStyle = style,
        transforms = sources.map((s) => s.transform).toList();
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
        background: frozenStyle.background,
        contain: frozenStyle.contain,
        style: frozenStyle,
        transforms: transforms,
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
      if (!edit) {
        exportTask?.dispose();
        final settings = ExportSettings(
          state: widget.state,
          photo: photo,
          owner: owner,
          recipe: Recipe().data,
          isCurrent: () => current && !cancelled,
        );
        preparingExport = settings;
        try {
          await settings.load();
          check();
          if (settings.error != null) throw AppFailure(settings.error!);
          final items = await settings.freezeSelected();
          check();
          exportTask = ExportSave(widget.state, owner, items);
        } finally {
          settings.dispose();
          if (identical(preparingExport, settings)) preparingExport = null;
        }
        exportRevision = revision;
        await exportTask!.run();
        check();
        if (!exportTask!.done) {
          throw AppFailure(exportTask!.error ?? '保存到手机相册未完成，请重试。');
        }
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('拼图已保存到手机相册')));
        }
      } else if (mounted) {
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

  void movePhoto(int old, int next) {
    change(() {
      sources.insert(next, sources.removeAt(old));
      selectedPhoto = null;
    });
  }

  void removePhoto(int index) {
    change(() {
      final removed = sources.removeAt(index);
      if (!sources.any((source) => source.path == removed.path)) {
        unawaited(discard(removed.path));
      }
      selectedPhoto = null;
    });
  }

  Future<void> replacePhoto(int index) async {
    if (busy || !current) return;
    cancelled = false;
    setState(() {
      busy = true;
      error = null;
    });
    final before = sources.length;
    try {
      final photo = await widget.state.pickPhoto();
      check();
      if (photo == null) return;
      await add(photo);
      check();
      if (sources.length > before) {
        final replacement = sources.removeLast(), removed = sources[index];
        setState(() {
          sources[index] = replacement;
        });
        if (!sources.any((source) => source.path == removed.path)) {
          await discard(removed.path);
        }
      }
    } catch (failure) {
      if (current) setState(() => error = '$failure');
    } finally {
      job = null;
      if (mounted) setState(() => busy = false);
      schedule();
    }
  }

  Future<void> download() async {
    if (busy || !current || sources.length < 2) return;
    if (exportTask != null &&
        exportRevision == revision &&
        !exportTask!.invalid) {
      cancelled = false;
      setState(() {
        busy = true;
        error = null;
      });
      try {
        await exportTask!.run();
        check();
        if (!exportTask!.done) {
          throw AppFailure(exportTask!.error ?? '保存未完成，请重试。');
        }
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('拼图已保存到手机相册')));
        }
      } catch (failure) {
        if (current) setState(() => error = '$failure');
      } finally {
        if (mounted) setState(() => busy = false);
      }
    } else {
      await save(edit: false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: true,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) cancelWork();
    },
    child: CollageWorkspace(
      paths: sources.map((s) => s.path).toList(),
      sizes: sources.map((s) => s.size).toList(),
      transforms: sources.map((s) => s.transform).toList(),
      style: style,
      tool: tool,
      selectedPhoto: selectedPhoto,
      busy: busy,
      enabled: current,
      error: error,
      onClose: () {
        cancelWork();
        Navigator.of(context).maybePop();
      },
      onEdit: () => save(),
      onDownload: download,
      onAdd: pick,
      onStyle: (value) => change(() => style = value),
      onTool: (value) => setState(() {
        tool = value;
        selectedPhoto = null;
      }),
      onSelected: (value) => setState(() => selectedPhoto = value),
      onTransform: (index, value) =>
          change(() => sources[index].transform = value),
      onMove: movePhoto,
      onRemove: removePhoto,
      onReplace: replacePhoto,
    ),
  );
}
