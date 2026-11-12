import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'curve_control.dart';
import 'recipes.dart';
import 'copy_adjustments.dart';
import 'versions.dart';
import 'widgets.dart';
import 'raw_develop.dart';
import 'crop_workspace.dart';
import 'split_compare.dart';
import 'export_settings.dart';
import 'export_settings_model.dart';
import 'border_panel.dart';
import 'photo_workspace_chrome.dart';
import 'local_adjustments.dart';
import 'selection_workspace.dart';
import 'legacy_local_workspace.dart';
import 'theme.dart';
import 'workspace_tools.dart';

part 'legacy_editor.dart';
part 'local_editor.dart';

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
  String? preview, comparison, error, activeJob, atmosphere;
  int parameterIndex = 1;
  bool atmosphereLoading = false;
  final panelRevision = ValueNotifier<int>(0);
  void refreshWorkspace(VoidCallback update) => setState(update);
  bool exporting = false, rendering = false, compare = false, restored = false;
  bool managingTools = false;
  bool analyzingCleanup = false;
  final scopeAnchor = GlobalKey();
  Json localState = {};
  String? selectedRegionId;
  Recipe? regionAdjustments;
  LocalAdjustmentQueue? localQueue;
  bool leaving = false, allowPop = false;
  Json? displayedOverlay;
  ui.Image? regionLayer;
  String? regionLayerJob;
  int regionLayerGeneration = 0;
  int displayedRevision = -1;
  bool regionLayerVisible = true, adjustingParameter = false;
  double progress = 0;
  Size? compositionFrame;
  int compositionFrameTurns = 0;
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
    widget.state.addListener(editorOwnerChanged);
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
      await reloadLocalState();
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
    widget.state.removeListener(editorOwnerChanged);
    clearRegionLayer();
    debounce?.cancel();
    if (restored && !exporting) unawaited(saveDraft().catchError((_) {}));
    unawaited(progressEvents?.cancel());
    if (activeJob != null) unawaited(widget.state.core.cancel(activeJob!));
    if (preview != null) unawaited(discardPreview(preview));
    if (comparison != null) unawaited(discardPreview(comparison));
    if (atmosphere != null) unawaited(discardPreview(atmosphere));
    panelRevision.dispose();
    super.dispose();
  }

  Future<void> saveDraft() async {
    await settleLocalAdjustments();
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
    final snapshot = recipe.clone();
    localQueue?.fillSnapshot(snapshot);
    undo.add(snapshot);
    if (undo.length > 40) undo.removeAt(0);
    redo.clear();
  }

  void change(void Function() mutation, {bool snapshot = true}) {
    if (exporting ||
        managingTools ||
        analyzingCleanup ||
        !restored ||
        !sameOwner) {
      return;
    }
    if (snapshot) checkpoint();
    clearRegionLayer();
    setState(() {
      compare = false;
      mutation();
      error = null;
    });
    revision++;
    panelRevision.value++;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(render());
    });
  }

  Future<void> render() async {
    if (managingTools || !sameOwner) return;
    clearRegionLayer();
    final current = revision;
    try {
      await settleLocalAdjustments();
    } catch (failure) {
      if (mounted && current == revision) setState(() => error = '$failure');
      return;
    }
    if (!mounted || current != revision) return;
    final splitting = compare;
    final frozen = recipe.clone();
    final previousJob = activeJob;
    if (previousJob != null) await widget.state.core.cancel(previousJob);
    if (!mounted || current != revision) return;
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
      String? reference;
      if (splitting) {
        final neutral = Recipe().data;
        for (final key in ['geometry', 'border']) {
          if (frozen.data[key] != null) neutral[key] = frozen.data[key];
        }
        late final Json before;
        try {
          before = await widget.state.core.call('media.preview', {
            'path': widget.photo.path,
            'recipe': neutral,
            'owner': owner,
          }, job);
        } catch (_) {
          await discardPreview(result['path']);
          rethrow;
        }
        reference = before['path'] as String;
        if (!mounted || current != revision || activeJob != job) {
          await discardPreview(reference);
          await discardPreview(result['path']);
          return;
        }
      }
      final old = preview, oldComparison = comparison;
      setState(() {
        preview = result['path'] as String;
        if (result['geometryWidth'] is num && result['geometryHeight'] is num) {
          compositionFrame = Size(
            (result['geometryWidth'] as num).toDouble(),
            (result['geometryHeight'] as num).toDouble(),
          );
          compositionFrameTurns =
              object(frozen.data['geometry'] ?? {})['turns'] as int? ?? 0;
        }
        comparison = reference;
        displayedOverlay = {
          'recipe': frozen.data,
          'sourceWidth': result['sourceWidth'],
          'sourceHeight': result['sourceHeight'],
          'outputWidth': result['width'],
          'outputHeight': result['height'],
        };
        displayedRevision = current;
        error = null;
      });
      unawaited(refreshRegionLayer());
      panelRevision.value++;
      if (oldComparison != null &&
          oldComparison != preview &&
          oldComparison != comparison) {
        unawaited(discardPreview(oldComparison));
      }
      if (atmosphere == null && !atmosphereLoading) {
        unawaited(loadAtmosphere(result['path'] as String));
      }
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
      await ResizeImage(FileImage(file), width: 1280).evict();
      await FileImage(file).evict();
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A preview is disposable; cleanup failure never affects the original.
    }
  }

  Future<void> openCrop({double initialRatio = -1}) async {
    if (!toolsEnabled) return;
    debounce?.cancel();
    revision++;
    setState(() => managingTools = true);
    try {
      await settleLocalAdjustments();
      if (activeJob != null) await widget.state.core.cancel(activeJob!);
      if (!mounted) return;
      final result = await hueRootPage<Json>(
        context,
        MaterialPageRoute(
          builder: (_) => CropWorkspace(
            core: widget.state.core,
            photo: widget.photo,
            owner: owner,
            recipe: recipe.clone().data,
            initialRatio: initialRatio,
          ),
        ),
      );
      if (result != null && mounted) {
        if ((widget.state.session['user']?['id'] as String? ?? '') != owner) {
          throw const AppFailure('账号已改变，请重新打开照片。');
        }
        checkpoint();
        setState(() {
          recipe.data['geometry'] = result;
          compare = false;
        });
        unawaited(saveDraft().catchError((_) {}));
      }
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) {
        setState(() => managingTools = false);
        unawaited(render());
      }
    }
  }

  Future<void> openTool({
    bool copying = false,
    bool savedVersions = false,
  }) async {
    if (exporting || managingTools || analyzingCleanup || !restored) return;
    debounce?.cancel();
    revision++;
    setState(() => managingTools = true);
    try {
      await settleLocalAdjustments();
      if (activeJob != null) await widget.state.core.cancel(activeJob!);
      if (!mounted) return;
      final applied = await Navigator.push<Json>(
        context,
        MaterialPageRoute(
          builder: (_) => copying
              ? CopyAdjustmentsPage(
                  state: widget.state,
                  source: widget.photo,
                  recipe: recipe.clone().data,
                  owner: owner,
                )
              : savedVersions
              ? VersionsPage(
                  core: widget.state.core,
                  owner: owner,
                  path: widget.photo.path,
                )
              : RecipesPage(
                  core: widget.state.core,
                  owner: owner,
                  path: widget.photo.path,
                  current: recipe.clone().data,
                ),
        ),
      );
      if (!mounted) return;
      if (applied != null) {
        if (copying) {
          showCopyReceipt(context, widget.state.core, owner, applied);
          return;
        }
        checkpoint();
        setState(() {
          compare = false;
          recipe = Recipe(data: applied);
        });
        await reloadLocalState();
      }
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) {
        setState(() => managingTools = false);
        unawaited(render());
      }
    }
  }

  Future<void> analyzeCleanup() async {
    if (exporting || managingTools || analyzingCleanup || !restored) return;
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
      await settleLocalAdjustments();
      if (!mounted || !sameOwner) return;
      final regionId = selectedRegionId;
      if (oldJob != null) await widget.state.core.cancel(oldJob);
      final result = await widget.state.core.call('media.cleanupAnalyze', {
        'path': widget.photo.path,
        'owner': owner,
        'regionId': regionId ?? '',
        'recipe': recipe.clone().data,
      }, job);
      if (!mounted ||
          !sameOwner ||
          activeJob != job ||
          regionId != selectedRegionId) {
        return;
      }
      checkpoint();
      setState(() {
        compare = false;
        adjustmentRecipe.data['cleanupData'] = result['cleanupData'];
        adjustmentRecipe.data['cleanup'] = {
          'amount': 100,
          'haze': 100,
          'noise': 100,
        };
      });
      if (regionId != null) {
        await localQueue!.change(regionId, {
          'adjustments': adjustmentRecipe.clone().data,
        });
      }
      panelRevision.value++;
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

  bool exportWindowOpen = false;
  Future<void> export() async {
    if (!toolsEnabled || exportWindowOpen) return;
    exportWindowOpen = true;
    debounce?.cancel();
    final previousJob = activeJob;
    revision++;
    setState(() {
      rendering = false;
      activeJob = null;
    });
    ExportSettings? settings;
    try {
      await settleLocalAdjustments();
      if (previousJob != null) await widget.state.core.cancel(previousJob);
      if (!mounted || !sameOwner || leaving) return;
      settings = ExportSettings(
        state: widget.state,
        photo: widget.photo,
        owner: owner,
        recipe: recipe.clone().data,
        isCurrent: () => mounted && sameOwner && !leaving,
      );
      await showLegacyExport(context, settings, preview: preview);
    } catch (failure) {
      if (mounted && sameOwner) report(context, failure);
    } finally {
      settings?.dispose();
      exportWindowOpen = false;
      if (mounted) {
        setState(() {
          exporting = false;
          rendering = false;
          activeJob = null;
        });
      }
    }
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
                exporting || managingTools || analyzingCleanup || value <= min
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
              onChangeStart: exporting || managingTools || analyzingCleanup
                  ? null
                  : (_) {
                      beginParameterGesture();
                      (start ?? checkpoint)();
                    },
              onChangeEnd: (_) => endParameterGesture(),
              onChanged: exporting || managingTools || analyzingCleanup
                  ? null
                  : changed,
            ),
          ),
          IconButton(
            tooltip: '增大$label',
            onPressed:
                exporting || managingTools || analyzingCleanup || value >= max
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
  Widget controls({int? tool}) {
    switch (tool ?? tab) {
      case 7:
        final settings = object(
          adjustmentRecipe.data['cleanup'] ??
              {'amount': 100, 'haze': 100, 'noise': 100},
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
                    : adjustmentRecipe.data['cleanupData'] == null
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
            if (adjustmentRecipe.data['cleanupData'] != null) ...[
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
                  (value) => changeAdjustment(() {
                    settings[entry.$1] = value.round();
                    adjustmentRecipe.data['cleanup'] = settings;
                  }, snapshot: false),
                ),
              TextButton(
                onPressed: exporting || analyzingCleanup
                    ? null
                    : () => changeAdjustment(() {
                        adjustmentRecipe.data.remove('cleanupData');
                        adjustmentRecipe.data.remove('cleanup');
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
                      value = adjustmentRecipe.values[index];
                  return Column(
                    children: [
                      slider(
                        name,
                        value.toDouble(),
                        (parameter['min'] as num).toDouble(),
                        (parameter['max'] as num).toDouble(),
                        (v) => changeAdjustment(
                          () => adjustmentRecipe.setValue(index, v.round()),
                          snapshot: false,
                        ),
                        display: index == 1
                            ? '${(value / 10).toStringAsFixed(1)} EV'
                            : '$value',
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => hueDialog<void>(
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
          adjustmentRecipe.data['palette'] ??
              {'color': 0, 'tone': 0, 'amount': 100},
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
                (value) => changeAdjustment(() {
                  palette[entry.$1] = value.round();
                  adjustmentRecipe.data['palette'] = palette;
                }, snapshot: false),
              ),
          ],
        );
      case 3:
        final geometry = object(recipe.data['geometry'] ?? {});
        return Column(
          children: [
            OutlinedButton.icon(
              onPressed: toolsEnabled ? openCrop : null,
              icon: const HueIcon(HueIconKind.crop),
              label: const Text('交互裁切与构图'),
            ),
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
              (adjustmentRecipe.data['curves'] as List? ??
                      List.generate(4, (_) => [0, 0, 255, 255]))
                  .map((row) => List<int>.from(row as List))
                  .toList(),
          enabled: toolsEnabled,
          onStart: checkpoint,
          onChanged: (value) => changeAdjustment(
            () => adjustmentRecipe.data['curves'] = value,
            snapshot: false,
          ),
        );
      case 6:
        final values = List<int>.from(
          adjustmentRecipe.data['hsl'] as List? ?? List.filled(24, 0),
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
                    onSelected: toolsEnabled
                        ? (_) {
                            setState(() => hslBand = band);
                            panelRevision.value++;
                          }
                        : null,
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
                (value) => changeAdjustment(() {
                  values[hslBand * 3 + axis] = value.round();
                  adjustmentRecipe.data['hsl'] = values;
                }, snapshot: false),
              ),
            TextButton(
              onPressed: exporting
                  ? null
                  : () => changeAdjustment(() {
                      for (var axis = 0; axis < 3; axis++) {
                        values[hslBand * 3 + axis] = 0;
                      }
                      adjustmentRecipe.data['hsl'] = values;
                    }),
              child: const Text('重置此颜色'),
            ),
          ],
        );
      default:
        return SizedBox(height: 280, child: borderDock());
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(leaveEditor());
    },
    child: legacyWorkspace(context),
  );
}
