import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'curve_control.dart';
import 'recipes.dart';
import 'widgets.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.state, required this.photo});
  final AppState state;
  final Photo photo;
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  Recipe recipe = Recipe();
  final List<Recipe> undo = [], redo = [];
  Timer? debounce;
  StreamSubscription<dynamic>? progressEvents;
  String? preview, error, activeJob;
  bool exporting = false, rendering = false, compare = false, restored = false;
  bool managingRecipes = false;
  bool analyzingCleanup = false;
  double progress = 0;
  int tab = 0, revision = 0, hslBand = 0;
  late final String owner =
      widget.state.session['user']?['id'] as String? ?? '';
  late final File legacyDraft = File(
    p.join(
      widget.state.core.root,
      'shared-drafts',
      owner.isEmpty ? 'guest' : owner,
      '${p.basenameWithoutExtension(widget.photo.path)}.json',
    ),
  );
  @override
  void initState() {
    super.initState();
    progressEvents = HueviaCore.progress.listen((event) {
      final value = object(event);
      if (mounted && value['jobId'] == activeJob) {
        setState(() => progress = (value['progress'] as num).toDouble());
      }
    }, onError: (_) {});
    unawaited(restore());
  }

  Future<void> restore() async {
    try {
      final saved = await widget.state.core.call('draft.load', {
        'path': widget.photo.path,
        'owner': owner,
      });
      if (saved['recipe'] != null) {
        recipe = Recipe(data: object(saved['recipe']));
      } else if (await legacyDraft.exists()) {
        // Validate the old development draft through the original native format.
        final migrated = await widget.state.core.call('draft.save', {
          'path': widget.photo.path,
          'owner': owner,
          'recipe': object(jsonDecode(await legacyDraft.readAsString())),
        });
        recipe = Recipe(data: object(migrated['recipe']));
      }
      if (mounted) {
        setState(() => restored = true);
        await render();
      }
    } catch (failure) {
      if (mounted) setState(() => error = '草稿未能打开：$failure');
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    if (restored && !exporting) unawaited(saveDraft().catchError((_) {}));
    unawaited(progressEvents?.cancel());
    if (activeJob != null) unawaited(widget.state.core.cancel(activeJob!));
    if (preview != null) unawaited(discardPreview(preview));
    super.dispose();
  }

  Future<void> saveDraft() async {
    if ((widget.state.session['user']?['id'] as String? ?? '') != owner) {
      throw const AppFailure('账号已改变，请重新打开照片。');
    }
    await widget.state.core.call('draft.save', {
      'path': widget.photo.path,
      'owner': owner,
      'recipe': recipe.clone().data,
    });
  }

  void checkpoint() {
    undo.add(recipe.clone());
    if (undo.length > 40) undo.removeAt(0);
    redo.clear();
  }

  void change(void Function() mutation, {bool snapshot = true}) {
    if (exporting || managingRecipes || analyzingCleanup || !restored) return;
    if (snapshot) checkpoint();
    setState(() {
      mutation();
      error = null;
    });
    revision++;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(render());
    });
  }

  Future<void> render() async {
    final current = revision;
    final frozen = recipe.clone();
    final previousJob = activeJob;
    if (previousJob != null) await widget.state.core.cancel(previousJob);
    if (!mounted) return;
    final job = 'preview-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      rendering = true;
      activeJob = job;
      progress = 0;
    });
    try {
      final result = await widget.state.core.call('media.preview', {
        'path': widget.photo.path,
        'recipe': frozen.data,
        'owner': owner,
      }, job);
      if (!mounted || current != revision || activeJob != job) {
        await discardPreview(result['path']);
        return;
      }
      final old = preview;
      setState(() {
        preview = result['path'] as String;
        error = null;
      });
      if (old != null &&
          old != result['path'] &&
          p.isWithin(p.join(widget.state.core.root, 'previews'), old)) {
        unawaited(discardPreview(old));
      }
    } catch (failure) {
      if (mounted && current == revision && activeJob == job) {
        setState(() => error = '$failure');
      }
    } finally {
      if (mounted && activeJob == job) {
        setState(() {
          rendering = false;
          activeJob = null;
        });
      }
    }
  }

  Future<void> discardPreview(Object? path) async {
    if (path is! String ||
        !p.isWithin(p.join(widget.state.core.root, 'previews'), path)) {
      return;
    }
    try {
      final file = File(path);
      await FileImage(file).evict();
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A preview is disposable; cleanup failure never affects the original.
    }
  }

  Future<void> openRecipes() async {
    if (exporting || managingRecipes || analyzingCleanup || !restored) return;
    debounce?.cancel();
    revision++;
    setState(() => managingRecipes = true);
    try {
      if (activeJob != null) await widget.state.core.cancel(activeJob!);
      if (!mounted) return;
      final applied = await Navigator.push<Json>(
        context,
        MaterialPageRoute(
          builder: (_) => RecipesPage(
            core: widget.state.core,
            owner: owner,
            path: widget.photo.path,
            current: recipe.clone().data,
          ),
        ),
      );
      if (!mounted) return;
      if (applied != null) {
        checkpoint();
        setState(() => recipe = Recipe(data: applied));
      }
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) {
        setState(() => managingRecipes = false);
        unawaited(render());
      }
    }
  }

  Future<void> analyzeCleanup() async {
    if (exporting || managingRecipes || analyzingCleanup || !restored) return;
    debounce?.cancel();
    revision++;
    final job = 'cleanup-${DateTime.now().microsecondsSinceEpoch}';
    final oldJob = activeJob;
    var succeeded = false;
    setState(() {
      analyzingCleanup = true;
      activeJob = job;
      progress = 0;
      error = null;
    });
    try {
      if (oldJob != null) await widget.state.core.cancel(oldJob);
      final result = await widget.state.core.call('media.cleanupAnalyze', {
        'path': widget.photo.path,
        'owner': owner,
      }, job);
      if (!mounted || activeJob != job) return;
      checkpoint();
      setState(() {
        recipe.data['cleanupData'] = result['cleanupData'];
        recipe.data['cleanup'] = {'amount': 100, 'haze': 100, 'noise': 100};
      });
      succeeded = true;
    } catch (failure) {
      if (mounted && activeJob == job) setState(() => error = '$failure');
    } finally {
      if (mounted && activeJob == job) {
        setState(() {
          analyzingCleanup = false;
          rendering = false;
          activeJob = null;
        });
        if (succeeded) unawaited(render());
      }
    }
  }

  Future<void> editBorderText() async {
    final border = object(recipe.clone().data['border'] ?? {});
    final fields = List<String>.from(
      border['fields'] as List? ?? List.filled(5, ''),
    );
    final inputs = [
      TextEditingController(text: border['brand'] as String? ?? ''),
      TextEditingController(text: border['model'] as String? ?? ''),
      ...fields.map((text) => TextEditingController(text: text)),
    ];
    var automatic = border['automatic'] != false,
        visible = border['visible'] as int? ?? 63;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('拍摄信息'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('自动读取原图信息'),
                    value: automatic,
                    onChanged: (value) => refresh(() => automatic = value),
                  ),
                  for (var i = 0; i < inputs.length; i++)
                    TextField(
                      controller: inputs[i],
                      enabled: !automatic,
                      maxLength: 96,
                      decoration: InputDecoration(
                        labelText: [
                          '品牌',
                          '型号',
                          '焦距',
                          '光圈',
                          '快门',
                          'ISO',
                          '拍摄时间',
                        ][i],
                      ),
                    ),
                  for (var i = 0; i < 6; i++)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '显示${['型号', '焦距', '光圈', '快门', 'ISO', '拍摄时间'][i]}',
                      ),
                      value: (visible & (1 << i)) != 0,
                      onChanged: (value) => refresh(() {
                        visible = value == true
                            ? visible | (1 << i)
                            : visible & ~(1 << i);
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('应用'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      change(() {
        border.addAll({
          'automatic': automatic,
          'visible': visible,
          'brand': inputs[0].text,
          'model': inputs[1].text,
          'fields': inputs.skip(2).map((input) => input.text).toList(),
        });
        recipe.data['border'] = border;
      });
    }
    for (final input in inputs) {
      input.dispose();
    }
  }

  Future<void> export() async {
    final size = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('导出照片', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text('保留原图，另存为 sRGB JPEG。'),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(sheet, 'full'),
                  child: const Text('完整尺寸 · JPEG 95'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.pop(sheet, 'share'),
                  child: const Text('适合分享 · 长边 2048'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(sheet, 'custom'),
                  child: const Text('自定义尺寸与质量'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (size == null || !mounted) return;
    final custom = size == 'custom'
        ? await customExportOptions()
        : <String, dynamic>{};
    if (custom == null || !mounted) return;
    debounce?.cancel();
    final previousJob = activeJob;
    final job = 'export-${DateTime.now().microsecondsSinceEpoch}';
    final frozen = recipe.clone();
    revision++;
    setState(() {
      exporting = true;
      rendering = false;
      progress = 0;
      activeJob = job;
    });
    try {
      if (previousJob != null) await widget.state.core.cancel(previousJob);
      if (!mounted) return;
      final result = await widget.state.core.call('media.export', {
        'path': widget.photo.path,
        'recipe': frozen.data,
        'owner': owner,
        'size': size,
        ...custom,
      }, job);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          sharePositionOrigin: shareAnchor(context),
          files: [XFile(result['path'] as String)],
          text: '${widget.photo.name} · Huevia',
        ),
      );
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) {
        setState(() {
          exporting = false;
          rendering = false;
          activeJob = null;
        });
      }
    }
  }

  Future<Json?> customExportOptions() async {
    final edge = TextEditingController(text: '2048'),
        form = GlobalKey<FormState>();
    var quality = 95;
    final result = await showDialog<Json>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: const Text('自定义导出'),
          content: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('设置长边上限，保留较小照片的尺寸。'),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: edge,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '长边 640–8192 px',
                    ),
                    validator: (value) {
                      final parsed = int.tryParse(value ?? '');
                      return parsed == null || parsed < 640 || parsed > 8192
                          ? '请输入 640–8192 之间的整数。'
                          : null;
                    },
                  ),
                  const SizedBox(height: 20),
                  Text('JPEG 质量 $quality'),
                  Slider(
                    min: 70,
                    max: 100,
                    divisions: 30,
                    value: quality.toDouble(),
                    onChanged: (value) =>
                        refresh(() => quality = value.round()),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(dialog, {
                    'longEdge': int.parse(edge.text),
                    'quality': quality,
                  });
                }
              },
              child: const Text('导出'),
            ),
          ],
        ),
      ),
    );
    edge.dispose();
    return result;
  }

  Widget slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> changed, {
    String? display,
    VoidCallback? start,
  }) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            display ?? value.round().toString(),
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      Row(
        children: [
          IconButton(
            tooltip: '减小$label',
            onPressed:
                exporting || managingRecipes || analyzingCleanup || value <= min
                ? null
                : () {
                    checkpoint();
                    changed((value - 1).clamp(min, max));
                  },
            icon: const Icon(Icons.remove_rounded),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChangeStart: exporting || managingRecipes || analyzingCleanup
                  ? null
                  : (_) => (start ?? checkpoint)(),
              onChanged: exporting || managingRecipes || analyzingCleanup
                  ? null
                  : changed,
            ),
          ),
          IconButton(
            tooltip: '增大$label',
            onPressed:
                exporting || managingRecipes || analyzingCleanup || value >= max
                ? null
                : () {
                    checkpoint();
                    changed((value + 1).clamp(min, max));
                  },
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    ],
  );
  Widget controls() {
    switch (tab) {
      case 7:
        final settings = object(
          recipe.data['cleanup'] ?? {'amount': 100, 'haze': 100, 'noise': 100},
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('自动分析原图中的灰雾和噪点，可分别调整两种效果。'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: exporting || analyzingCleanup || !restored
                  ? null
                  : analyzeCleanup,
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: Text(
                analyzingCleanup
                    ? '正在分析原图…'
                    : recipe.data['cleanupData'] == null
                    ? '分析并应用'
                    : '重新分析原图',
              ),
            ),
            if (analyzingCleanup)
              TextButton(
                onPressed: activeJob == null
                    ? null
                    : () => widget.state.core.cancel(activeJob!),
                child: const Text('取消分析'),
              ),
            if (recipe.data['cleanupData'] != null) ...[
              for (final entry in [
                ('amount', '总强度'),
                ('haze', '去灰'),
                ('noise', '降噪'),
              ])
                slider(
                  entry.$2,
                  (settings[entry.$1] as int? ?? 100).toDouble(),
                  0,
                  100,
                  (value) => change(() {
                    settings[entry.$1] = value.round();
                    recipe.data['cleanup'] = settings;
                  }, snapshot: false),
                ),
              TextButton(
                onPressed: exporting || analyzingCleanup
                    ? null
                    : () => change(() {
                        recipe.data.remove('cleanupData');
                        recipe.data.remove('cleanup');
                      }),
                child: const Text('重置自动去灰'),
              ),
            ],
          ],
        );
      case 0:
        return Column(
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('preset-${recipe.data['presetId']}'),
              initialValue: recipe.data['presetId'] as String,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '滤镜预设'),
              items: [
                const DropdownMenuItem(value: '', child: Text('无滤镜')),
                if ((recipe.data['presetId'] as String).isNotEmpty &&
                    !widget.state.presets.any(
                      (preset) => preset.id == recipe.data['presetId'],
                    ))
                  DropdownMenuItem(
                    value: recipe.data['presetId'] as String,
                    child: Text('${recipe.data['presetName'] ?? '已保存滤镜'} · 草稿'),
                  ),
                ...widget.state.presets.map(
                  (preset) => DropdownMenuItem(
                    value: preset.id,
                    child: Text(
                      preset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
              onChanged: exporting
                  ? null
                  : (value) => change(() {
                      final selected = value ?? '';
                      if ((recipe.data['presetId'] as String).isEmpty &&
                          selected.isNotEmpty) {
                        recipe.data['strength'] = 100;
                      }
                      recipe.data['presetId'] = selected;
                      if (selected.isEmpty) recipe.data['presetName'] = '无滤镜';
                      for (final preset in widget.state.presets) {
                        if (preset.id == selected) {
                          recipe.data['presetName'] = preset.name;
                        }
                      }
                    }),
            ),
            const SizedBox(height: 16),
            slider(
              '滤镜强度',
              (recipe.data['strength'] as int).toDouble(),
              0,
              100,
              (value) => change(
                () => recipe.data['strength'] = value.round(),
                snapshot: false,
              ),
            ),
          ],
        );
      case 1:
        return Column(
          children: [
            for (final raw in widget.state.core.schema['parameters'] as List)
              Builder(
                builder: (context) {
                  final parameter = object(raw),
                      index = parameter['index'] as int,
                      name = parameter['label'] as String,
                      value = recipe.values[index];
                  return Column(
                    children: [
                      slider(
                        name,
                        value.toDouble(),
                        (parameter['min'] as num).toDouble(),
                        (parameter['max'] as num).toDouble(),
                        (v) => change(
                          () => recipe.setValue(index, v.round()),
                          snapshot: false,
                        ),
                        display: index == 1
                            ? '${(value / 10).toStringAsFixed(1)} EV'
                            : '$value',
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (dialog) => AlertDialog(
                              title: Text(name),
                              content: SingleChildScrollView(
                                child: Text(parameter['help'] as String),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog),
                                  child: const Text('知道了'),
                                ),
                              ],
                            ),
                          ),
                          child: Text('$name说明'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
          ],
        );
      case 2:
        final palette = object(
          recipe.data['palette'] ?? {'color': 0, 'tone': 0, 'amount': 100},
        );
        return Column(
          children: [
            for (final entry in [
              ('color', '色彩', -100.0),
              ('tone', '明暗', -100.0),
              ('amount', '强度', 0.0),
            ])
              slider(
                entry.$2,
                (palette[entry.$1] as int).toDouble(),
                entry.$3,
                100,
                (value) => change(() {
                  palette[entry.$1] = value.round();
                  recipe.data['palette'] = palette;
                }, snapshot: false),
              ),
          ],
        );
      case 3:
        final geometry = object(recipe.data['geometry'] ?? {});
        return Column(
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.rotate_right_rounded),
                  label: const Text('旋转 90°'),
                  onPressed: exporting
                      ? null
                      : () => change(() {
                          geometry['turns'] =
                              ((geometry['turns'] as int? ?? 0) + 1) % 4;
                          geometry.addAll({
                            'left': 0,
                            'top': 0,
                            'right': 1000000,
                            'bottom': 1000000,
                          });
                          recipe.data['geometry'] = geometry;
                        }),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.flip_rounded),
                  label: const Text('水平翻转'),
                  onPressed: exporting
                      ? null
                      : () => change(() {
                          geometry['mirrored'] = geometry['mirrored'] != true;
                          final left = geometry['left'] as int? ?? 0;
                          geometry['left'] =
                              1000000 - (geometry['right'] as int? ?? 1000000);
                          geometry['right'] = 1000000 - left;
                          recipe.data['geometry'] = geometry;
                        }),
                ),
              ],
            ),
            const SizedBox(height: 16),
            slider(
              '拉直',
              (geometry['angle'] as int? ?? 0).toDouble(),
              -450,
              450,
              (value) => change(() {
                geometry['angle'] = value.round();
                recipe.data['geometry'] = geometry;
              }, snapshot: false),
              display:
                  '${((geometry['angle'] as int? ?? 0) / 10).toStringAsFixed(1)}°',
            ),
            for (final entry in [
              ('horizontalPerspective', '水平透视'),
              ('verticalPerspective', '垂直透视'),
            ])
              slider(
                entry.$2,
                (geometry[entry.$1] as int? ?? 0).toDouble(),
                -100,
                100,
                (value) => change(() {
                  geometry[entry.$1] = value.round();
                  recipe.data['geometry'] = geometry;
                }, snapshot: false),
              ),
            const SizedBox(height: 12),
            const Text('裁剪范围'),
            for (final entry in [
              ('left', '左侧', 0),
              ('top', '顶部', 0),
              ('right', '右侧', 1000000),
              ('bottom', '底部', 1000000),
            ])
              slider(
                entry.$2,
                (geometry[entry.$1] as int? ?? entry.$3) / 10000,
                0,
                100,
                (value) => change(() {
                  var next = (value * 10000).round();
                  final opposite = {
                    'left': 'right',
                    'right': 'left',
                    'top': 'bottom',
                    'bottom': 'top',
                  }[entry.$1]!;
                  if (entry.$3 == 0) {
                    next = next.clamp(
                      0,
                      (geometry[opposite] as int? ?? 1000000) - 1000,
                    );
                  } else {
                    next = next.clamp(
                      (geometry[opposite] as int? ?? 0) + 1000,
                      1000000,
                    );
                  }
                  geometry[entry.$1] = next;
                  recipe.data['geometry'] = geometry;
                }, snapshot: false),
                display:
                    '${((geometry[entry.$1] as int? ?? entry.$3) / 10000).toStringAsFixed(1)}%',
              ),
            TextButton(
              onPressed: exporting
                  ? null
                  : () => change(() => recipe.data.remove('geometry')),
              child: const Text('重置构图'),
            ),
          ],
        );
      case 5:
        return CurveControl(
          curves:
              (recipe.data['curves'] as List? ??
                      List.generate(4, (_) => [0, 0, 255, 255]))
                  .map((row) => List<int>.from(row as List))
                  .toList(),
          enabled: !exporting && restored,
          onStart: checkpoint,
          onChanged: (value) =>
              change(() => recipe.data['curves'] = value, snapshot: false),
        );
      case 6:
        final values = List<int>.from(
          recipe.data['hsl'] as List? ?? List.filled(24, 0),
        );
        return Column(
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var band = 0; band < 8; band++)
                  ChoiceChip(
                    label: Text(
                      ['红', '橙', '黄', '绿', '青', '蓝', '紫', '洋红'][band],
                    ),
                    selected: hslBand == band,
                    onSelected: (_) => setState(() => hslBand = band),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            for (var axis = 0; axis < 3; axis++)
              slider(
                ['色相', '饱和度', '明度'][axis],
                values[hslBand * 3 + axis].toDouble(),
                -100,
                100,
                (value) => change(() {
                  values[hslBand * 3 + axis] = value.round();
                  recipe.data['hsl'] = values;
                }, snapshot: false),
              ),
            TextButton(
              onPressed: exporting
                  ? null
                  : () => change(() {
                      for (var axis = 0; axis < 3; axis++) {
                        values[hslBand * 3 + axis] = 0;
                      }
                      recipe.data['hsl'] = values;
                    }),
              child: const Text('重置此颜色'),
            ),
          ],
        );
      default:
        final border = object(recipe.data['border'] ?? {});
        return Column(
          children: [
            DropdownButtonFormField<int>(
              key: ValueKey('border-${border['template']}'),
              initialValue: border['template'] as int? ?? 0,
              decoration: const InputDecoration(labelText: '边框样式'),
              items: [
                for (var i = 0; i < 4; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(['无边框', '模糊居中', '模糊侧栏', '白底信息'][i]),
                  ),
              ],
              onChanged: exporting
                  ? null
                  : (value) => change(() {
                      border['template'] = value;
                      recipe.data['border'] = border;
                    }),
            ),
            const SizedBox(height: 16),
            slider(
              '边距',
              (border['margin'] as int? ?? 100).toDouble(),
              50,
              160,
              (value) => change(() {
                border['margin'] = value.round();
                recipe.data['border'] = border;
              }, snapshot: false),
            ),
            for (final entry in [
              ('corner', '圆角', 200.0),
              ('shadow', '阴影', 150.0),
              ('blur', '模糊', 200.0),
            ])
              slider(
                entry.$2,
                (border[entry.$1] as int? ?? 100).toDouble(),
                0,
                entry.$3,
                (value) => change(() {
                  border[entry.$1] = value.round();
                  recipe.data['border'] = border;
                }, snapshot: false),
              ),
            DropdownButtonFormField<int>(
              key: ValueKey('logo-${border['logo']}'),
              initialValue: border['logo'] as int? ?? 0,
              decoration: const InputDecoration(labelText: '品牌标识'),
              items: [
                for (var i = 0; i < 4; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                      ['自动', 'Nikon 黄色方形', 'Nikon 白色文字', 'Nikon 黑色文字'][i],
                    ),
                  ),
              ],
              onChanged: exporting
                  ? null
                  : (value) => change(() {
                      border['logo'] = value;
                      recipe.data['border'] = border;
                    }),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: exporting ? null : editBorderText,
              child: const Text('拍摄信息与显示项目'),
            ),
            TextButton(
              onPressed: exporting
                  ? null
                  : () => change(
                      () => recipe.data['border'] = {
                        'template': border['template'] ?? 0,
                      },
                    ),
              child: const Text('重置边框设置'),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = compare && widget.photo.info['raw'] != true
        ? widget.photo.path
        : preview;
    final visual = Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Theme.of(context).colorScheme.surfaceContainer),
        if (image != null)
          InteractiveViewer(
            minScale: 1,
            maxScale: 8,
            child: Center(
              child: Image.file(
                File(image),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                semanticLabel: '照片效果预览',
                errorBuilder: (_, _, _) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.image_not_supported_outlined),
                        const SizedBox(height: 12),
                        const Text('预览无法读取，请重试。'),
                        TextButton(
                          onPressed: rendering || exporting || analyzingCleanup
                              ? null
                              : () {
                                  setState(() => compare = false);
                                  unawaited(restored ? render() : restore());
                                },
                          child: const Text('重新生成预览'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          const Center(child: CircularProgressIndicator()),
        if (rendering || exporting || analyzingCleanup)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              minHeight: 3,
            ),
          ),
      ],
    );
    final panel = Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              for (var i = 0; i < 8; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      ['滤镜', '调节', '调色盘', '构图', '边框', '曲线', 'HSL', '去灰'][i],
                    ),
                    selected: tab == i,
                    onSelected: (_) => setState(() => tab = i),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            key: ValueKey('editor-panel-$tab'),
            padding: const EdgeInsets.all(20),
            children: [
              controls(),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(
                  onPressed:
                      rendering ||
                          exporting ||
                          analyzingCleanup ||
                          managingRecipes
                      ? null
                      : restored
                      ? render
                      : restore,
                  child: const Text('重试预览'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑'),
        actions: [
          IconButton(
            tooltip: '撤销',
            onPressed:
                undo.isEmpty || exporting || managingRecipes || analyzingCleanup
                ? null
                : () {
                    redo.add(recipe.clone());
                    final previous = undo.removeLast();
                    change(() => recipe = previous, snapshot: false);
                  },
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: '重做',
            onPressed:
                redo.isEmpty || exporting || managingRecipes || analyzingCleanup
                ? null
                : () {
                    undo.add(recipe.clone());
                    final next = redo.removeLast();
                    change(() => recipe = next, snapshot: false);
                  },
            icon: const Icon(Icons.redo_rounded),
          ),
          IconButton(
            tooltip: compare ? '显示效果' : '对比原图',
            onPressed: widget.photo.info['raw'] == true
                ? null
                : () => setState(() => compare = !compare),
            icon: const Icon(Icons.compare_rounded),
          ),
          IconButton(
            tooltip: '导出照片',
            onPressed:
                exporting ||
                    managingRecipes ||
                    analyzingCleanup ||
                    preview == null
                ? null
                : export,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: '编辑选项',
            enabled:
                restored && !exporting && !managingRecipes && !analyzingCleanup,
            onSelected: (_) => openRecipes(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'recipes', child: Text('我的配方')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth > 680
              ? Row(
                  children: [
                    Expanded(child: visual),
                    SizedBox(width: 340, child: panel),
                  ],
                )
              : Column(
                  children: [
                    Expanded(flex: 5, child: visual),
                    Expanded(flex: 4, child: panel),
                  ],
                ),
        ),
      ),
      bottomNavigationBar: exporting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('正在生成效果图 ${(progress * 100).round()}%'),
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
                ),
              ),
            )
          : null,
    );
  }
}
