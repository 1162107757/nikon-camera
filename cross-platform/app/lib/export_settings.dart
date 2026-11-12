import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';

import 'appearance.dart';
import 'domain.dart';
import 'export_preview.dart';
import 'export_save.dart';
import 'export_settings_model.dart';
import 'original_save.dart';
import 'theme.dart';
import 'widgets.dart';

enum _ExportAction { save, more, versions, original }

Brightness _exportBrightness(BuildContext context) =>
    switch (appearanceMode.value) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(context),
    };

/// Mirrors PhotoVersionExport's quick → advanced → preview navigation.
/// The settings owner outlives all three windows and owns their frozen recipes.
Future<void> showLegacyExport(
  BuildContext context,
  ExportSettings model, {
  String? preview,
}) async {
  final theme = hueviaTheme(_exportBrightness(context), home: false);
  final palette = theme.extension<HuePalette>()!;
  unawaited(model.load());
  while (context.mounted && model.current) {
    if (!context.mounted) return;
    final route = ModalBottomSheetRoute<_ExportAction>(
      builder: (sheet) => Theme(
        data: theme,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(sheet).bottom,
          ),
          child: Material(
            color: palette.card,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
            clipBehavior: Clip.antiAlias,
            child: _QuickExport(model: model, preview: preview),
          ),
        ),
      ),
      isScrollControlled: true,
      useSafeArea: true,
      modalBarrierColor: const Color.fromRGBO(0, 0, 0, .48),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      clipBehavior: Clip.none,
    );
    final action = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    if (!context.mounted || !model.current || action == null) return;
    final items = await model.freezeSelected();
    if (!context.mounted || !model.current) return;
    if (action == _ExportAction.save) {
      if (context.mounted && model.current) {
        await _save(context, model, items, theme);
      }
      return;
    }
    (String, String?)? original;
    final advancedRoute = MaterialPageRoute<_ExportAction>(
      builder: (_) => Theme(
        data: theme,
        child: _AdvancedExport(
          model: model,
          preview: preview,
          onOriginal: (source, expected) => original = (source, expected),
        ),
      ),
    );
    final next = await hueRootPage<_ExportAction>(context, advancedRoute);
    await advancedRoute.completed;
    if (next == _ExportAction.original &&
        original != null &&
        context.mounted &&
        model.current) {
      await _saveOriginal(context, model, original!.$1, original!.$2, theme);
    }
    if (next != _ExportAction.versions) return;
  }
}

Future<void> _save(
  BuildContext context,
  ExportSettings settings,
  List<ExportItem> values,
  ThemeData theme,
) async {
  final queue = ExportSave(settings.state, settings.owner, values);
  try {
    await hueDialog<void>(
      context: context,
      builder: (_) => Theme(
        data: theme,
        child: _ExportProgress(queue: queue),
      ),
    );
  } finally {
    queue.dispose();
  }
}

/// The original closes the export windows before confirming over the editor.
Future<void> _saveOriginal(
  BuildContext context,
  ExportSettings model,
  String source,
  String? expected,
  ThemeData theme,
) async {
  bool current() =>
      context.mounted &&
      model.current &&
      ModalRoute.of(context)?.isCurrent == true;
  Future<T?> dialog<T>(WidgetBuilder builder) => hueDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(
      alpha: theme.extension<HuePalette>()!.dark ? .42 : .28,
    ),
    builder: (_) => Theme(
      data: theme,
      child: Builder(builder: builder),
    ),
  );
  try {
    final checked = await model.request('source.inspect', {
      'owner': model.owner,
      'path': source,
      'expectedSourceSha': ?expected,
    });
    if (!context.mounted || !current()) return;
    final format = checked['format'];
    if (format == 'JPG' || format == 'JPEG') {
      final accepted = await dialog<bool>((_) => const _OriginalConfirmation());
      if (accepted != true || !current()) return;
      final save = OriginalSave(
        model.state,
        model.owner,
        checked['path'] as String,
        checked['sourceSha'] as String,
        source == model.photo.path ? model.photo.name : path.basename(source),
      );
      try {
        await dialog<void>((_) => _OriginalProgress(save: save));
      } finally {
        save.dispose();
      }
    } else {
      await SharePlus.instance.share(
        ShareParams(
          sharePositionOrigin: shareAnchor(context),
          files: [XFile(checked['path'] as String)],
          fileNameOverrides: [
            source == model.photo.path
                ? model.photo.name
                : path.basename(source),
          ],
        ),
      );
    }
  } catch (failure) {
    if (context.mounted && current()) report(context, failure);
  }
}

Widget _copy(
  String text,
  double size,
  Color color, {
  FontWeight? weight,
  int? lines,
  TextAlign? align,
}) => Text(
  text,
  maxLines: lines,
  overflow: lines == null ? null : TextOverflow.ellipsis,
  textAlign: align,
  style: TextStyle(
    fontSize: size,
    height: 1.2,
    color: color,
    fontWeight: weight ?? FontWeight.w400,
  ),
);

Widget _originalAction(
  BuildContext context,
  String label,
  VoidCallback? action, {
  bool primary = false,
}) {
  final p = HuePalette.of(context);
  return TextButton(
    onPressed: action,
    style: TextButton.styleFrom(
      minimumSize: const Size(64, 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      foregroundColor: primary ? p.onPrimaryContainer : p.secondary,
      backgroundColor: primary ? p.primaryContainer : Colors.transparent,
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    child: Text(label),
  );
}

Widget _exportButton(
  String label,
  VoidCallback? action,
  HuePalette p, {
  bool primary = false,
  bool download = false,
  bool chevron = false,
  bool card = false,
  double height = 48,
  double radius = 12,
  FontWeight primaryWeight = FontWeight.w700,
}) => SizedBox(
  height: height,
  child: TextButton(
    onPressed: action,
    style: TextButton.styleFrom(
      foregroundColor: primary ? p.onPrimaryContainer : p.ink,
      disabledForegroundColor: p.secondary.withValues(alpha: .45),
      backgroundColor: primary
          ? p.primaryContainer
          : card
          ? p.card
          : p.container,
      padding: EdgeInsets.symmetric(horizontal: download ? 12 : 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
    child: primary
        ? Row(
            children: [
              if (download) ...[
                HueIcon(
                  HueIconKind.download,
                  size: 24,
                  color: p.onPrimaryContainer,
                ),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Center(
                  child: _copy(
                    label,
                    14,
                    action == null ? p.secondary : p.onPrimaryContainer,
                    weight: primaryWeight,
                    lines: 2,
                    align: TextAlign.center,
                  ),
                ),
              ),
            ],
          )
        : Row(
            children: [
              Expanded(
                child: _copy(
                  label,
                  13,
                  action == null
                      ? p.secondary.withValues(alpha: .45)
                      : card
                      ? p.ink
                      : p.secondary,
                ),
              ),
              if (chevron)
                HueIcon(HueIconKind.chevron, color: p.secondary, size: 24),
            ],
          ),
  ),
);

class _ExportMark extends CustomPainter {
  const _ExportMark(this.selected, this.p);
  final bool selected;
  final HuePalette p;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 22, size.height / 22);
    final paint = Paint()
      ..isAntiAlias = true
      ..color = selected ? p.primaryContainer : p.secondary
      ..style = selected ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(const Offset(11, 11), 9.5, paint);
    if (selected) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = p.onPrimaryContainer
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(
        Path()
          ..moveTo(6.5, 11)
          ..lineTo(9.5, 14)
          ..lineTo(15.8, 7.5),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_ExportMark old) => old.selected != selected || old.p != p;
}

class _QuickExport extends StatelessWidget {
  const _QuickExport({required this.model, this.preview});
  final ExportSettings model;
  final String? preview;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      final p = HuePalette.of(context),
          compact = MediaQuery.sizeOf(context).height < 500;
      final valid =
          model.enabled && model.error == null && model.selected.isNotEmpty;
      final current = model.variants
          .where((v) => v.id == 'current')
          .firstOrNull;
      final detail = current?.ready == true
          ? object(
                      (current!.description['qualities']
                          as List)[model.quality],
                    )['detail']
                    as String? ??
                ''
          : '';
      Future<void> finish(_ExportAction action) async {
        if (!model.enabled || model.selected.isEmpty) return;
        try {
          // Keep the modal in place while saved recipes are being inspected.
          await model.freezeSelected();
          if (context.mounted &&
              model.current &&
              ModalRoute.of(context)?.isCurrent == true) {
            Navigator.pop(context, action);
          }
        } catch (_) {
          /* The model displays the validation failure in this sheet. */
        }
      }

      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height - 48,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              compact ? 8 : 12,
              22,
              compact ? 10 : 18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 30,
                    height: 3,
                    decoration: BoxDecoration(
                      color: p.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                SizedBox(height: compact ? 6 : 14),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      Expanded(
                        child: _copy(
                          '导出照片',
                          17,
                          p.ink,
                          weight: FontWeight.w500,
                        ),
                      ),
                      if (compact)
                        TextButton(
                          onPressed: valid
                              ? () => finish(_ExportAction.more)
                              : null,
                          child: _copy('更多设置', 12, p.secondary),
                        ),
                      IconButton(
                        tooltip: '取消导出，返回照片',
                        onPressed: () => Navigator.pop(context),
                        icon: HueIcon(
                          HueIconKind.close,
                          color: p.secondary,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    top: compact ? 0 : 8,
                    bottom: compact ? 6 : 12,
                  ),
                  child: _ExportSummary(
                    model: model,
                    preview: preview,
                    quick: true,
                    size: 48,
                  ),
                ),
                if (model.loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                if (model.stale) _copy('照片或账号已变化，请返回后重新打开。', 13, p.secondary),
                if (model.error != null) ...[
                  _copy(model.error!, 13, Theme.of(context).colorScheme.error),
                  TextButton(
                    onPressed: model.enabled ? model.load : null,
                    child: const Text('重试导出设置'),
                  ),
                ],
                if (!model.stale) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _copy('导出版本 · 可多选', 12, p.secondary),
                  ),
                  for (final variant in model.variants)
                    Semantics(
                      checked: model.selected.contains(variant.id),
                      label: variant.label,
                      child: InkWell(
                        onTap: model.enabled
                            ? () {
                                try {
                                  model.select(
                                    variant.id,
                                    !model.selected.contains(variant.id),
                                  );
                                } catch (failure) {
                                  report(context, failure);
                                }
                              }
                            : null,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: CustomPaint(
                                    size: const Size(22, 22),
                                    painter: _ExportMark(
                                      model.selected.contains(variant.id),
                                      p,
                                    ),
                                  ),
                                ),
                              ),
                              _ExportThumb(
                                model: model,
                                variant: variant,
                                preview: preview,
                                size: 40,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _copy(
                                  variant.label,
                                  13,
                                  p.ink,
                                  lines: 1,
                                ),
                              ),
                              if (variant.id == 'current')
                                _copy('当前', 11, p.secondary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  SizedBox(
                    height: 32,
                    child: Row(
                      children: [
                        SizedBox(width: 48, child: _copy('画质', 13, p.ink)),
                        Expanded(
                          child: _copy(
                            detail,
                            11,
                            p.secondary,
                            lines: 1,
                            align: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, box) => SizedBox(
                      height: 48,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          activeTrackColor: p.primary,
                          inactiveTrackColor: p.outline,
                          thumbColor: p.primary,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                            elevation: 0,
                            pressedElevation: 0,
                          ),
                          trackShape: const RectangularSliderTrackShape(),
                          activeTickMarkColor: p.secondary,
                          inactiveTickMarkColor: p.secondary,
                          tickMarkShape: const RoundSliderTickMarkShape(
                            tickMarkRadius: 2,
                          ),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          min: 0,
                          max: 3,
                          divisions: 3,
                          value: model.quality.toDouble(),
                          padding: EdgeInsets.symmetric(
                            horizontal: box.maxWidth / 8,
                          ),
                          semanticFormatterCallback: (v) =>
                              ['轻量', '均衡', '高清', '原画'][v.round()],
                          onChanged: model.enabled
                              ? (v) => model.chooseQuality(v.round())
                              : null,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final (i, label) in ['轻量', '均衡', '高清', '原画'].indexed)
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: TextButton(
                              onPressed: model.enabled
                                  ? () => model.chooseQuality(i)
                                  : null,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                              ),
                              child: _copy(
                                label,
                                12,
                                i == model.quality ? p.primary : p.secondary,
                                weight: i == model.quality
                                    ? FontWeight.w500
                                    : null,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (!compact)
                    _exportButton(
                      '更多设置',
                      valid ? () => finish(_ExportAction.more) : null,
                      p,
                      chevron: true,
                    ),
                  const SizedBox(height: 9),
                  _exportButton(
                    '导出到手机相册',
                    valid ? () => finish(_ExportAction.save) : null,
                    p,
                    primary: true,
                    download: true,
                    height: 52,
                    radius: 14,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ExportSummary extends StatelessWidget {
  const _ExportSummary({
    required this.model,
    required this.size,
    this.preview,
    this.quick = false,
  });
  final ExportSettings model;
  final String? preview;
  final double size;
  final bool quick;
  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context), chosen = model.chosen;
    var hint = quick ? '保留原图，生成新照片' : '每个版本分别保存为 JPEG';
    if (chosen.length == 1) {
      hint = chosen.first.label;
      if (quick && chosen.first.ready) {
        final d = object(
          (chosen.first.description['qualities'] as List)[model.quality],
        );
        hint = '${d['width']} × ${d['height']} px';
      } else if (quick) {
        hint = '读取成品尺寸…';
      }
    }
    return Row(
      children: [
        if (chosen.isNotEmpty)
          _ExportThumb(
            model: model,
            variant: chosen.first,
            preview: preview,
            size: size,
          ),
        if (chosen.isNotEmpty) const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _copy(
                chosen.isEmpty
                    ? '请选择导出版本'
                    : chosen.length > 1
                    ? '已选 ${chosen.length} 个版本'
                    : quick
                    ? chosen.first.label
                    : model.photo.name,
                14,
                p.ink,
                weight: quick ? null : FontWeight.w500,
                lines: 1,
              ),
              const SizedBox(height: 4),
              _copy(hint, 12, p.secondary, lines: 2),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExportThumb extends StatefulWidget {
  const _ExportThumb({
    required this.model,
    required this.variant,
    required this.size,
    this.preview,
  });
  final ExportSettings model;
  final ExportVariant variant;
  final double size;
  final String? preview;
  @override
  State<_ExportThumb> createState() => _ExportThumbState();
}

class _ExportThumbState extends State<_ExportThumb> {
  String? path;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void didUpdateWidget(covariant _ExportThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.variant.id != widget.variant.id) {
      path = null;
      unawaited(load());
    }
  }

  Future<void> load() async {
    final id = widget.variant.id;
    try {
      final value = id == 'current'
          ? widget.preview ?? widget.model.photo.path
          : id == 'original'
          ? widget.model.photo.path
          : (await widget.model.request('version.open', {
                  'owner': widget.model.owner,
                  'id': id.substring(6),
                }))['path']
                as String;
      if (mounted && widget.model.current && widget.variant.id == id) {
        setState(() => path = value);
      }
    } catch (_) {
      /* Failed thumbnails never prevent exporting a valid version. */
    }
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(
      width: widget.size,
      height: widget.size,
      child: path == null || !widget.model.current
          ? const SizedBox()
          : Image.file(
              File(path!),
              fit: BoxFit.cover,
              cacheWidth: 192,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => const SizedBox(),
            ),
    ),
  );
}

class _AdvancedExport extends StatefulWidget {
  const _AdvancedExport({
    required this.model,
    required this.onOriginal,
    this.preview,
  });
  final void Function(String, String?) onOriginal;
  final ExportSettings model;
  final String? preview;
  @override
  State<_AdvancedExport> createState() => _AdvancedExportState();
}

class _AdvancedExportState extends State<_AdvancedExport> {
  final edge = TextEditingController(),
      quality = TextEditingController(text: '95');
  int mode = 0;
  bool busy = false, customEntered = false;
  String? error;
  ExportSettings get model => widget.model;
  int get maximum => model.chosen.length > 1
      ? 8192
      : model.chosen.first.description['maximumEdge'] as int;
  bool get customEnabled => maximum >= 640;
  Json get options => mode == 0
      ? {'size': 'full'}
      : mode == 1
      ? {'size': 'share'}
      : {
          'size': 'custom',
          'longEdge': int.tryParse(edge.text),
          'quality': int.tryParse(quality.text),
        };
  bool get valid =>
      model.current &&
      !busy &&
      (mode != 2 ||
          (customEnabled &&
              int.tryParse(edge.text) != null &&
              int.parse(edge.text) >= 640 &&
              int.parse(edge.text) <= maximum &&
              int.tryParse(quality.text) != null &&
              int.parse(quality.text) >= 70 &&
              int.parse(quality.text) <= 100));
  @override
  void initState() {
    super.initState();
    edge.text = '${math.min(2048, maximum)}';
    edge.addListener(update);
    quality.addListener(update);
    model.addListener(update);
  }

  void update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    model.removeListener(update);
    edge.dispose();
    quality.dispose();
    super.dispose();
  }

  Future<void> act({required bool preview}) async {
    if (!valid) return;
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // Settle focus and the editable controls before covering their route.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !model.current) return;
      final items = await model.freezeSelected(options: options);
      if (!mounted || !model.current) return;
      if (preview) {
        var index = 0;
        if (items.length > 1) {
          final chosen = await hueDialog<int>(
            context: context,
            builder: (dialog) => SimpleDialog(
              title: const Text('预览照片'),
              children: [
                for (final (i, item) in items.indexed)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(dialog, i),
                    child: Text(item.label),
                  ),
              ],
            ),
          );
          if (chosen == null || !mounted || !model.current) return;
          index = chosen;
        }
        final item = items[index];
        await hueRootPage<void>(
          context,
          PageRouteBuilder(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (_, _, _) => ExportPreviewPage(
              state: model.state,
              photo: model.photo,
              recipe: item.recipe,
              owner: model.owner,
              options: item.options,
              reviewOnly: true,
            ),
          ),
        );
      } else {
        await _save(context, model, items, Theme.of(context));
        if (mounted) Navigator.pop(context);
      }
    } catch (failure) {
      if (mounted && model.current) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void original(String source, String? expected) {
    if (busy || !model.current) return;
    FocusScope.of(context).unfocus();
    widget.onOriginal(source, expected);
    Navigator.pop(context, _ExportAction.original);
  }

  Widget input(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    style: const TextStyle(fontSize: 14),
    enabled: !busy && model.current,
    onTap: () => controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    if (!model.current) {
      return Scaffold(
        appBar: AppBar(title: const Text('导出照片')),
        body: const Center(child: Text('照片或账号已变化，请重新打开导出设置。')),
      );
    }
    final usable = valid;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 56,
          leadingWidth: 72,
          leading: IconButton(
            tooltip: '返回编辑，取消导出设置',
            onPressed: busy ? null : () => Navigator.pop(context),
            icon: HueIcon(HueIconKind.back, color: p.ink, size: 22),
          ),
          centerTitle: true,
          title: _copy('导出照片', 18, p.ink, weight: FontWeight.w700),
          actions: [
            IconButton(
              tooltip: '取消导出',
              onPressed: busy ? null : () => Navigator.pop(context),
              icon: HueIcon(HueIconKind.close, color: p.secondary, size: 22),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ExportSummary(
                              model: model,
                              preview: widget.preview,
                              size: 72,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: SizedBox(
                                height: 48,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: p.ink,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () => Navigator.pop(
                                          context,
                                          _ExportAction.versions,
                                        ),
                                  child: const Text('更改导出版本'),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: p.container,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  for (final (i, label) in [
                                    '完整尺寸',
                                    '分享',
                                    '自定义',
                                  ].indexed)
                                    Expanded(
                                      child: SizedBox(
                                        height: 48,
                                        child: Semantics(
                                          selected: mode == i,
                                          child: TextButton(
                                            onPressed:
                                                busy ||
                                                    (i == 2 && !customEnabled)
                                                ? null
                                                : () => setState(() {
                                                    mode = i;
                                                    if (i == 2 &&
                                                        !customEntered) {
                                                      customEntered = true;
                                                      edge.text =
                                                          '${math.min(4096, maximum)}';
                                                      quality.text = '90';
                                                    }
                                                  }),
                                            style: TextButton.styleFrom(
                                              backgroundColor: mode == i
                                                  ? p.card
                                                  : Colors.transparent,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              padding: EdgeInsets.zero,
                                            ),
                                            child: _copy(
                                              label,
                                              14,
                                              i == 2 && !customEnabled
                                                  ? p.secondary.withValues(
                                                      alpha: .45,
                                                    )
                                                  : mode == i
                                                  ? p.ink
                                                  : p.secondary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                              decoration: BoxDecoration(
                                color: p.card,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (mode == 2) ...[
                                    const SizedBox(height: 20),
                                    _copy('最终成品长边', 13, p.secondary),
                                    const SizedBox(height: 8),
                                    input(edge, '640–$maximum px'),
                                    Slider(
                                      min: 640,
                                      max: maximum.toDouble(),
                                      value: (int.tryParse(edge.text) ?? 640)
                                          .clamp(640, maximum)
                                          .toDouble(),
                                      onChanged: busy
                                          ? null
                                          : (v) => edge.text = '${v.round()}',
                                      semanticFormatterCallback: (v) =>
                                          '${v.round()} 像素',
                                    ),
                                    _copy(
                                      '640–$maximum px · 保持比例，不放大',
                                      12,
                                      p.secondary,
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  _copy(
                                    model.chosen.length == 1
                                        ? '成品尺寸 · 含边框'
                                        : '各照片尺寸 · 含边框',
                                    12,
                                    p.secondary,
                                  ),
                                  const SizedBox(height: 8),
                                  for (final variant in model.chosen)
                                    _dimensions(variant, p),
                                  const SizedBox(height: 6),
                                  _copy(
                                    mode == 0 ? '保留当前构图与边框的完整尺寸' : '保持比例 · 不放大',
                                    12,
                                    p.secondary,
                                  ),
                                  if (!customEnabled)
                                    _copy(
                                      '此图长边不足 640 px，可选完整尺寸或分享。',
                                      12,
                                      p.secondary,
                                    ),
                                  const SizedBox(height: 22),
                                  Divider(
                                    color: p.outline,
                                    height: 1,
                                    thickness: 1,
                                  ),
                                  _value('格式', 'JPEG · sRGB', p),
                                  if (mode != 2)
                                    _value(
                                      'JPEG 质量',
                                      mode == 0 ? '95' : '90',
                                      p,
                                    ),
                                  if (mode == 2) ...[
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _copy(
                                            'JPEG 质量',
                                            13,
                                            p.secondary,
                                          ),
                                        ),
                                        SizedBox(
                                          width: 96,
                                          child: input(quality, '70–100'),
                                        ),
                                      ],
                                    ),
                                    Slider(
                                      min: 70,
                                      max: 100,
                                      value: (int.tryParse(quality.text) ?? 95)
                                          .clamp(70, 100)
                                          .toDouble(),
                                      onChanged: busy
                                          ? null
                                          : (v) =>
                                                quality.text = '${v.round()}',
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _copy('保留拍摄信息 · 不含定位', 12, p.secondary),
                            const SizedBox(height: 16),
                            _exportButton(
                              model.chosen.length == 1 ? '查看成品预览' : '逐张查看成品预览',
                              usable ? () => act(preview: true) : null,
                              p,
                              chevron: true,
                              card: true,
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 32,
                              child: Row(
                                children: [
                                  Expanded(child: _copy('原始文件', 13, p.ink)),
                                  _copy('不应用编辑', 12, p.secondary),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: _originalButton(
                                    path
                                        .extension(model.photo.name)
                                        .replaceFirst('.', '')
                                        .toUpperCase()
                                        .replaceFirst(RegExp(r'^JPG$'), 'JPEG'),
                                    () => original(
                                      model.photo.path,
                                      model.sourceSha,
                                    ),
                                    p,
                                  ),
                                ),
                                if (model.photo.info['rawSource'] is String &&
                                    (model.photo.info['rawSource'] as String)
                                        .isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _originalButton(
                                      path
                                          .extension(
                                            model.photo.info['rawSource']
                                                as String,
                                          )
                                          .replaceFirst('.', '')
                                          .toUpperCase(),
                                      () => original(
                                        model.photo.info['rawSource'] as String,
                                        model.photo.info['rawSourceSha']
                                            as String?,
                                      ),
                                      p,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (mode == 2 && !valid && !busy)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: _copy(
                                  '请输入 640–$maximum 的整数长边和 70–100 的 JPEG 质量。',
                                  13,
                                  Theme.of(context).colorScheme.error,
                                ),
                              ),
                            if (error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: _copy(
                                  error!,
                                  13,
                                  Theme.of(context).colorScheme.error,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: _exportButton(
                      model.chosen.length == 1
                          ? '导出到手机相册'
                          : '导出 ${model.chosen.length} 张到相册',
                      usable ? () => act(preview: false) : null,
                      p,
                      primary: true,
                      height: 52,
                      radius: 16,
                      primaryWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _originalButton(
    String format,
    VoidCallback action,
    HuePalette p,
  ) => SizedBox(
    height: 48,
    child: TextButton(
      onPressed: busy ? null : action,
      style: TextButton.styleFrom(
        backgroundColor: p.container,
        foregroundColor: p.ink,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        children: [
          Expanded(child: _copy(format, 13, p.ink, weight: FontWeight.w500)),
          HueIcon(HueIconKind.download, color: p.secondary, size: 18),
        ],
      ),
    ),
  );

  Widget _dimensions(ExportVariant variant, HuePalette p) {
    final d = variant.description;
    if (mode == 2) {
      final e = int.tryParse(edge.text), q = int.tryParse(quality.text);
      if (e == null ||
          e < 640 ||
          e > maximum ||
          q == null ||
          q < 70 ||
          q > 100) {
        return _copy('—', model.chosen.length == 1 ? 20 : 12, p.ink);
      }
    }
    final w = d['fullWidth'] as int,
        h = d['fullHeight'] as int,
        full = math.max(w, h);
    final target = mode == 0
        ? full
        : math.min(full, mode == 1 ? 2048 : int.tryParse(edge.text) ?? full);
    final width = w >= h ? target : math.max(1, (w * target / full).round());
    final height = h >= w ? target : math.max(1, (h * target / full).round());
    return model.chosen.length == 1
        ? _copy('$width × $height px', 20, p.ink, weight: FontWeight.w500)
        : ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Row(
              children: [
                Expanded(
                  child: _copy(variant.label, 12, p.secondary, lines: 1),
                ),
                const SizedBox(width: 12),
                _copy('$width × $height px', 12, p.ink),
              ],
            ),
          );
  }

  Widget _value(String label, String value, HuePalette p) => SizedBox(
    height: 44,
    child: Row(
      children: [
        Expanded(child: _copy(label, 13, p.secondary)),
        _copy(value, 13, p.ink),
      ],
    ),
  );
}

/// Original AppDialog padding without Material's extra title/content spacing.
class _OriginalConfirmation extends StatelessWidget {
  const _OriginalConfirmation();
  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return Dialog(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Text(
                '保存 JPEG 原始文件？',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.36,
                  fontWeight: FontWeight.w500,
                  color: p.ink,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: _OriginalNotice(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
              child: OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 4,
                overflowSpacing: 4,
                children: [
                  _originalAction(
                    context,
                    '取消',
                    () => Navigator.pop(context, false),
                  ),
                  _originalAction(
                    context,
                    '保存原始文件',
                    () => Navigator.pop(context, true),
                    primary: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Android's original TextView uses balanced line breaking and 3 dp extra leading.
/// Find the narrowest measure retaining its line count, including enlarged text.
class _OriginalNotice extends StatelessWidget {
  const _OriginalNotice();
  static const message =
      '不会应用当前滤镜、调节、构图与边框，也不使用上方尺寸和质量设置。完整保留原文件内容及其已有信息（可能包含定位）。';
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontSize: 14,
        letterSpacing: 0,
        height: 1.4 + 3 / 14,
        color: HuePalette.of(context).secondary,
      );
      final scaler = MediaQuery.textScalerOf(context),
          direction = Directionality.of(context);
      const behavior = TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      );
      final painter = TextPainter(
        text: TextSpan(text: message, style: style),
        textDirection: direction,
        textScaler: scaler,
        textHeightBehavior: behavior,
      )..layout(maxWidth: constraints.maxWidth);
      final lines = painter.computeLineMetrics().length;
      var low = 0.0, high = constraints.maxWidth;
      for (var step = 0; step < 14; step++) {
        final middle = (low + high) / 2;
        painter.layout(maxWidth: middle);
        if (painter.computeLineMetrics().length <= lines) {
          high = middle;
        } else {
          low = middle;
        }
      }
      painter.dispose();
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: SizedBox(
          width: high,
          child: Text(message, style: style, textHeightBehavior: behavior),
        ),
      );
    },
  );
}

class _OriginalProgress extends StatefulWidget {
  const _OriginalProgress({required this.save});
  final OriginalSave save;
  @override
  State<_OriginalProgress> createState() => _OriginalProgressState();
}

class _OriginalProgressState extends State<_OriginalProgress> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.save.run());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.save,
    builder: (context, _) {
      final save = widget.save;
      return PopScope(
        canPop: !save.busy,
        child: AlertDialog(
          actionsPadding: const EdgeInsets.all(8),
          buttonPadding: const EdgeInsets.only(left: 4),
          title: Text(
            save.invalid
                ? '账号已变化'
                : save.done
                ? '已保存到手机相册'
                : '保存 JPEG 原始文件',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!save.invalid) Text(save.filename),
                if (save.busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: LinearProgressIndicator(),
                  ),
                if (save.error != null && !save.invalid) Text(save.error!),
                if (save.invalid) const Text('请返回后重新打开照片。'),
              ],
            ),
          ),
          actions: [
            if (save.busy)
              _originalAction(
                context,
                '停止保存',
                save.stopped ? null : save.cancel,
              ),
            if (!save.busy && !save.done && !save.invalid)
              _originalAction(context, '重试保存', save.run, primary: true),
            if (!save.busy)
              _originalAction(
                context,
                save.done ? '完成' : '关闭',
                () => Navigator.pop(context),
                primary: save.done,
              ),
          ],
        ),
      );
    },
  );
}

class _ExportProgress extends StatefulWidget {
  const _ExportProgress({required this.queue});
  final ExportSave queue;
  @override
  State<_ExportProgress> createState() => _ExportProgressState();
}

class _ExportProgressState extends State<_ExportProgress> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.queue.run());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.queue,
    builder: (context, _) {
      final q = widget.queue;
      return PopScope(
        canPop: !q.busy,
        child: AlertDialog(
          title: Text(
            q.invalid
                ? '账号已变化'
                : q.done
                ? '已保存到手机相册'
                : '导出照片',
          ),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!q.invalid) Text('${q.completed} / ${q.items.length}'),
                  if (q.busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: LinearProgressIndicator(),
                    ),
                  if (!q.invalid)
                    for (final item in q.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text('${item.input.label} · ${item.phase}'),
                      ),
                  if (q.error != null && !q.invalid) Text(q.error!),
                  if (q.invalid) const Text('请返回后重新打开照片。'),
                ],
              ),
            ),
          ),
          actions: [
            if (q.busy)
              TextButton(
                onPressed: q.stopped ? null : q.cancel,
                child: const Text('停止导出'),
              ),
            if (!q.busy && !q.done && !q.invalid)
              TextButton(onPressed: q.run, child: const Text('重试未完成项')),
            if (!q.busy)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(q.done ? '完成' : '关闭'),
              ),
          ],
        ),
      );
    },
  );
}
