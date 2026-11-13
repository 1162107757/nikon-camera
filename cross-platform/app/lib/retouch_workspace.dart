import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'theme.dart';

/// Tentative edits remain owned by this route until Apply returns localData.
class RetouchWorkspace extends StatefulWidget {
  const RetouchWorkspace({
    super.key,
    required this.state,
    required this.photo,
    required this.owner,
    required this.recipe,
    required this.isCurrent,
    this.patch = false,
  });
  final AppState state;
  final Photo photo;
  final String owner;
  final Json recipe;
  final bool Function() isCurrent;
  final bool patch;
  @override
  State<RetouchWorkspace> createState() => _RetouchWorkspaceState();
}

class _RetouchWorkspaceState extends State<RetouchWorkspace> {
  Json? data, frame;
  final undo = <Json>[], redo = <Json>[];
  String? job, error;
  bool busy = true, stopped = false, manual = false, healMode = false;
  int selected = 0, tab = 0, bodyTool = 0;
  double radius = .025;
  double targetX = .5, targetY = .5;
  final points = <Offset>[];
  List<Json> people = [];
  int bodyPerson = 0;
  final temporary = <String>{};
  bool get current =>
      mounted &&
      widget.isCurrent() &&
      widget.state.session['logoutPending'] != true &&
      (widget.state.session['user']?['id'] as String? ?? '') == widget.owner;
  Json get portrait => object(data?['portrait'] ?? {});
  List<Json> get faces =>
      (portrait['faces'] as List? ?? []).map(object).toList();
  Json get chosen =>
      faces.isEmpty ? {} : faces[selected.clamp(0, faces.length - 1)];
  Json get skin => object(portrait['skin'] ?? {});
  Json get area => (portrait['body'] as List? ?? []).length == 3
      ? object((portrait['body'] as List)[bodyTool])
      : {};
  @override
  void initState() {
    super.initState();
    widget.state.addListener(accountChanged);
    unawaited(load());
  }

  void accountChanged() {
    if (!current) {
      unawaited(stop());
      if (mounted) setState(() => error = '账号已改变，请返回重新打开照片。');
    }
  }

  Future<Json> call(String op, Json value) async {
    if (!current || stopped) throw const AppFailure('编辑计算已停止。');
    final id = 'retouch-${DateTime.now().microsecondsSinceEpoch}';
    job = id;
    try {
      final result = await widget.state.core.call(op, {
        'path': widget.photo.path,
        'owner': widget.owner,
        ...value,
      }, id);
      if (!current || stopped) throw const AppFailure('编辑计算已停止。');
      return result;
    } finally {
      if (job == id) job = null;
    }
  }

  Future<void> remove(String path) async {
    if (!p.isWithin(p.join(widget.state.core.root, 'previews'), path)) return;
    try {
      await File(path).delete();
    } on FileSystemException {
      /* disposable */
    }
  }

  Future<Json> render(Json next) async {
    final result = await call(
      widget.patch ? 'media.localPreview' : 'media.reviewPreview',
      {
        'recipe': {
          ...widget.recipe,
          'localData': next['localData'],
          'geometry': <String, dynamic>{},
          'border': <String, dynamic>{},
        },
        'maxEdge': 1280,
      },
    );
    final path = result['path'] as String;
    temporary.add(path);
    return result;
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        busy = true;
        stopped = false;
        error = null;
      });
    }
    try {
      final next = await call('media.retouchDescribe', {
        'localData': widget.recipe['localData'] ?? '',
      });
      final image = await render(next);
      if (current) {
        setState(() {
          data = next;
          frame = image;
          if (next['people'] is List) {
            people = (next['people'] as List).map(object).toList();
            bodyPerson = next['selectedPerson'] as int? ?? 0;
          }
        });
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> perform(String op, Json payload) async {
    if (busy || !current || data == null) return;
    setState(() {
      busy = true;
      stopped = false;
      error = null;
    });
    try {
      final next = await call(op, {
        'localData': data!['localData'],
        ...payload,
      });
      final image = await render(next);
      if (current) {
        setState(() {
          undo.add(data!);
          if (undo.length > 20) undo.removeAt(0);
          redo.clear();
          data = next;
          frame = image;
          selected = selected.clamp(0, math.max(0, faces.length - 1));
          if (payload['action'] == 'manualFace') {
            selected = math.max(0, faces.length - 1);
            manual = false;
          }
          if (next['people'] is List) {
            people = (next['people'] as List).map(object).toList();
            bodyPerson = next['selectedPerson'] as int? ?? 0;
          }
        });
      }
    } catch (failure) {
      if (mounted && !stopped) setState(() => error = '$failure');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          points.clear();
        });
      }
    }
  }

  Future<void> history(bool forward) async {
    final from = forward ? redo : undo, to = forward ? undo : redo;
    if (busy || from.isEmpty || !current || data == null) return;
    setState(() {
      busy = true;
      stopped = false;
      error = null;
    });
    try {
      final next = from.last;
      final image = await render(next);
      if (current) {
        setState(() {
          to.add(data!);
          from.removeLast();
          data = next;
          frame = image;
        });
      }
    } catch (failure) {
      if (mounted && !stopped) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> stop() async {
    stopped = true;
    if (job != null) {
      try {
        await widget.state.core.cancel(job!);
      } catch (_) {
        /* The next result boundary also checks stopped. */
      }
    }
  }

  void change(String action, Json value) => unawaited(
    perform('media.retouchChange', {
      'action': action,
      'index': selected,
      'value': value,
    }),
  );
  Widget tones(Json source, String action) => Column(
    children: [
      DropdownButtonFormField<int>(
        key: ValueKey('tone-$action-${data?['sha256']}-$selected'),
        initialValue: source['toneId'] as int? ?? 0,
        decoration: const InputDecoration(labelText: '肤色目标'),
        items: [
          for (final row in data?['tones'] as List? ?? [])
            DropdownMenuItem(
              value: object(row)['id'] as int,
              child: Text(object(row)['name'] as String),
            ),
        ],
        onChanged: busy
            ? null
            : (value) => change(action, {
                'toneId': value,
                'toneAmount': (source['toneAmount'] as num?)?.toDouble() == 0
                    ? .35
                    : source['toneAmount'],
              }),
      ),
      _RetouchSlider(
        key: ValueKey('tone-amount-$action-${data?['sha256']}'),
        label: '肤色强度',
        value: ((source['toneAmount'] as num?)?.toDouble() ?? 0) * 100,
        min: 0,
        max: 100,
        enabled: !busy,
        onEnd: (value) => change(action, {'toneAmount': value / 100}),
      ),
    ],
  );
  Widget positionTool({required bool patch}) => ExpansionTile(
    title: const Text('精确定位'),
    children: [
      _RetouchSlider(
        label: '位置左右',
        value: targetX * 100,
        min: 0,
        max: 100,
        enabled: !busy,
        onEnd: (value) => setState(() => targetX = value / 100),
      ),
      _RetouchSlider(
        label: '位置上下',
        value: targetY * 100,
        min: 0,
        max: 100,
        enabled: !busy,
        onEnd: (value) => setState(() => targetY = value / 100),
      ),
      FilledButton.tonal(
        onPressed: busy
            ? null
            : () => unawaited(
                perform(
                  patch ? 'media.retouchPatch' : 'media.retouchHeal',
                  patch
                      ? {
                          'points': [targetX, targetY],
                          'radius': radius,
                        }
                      : {'x': targetX, 'y': targetY, 'radius': radius},
                ),
              ),
        child: Text(patch ? '修补此位置' : '修复此位置'),
      ),
    ],
  );
  Widget slider(
    String label,
    String key,
    Json source, {
    double min = 0,
    double max = 100,
    String? action,
  }) {
    final initial = ((source[key] as num?)?.toDouble() ?? 0).clamp(min, max);
    return StatefulBuilder(
      key: ValueKey('$key-${data?['sha256']}-$selected-$bodyTool'),
      builder: (context, update) {
        var value = initial;
        return _RetouchSlider(
          label: label,
          value: value,
          min: min,
          max: max,
          enabled: !busy && current,
          onEnd: (v) => change(
            action ??
                (tab == 0
                    ? 'face'
                    : tab == 1
                    ? 'skin'
                    : 'body'),
            {if (tab == 2) 'tool': bodyTool, key: v.round()},
          ),
        );
      },
    );
  }

  Widget controls() {
    if (widget.patch) {
      return Column(
        children: [
          const Text('涂抹需要移除的小范围，松手后自动寻找附近干净纹理。'),
          _RetouchSlider(
            label: '画笔大小',
            value: radius * 1000,
            min: 5,
            max: 100,
            enabled: !busy,
            onEnd: (v) => setState(() => radius = v / 1000),
          ),
          Text('已创建 ${data?['patchCount'] ?? 0} 个修补'),
          positionTool(patch: true),
          if ((data?['patchCount'] as int? ?? 0) > 0)
            TextButton(
              onPressed: busy
                  ? null
                  : () => unawaited(
                      perform('media.retouchChange', {
                        'action': 'removePatch',
                        'index': (data!['patchCount'] as int) - 1,
                      }),
                    ),
              child: const Text('移除最后一个修补'),
            ),
        ],
      );
    }
    return Column(
      children: [
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('脸部')),
            ButtonSegment(value: 1, label: Text('皮肤')),
            ButtonSegment(value: 2, label: Text('身体')),
          ],
          selected: {tab},
          onSelectionChanged: busy
              ? null
              : (v) => setState(() {
                  tab = v.single;
                  manual = false;
                }),
        ),
        const SizedBox(height: 10),
        FilledButton.tonal(
          onPressed: busy
              ? null
              : () => unawaited(
                  perform('media.retouchAnalyze', {
                    'mode': ['face', 'skin', 'body'][tab],
                  }),
                ),
          child: Text(['自动选脸与五官分析', '分析皮肤范围', '自动定位身体'][tab]),
        ),
        if (tab == 0) ...[
          Wrap(
            spacing: 8,
            children: [
              for (var i = 0; i < faces.length; i++)
                ChoiceChip(
                  label: Text('人物 ${i + 1}'),
                  selected: selected == i,
                  onSelected: busy ? null : (_) => setState(() => selected = i),
                ),
              FilterChip(
                label: const Text('手动添加人脸'),
                selected: manual,
                onSelected: busy
                    ? null
                    : (v) => setState(() {
                        manual = v;
                        if (v) healMode = false;
                      }),
              ),
              FilterChip(
                label: const Text('点按祛痘'),
                selected: healMode,
                onSelected: busy
                    ? null
                    : (value) => setState(() {
                        healMode = value;
                        manual = false;
                      }),
              ),
            ],
          ),
          if (faces.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('自动分析无人脸时，可点击“手动添加人脸”后在照片上点选脸部。'),
            ),
          if (manual)
            TextButton(
              onPressed: busy
                  ? null
                  : () => change('manualFace', {'cx': .5, 'cy': .4}),
              child: const Text('在中心添加人脸后调整范围'),
            ),
          if (faces.isNotEmpty) ...[
            ExpansionTile(
              title: const Text('调整脸部范围'),
              children: [
                for (final entry in [
                  ('中心左右', 'cx', 0.0, 100.0),
                  ('中心上下', 'cy', 0.0, 100.0),
                  ('脸部宽度', 'rx', 1.0, 50.0),
                  ('脸部高度', 'ry', 1.0, 50.0),
                ])
                  _RetouchSlider(
                    key: ValueKey('${data?['sha256']}-${entry.$2}-$selected'),
                    label: entry.$1,
                    value: (chosen[entry.$2] as num).toDouble() * 100,
                    min: entry.$3,
                    max: entry.$4,
                    enabled: !busy,
                    onEnd: (value) => change('face', {entry.$2: value / 100}),
                  ),
              ],
            ),
            slider('提亮', 'brightness', chosen, min: -100),
            slider('磨皮', 'smoothing', chosen),
            slider('纹理保留', 'texture', chosen),
            slider('肤色冷暖', 'warmth', chosen, min: -100),
            slider('红润', 'redness', chosen, min: -100),
            slider('柔光补光', 'FILL', chosen),
            slider('面部光影', 'light', chosen, min: -100),
            slider('阴影提亮', 'shadows', chosen),
            slider('眼下修复', 'UNDER_EYE', chosen),
            if (chosen['hasLandmarks'] == true) ...[
              slider('眼神清晰', 'EYE_DETAIL', chosen),
              slider('眼白净化', 'EYE_WHITE', chosen),
              slider('牙齿去黄', 'TEETH', chosen),
            ],
            slider('光源左右', 'LIGHT_X', chosen, min: -100),
            slider('光源上下', 'LIGHT_Y', chosen, min: -100),
            slider('自然精修', 'NATURAL', chosen),
            tones(chosen, 'face'),
            TextButton(
              onPressed: busy ? null : () => change('removeFace', {}),
              child: const Text('移除所选人脸'),
            ),
          ],
          if (healMode)
            _RetouchSlider(
              label: '祛痘半径',
              value: radius * 1000,
              min: 2,
              max: 100,
              enabled: !busy,
              onEnd: (value) => setState(() => radius = value / 1000),
            ),
          if (healMode) positionTool(patch: false),
        ],
        if (tab == 1) ...[
          Text(
            portrait['hasSkinMask'] == true
                ? ((portrait['skinPixels'] as int? ?? 0) >= 32
                      ? '皮肤范围已分析'
                      : '未找到可确认的皮肤范围，可重试或使用局部画笔。')
                : '先分析皮肤范围，再调节效果。',
          ),
          if (data?['analysisEngine'] == 'Vision')
            const Text('此设备以人物分割和脸部取样肤色范围选择皮肤。'),
          if (portrait['hasSkinMask'] == true &&
              (portrait['skinPixels'] as int? ?? 0) >= 32) ...[
            slider('全身磨皮', 'smoothing', skin),
            slider('匀肤', 'EVENNESS', skin),
            slider('去油光', 'SHINE', skin),
            slider('纹理保留', 'TEXTURE', skin),
            tones(skin, 'skin'),
          ],
        ],
        if (tab == 2) ...[
          if (people.length > 1)
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < people.length; i++)
                  ChoiceChip(
                    label: Text('人物 ${i + 1}'),
                    selected: bodyPerson == i,
                    onSelected: busy
                        ? null
                        : (_) => unawaited(
                            perform('media.retouchAnalyze', {
                              'mode': 'body',
                              'person': i,
                            }),
                          ),
                  ),
              ],
            ),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('瘦身')),
              ButtonSegment(value: 1, label: Text('瘦腿')),
              ButtonSegment(value: 2, label: Text('拉长')),
            ],
            selected: {bodyTool},
            onSelectionChanged: busy
                ? null
                : (v) => setState(() => bodyTool = v.single),
          ),
          slider('强度', 'amount', area),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('单腿模式'),
            value: portrait['singleLeg'] == true,
            onChanged: busy
                ? null
                : (value) =>
                      change('body', {'tool': bodyTool, 'singleLeg': value}),
          ),
          for (final entry in [
            ('左边界', 'left'),
            ('上边界', 'top'),
            ('右边界', 'right'),
            ('下边界', 'bottom'),
          ])
            _RetouchSlider(
              key: ValueKey('${data?['sha256']}-$bodyTool-${entry.$2}'),
              label: entry.$1,
              value: ((area[entry.$2] as num?)?.toDouble() ?? .5) * 100,
              min: 0,
              max: entry.$2 == 'bottom' ? 96 : 100,
              enabled: !busy,
              onEnd: (v) =>
                  change('body', {'tool': bodyTool, entry.$2: v / 100}),
            ),
          if (portrait['hasBodyMask'] == true)
            slider('背景保护', 'protection', portrait, action: 'body'),
        ],
      ],
    );
  }

  Widget stage() => LayoutBuilder(
    builder: (context, bounds) {
      final width = (frame?['width'] as num?)?.toDouble() ?? 1,
          height = (frame?['height'] as num?)?.toDouble() ?? 1;
      final scale = math.min(
            bounds.maxWidth / width,
            bounds.maxHeight / height,
          ),
          size = Size(width * scale, height * scale);
      Offset point(Offset local) => Offset(
        (local.dx / size.width).clamp(0, 1),
        (local.dy / size.height).clamp(0, 1),
      );
      return Center(
        child: SizedBox.fromSize(
          size: size,
          child: GestureDetector(
            onTapUp: busy
                ? null
                : (event) {
                    final at = point(event.localPosition);
                    if (widget.patch) {
                      unawaited(
                        perform('media.retouchPatch', {
                          'points': [at.dx, at.dy],
                          'radius': radius,
                        }),
                      );
                      return;
                    }
                    if (healMode && tab == 0) {
                      unawaited(
                        perform('media.retouchHeal', {
                          'x': at.dx,
                          'y': at.dy,
                          'radius': radius,
                        }),
                      );
                      return;
                    }
                    if (manual) {
                      setState(() => manual = false);
                      change('manualFace', {'cx': at.dx, 'cy': at.dy});
                    } else {
                      for (var i = 0; i < faces.length; i++) {
                        final f = faces[i];
                        if ((at.dx - (f['cx'] as num)).abs() <
                                (f['rx'] as num) &&
                            (at.dy - (f['cy'] as num)).abs() <
                                (f['ry'] as num)) {
                          setState(() => selected = i);
                          break;
                        }
                      }
                    }
                  },
            onPanStart: !widget.patch || busy
                ? null
                : (event) => setState(() {
                    points.clear();
                    points.add(point(event.localPosition));
                  }),
            onPanUpdate: !widget.patch || busy
                ? null
                : (event) {
                    if (points.length < 512) {
                      setState(() => points.add(point(event.localPosition)));
                    }
                  },
            onPanEnd: !widget.patch || busy
                ? null
                : (_) {
                    if (points.isNotEmpty) {
                      unawaited(
                        perform('media.retouchPatch', {
                          'points': points.expand((v) => [v.dx, v.dy]).toList(),
                          'radius': radius,
                        }),
                      );
                    }
                  },
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (frame != null)
                  Image.file(
                    File(frame!['path'] as String),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    semanticLabel: '待编辑照片：${widget.photo.name}',
                  ),
                IgnorePointer(
                  child: CustomPaint(
                    painter: _RetouchOverlay(
                      faces: widget.patch || tab != 0 ? [] : faces,
                      selected: selected,
                      points: points.toList(),
                      radius: radius,
                      body: !widget.patch && tab == 2 ? area : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: hueviaTheme(Brightness.dark, home: false),
    child: PopScope(
      canPop: !busy,
      child: Scaffold(
        backgroundColor: const Color(0xff191918),
        appBar: AppBar(
          title: Text(widget.patch ? '自动修补' : '人像精修'),
          actions: [
            TextButton(
              onPressed: busy || data == null || !current
                  ? null
                  : () => Navigator.pop(context, data),
              child: const Text('应用'),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(flex: 5, child: stage()),
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.orangeAccent),
                  ),
                ),
              if (error != null && data == null && !busy)
                TextButton(
                  onPressed: () => unawaited(load()),
                  child: const Text('重新载入'),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: '撤销',
                    onPressed: busy || undo.isEmpty
                        ? null
                        : () => unawaited(history(false)),
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton(
                    tooltip: '重做',
                    onPressed: busy || redo.isEmpty
                        ? null
                        : () => unawaited(history(true)),
                    icon: const Icon(Icons.redo),
                  ),
                  if (busy)
                    TextButton(
                      onPressed: () => unawaited(stop()),
                      child: const Text('停止计算'),
                    ),
                  if (!busy)
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                ],
              ),
              Expanded(
                flex: 4,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: controls(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    unawaited(stop());
    for (final path in temporary) {
      unawaited(remove(path));
    }
    super.dispose();
  }
}

class _RetouchSlider extends StatefulWidget {
  const _RetouchSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onEnd,
  });
  final String label;
  final double value, min, max;
  final bool enabled;
  final ValueChanged<double> onEnd;
  @override
  State<_RetouchSlider> createState() => _RetouchSliderState();
}

class _RetouchSliderState extends State<_RetouchSlider> {
  double? pending;
  @override
  void didUpdateWidget(_RetouchSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) pending = null;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(widget.label)),
          Text('${(pending ?? widget.value).round()}'),
        ],
      ),
      Slider(
        semanticFormatterCallback: (value) =>
            '${widget.label} ${value.round()}',
        value: (pending ?? widget.value).clamp(widget.min, widget.max),
        min: widget.min,
        max: widget.max,
        divisions: (widget.max - widget.min).round(),
        onChanged: widget.enabled ? (v) => setState(() => pending = v) : null,
        onChangeEnd: widget.enabled ? widget.onEnd : null,
      ),
    ],
  );
}

class _RetouchOverlay extends CustomPainter {
  _RetouchOverlay({
    required this.faces,
    required this.selected,
    required this.points,
    required this.radius,
    this.body,
  });
  final List<Json> faces;
  final int selected;
  final List<Offset> points;
  final double radius;
  final Json? body;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xffffe335);
    for (var i = 0; i < faces.length; i++) {
      final f = faces[i];
      pen.color = i == selected ? const Color(0xffffe335) : Colors.white54;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(
            (f['cx'] as num).toDouble() * size.width,
            (f['cy'] as num).toDouble() * size.height,
          ),
          width: (f['rx'] as num) * size.width * 2,
          height: (f['ry'] as num) * size.height * 2,
        ),
        pen,
      );
    }
    if (body != null && body!.isNotEmpty) {
      pen.color = const Color(0xffffe335);
      canvas.drawRect(
        Rect.fromLTRB(
          (body!['left'] as num) * size.width,
          (body!['top'] as num) * size.height,
          (body!['right'] as num) * size.width,
          (body!['bottom'] as num) * size.height,
        ),
        pen,
      );
    }
    pen
      ..color = const Color(0x88ffe335)
      ..strokeWidth = radius * math.min(size.width, size.height) * 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < points.length; i++) {
      final a = Offset(points[i].dx * size.width, points[i].dy * size.height);
      final b = i == 0
          ? a
          : Offset(
              points[i - 1].dx * size.width,
              points[i - 1].dy * size.height,
            );
      canvas.drawLine(a, b, pen);
    }
  }

  @override
  bool shouldRepaint(covariant _RetouchOverlay oldDelegate) => true;
}
