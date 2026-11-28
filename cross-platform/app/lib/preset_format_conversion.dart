import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'original_files.dart';
import 'preset_display_name.dart';
import 'theme.dart';
import 'widgets.dart';

const presetConversionFormats = ['NCP', 'NP2', 'NP3'];

class PresetFormatConversionPage extends StatefulWidget {
  const PresetFormatConversionPage({
    super.key,
    required this.state,
    required this.preset,
  });

  final AppState state;
  final Preset preset;

  @override
  State<PresetFormatConversionPage> createState() =>
      _PresetFormatConversionPageState();
}

class _ConversionPlan {
  _ConversionPlan(Json value)
    : source = value['sourceFormat'] as String,
      target = value['targetFormat'] as String,
      cameraName = value['cameraName'] as String,
      rows = (value['rows'] as List).map(object).toList(growable: false),
      bytes = base64Decode(value['bytes'] as String);

  final String source, target, cameraName;
  final List<Json> rows;
  final Uint8List bytes;
  Iterable<Json> get omitted => rows.where((row) => row['status'] == 'omitted');
}

class _PresetFormatConversionPageState
    extends State<PresetFormatConversionPage> {
  late final String owner;
  late final targets = presetConversionFormats
      .where((format) => format != widget.preset.format)
      .toList(growable: false);
  late String target = targets.first;
  int generation = 0;
  bool retired = false, loading = true, saving = false, added = false;
  String? error, feedback;
  _ConversionPlan? preview, result;

  bool get active =>
      !retired &&
      widget.state.session['logoutPending'] != true &&
      (widget.state.session['user']?['id'] as String? ?? '') == owner;

  @override
  void initState() {
    super.initState();
    owner = widget.state.session['user']?['id'] as String? ?? '';
    widget.state.addListener(accountChanged);
    if (active) {
      load();
    } else {
      accountChanged();
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    super.dispose();
  }

  void accountChanged() {
    if (active || retired) return;
    setState(() {
      retired = true;
      preview = null;
      result = null;
      loading = false;
      error = '登录状态已变化，请重新打开预设。';
    });
  }

  Future<void> load() async {
    if (!active) return;
    final request = ++generation;
    final chosen = target;
    setState(() {
      preview = null;
      error = null;
      loading = true;
    });
    try {
      final preset = widget.preset;
      final value = await widget.state.core.call(
        preset.online ? 'online.convertPlan' : 'library.convertPlan',
        {
          'owner': owner,
          if (preset.online) 'preset': preset.data else 'id': preset.id,
          'targetFormat': chosen,
        },
      );
      if (!mounted || !active || request != generation) return;
      final plan = _ConversionPlan(value);
      if (plan.target != chosen ||
          plan.source == chosen ||
          plan.bytes.isEmpty) {
        throw const AppFailure('未收到有效的转换结果，请重试。');
      }
      setState(() => preview = plan);
    } catch (failure) {
      if (mounted && active && request == generation) {
        setState(() => error = '$failure');
      }
    } finally {
      if (mounted && active && request == generation) {
        setState(() => loading = false);
      }
    }
  }

  String get sourceFilename {
    final name = widget.preset.data['originalFileName'];
    return name is String && name.trim().isNotEmpty
        ? name
        : '${widget.preset.name}.${widget.preset.format}';
  }

  String filename(_ConversionPlan plan) {
    final stem = widget.preset.name
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'^[ .]+|[ .]+$'), '');
    final safe = String.fromCharCodes(stem.runes.take(52));
    return '${safe.isEmpty ? 'Huevia' : safe}.${plan.target}';
  }

  Future<void> publish({required bool toLibrary}) async {
    final frozen = result;
    if (saving || frozen == null || !active) return;
    final name = filename(frozen);
    setState(() {
      saving = true;
      feedback = null;
    });
    Directory? staging;
    try {
      final root = widget.state.core.root;
      if (root.isEmpty) throw const AppFailure('应用资料目录暂不可用。');
      final folder = await Directory(p.join(root, 'preset-conversions'))
          .create(recursive: true);
      staging = await folder.createTemp('copy-');
      final file = await File(p.join(staging.path, name))
          .writeAsBytes(frozen.bytes, flush: true);
      if (!mounted || !active) return;
      if (toLibrary) {
        final saved = await widget.state.core.call('library.import', {
          'path': file.path,
          'name': name,
          'owner': owner,
        });
        if (!mounted || !active) return;
        setState(() {
          added = true;
          feedback = saved['added'] == false
              ? '我的预设中已有相同的转换副本。'
              : '转换副本已加入我的预设。';
        });
        await widget.state.refreshLibrary();
      } else {
        final bool saved;
        if (OriginalFiles.canChooseTarget) {
          saved =
              await OriginalFiles.channel.invokeMethod<bool>('savePreset', {
                'path': file.path,
                'owner': owner,
              }) ==
              true;
        } else {
          final location = await getSaveLocation(suggestedName: name);
          if (location == null || !mounted || !active) return;
          await file.copy(location.path);
          saved = true;
        }
        if (saved && mounted && active) setState(() => feedback = '转换副本已保存。');
      }
    } catch (failure) {
      if (mounted && active) {
        setState(() {
          feedback = failure is PlatformException
              ? failure.message ?? '文件保存未完成。'
              : '$failure';
        });
      }
    } finally {
      if (staging != null) {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException {
          /* Best effort staging cleanup. */
        }
      }
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = hueviaTheme(Theme.of(context).brightness, home: false);
    final converted = result;
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) {
          final palette = HuePalette.of(context);
          return PopScope(
            canPop: !saving,
            child: Scaffold(
              appBar: HueHeader(
                title: converted == null ? '转换格式' : '转换完成',
                back: true,
              ),
              body: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                        children: converted == null
                            ? choose(palette)
                            : outcome(palette, converted),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: converted == null
                            ? [
                                FilledButton(
                                  onPressed:
                                      active && !loading && preview != null
                                      ? () => setState(() {
                                          result = preview;
                                          added = false;
                                        })
                                      : null,
                                  child: Text('转换为 $target'),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '生成新文件，保留源预设',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: palette.secondary,
                                  ),
                                ),
                              ]
                            : [
                                FilledButton(
                                  onPressed: saving
                                      ? null
                                      : () => publish(toLibrary: false),
                                  child: const Text('保存文件'),
                                ),
                                const SizedBox(height: 6),
                                OutlinedButton(
                                  onPressed: saving || added
                                      ? null
                                      : () => publish(toLibrary: true),
                                  child: Text(added ? '已加入我的预设' : '加入我的预设'),
                                ),
                              ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> choose(HuePalette palette) {
    final preset = widget.preset, plan = preview;
    return [
      ListTile(
        tileColor: palette.container,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        leading: SizedBox(
          width: 54,
          height: 54,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: PresetImage(
              preset: preset,
              core: widget.state.core,
              owner: owner,
            ),
          ),
        ),
        title: const Text('源预设', style: TextStyle(fontSize: 12)),
        subtitle: PresetDisplayName(
          state: widget.state,
          preset: preset,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        trailing: _FormatBadge(format: plan?.source ?? preset.format),
      ),
      const SizedBox(height: 18),
      const _ConversionHeading('目标格式'),
      const SizedBox(height: 8),
      Row(
        children: [
          for (final format in targets) ...[
            if (format != targets.first) const SizedBox(width: 9),
            Expanded(
              child: Semantics(
                selected: target == format,
                child: OutlinedButton(
                  onPressed: !active || target == format
                      ? null
                      : () {
                          target = format;
                          load();
                        },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(49),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    foregroundColor: palette.ink,
                    disabledForegroundColor: active && target == format
                        ? palette.onPrimaryContainer
                        : null,
                    disabledBackgroundColor: active && target == format
                        ? palette.primaryContainer
                        : null,
                    side: BorderSide(
                      color: target == format
                          ? palette.primary
                          : palette.outline,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          format,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (target == format) const Icon(Icons.check, size: 17),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 18),
      const _ConversionHeading('转换参数'),
      if (loading)
        const Padding(
          padding: EdgeInsets.only(top: 14),
          child: LinearProgressIndicator(),
        ),
      if (error != null) ...[
        const SizedBox(height: 10),
        Text(error!, style: TextStyle(color: palette.primary)),
        if (active)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: load, child: const Text('重试')),
          ),
      ],
      if (plan != null) ...[
        if (plan.omitted.isNotEmpty) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                '${plan.omitted.length} 项参数将省略\n其余兼容参数可继续转换。',
                style: TextStyle(
                  color: palette.onPrimaryContainer,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 9),
        _ConversionTable(rows: plan.rows),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text('输出机内名称', style: TextStyle(color: palette.secondary)),
            Text(
              plan.cameraName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    ];
  }

  List<Widget> outcome(HuePalette palette, _ConversionPlan plan) => [
    const SizedBox(height: 16),
    ClipRRect(
      borderRadius: BorderRadius.circular(19),
      child: ColoredBox(
        color: palette.card,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 150,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PresetImage(
                    preset: widget.preset,
                    core: widget.state.core,
                    owner: owner,
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        child: Text('源预设样片', style: TextStyle(fontSize: 11)),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 10,
                    right: 10,
                    child: _FormatBadge(format: plan.target),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ConversionHeading(filename(plan)),
                  const SizedBox(height: 5),
                  Text('机内名称  ${plan.cameraName}'),
                  const SizedBox(height: 3),
                  Text(
                    '源文件  $sourceFilename',
                    style: TextStyle(color: palette.secondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 9),
    ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.check, color: palette.primary),
      title: Text(
        '已生成 ${plan.source} → ${plan.target} 转换副本',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: plan.omitted.isEmpty
          ? null
          : Text('${plan.omitted.map((row) => row['label']).join('、')}已省略。'),
    ),
    if (feedback != null)
      Semantics(
        liveRegion: true,
        child: Text(feedback!, style: TextStyle(color: palette.secondary)),
      ),
  ];
}

class _ConversionHeading extends StatelessWidget {
  const _ConversionHeading(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
  );
}

class _FormatBadge extends StatelessWidget {
  const _FormatBadge({required this.format});
  final String format;
  @override
  Widget build(BuildContext context) {
    final palette = HuePalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.container,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Text(
          format,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: palette.ink,
          ),
        ),
      ),
    );
  }
}

class _ConversionTable extends StatelessWidget {
  const _ConversionTable({required this.rows});
  final List<Json> rows;

  @override
  Widget build(BuildContext context) {
    final palette = HuePalette.of(context);
    final border = BorderRadius.circular(12);
    TableRow row(
      String parameter,
      String status, {
      String note = '',
      Color? statusColor,
      bool heading = false,
    }) => TableRow(
      decoration: heading ? BoxDecoration(color: palette.container) : null,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                parameter,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: heading ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              if (note.isNotEmpty)
                Text(
                  note,
                  style: TextStyle(fontSize: 11, color: palette.secondary),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          child: Text(
            status,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: statusColor,
            ),
          ),
        ),
      ],
    );
    return ClipRRect(
      borderRadius: border,
      child: Table(
        border: TableBorder.symmetric(
          inside: BorderSide(color: palette.outline),
          outside: BorderSide(color: palette.outline),
          borderRadius: border,
        ),
        columnWidths: const {1: FractionColumnWidth(.31)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          row('参数', '转换结果', heading: true),
          for (final value in rows)
            row(
              value['label'] as String,
              switch (value['status']) {
                'retained' => '保留',
                'approximate' => '近似转换',
                _ => '省略',
              },
              note: value['note'] as String? ?? '',
              statusColor: switch (value['status']) {
                'retained' =>
                  palette.dark
                      ? const Color(0xffa5d6ba)
                      : const Color(0xff33634d),
                'approximate' =>
                  palette.dark
                      ? const Color(0xffeac28d)
                      : const Color(0xff825314),
                _ => palette.primary,
              },
            ),
        ],
      ),
    );
  }
}
