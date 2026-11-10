import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';

class RawDevelopPage extends StatefulWidget {
  const RawDevelopPage({super.key, required this.state, required this.photo});
  final AppState state;
  final Photo photo;
  @override
  State<RawDevelopPage> createState() => _RawDevelopPageState();
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
  bool running = false, pending = false, forwarding = false;
  Timer? debounce;
  StreamSubscription<dynamic>? events;
  Json snapshot() => object(jsonDecode(jsonEncode(settings)));
  @override
  void initState() {
    super.initState();
    events = HueviaCore.progress.listen((event) {
      final value = object(event);
      if (mounted && value['jobId'] == activeJob) {
        setState(() => progress = (value['progress'] as num).toDouble());
      }
    }, onError: (_) {});
    unawaited(render());
  }

  @override
  void dispose() {
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
      await File(path).delete();
    } on FileSystemException {
      /* Disposable native output. */
    }
  }

  void changed(String key, Object value) {
    if (forwarding) return;
    setState(() {
      settings[key] = value;
      error = null;
    });
    revision++;
    debounce?.cancel();
    debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(render()),
    );
  }

  Future<void> render() async {
    if (forwarding || !mounted) return;
    if (running) {
      pending = true;
      if (activeJob != null) await widget.state.core.cancel(activeJob!);
      return;
    }
    final current = revision,
        frozen = snapshot(),
        job = 'raw-preview-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      running = true;
      activeJob = job;
      progress = 0;
    });
    try {
      final result = await widget.state.core.call('media.rawPreview', {
        'path': widget.photo.path,
        'owner': owner,
        'settings': frozen,
      }, job);
      final path = result['path'] as String;
      if (!mounted || current != revision || forwarding) {
        await discard(path);
        return;
      }
      final old = preview;
      setState(() {
        preview = path;
        colorStatus = result['rawColorStatus'] as String? ?? '';
        error = null;
      });
      if (old != null && old != path) await discard(old);
    } catch (failure) {
      if (mounted && current == revision && !forwarding) {
        setState(() => error = '$failure');
      }
    } finally {
      if (mounted && activeJob == job) {
        setState(() {
          running = false;
          activeJob = null;
        });
      }
      if (mounted && pending && !forwarding) {
        pending = false;
        unawaited(render());
      }
    }
  }

  Future<void> openEditor() async {
    if (forwarding) return;
    debounce?.cancel();
    pending = false;
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
      final result = await widget.state.core.call('media.rawDevelop', {
        'path': widget.photo.path,
        'owner': owner,
        'settings': frozen,
      }, job);
      temporary = result['path'] as String;
      if (!mounted) return;
      final photo = await widget.state.importPhoto(
        XFile(
          temporary,
          name: '${p.basenameWithoutExtension(widget.photo.name)}.jpg',
        ),
      );
      final working = await widget.state.updatePhoto(photo, {
        'rawSource': widget.photo.path,
        'rawSourceSha': result['sourceSha'],
        'development': result['settings'],
        'rawColorStatus': result['rawColorStatus'],
      });
      await widget.state.updatePhoto(widget.photo, {
        'lastDevelopment': result['settings'],
      });
      if (mounted) {
        context.push('/edit/${widget.state.photos.indexOf(working)}');
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
      }
    }
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
  @override
  Widget build(BuildContext context) {
    final image = Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Theme.of(context).colorScheme.surfaceContainer),
        if (preview != null)
          InteractiveViewer(
            maxScale: 8,
            child: Center(
              child: Image.file(
                File(preview!),
                fit: BoxFit.contain,
                semanticLabel: 'RAW 显影预览',
              ),
            ),
          )
        else
          const Center(child: Icon(Icons.raw_on_outlined, size: 48)),
        if (running || forwarding)
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
            colorStatus == 'NEUTRAL'
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
                  onPressed: openEditor,
                  child: const Text('完成显影，继续编辑'),
                ),
        ),
      ),
    );
  }
}
