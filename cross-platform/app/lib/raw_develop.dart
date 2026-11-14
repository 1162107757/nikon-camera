import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'theme.dart';
import 'raw_reference.dart';
import 'latest_preview_queue.dart';
import 'editing_detail_preview.dart';
import 'widgets.dart';

class RawDevelopPage extends StatefulWidget {
  const RawDevelopPage({
    super.key,
    required this.state,
    required this.photo,
    this.automaticallyEdit = false,
    this.isCurrent,
  });
  final AppState state;
  final Photo photo;
  final bool automaticallyEdit;
  final bool Function()? isCurrent;
  @override
  State<RawDevelopPage> createState() => _RawDevelopPageState();
}

class _RawPreviewRequest {
  _RawPreviewRequest(
    this.settings,
    this.reference,
    this.path,
    this.generation,
    this.revision,
  );
  final Json settings;
  final Json? reference;
  final String path;
  final int generation;
  final int revision;
}

class _RawDevelopPageState extends State<RawDevelopPage> {
  static const defaults = <String, dynamic>{
    'whiteBalance': 'CAMERA',
    'colorMode': 'CAMERA_JPEG',
    'temperature': 5500,
    'tint': 0,
    'exposure': 0,
    'highlights': 2,
    'quality': 3,
  };
  late Json settings = {
    ...defaults,
    ...?widget.photo.info['lastDevelopment'] as Map<String, dynamic>?,
  };
  late final String owner =
      widget.state.session['user']?['id'] as String? ?? '';
  String? preview, error, activeJob;
  String colorStatus = '';
  double progress = 0;
  int revision = 0;
  bool running = false, forwarding = false;
  int previewGeneration = 0;
  Size? previewPixelSize;
  Size? detailViewportSize;
  Rect? detailImageFrame;
  double detailPixelRatio = 1;
  bool detailViewportScheduled = false,
      detailFrameCurrent = false,
      detailRouteCurrent = true;
  final previewTransform = TransformationController();
  late final detailPreview = EditingDetailPreviewController(
    core: widget.state.core,
    owner: owner,
    sourcePath: widget.photo.path,
    isCurrent: () => sourceCurrent && !forwarding && detailRouteCurrent,
    maxTileEdge: 2048,
  );
  late final previewQueue = LatestPreviewQueue<_RawPreviewRequest, Json>(
    render: renderPreview,
    isCurrent: previewCurrent,
    onFrame: (request, result, interactive, latest) {
      final old = preview;
      setState(() {
        preview = result['path'] as String;
        final width = result['width'], height = result['height'];
        previewPixelSize =
            width is num &&
                height is num &&
                width.isFinite &&
                height.isFinite &&
                width > 0 &&
                height > 0
            ? Size(width.toDouble(), height.toDouble())
            : null;
        colorStatus = result['rawColorStatus'] as String? ?? '';
        error = null;
      });
      if (!interactive &&
          latest &&
          request.revision == revision &&
          previewPixelSize != null) {
        detailFrameCurrent = true;
        detailPreview.configureRaw(
          settings: request.settings,
          reference: request.reference,
          revision: request.revision,
          frameIdentity: preview!,
          outputSize: previewPixelSize!,
          expectedSourceSha: result['sourceSha'] as String? ?? '',
        );
        detailPreview.setEnabled(true);
        scheduleDetailViewport();
      }
      if (old != null && old != preview) unawaited(discard(old));
    },
    onError: (_, failure, stack) {
      if (sourceCurrent && !forwarding) setState(() => error = '$failure');
    },
    discard: (result) => discard(result['path'] as String),
  );
  bool selectingReference = false;
  late RawJpegReference? reference = RawJpegReference.restore(
    widget.photo.info,
    widget.state.core.root,
  );
  Timer? debounce;
  StreamSubscription<dynamic>? events;
  Json snapshot() => object(jsonDecode(jsonEncode(settings)));
  bool get sourceCurrent =>
      mounted &&
      widget.isCurrent?.call() != false &&
      widget.state.session['logoutPending'] != true &&
      (widget.state.session['user']?['id'] as String? ?? '') == owner;

  void ownerChanged() {
    if (sourceCurrent || !mounted) return;
    debounce?.cancel();
    pauseDetail();
    detailPreview.invalidate();
    previewGeneration++;
    previewQueue.reset();
    revision++;
    final old = preview;
    if (activeJob != null) unawaited(widget.state.core.cancel(activeJob!));
    setState(() {
      preview = null;
      previewPixelSize = null;
      reference = null;
      error = '照片或账号已变化，请返回重新打开。';
    });
    if (old != null) unawaited(discard(old));
  }

  @override
  void initState() {
    super.initState();
    detailPreview.setEnabled(false);
    previewTransform.addListener(updateDetailViewport);
    widget.state.addListener(ownerChanged);
    events = widget.state.core.operationProgress.listen((event) {
      final value = object(event);
      final received = value['progress'];
      if (mounted &&
          activeJob != null &&
          value['jobId'] == activeJob &&
          received is num &&
          received.isFinite &&
          received >= 0 &&
          received <= 1) {
        setState(() => progress = received.toDouble());
      }
    }, onError: (_) {});
    unawaited(widget.automaticallyEdit ? openEditor() : render());
  }

  @override
  void dispose() {
    previewTransform.removeListener(updateDetailViewport);
    previewTransform.dispose();
    detailPreview.dispose();
    previewQueue.close();
    widget.state.removeListener(ownerChanged);
    debounce?.cancel();
    unawaited(events?.cancel());
    if (activeJob != null) unawaited(widget.state.core.cancel(activeJob!));
    if (preview != null) unawaited(discard(preview!));
    super.dispose();
  }

  Future<void> discard(String path, {bool full = false}) async {
    if (!p.isWithin(
      p.join(widget.state.core.root, full ? 'raw-editor' : 'previews'),
      path,
    )) {
      return;
    }
    try {
      if (!full) await FileImage(File(path)).evict();
      await File(path).delete();
    } on FileSystemException {
      /* Disposable native output. */
    }
  }

  void changed(String key, Object value) {
    if (forwarding || !sourceCurrent) return;
    pauseDetail();
    setState(() {
      settings[key] = value;
      error = null;
    });
    revision++;
    unawaited(queuePreview(interactive: true));
    debounce?.cancel();
    debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(render()),
    );
  }

  bool previewCurrent(_RawPreviewRequest request) =>
      sourceCurrent &&
      !forwarding &&
      request.generation == previewGeneration &&
      request.path == widget.photo.path;

  Future<void> render() {
    debounce?.cancel();
    return queuePreview(interactive: false);
  }

  Future<void> queuePreview({required bool interactive}) {
    if (forwarding || !sourceCurrent) return Future.value();
    pauseDetail();
    return previewQueue.offer(
      _RawPreviewRequest(
        snapshot(),
        reference == null
            ? null
            : object(jsonDecode(jsonEncode(reference!.payload))),
        widget.photo.path,
        previewGeneration,
        revision,
      ),
      interactive: interactive,
    );
  }

  Future<Json> renderPreview(
    _RawPreviewRequest request,
    bool interactive,
  ) async {
    final job = 'raw-preview-${DateTime.now().microsecondsSinceEpoch}';
    if (!previewCurrent(request)) {
      throw const AppFailure('照片或账号已变化，请重新打开。');
    }
    setState(() {
      running = true;
      activeJob = job;
      progress = 0;
    });
    try {
      final result = await widget.state.core.call('media.rawPreview', {
        'path': request.path,
        'owner': owner,
        'settings': request.settings,
        if (request.reference != null) 'reference': request.reference,
      }, job);
      if (!mounted || !previewCurrent(request)) return result;
      final path = result['path'] as String;
      Object? decodeFailure;
      // A faster native queue can replace a FileImage before its asynchronous
      // read finishes. Decode each accepted candidate before retiring the old
      // file, so rapid frames never delete an image that is still being read.
      await precacheImage(
        FileImage(File(path)),
        context,
        onError: (failure, stack) => decodeFailure = failure,
      );
      if (decodeFailure != null) {
        await discard(path);
        throw const AppFailure('无法读取 RAW 显影预览，请重试。');
      }
      return result;
    } finally {
      if (mounted && activeJob == job) {
        setState(() {
          running = false;
          activeJob = null;
        });
      }
    }
  }

  Future<void> openEditor() async {
    if (forwarding || !sourceCurrent) return;
    debounce?.cancel();
    detailPreview.setEnabled(false);
    previewGeneration++;
    previewQueue.reset();
    revision++;
    final frozen = snapshot(),
        previous = activeJob,
        job = 'raw-develop-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      forwarding = true;
      activeJob = job;
      progress = 0;
      error = null;
    });
    String? temporary;
    try {
      if (previous != null) await widget.state.core.cancel(previous);
      if (!sourceCurrent) return;
      final result = await widget.state.core.call('media.rawDevelop', {
        'path': widget.photo.path,
        'owner': owner,
        'settings': frozen,
        if (reference != null) 'reference': reference!.payload,
      }, job);
      temporary = result['path'] as String;
      if (!sourceCurrent) return;
      final photo = await widget.state.importPhoto(
        XFile(temporary),
        displayName: '${p.basenameWithoutExtension(widget.photo.name)}.jpg',
      );
      if (!sourceCurrent) return;
      final working = await widget.state.updatePhoto(photo, {
        'rawSource': widget.photo.path,
        'rawSourceSha': result['sourceSha'],
        'development': result['settings'],
        'rawColorStatus': result['rawColorStatus'],
      });
      if (!sourceCurrent) return;
      await widget.state.updatePhoto(widget.photo, {
        'lastDevelopment': result['settings'],
      });
      if (mounted && sourceCurrent) {
        if (widget.automaticallyEdit) {
          context.replace(working.editorLocation);
        } else {
          context.push(working.editorLocation);
        }
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (temporary != null) await discard(temporary, full: true);
      if (mounted) {
        setState(() {
          forwarding = false;
          running = false;
          activeJob = null;
        });
        scheduleDetailViewport();
      }
    }
  }

  void pauseDetail() {
    detailFrameCurrent = false;
    detailPreview.setEnabled(false);
  }

  void scheduleDetailViewport() {
    if (detailViewportScheduled || !mounted) return;
    detailViewportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      detailViewportScheduled = false;
      if (mounted) updateDetailViewport();
    });
  }

  void updateDetailViewport() {
    final viewport = detailViewportSize, plane = detailImageFrame;
    if (!mounted || viewport == null || plane == null) return;
    if (!detailRouteCurrent || forwarding || !sourceCurrent) {
      detailPreview.setEnabled(false);
      return;
    }
    if (detailFrameCurrent) detailPreview.setEnabled(true);
    final frame = MatrixUtils.transformRect(previewTransform.value, plane);
    final clip = Offset.zero & viewport;
    final visible = frame.intersect(clip);
    detailPreview.setViewport(
      visibleRegion: editingDetailVisibleRegion(frame, clip),
      zoom: previewTransform.value.getMaxScaleOnAxis(),
      viewportPixelSize: visible.isEmpty
          ? Size.zero
          : visible.size * detailPixelRatio,
    );
  }

  Widget previewPlane(BoxConstraints bounds) {
    final size = previewPixelSize;
    Widget plane = Image.file(
      File(preview!),
      fit: BoxFit.contain,
      semanticLabel: 'RAW 显影预览',
    );
    if (size != null) {
      final fitted = applyBoxFit(
        BoxFit.contain,
        size,
        bounds.biggest,
      ).destination;
      final nextFrame = Alignment.center.inscribe(
        fitted,
        Offset.zero & bounds.biggest,
      );
      final ratio = MediaQuery.devicePixelRatioOf(context);
      if (detailViewportSize != bounds.biggest ||
          detailImageFrame != nextFrame ||
          detailPixelRatio != ratio) {
        detailViewportSize = bounds.biggest;
        detailImageFrame = nextFrame;
        detailPixelRatio = ratio;
        scheduleDetailViewport();
      }
      plane = SizedBox(
        width: fitted.width,
        height: fitted.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            plane,
            EditingDetailTileLayer(controller: detailPreview),
          ],
        ),
      );
    }
    return InteractiveViewer(
      transformationController: previewTransform,
      maxScale: 32,
      child: Center(child: plane),
    );
  }

  Widget slider(
    String key,
    String name,
    double min,
    double max, {
    String? display,
  }) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(name)),
          Text(display ?? '${settings[key]}'),
        ],
      ),
      Slider(
        min: min,
        max: max,
        value: (settings[key] as num).toDouble().clamp(min, max),
        onChanged: forwarding
            ? null
            : (value) {
                if (key == 'temperature' || key == 'tint') {
                  settings['whiteBalance'] = 'CUSTOM';
                }
                changed(key, value.round());
              },
        onChangeEnd: forwarding ? null : (_) => unawaited(render()),
      ),
    ],
  );
  Widget selection(String key, String label, List<(Object, String)> choices) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DropdownButtonFormField<Object>(
          key: ValueKey('$key-${settings[key]}'),
          initialValue: settings[key],
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: choices
              .map(
                (choice) =>
                    DropdownMenuItem(value: choice.$1, child: Text(choice.$2)),
              )
              .toList(),
          onChanged: forwarding
              ? null
              : (value) {
                  if (value != null) changed(key, value);
                },
        ),
      );

  Future<void> chooseReference() async {
    if (forwarding || selectingReference) return;
    setState(() => selectingReference = true);
    try {
      final candidates = widget.state.photos
          .where(
            (photo) =>
                photo.path != widget.photo.path &&
                photo.info['raw'] != true &&
                [
                  '.jpg',
                  '.jpeg',
                ].contains(p.extension(photo.name).toLowerCase()),
          )
          .toList();
      final selected = await hueBottomSheet<String>(
        context: context,
        builder: (sheet) => SizedBox(
          height: (MediaQuery.sizeOf(sheet).height * .65).clamp(220, 560),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('选择同一张照片的 JPEG 参考'),
              ),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: const Text('从手机选择 JPEG'),
                      onTap: () => Navigator.pop(sheet, 'pick'),
                    ),
                    for (final photo in candidates)
                      ListTile(
                        title: Text(photo.name),
                        onTap: () => Navigator.pop(sheet, photo.path),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      if (!mounted || selected == null) return;
      String path, name;
      if (selected == 'pick') {
        final picked = await widget.state.core.pickFile(preset: false);
        if (!mounted || picked == null) return;
        path = picked['path'] as String;
        name = picked['name'] as String? ?? p.basename(path);
      } else {
        final photo = candidates.firstWhere((photo) => photo.path == selected);
        path = photo.path;
        name = photo.name;
      }
      if (!mounted) return;
      final confirmed = await hueDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('确认同一次拍摄'),
          content: Text(
            'RAW：${widget.photo.name}\nJPEG：$name\n\n仅凭文件名无法确认是否同一张照片，请核对画面和拍摄时刻。匹配或高光校验未通过时，会保留中性色彩。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('使用此 JPEG'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      if ((widget.state.session['user']?['id'] as String? ?? '') != owner) {
        throw const AppFailure('账号已改变，请重新打开照片。');
      }
      final checked = await widget.state.core.call('media.rawReferenceInfo', {
        'path': widget.photo.path,
        'owner': owner,
        'referencePath': path,
      });
      if (!mounted) return;
      if ((widget.state.session['user']?['id'] as String? ?? '') != owner) {
        throw const AppFailure('账号已改变，请重新打开照片。');
      }
      final next = RawJpegReference.checked(
        checked,
        widget.state.core.root,
        name: name,
      );
      pauseDetail();
      await widget.state.updatePhoto(widget.photo, {
        'rawJpegReference': next.stored(widget.state.core.root),
      });
      if (!mounted) return;
      setState(() {
        reference = next;
        settings['colorMode'] = 'CAMERA_JPEG';
        error = null;
      });
      previewGeneration++;
      previewQueue.reset();
      revision++;
      unawaited(render());
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => selectingReference = false);
    }
  }

  Future<void> clearReference() async {
    if (forwarding || selectingReference) return;
    pauseDetail();
    setState(() => selectingReference = true);
    try {
      await widget.state.updatePhoto(widget.photo, {'rawJpegReference': null});
      if (!mounted) return;
      setState(() => reference = null);
      previewGeneration++;
      previewQueue.reset();
      revision++;
      unawaited(render());
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => selectingReference = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    if (detailRouteCurrent != routeCurrent) {
      detailRouteCurrent = routeCurrent;
      scheduleDetailViewport();
    }
    if (widget.automaticallyEdit && error == null) {
      return Scaffold(
        backgroundColor: const Color(0xff242b27),
        appBar: HueHeader(title: widget.photo.name, back: true),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                value: progress > 0 ? progress : null,
                color: const Color(0xffffe335),
              ),
              const SizedBox(height: 16),
              const Text('正在显影 RAW…', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
    }
    final image = Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Theme.of(context).colorScheme.surfaceContainer),
        if (preview != null)
          LayoutBuilder(builder: (_, bounds) => previewPlane(bounds))
        else
          const Center(child: Icon(Icons.raw_on_outlined, size: 48)),
        if ((running && preview == null) || forwarding)
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(minHeight: 3),
          ),
      ],
    );
    final controls = ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(widget.photo.name, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('保留 RAW 原文件，完成显影后继续编辑。'),
        const SizedBox(height: 20),
        selection('colorMode', '色彩', [
          ('CAMERA_JPEG', '匹配相机 JPEG'),
          ('NEUTRAL', '中性 sRGB'),
        ]),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('JPEG 色彩参考'),
          subtitle: Text(
            reference?.name ?? '优先使用 RAW 内嵌 JPEG，可手动选择同次拍摄的 JPEG。',
          ),
          trailing: selectingReference
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: forwarding || selectingReference
                  ? null
                  : chooseReference,
              child: Text(reference == null ? '选择 JPEG 参考' : '更换 JPEG 参考'),
            ),
            if (reference != null)
              TextButton(
                onPressed: forwarding || selectingReference
                    ? null
                    : clearReference,
                child: const Text('恢复内嵌参考'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        selection('whiteBalance', '白平衡', [
          ('CAMERA', '相机白平衡'),
          ('AUTO', '自动白平衡'),
          ('CUSTOM', '自定义'),
        ]),
        slider(
          'temperature',
          '色温',
          2000,
          12000,
          display: '${settings['temperature']} K',
        ),
        slider('tint', '色调', -100, 100),
        slider(
          'exposure',
          '显影曝光',
          -50,
          50,
          display:
              '${((settings['exposure'] as num) / 10).toStringAsFixed(1)} EV',
        ),
        selection('highlights', '高光处理', [
          for (var i = 0; i < 10; i++)
            (
              i,
              i == 0
                  ? '裁切'
                  : i == 1
                  ? '保留'
                  : i == 2
                  ? '混合（默认）'
                  : '重建 $i',
            ),
        ]),
        selection('quality', '解马赛克', [(3, '高质量 AHD'), (0, '快速线性')]),
        if (colorStatus.isNotEmpty)
          Text(
            colorStatus == 'EXTERNAL_MATCHED'
                ? '已使用所选 JPEG 的色彩近似，RAW 原始细节保持。'
                : colorStatus.startsWith('EXTERNAL_')
                ? '所选 JPEG 未通过画面对齐或高光校验，使用中性色彩。请确认来自同次拍摄，或更换参考照片。'
                : colorStatus == 'NEUTRAL'
                ? '使用中性色彩'
                : colorStatus == 'NO_REFERENCE'
                ? '未找到内嵌 JPEG，使用安全显影色彩。'
                : colorStatus.startsWith('UNSAFE') ||
                      colorStatus == 'UNRELIABLE_FIT'
                ? '相机色彩匹配未通过校验，使用安全显影色彩。'
                : '已完成显影色彩校验。',
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              onPressed: forwarding
                  ? null
                  : () {
                      pauseDetail();
                      setState(() => settings = {...defaults});
                      revision++;
                      unawaited(render());
                    },
              child: const Text('重置显影'),
            ),
            if (error != null)
              TextButton(
                onPressed: running || forwarding ? null : render,
                child: const Text('重试'),
              ),
          ],
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('RAW 显影')),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth > 680
              ? Row(
                  children: [
                    Expanded(child: image),
                    SizedBox(width: 340, child: controls),
                  ],
                )
              : Column(
                  children: [
                    Expanded(flex: 5, child: image),
                    Expanded(flex: 4, child: controls),
                  ],
                ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: forwarding
              ? Row(
                  children: [
                    Expanded(
                      child: Text('正在生成完整编辑副本 ${(progress * 100).round()}%'),
                    ),
                    TextButton(
                      onPressed: () {
                        if (activeJob != null) {
                          unawaited(widget.state.core.cancel(activeJob!));
                        }
                      },
                      child: const Text('取消'),
                    ),
                  ],
                )
              : FilledButton(
                  onPressed: selectingReference ? null : openEditor,
                  child: const Text('完成显影，继续编辑'),
                ),
        ),
      ),
    );
  }
}
