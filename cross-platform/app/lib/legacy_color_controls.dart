import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

const _yellow = Color(0xffffe335);
const _white = Color(0xfff4f5f7);
const _muted = Color(0xffc8cdca);

/// The original colour dialog's compact eight-colour, three-axis control pane.
/// The parent owns the tentative recipe, preview, and Apply/Cancel transaction.
class LegacyHslControls extends StatelessWidget {
  const LegacyHslControls({
    super.key,
    required this.values,
    required this.selectedBand,
    required this.onBandChanged,
    required this.onChanged,
    this.onStart,
    this.onEnd,
    this.enabled = true,
  }) : assert(values.length == 24),
       assert(selectedBand >= 0 && selectedBand < 8);

  final List<int> values;
  final int selectedBand;
  final ValueChanged<int> onBandChanged;
  final ValueChanged<List<int>> onChanged;
  final VoidCallback? onStart, onEnd;
  final bool enabled;

  static const names = ['红', '橙', '黄', '绿', '青', '蓝', '紫', '洋红'];
  static const colors = [
    Color(0xffee6d65),
    Color(0xffe9a05c),
    Color(0xffe6cc55),
    Color(0xff83bd6d),
    Color(0xff61bdbc),
    Color(0xff6d99db),
    Color(0xffa17ad1),
    Color(0xffd17ca7),
  ];

  void edit(int axis, int value) {
    final next = List<int>.from(values);
    next[selectedBand * 3 + axis] = value;
    onChanged(next);
  }

  void reset(bool all) {
    onStart?.call();
    final next = List<int>.from(values);
    for (var i = 0; i < next.length; i++) {
      if (all || i ~/ 3 == selectedBand) next[i] = 0;
    }
    onChanged(next);
    onEnd?.call();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var band = 0; band < 8; band++)
                Semantics(
                  selected: selectedBand == band,
                  child: SizedBox(
                    width:
                        48.0 *
                        MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.4),
                    height: 48,
                    child: TextButton(
                      key: ValueKey('hsl-band-$band'),
                      onPressed: enabled ? () => onBandChanged(band) : null,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        foregroundColor: selectedBand == band
                            ? _yellow
                            : _white,
                        backgroundColor: selectedBand == band
                            ? _yellow.withValues(alpha: .15)
                            : Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: colors[band],
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox(width: 9, height: 9),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            names[band],
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (var axis = 0; axis < 3; axis++)
          _ColorSlider(
            key: ValueKey('hsl-axis-$axis'),
            label: ['色相', '饱和度', '明亮度'][axis],
            semanticLabel:
                '${names[selectedBand]}色${['色相', '饱和度', '明亮度'][axis]}',
            value: values[selectedBand * 3 + axis],
            min: -100,
            max: 100,
            enabled: enabled,
            onStart: onStart,
            onEnd: onEnd,
            onChanged: (value) => edit(axis, value),
          ),
        Row(
          children: [
            Expanded(
              child: _textButton('重置此颜色', enabled ? () => reset(false) : null),
            ),
            Expanded(
              child: _textButton('重置 HSL', enabled ? () => reset(true) : null),
            ),
          ],
        ),
      ],
    ),
  );
}

/// The legacy palette maps horizontal position to colour intensity and vertical
/// position to tonal contrast. No separate rendering or draft state lives here.
class LegacyPaletteControls extends StatelessWidget {
  const LegacyPaletteControls({
    super.key,
    required this.color,
    required this.tone,
    required this.amount,
    required this.onChanged,
    this.onStart,
    this.onEnd,
    this.onReset,
    this.onUndo,
    this.onRedo,
    this.scope = '全图',
    this.padHeight = 208,
    this.enabled = true,
  });

  final int color, tone, amount;
  final void Function(int color, int tone, int amount) onChanged;
  final VoidCallback? onStart, onEnd, onReset, onUndo, onRedo;
  final String scope;
  final double padHeight;
  final bool enabled;

  Future<void> exact(BuildContext context, bool colour) async {
    final value = await showLegacyColorNumberInput(
      context,
      title: colour ? '颜色 · 清淡至鲜艳' : '影调 · 低对比至高对比',
      value: colour ? color : tone,
      min: -100,
      max: 100,
    );
    if (!context.mounted || !enabled || value == null) return;
    onStart?.call();
    onChanged(colour ? value : color, colour ? tone : value, amount);
    onEnd?.call();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                scope,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _white),
              ),
            ),
            Expanded(
              child: _textButton(
                '颜色  ${_signed(color)}',
                enabled ? () => exact(context, true) : null,
                key: const Key('palette-color-value'),
              ),
            ),
            Expanded(
              child: _textButton(
                '影调  ${_signed(tone)}',
                enabled ? () => exact(context, false) : null,
                key: const Key('palette-tone-value'),
              ),
            ),
            _iconButton(Icons.refresh, '重置调色盘', enabled ? onReset : null),
          ],
        ),
        SizedBox(
          height: math.max(172.0, padHeight),
          child: LegacyPalettePad(
            color: color,
            tone: tone,
            enabled: enabled,
            onStart: onStart,
            onEnd: onEnd,
            onChanged: (c, t) => onChanged(c, t, amount),
            onExactColor: () => exact(context, true),
          ),
        ),
        _ColorSlider(
          label: '强度',
          semanticLabel: '调色盘强度',
          value: amount,
          min: 0,
          max: 100,
          suffix: '%',
          enabled: enabled,
          onStart: onStart,
          onEnd: onEnd,
          onChanged: (value) => onChanged(color, tone, value),
        ),
        _historyRow(
          '调色盘',
          enabled ? onUndo : null,
          enabled ? onRedo : null,
          hint: '拖动调色 · 按住对比',
        ),
      ],
    ),
  );
}

class LegacyCleanupControls extends StatefulWidget {
  const LegacyCleanupControls({
    super.key,
    required this.amount,
    required this.haze,
    required this.noise,
    required this.hasAnalysis,
    required this.onChanged,
    required this.onAnalyze,
    required this.onReset,
    this.analyzing = false,
    this.enabled = true,
    this.onStart,
    this.onEnd,
    this.onUndo,
    this.onRedo,
    this.onCancelAnalysis,
    this.onExpandedChanged,
  });

  final int amount, haze, noise;
  final bool hasAnalysis, analyzing, enabled;
  final void Function(int amount, int haze, int noise) onChanged;
  final VoidCallback onAnalyze, onReset;
  final VoidCallback? onStart, onEnd, onUndo, onRedo, onCancelAnalysis;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<LegacyCleanupControls> createState() => _LegacyCleanupControlsState();
}

class _LegacyCleanupControlsState extends State<LegacyCleanupControls> {
  bool expanded = false;

  bool get adjustable =>
      widget.enabled && widget.hasAnalysis && !widget.analyzing;

  Widget axis(int axis, String label) => _ColorSlider(
    key: ValueKey('cleanup-axis-$axis'),
    label: label,
    semanticLabel: axis == 0 ? '去灰强度' : label,
    value: [widget.amount, widget.haze, widget.noise][axis],
    min: 0,
    max: 100,
    suffix: '%',
    enabled: adjustable,
    onStart: widget.onStart,
    onEnd: widget.onEnd,
    onChanged: (value) => widget.onChanged(
      axis == 0 ? value : widget.amount,
      axis == 1 ? value : widget.haze,
      axis == 2 ? value : widget.noise,
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        axis(0, '强度'),
        Row(
          children: [
            _iconButton(
              Icons.undo,
              '撤销去灰调整',
              widget.enabled && !widget.analyzing ? widget.onUndo : null,
            ),
            _iconButton(
              Icons.redo,
              '重做去灰调整',
              widget.enabled && !widget.analyzing ? widget.onRedo : null,
            ),
            const Expanded(
              child: Text(
                '按住画面右下角对比',
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(fontSize: 11, color: _muted),
              ),
            ),
            _iconButton(
              Icons.refresh,
              '重置去灰',
              widget.enabled && !widget.analyzing ? widget.onReset : null,
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Semantics(
                expanded: expanded,
                child: _textButton(
                  expanded ? '收起高级' : '高级',
                  widget.enabled
                      ? () {
                          setState(() => expanded = !expanded);
                          widget.onExpandedChanged?.call(expanded);
                        }
                      : null,
                  key: const Key('cleanup-advanced'),
                ),
              ),
            ),
            if (widget.analyzing && widget.onCancelAnalysis != null)
              _textButton('取消分析', widget.onCancelAnalysis),
          ],
        ),
        if (expanded) ...[
          axis(1, '去灰雾'),
          axis(2, '降噪'),
          SizedBox(
            width: double.infinity,
            child: _textButton(
              widget.analyzing
                  ? '正在分析画面…'
                  : widget.hasAnalysis
                  ? '重新分析'
                  : '自动分析',
              widget.enabled && !widget.analyzing ? widget.onAnalyze : null,
              key: const Key('cleanup-analyze'),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Compact numeric row with a tap-to-enter readout. Interrupted multi-touch
/// gestures restore their starting value and do not resume on the remaining finger.
class _ColorSlider extends StatefulWidget {
  const _ColorSlider({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onStart,
    this.onEnd,
    this.enabled = true,
    this.suffix = '',
  });
  final String label, semanticLabel, suffix;
  final int value, min, max;
  final ValueChanged<int> onChanged;
  final VoidCallback? onStart, onEnd;
  final bool enabled;
  @override
  State<_ColorSlider> createState() => _ColorSliderState();
}

class _ColorSliderState extends State<_ColorSlider> {
  final pointers = <int>{};
  int? origin;
  bool interrupted = false;

  void start() {
    if (!widget.enabled || interrupted || origin != null) return;
    origin = widget.value;
    widget.onStart?.call();
  }

  void finish({bool cancel = false}) {
    final before = origin;
    if (before == null) return;
    origin = null;
    if (cancel) widget.onChanged(before);
    widget.onEnd?.call();
  }

  void change(double value) {
    if (!widget.enabled || interrupted) return;
    final atomic = origin == null;
    if (atomic) widget.onStart?.call();
    widget.onChanged(value.round());
    if (atomic) widget.onEnd?.call();
  }

  Future<void> exact() async {
    final value = await showLegacyColorNumberInput(
      context,
      title: widget.semanticLabel,
      value: widget.value,
      min: widget.min,
      max: widget.max,
      suffix: widget.suffix,
    );
    if (!mounted || !widget.enabled || value == null || value == widget.value) {
      return;
    }
    widget.onStart?.call();
    widget.onChanged(value);
    widget.onEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return SizedBox(
      height: math.max(48.0, 30 * scale),
      child: Row(
        children: [
          SizedBox(
            width: 56.0 * scale.clamp(1, 1.5),
            child: Text(
              widget.label,
              style: const TextStyle(fontSize: 12, color: _white),
            ),
          ),
          Expanded(
            child: Listener(
              onPointerDown: (event) {
                if (pointers.isEmpty) interrupted = false;
                pointers.add(event.pointer);
                if (pointers.length > 1) {
                  interrupted = true;
                  finish(cancel: true);
                }
              },
              onPointerUp: (event) => pointers.remove(event.pointer),
              onPointerCancel: (event) {
                pointers.remove(event.pointer);
                interrupted = true;
                finish(cancel: true);
              },
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _yellow,
                  inactiveTrackColor: const Color(0x35ffffff),
                  thumbColor: _yellow,
                  overlayColor: _yellow.withValues(alpha: .12),
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 16,
                  ),
                ),
                child: Slider(
                  label: widget.semanticLabel,
                  semanticFormatterCallback: (value) =>
                      '${widget.semanticLabel} ${value.round()}${widget.suffix}',
                  value: widget.value.clamp(widget.min, widget.max).toDouble(),
                  min: widget.min.toDouble(),
                  max: widget.max.toDouble(),
                  onChangeStart: widget.enabled ? (_) => start() : null,
                  onChangeEnd: widget.enabled ? (_) => finish() : null,
                  onChanged: widget.enabled ? change : null,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48.0 * scale,
            child: TextButton(
              onPressed: widget.enabled ? exact : null,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 48),
                foregroundColor: _yellow,
              ),
              child: Text(
                '${widget.min < 0 ? _signed(widget.value) : widget.value}${widget.suffix}',
                maxLines: 1,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LegacyPalettePad extends StatefulWidget {
  const LegacyPalettePad({
    super.key,
    required this.color,
    required this.tone,
    required this.onChanged,
    this.onStart,
    this.onEnd,
    this.onExactColor,
    this.enabled = true,
  });
  final int color, tone;
  final void Function(int color, int tone) onChanged;
  final VoidCallback? onStart, onEnd, onExactColor;
  final bool enabled;
  @override
  State<LegacyPalettePad> createState() => _LegacyPalettePadState();
}

class _LegacyPalettePadState extends State<LegacyPalettePad> {
  final pointers = <int>{};
  (int, int)? origin;
  bool interrupted = false;
  ui.Image? field;

  @override
  void initState() {
    super.initState();
    final pixels = Uint8List(96 * 96 * 4);
    for (var y = 0; y < 96; y++) {
      final v = y / 95;
      final t = _smooth(v < .48 ? v / .48 : (v - .48) / .52);
      final left = Color.lerp(
        v < .48 ? const Color(0xff343437) : const Color(0xff777979),
        v < .48 ? const Color(0xff777979) : const Color(0xffb7b1a7),
        t,
      )!;
      final right = Color.lerp(
        v < .48 ? const Color(0xff81503d) : const Color(0xffdc8c87),
        v < .48 ? const Color(0xffdc8c87) : const Color(0xffcbb595),
        t,
      )!;
      for (var x = 0; x < 96; x++) {
        final c = Color.lerp(left, right, _smooth(x / 95))!;
        final at = (y * 96 + x) * 4;
        pixels[at] = (c.r * 255).round();
        pixels[at + 1] = (c.g * 255).round();
        pixels[at + 2] = (c.b * 255).round();
        pixels[at + 3] = 255;
      }
    }
    ui.decodeImageFromPixels(pixels, 96, 96, ui.PixelFormat.rgba8888, (image) {
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => field = image);
    });
  }

  @override
  void dispose() {
    field?.dispose();
    super.dispose();
  }

  Rect frame(Size size, double scale) {
    final inset = math.max(24.0, 16 * scale);
    final height = math.max(1.0, size.height - inset * 2);
    final side = math.max(28.0, 22 * scale);
    final width = math.min(math.max(1.0, size.width - side * 2), height * 1.15);
    return Rect.fromLTWH((size.width - width) / 2, inset, width, height);
  }

  void move(Offset position, Rect bounds) {
    if (origin == null || interrupted || !widget.enabled) return;
    widget.onChanged(
      ((position.dx - bounds.left) / bounds.width * 200 - 100).round().clamp(
        -100,
        100,
      ),
      ((bounds.bottom - position.dy) / bounds.height * 200 - 100).round().clamp(
        -100,
        100,
      ),
    );
  }

  void start() {
    if (!widget.enabled || interrupted || origin != null) return;
    origin = (widget.color, widget.tone);
    widget.onStart?.call();
  }

  void finish({bool cancel = false}) {
    final before = origin;
    if (before == null) return;
    origin = null;
    if (cancel) widget.onChanged(before.$1, before.$2);
    widget.onEnd?.call();
  }

  void atomic(int color, int tone) {
    if (!widget.enabled) return;
    widget.onStart?.call();
    widget.onChanged(color.clamp(-100, 100), tone.clamp(-100, 100));
    widget.onEnd?.call();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final size = bounds.biggest;
      final scale = MediaQuery.textScalerOf(context).scale(1);
      final rect = frame(size, scale);
      return Semantics(
        label: '调色盘，左右调整颜色浓淡，上下调整影调对比',
        value: '颜色 ${_signed(widget.color)}，影调 ${_signed(widget.tone)}',
        enabled: widget.enabled,
        customSemanticsActions: {
          const CustomSemanticsAction(label: '颜色更鲜艳'): () =>
              atomic(widget.color + 5, widget.tone),
          const CustomSemanticsAction(label: '颜色更清淡'): () =>
              atomic(widget.color - 5, widget.tone),
          const CustomSemanticsAction(label: '提高影调对比'): () =>
              atomic(widget.color, widget.tone + 5),
          const CustomSemanticsAction(label: '降低影调对比'): () =>
              atomic(widget.color, widget.tone - 5),
        },
        child: Focus(
          canRequestFocus: widget.enabled,
          onKeyEvent: (_, event) {
            if (!widget.enabled ||
                (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
              return KeyEventResult.ignored;
            }
            final step = HardwareKeyboard.instance.isShiftPressed ? 5 : 1;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.arrowLeft) {
              atomic(widget.color - step, widget.tone);
            } else if (key == LogicalKeyboardKey.arrowRight) {
              atomic(widget.color + step, widget.tone);
            } else if (key == LogicalKeyboardKey.arrowUp) {
              atomic(widget.color, widget.tone + step);
            } else if (key == LogicalKeyboardKey.arrowDown) {
              atomic(widget.color, widget.tone - step);
            } else if (key == LogicalKeyboardKey.enter) {
              widget.onExactColor?.call();
            } else {
              return KeyEventResult.ignored;
            }
            return KeyEventResult.handled;
          },
          child: Listener(
            onPointerDown: (event) {
              if (pointers.isEmpty) interrupted = false;
              pointers.add(event.pointer);
              if (pointers.length > 1) {
                interrupted = true;
                finish(cancel: true);
              }
            },
            onPointerUp: (event) => pointers.remove(event.pointer),
            onPointerCancel: (event) {
              pointers.remove(event.pointer);
              interrupted = true;
              finish(cancel: true);
            },
            child: GestureDetector(
              key: const Key('legacy-palette-pad'),
              behavior: HitTestBehavior.opaque,
              onPanStart: !widget.enabled
                  ? null
                  : (event) {
                      if (rect.contains(event.localPosition)) {
                        start();
                        move(event.localPosition, rect);
                      }
                    },
              onPanUpdate: !widget.enabled
                  ? null
                  : (event) => move(event.localPosition, rect),
              onPanEnd: !widget.enabled ? null : (_) => finish(),
              onPanCancel: !widget.enabled ? null : () => finish(cancel: true),
              onTapUp: !widget.enabled
                  ? null
                  : (event) {
                      if (interrupted || !rect.contains(event.localPosition)) {
                        return;
                      }
                      start();
                      move(event.localPosition, rect);
                      finish();
                    },
              child: CustomPaint(
                size: size,
                painter: _PalettePainter(
                  field,
                  rect,
                  widget.color,
                  widget.tone,
                  scale,
                  widget.enabled,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _PalettePainter extends CustomPainter {
  const _PalettePainter(
    this.field,
    this.rect,
    this.color,
    this.tone,
    this.scale,
    this.enabled,
  );
  final ui.Image? field;
  final Rect rect;
  final int color, tone;
  final double scale;
  final bool enabled;
  @override
  void paint(Canvas canvas, Size size) {
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.save();
    canvas.clipRRect(rounded);
    if (field != null) {
      canvas.drawImageRect(
        field!,
        const Rect.fromLTWH(0, 0, 96, 96),
        rect,
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(255, 255, 255, enabled ? 1 : .4),
      );
    } else {
      canvas.drawRect(rect, Paint()..color = const Color(0xff777979));
    }
    canvas.restore();
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0x28ffffff)
      ..strokeWidth = 1;
    canvas.drawRRect(rounded, ink);
    ink.color = const Color(0x36ffffff);
    canvas.drawLine(
      Offset(rect.center.dx, rect.top + 8),
      Offset(rect.center.dx, rect.bottom - 8),
      ink,
    );
    canvas.drawLine(
      Offset(rect.left + 8, rect.center.dy),
      Offset(rect.right - 8, rect.center.dy),
      ink,
    );
    final point = Offset(
      rect.left + rect.width * (color + 100) / 200,
      rect.bottom - rect.height * (tone + 100) / 200,
    );
    canvas.drawCircle(
      point,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0x66000000),
    );
    canvas.drawCircle(
      point,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white,
    );
    canvas.drawCircle(point, 5, Paint()..color = Colors.white);
    void label(String value, Offset center) {
      final text = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(fontSize: 11 * scale, color: _muted),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
    }

    label('层次', Offset(rect.center.dx, rect.top / 2));
    label('柔和', Offset(rect.center.dx, (rect.bottom + size.height) / 2));
    final gap = math.max(16.0, 12 * scale);
    label('淡', Offset(rect.left - gap, rect.center.dy));
    label('鲜', Offset(rect.right + gap, rect.center.dy));
  }

  @override
  bool shouldRepaint(covariant _PalettePainter old) =>
      old.field != field ||
      old.rect != rect ||
      old.color != color ||
      old.tone != tone ||
      old.scale != scale ||
      old.enabled != enabled;
}

/// Shared by legacy colour readouts, including the curve workspace's exact point dialog.
Future<int?> showLegacyColorNumberInput(
  BuildContext context, {
  required String title,
  required int value,
  required int min,
  required int max,
  String suffix = '',
}) => showDialog<int>(
  context: context,
  builder: (_) => _ColorNumberDialog(
    title: title,
    value: value,
    min: min,
    max: max,
    suffix: suffix,
  ),
);

class _ColorNumberDialog extends StatefulWidget {
  const _ColorNumberDialog({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
  });
  final String title, suffix;
  final int value, min, max;
  @override
  State<_ColorNumberDialog> createState() => _ColorNumberDialogState();
}

class _ColorNumberDialogState extends State<_ColorNumberDialog> {
  late final input = TextEditingController(text: '${widget.value}');
  late double position = widget.value.toDouble();
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void apply() {
    final value = int.tryParse(input.text.trim());
    if (value == null || value < widget.min || value > widget.max) {
      setState(() => error = '请输入${widget.min}至${widget.max}的整数');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('legacy-color-exact-input'),
            controller: input,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(
              signed: widget.min < 0,
            ),
            decoration: InputDecoration(
              labelText: '${widget.min}–${widget.max}${widget.suffix}',
              errorText: error,
            ),
            onSubmitted: (_) => apply(),
            onChanged: (text) {
              final value = int.tryParse(text.trim());
              if (value != null && value >= widget.min && value <= widget.max) {
                setState(() {
                  position = value.toDouble();
                  error = null;
                });
              }
            },
          ),
          Slider(
            value: position.clamp(widget.min.toDouble(), widget.max.toDouble()),
            min: widget.min.toDouble(),
            max: widget.max.toDouble(),
            onChanged: (value) => setState(() {
              position = value.roundToDouble();
              input.text = '${value.round()}';
              error = null;
            }),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(onPressed: apply, child: const Text('应用')),
    ],
  );
}

Widget _textButton(String label, VoidCallback? onPressed, {Key? key}) =>
    TextButton(
      key: key,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        foregroundColor: _yellow,
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Text(label, maxLines: 2, textAlign: TextAlign.center),
    );
Widget _iconButton(IconData icon, String label, VoidCallback? callback) =>
    IconButton(
      onPressed: callback,
      tooltip: label,
      color: _white,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      iconSize: 22,
      icon: Icon(icon),
    );
Widget _historyRow(
  String name,
  VoidCallback? undo,
  VoidCallback? redo, {
  required String hint,
}) => Row(
  children: [
    _iconButton(Icons.undo, '撤销$name调整', undo),
    _iconButton(Icons.redo, '重做$name调整', redo),
    Expanded(
      child: Text(
        hint,
        textAlign: TextAlign.end,
        maxLines: 2,
        style: const TextStyle(fontSize: 11, color: _muted),
      ),
    ),
  ],
);
String _signed(int value) => value > 0 ? '+$value' : '$value';
double _smooth(double value) => value * value * (3 - 2 * value);
