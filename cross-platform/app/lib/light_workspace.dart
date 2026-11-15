import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'legacy_local_preview.dart';
import 'editing_viewport.dart';

/// Source-coordinate relighting uses the same masks for preview, drafts and exports.
List<Json> lightMasks({
  required int style,
  required double amount,
  required double angle,
  required double size,
  required double warmth,
  required Offset center,
}) {
  if (amount == 0) return [];
  final radians = angle * math.pi / 180;
  final dx = math.cos(radians) * .42, dy = math.sin(radians) * .42;
  final radial = style != 1;
  return [
    {
      'kind': radial ? 'radial' : 'linear',
      'x0': radial ? center.dx : (center.dx - dx).clamp(0.0, 1.0),
      'y0': radial ? center.dy : (center.dy - dy).clamp(0.0, 1.0),
      'x1': radial ? size : (center.dx + dx).clamp(0.0, 1.0),
      'y1': radial ? size : (center.dy + dy).clamp(0.0, 1.0),
      'radius': .08,
      'feather': style == 2 ? .55 : .95,
      'exposure': ((style == 3 ? -1 : 1) * amount * (style == 2 ? .24 : .15))
          .round(),
      'temperature': (warmth * amount / 100).round(),
      'saturation': 0,
      'inverted': false,
      'enabled': true,
      'points': <double>[],
    },
  ];
}

class LightWorkspace extends StatefulWidget {
  const LightWorkspace({
    super.key,
    required this.state,
    required this.photo,
    required this.owner,
    required this.recipe,
    required this.localState,
    required this.frame,
    required this.isCurrent,
    required this.onFinished,
    required this.onBackReady,
    required this.layoutBuilder,
  });
  final AppState state;
  final Photo photo;
  final String owner;
  final Json recipe, localState, frame;
  final bool Function() isCurrent;
  final ValueChanged<Json?> onFinished;
  final ValueChanged<VoidCallback?> onBackReady;
  final EditingWorkspaceLayoutBuilder layoutBuilder;
  @override
  State<LightWorkspace> createState() => _LightWorkspaceState();
}

class _LightWorkspaceState extends State<LightWorkspace> {
  int style = 0;
  double amount = 0, angle = 0, size = .5, warmth = 0;
  Offset center = const Offset(.5, .5);
  bool closing = false, original = false;
  Timer? debounce;
  bool get current =>
      mounted &&
      !closing &&
      widget.isCurrent() &&
      widget.state.session['logoutPending'] != true &&
      (widget.state.session['user']?['id'] as String? ?? '') == widget.owner;
  late final preview = LegacyLocalPreview(
    core: widget.state.core,
    photo: widget.photo,
    owner: widget.owner,
    recipe: widget.recipe,
    localState: widget.localState,
    initialFrame: widget.frame,
    isCurrent: () => current,
    discard: discard,
  );

  Future<void> discard(String? path) async {
    if (path == null ||
        !p.isWithin(p.join(widget.state.core.root, 'previews'), path)) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    try {
      await FileImage(File(path)).evict();
      await File(path).delete();
    } on FileSystemException {
      /* Owned temporary preview may be pruned later. */
    }
  }

  @override
  void initState() {
    super.initState();
    preview.addListener(changed);
    widget.state.addListener(changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onBackReady(() => finish());
    });
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void offer() {
    if (!current) return;
    preview.offer({
      'masks': [
        ...(widget.localState['masks'] as List? ?? []),
        ...lightMasks(
          style: style,
          amount: amount,
          angle: angle,
          size: size,
          warmth: warmth,
          center: center,
        ),
      ],
      'clones': widget.localState['clones'] ?? [],
    }, interactive: false);
  }

  void adjust(VoidCallback update, {bool immediate = false}) {
    if (!current) return;
    setState(update);
    debounce?.cancel();
    if (immediate) {
      offer();
    } else {
      debounce = Timer(const Duration(milliseconds: 120), offer);
    }
  }

  void finish([Json? result]) {
    if (!mounted || closing || result != null && !current) return;
    closing = true;
    debounce?.cancel();
    widget.onFinished(result);
  }

  @override
  void dispose() {
    debounce?.cancel();
    widget.onBackReady(null);
    widget.state.removeListener(changed);
    preview.removeListener(changed);
    preview.dispose();
    unawaited(discard(widget.frame['path'] as String?));
    super.dispose();
  }

  Widget slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> change,
  ) => Row(
    children: [
      SizedBox(width: 48, child: Text(label)),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          onChanged: current ? change : null,
          onChangeEnd: (_) {
            debounce?.cancel();
            offer();
          },
        ),
      ),
      SizedBox(
        width: 42,
        child: Text(value.round().toString(), textAlign: TextAlign.end),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final frame = original ? widget.frame : preview.frame ?? widget.frame;
    final photo = LayoutBuilder(
      builder: (context, bounds) {
        final width = (frame['width'] as num? ?? 1).toDouble(),
            height = (frame['height'] as num? ?? 1).toDouble();
        final scale = math.min(
          bounds.maxWidth / width,
          bounds.maxHeight / height,
        );
        return Center(
          child: SizedBox(
            width: width * scale,
            height: height * scale,
            child: GestureDetector(
              onTapDown: !current
                  ? null
                  : (details) => adjust(
                      () => center = Offset(
                        (details.localPosition.dx / (width * scale)).clamp(
                          0,
                          1,
                        ),
                        (details.localPosition.dy / (height * scale)).clamp(
                          0,
                          1,
                        ),
                      ),
                      immediate: true,
                    ),
              child: Image.file(
                File(frame['path'] as String),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    const Center(child: Text('预览读取失败，请返回重试')),
              ),
            ),
          ),
        );
      },
    );
    final panel = SafeArea(
      top: false,
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '取消光影',
                onPressed: () => finish(),
                icon: const Icon(Icons.close),
              ),
              const Expanded(
                child: Text(
                  '光影',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: !current
                    ? null
                    : () => adjust(() {
                        amount = warmth = angle = 0;
                        center = const Offset(.5, .5);
                        size = .5;
                      }, immediate: true),
                child: const Text('重置'),
              ),
              TextButton(
                key: const Key('apply-light'),
                onPressed:
                    current && preview.ready && !(debounce?.isActive ?? false)
                    ? () => finish(preview.result)
                    : null,
                child: const Text('应用'),
              ),
            ],
          ),
          if (preview.busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                Wrap(
                  spacing: 8,
                  children: [
                    for (var i = 0; i < 4; i++)
                      ChoiceChip(
                        label: Text(const ['柔光', '侧光', '聚光', '阴影'][i]),
                        selected: style == i,
                        onSelected: !current
                            ? null
                            : (_) => adjust(() {
                                style = i;
                                if (amount == 0) amount = 50;
                              }, immediate: true),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('轻点照片调整光影位置', style: TextStyle(fontSize: 12)),
                slider('强度', amount, 0, 100, (v) => adjust(() => amount = v)),
                if (style == 1)
                  slider('方向', angle, 0, 360, (v) => adjust(() => angle = v))
                else
                  slider(
                    '范围',
                    size * 100,
                    10,
                    100,
                    (v) => adjust(() => size = v / 100),
                  ),
                slider(
                  '冷暖',
                  warmth,
                  -100,
                  100,
                  (v) => adjust(() => warmth = v),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => setState(() => original = !original),
                      child: Text(original ? '查看效果' : '对比进入前'),
                    ),
                    const Spacer(),
                    if (preview.error != null)
                      TextButton(
                        onPressed: preview.retry,
                        child: const Text('重试预览'),
                      ),
                  ],
                ),
                if (preview.error != null)
                  Text(
                    '${preview.error}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (!current) const Text('编辑状态已改变，请返回后重新打开。'),
              ],
            ),
          ),
        ],
      ),
    );
    return widget.layoutBuilder(context, photo, panel);
  }
}
