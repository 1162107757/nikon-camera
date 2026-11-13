import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'workspace_tools.dart';

// Authored dimensions and paths from PhotoPortraitDialog, PhotoWorkspaceUi and
// PhotoPrismaStyle. The owning workspace supplies all editing state/actions.
const retouchOriginalText = Color(0xfff4f5f7);
const retouchOriginalMuted = Color(0xffc8cdca);
const retouchOriginalAccent = Color(0xffffe335);

class RetouchOriginalMetrics {
  const RetouchOriginalMetrics._({
    required this.side,
    required this.dockWidth,
    required this.dockHeight,
    required this.rawDockHeight,
    required this.toolWidth,
    required this.toolHeight,
    required this.entryWidth,
    required this.entryHeight,
  });
  final bool side;
  final double dockWidth,
      dockHeight,
      rawDockHeight,
      toolWidth,
      toolHeight,
      entryWidth,
      entryHeight;
  static RetouchOriginalMetrics resolve(
    Size body,
    double fontScale, {
    required int mode,
    required bool choosingGroup,
    bool hasSliderSelection = true,
    bool lighting = false,
    bool photoSampling = false,
    bool tonePreviewing = false,
  }) {
    final scale = math.max(1.0, fontScale), large = fontScale >= 1.2;
    final entryHeight = 48 + 20 * scale;
    double raw;
    if (choosingGroup) {
      raw = entryHeight;
    } else {
      if (mode >= 3) {
        raw = mode >= 4
            ? (large ? 144 : 132)
            : (photoSampling || tonePreviewing ? 116 : 196) + (large ? 84 : 72);
      } else {
        raw = (large ? 144 : 132) + (mode == 2 ? 48 : 0);
      }
      if ((mode == 0 || mode >= 3) && !hasSliderSelection) raw -= 48;
      if (lighting) raw += 160;
    }
    final side = body.width > body.height && body.width >= 480;
    return RetouchOriginalMetrics._(
      side: side,
      dockWidth: side
          ? math.min(320, math.max(1, body.width * .44))
          : body.width,
      dockHeight: side
          ? body.height
          : math.max(1, math.min(raw, body.height / 2)),
      rawDockHeight: raw,
      toolWidth: large ? 80 : 72,
      toolHeight: large ? 84 : 72,
      entryWidth: 56 * scale,
      entryHeight: entryHeight,
    );
  }
}

class RetouchOriginalSlider extends StatefulWidget {
  const RetouchOriginalSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.onChangeCancel,
    this.valueLabel,
    this.formatValue,
    this.semanticLabel,
    this.labelWidth = 80,
    this.valueWidth = 44,
    this.trailing,
  });
  final String label;
  final double value, min, max, labelWidth, valueWidth;
  final Widget? trailing;
  final String? valueLabel, semanticLabel;
  final String Function(double value)? formatValue;
  final ValueChanged<double>? onChanged, onChangeStart, onChangeEnd;
  final VoidCallback? onChangeCancel;
  @override
  State<RetouchOriginalSlider> createState() => _OriginalSliderState();
}

class _OriginalSliderState extends State<RetouchOriginalSlider> {
  double? pending;
  final pointers = <int>{};
  bool dragging = false, cancelled = false;
  void cancel() {
    cancelled = true;
    if (!dragging) return;
    dragging = false;
    setState(() => pending = null);
    widget.onChangeCancel?.call();
  }

  void release(int pointer) {
    pointers.remove(pointer);
    if (pointers.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && pointers.isEmpty) cancelled = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = (pending ?? widget.value).clamp(widget.min, widget.max);
    final label = widget.formatValue != null
        ? widget.formatValue!(value)
        : pending == null && widget.valueLabel != null
        ? widget.valueLabel!
        : widget.min < 0 && value > 0
        ? '+${value.round()}'
        : '${value.round()}';
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          SizedBox(
            width: widget.labelWidth,
            child: Text(
              widget.label,
              style: const TextStyle(
                fontSize: 12,
                color: retouchOriginalText,
                height: 1,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                trackShape: const _OriginalSliderTrack(),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                  disabledThumbRadius: 7,
                  elevation: 0,
                  pressedElevation: 0,
                ),
                overlayShape: SliderComponentShape.noOverlay,
                tickMarkShape: SliderTickMarkShape.noTickMark,
                thumbColor: Colors.white,
                disabledThumbColor: Colors.white,
                activeTrackColor: retouchOriginalAccent,
                inactiveTrackColor: const Color(0x66ffffff),
                showValueIndicator: ShowValueIndicator.never,
              ),
              child: Listener(
                onPointerDown: (event) {
                  if (pointers.isEmpty) cancelled = false;
                  pointers.add(event.pointer);
                  if (pointers.length > 1) cancel();
                },
                onPointerUp: (event) => release(event.pointer),
                onPointerCancel: (event) {
                  cancel();
                  release(event.pointer);
                },
                child: Slider(
                  value: value,
                  min: widget.min,
                  max: widget.max,
                  padding: EdgeInsets.zero,
                  semanticFormatterCallback: (_) =>
                      '${widget.semanticLabel ?? widget.label}，$label',
                  onChanged: widget.onChanged == null
                      ? null
                      : (value) {
                          if (cancelled) return;
                          setState(() => pending = value);
                          widget.onChanged!(value);
                        },
                  onChangeStart: widget.onChanged == null
                      ? null
                      : (value) {
                          if (cancelled) return;
                          dragging = true;
                          setState(() => pending = value);
                          widget.onChangeStart?.call(value);
                        },
                  onChangeEnd: widget.onChanged == null
                      ? null
                      : (value) {
                          if (cancelled) return;
                          dragging = false;
                          widget.onChangeEnd?.call(value);
                          if (mounted) setState(() => pending = null);
                        },
                ),
              ),
            ),
          ),
          SizedBox(
            width: widget.valueWidth,
            child:
                widget.trailing ??
                Text(
                  label,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 12,
                    color: retouchOriginalAccent,
                    height: 1,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

class _OriginalSliderTrack extends SliderTrackShape {
  const _OriginalSliderTrack();
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) => Rect.fromLTRB(
    offset.dx + math.min(14, parentBox.size.width / 2),
    offset.dy + parentBox.size.height / 2 - 1,
    offset.dx + math.max(14, parentBox.size.width - 14),
    offset.dy + parentBox.size.height / 2 + 1,
  );
  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(1)),
      Paint()..color = const Color(0x66ffffff),
    );
    // Native ClipDrawable fills from the left, independent of the label direction.
    final progress = Rect.fromLTRB(
      rect.left,
      rect.top,
      thumbCenter.dx.clamp(rect.left, rect.right),
      rect.bottom,
    );
    context.canvas.drawRRect(
      RRect.fromRectAndRadius(progress, const Radius.circular(1)),
      Paint()..color = retouchOriginalAccent,
    );
  }
}

/// icon is the original LineIcon key. entry uses original AppIcon paths for
/// skin/color (TINT), face/natural (PERSON), body (BODY).
class RetouchOriginalToolButton extends StatefulWidget {
  const RetouchOriginalToolButton({
    super.key,
    required this.label,
    required this.icon,
    this.semanticLabel,
    this.selected = false,
    this.onPressed,
    this.entry = false,
  });
  final String label, icon;
  final String? semanticLabel;
  final bool selected, entry;
  final VoidCallback? onPressed;
  @override
  State<RetouchOriginalToolButton> createState() => _OriginalToolState();
}

class _OriginalToolState extends State<RetouchOriginalToolButton> {
  bool pressed = false, focused = false;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final metrics = RetouchOriginalMetrics.resolve(
      Size.zero,
      scale,
      mode: 0,
      choosingGroup: true,
    );
    final enabled = widget.onPressed != null;
    final selected = widget.selected || pressed;
    final color = widget.entry
        ? (widget.selected ? retouchOriginalAccent : Colors.white)
        : selected
        ? retouchOriginalAccent
        : retouchOriginalText;
    final labelColor = widget.entry
        ? (widget.selected ? retouchOriginalAccent : const Color(0x99ffffff))
        : !enabled
        ? color.withAlpha(0x60)
        : color;
    final caption = Text(
      widget.label,
      maxLines: widget.entry ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 10.5, height: 1, color: labelColor),
    );
    final circle = Container(
      width: 39,
      height: 39,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: pressed
            ? const Color(0xe62e3827)
            : widget.selected
            ? const Color(0xe6111713)
            : const Color(0x9c101412),
        border: focused ? Border.all(color: retouchOriginalAccent) : null,
      ),
      alignment: Alignment.center,
      child: Opacity(
        opacity: enabled
            ? (pressed && !widget.entry ? 190 / 255 : 1)
            : 80 / 255,
        child: RetouchOriginalGlyph(
          widget.icon,
          size: 21,
          color: color,
          entry: widget.entry,
        ),
      ),
    );
    return Semantics(
      label: widget.semanticLabel ?? widget.label,
      button: true,
      selected: widget.selected,
      enabled: enabled,
      onTap: widget.onPressed,
      child: Tooltip(
        message: widget.semanticLabel ?? widget.label,
        child: SizedBox(
          width: widget.entry ? metrics.entryWidth : metrics.toolWidth,
          height: widget.entry ? metrics.entryHeight : metrics.toolHeight,
          child: InkWell(
            onTap: widget.onPressed,
            excludeFromSemantics: true,
            splashColor: widget.entry
                ? const Color(0x22ffe335)
                : Colors.transparent,
            highlightColor: Colors.transparent,
            onFocusChange: (value) => setState(() => focused = value),
            onHighlightChanged: (value) => setState(() => pressed = value),
            child: ExcludeSemantics(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  widget.entry ? 0 : 4,
                  3,
                  widget.entry ? 0 : 4,
                  widget.entry ? 0 : 2,
                ),
                child: Column(
                  mainAxisAlignment: widget.entry
                      ? MainAxisAlignment.start
                      : MainAxisAlignment.center,
                  children: [
                    circle,
                    const SizedBox(height: 4),
                    SizedBox(
                      height: widget.entry
                          ? 20 * math.max(1, scale)
                          : math.min(
                              metrics.toolHeight - 48,
                              10.5 * scale * 1.2,
                            ),
                      child: Align(
                        alignment: widget.entry
                            ? Alignment.topCenter
                            : Alignment.center,
                        child: widget.entry
                            ? Baseline(
                                baseline: 14 * math.max(1, scale),
                                baselineType: TextBaseline.alphabetic,
                                child: caption,
                              )
                            : caption,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RetouchOriginalUtilityButton extends StatefulWidget {
  const RetouchOriginalUtilityButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.selected = false,
    this.onPressed,
    this.onCompare,
    this.bodyCompareTransient = false,
  });
  final String icon, semanticLabel;
  final bool selected;
  final bool bodyCompareTransient;
  final VoidCallback? onPressed;
  final ValueChanged<bool>? onCompare;
  @override
  State<RetouchOriginalUtilityButton> createState() => _OriginalUtilityState();
}

class _OriginalUtilityState extends State<RetouchOriginalUtilityButton> {
  bool pressed = false;
  bool keyboardHeld = false, pointerCancelled = false;
  final pointers = <int>{};
  Timer? compareTimer;
  @override
  void didUpdateWidget(RetouchOriginalUtilityButton old) {
    super.didUpdateWidget(old);
    if (old.bodyCompareTransient != widget.bodyCompareTransient ||
        widget.onCompare == null) {
      compareTimer?.cancel();
      compareTimer = null;
      pressed = keyboardHeld = false;
      pointers.clear();
    }
  }

  @override
  void dispose() {
    compareTimer?.cancel();
    super.dispose();
  }

  void hold(bool value, {bool force = false}) {
    final transient = compareTimer != null;
    compareTimer?.cancel();
    compareTimer = null;
    if (widget.onCompare == null ||
        (pressed == value && !(transient && !value) && !force)) {
      return;
    }
    setState(() => pressed = value);
    widget.onCompare!(value);
  }

  void invokeAction() {
    if (widget.onCompare == null) {
      widget.onPressed?.call();
      return;
    }
    if (!widget.bodyCompareTransient) {
      widget.onCompare!(!widget.selected);
      return;
    }
    compareTimer?.cancel();
    widget.onCompare!(true);
    compareTimer = Timer(const Duration(milliseconds: 650), () {
      compareTimer = null;
      if (mounted) widget.onCompare?.call(false);
    });
  }

  KeyEventResult key(FocusNode node, KeyEvent event) {
    if (widget.onCompare == null ||
        !const [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.space,
          LogicalKeyboardKey.select,
        ].contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent && !keyboardHeld) {
      keyboardHeld = true;
      if (widget.bodyCompareTransient) hold(true);
    } else if (event is KeyUpEvent && keyboardHeld) {
      keyboardHeld = false;
      if (widget.bodyCompareTransient) {
        hold(false);
      } else {
        invokeAction();
      }
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null || widget.onCompare != null;
    return Semantics(
      label: widget.semanticLabel,
      button: true,
      enabled: enabled,
      selected: widget.selected,
      onTap: enabled ? invokeAction : null,
      child: Focus(
        canRequestFocus: enabled && widget.onCompare != null,
        onKeyEvent: key,
        onFocusChange: (focused) {
          if (!focused) {
            if (widget.bodyCompareTransient &&
                (pressed || keyboardHeld || compareTimer != null)) {
              hold(false, force: true);
            }
            keyboardHeld = false;
          }
        },
        child: Tooltip(
          message: widget.semanticLabel,
          child: Listener(
            onPointerDown: widget.onCompare == null
                ? null
                : (event) {
                    pointers.add(event.pointer);
                    if (pointers.length > 1) {
                      pointerCancelled = true;
                      hold(false);
                    } else {
                      pointerCancelled = false;
                      hold(true);
                    }
                  },
            onPointerMove: widget.onCompare == null
                ? null
                : (event) {
                    final point = event.localPosition;
                    if (widget.bodyCompareTransient &&
                        !pointerCancelled &&
                        (point.dx < 0 ||
                            point.dy < 0 ||
                            point.dx >= 48 ||
                            point.dy >= 48)) {
                      pointerCancelled = true;
                      hold(false);
                    }
                  },
            onPointerUp: widget.onCompare == null
                ? null
                : (event) {
                    pointers.remove(event.pointer);
                    hold(false);
                  },
            onPointerCancel: widget.onCompare == null
                ? null
                : (event) {
                    pointers.remove(event.pointer);
                    pointerCancelled = true;
                    hold(false);
                  },
            child: InkWell(
              canRequestFocus: widget.onCompare == null,
              onTap: enabled
                  ? (widget.onCompare == null ? invokeAction : () {})
                  : null,
              excludeFromSemantics: true,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onHighlightChanged: widget.onCompare == null
                  ? (value) => setState(() => pressed = value)
                  : null,
              borderRadius: BorderRadius.circular(24),
              child: SizedBox.square(
                dimension: 48,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0x6e0e1513),
                    ),
                    child: RetouchOriginalGlyph(
                      widget.icon,
                      size: 24,
                      color:
                          (widget.selected || pressed
                                  ? retouchOriginalAccent
                                  : retouchOriginalText)
                              .withAlpha(enabled ? (pressed ? 190 : 255) : 80),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RetouchOriginalFaceBar extends StatelessWidget {
  const RetouchOriginalFaceBar({
    super.key,
    required this.selectionLabel,
    this.onSelect,
    required this.onDetect,
    required this.onAdd,
    required this.onMore,
    this.onSelectAnchor,
  });
  final String selectionLabel;
  final VoidCallback? onSelect, onDetect, onAdd;
  final ValueChanged<BuildContext>? onMore;
  final ValueChanged<BuildContext>? onSelectAnchor;
  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    padding: const EdgeInsets.only(left: 8, right: 4),
    color: const Color(0x7017221e),
    child: Row(
      children: [
        Expanded(
          child: Builder(
            builder: (anchor) => RetouchOriginalTextButton(
              selectionLabel,
              onSelectAnchor == null ? onSelect : () => onSelectAnchor!(anchor),
              singleLine: true,
            ),
          ),
        ),
        SizedBox(
          width: 96,
          child: RetouchOriginalTextButton(
            '自动选脸',
            onDetect,
            color: retouchOriginalAccent,
          ),
        ),
        RetouchOriginalUtilityButton(
          icon: 'add',
          semanticLabel: '手动添加人脸',
          onPressed: onAdd,
        ),
        Builder(
          builder: (anchor) => RetouchOriginalUtilityButton(
            icon: 'more',
            semanticLabel: '更多人像操作',
            onPressed: onMore == null ? null : () => onMore!(anchor),
          ),
        ),
      ],
    ),
  );
}

class RetouchOriginalTextButton extends StatelessWidget {
  const RetouchOriginalTextButton(
    this.label,
    this.onPressed, {
    super.key,
    this.color = retouchOriginalText,
    this.selected = false,
    this.singleLine = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool selected;
  final bool singleLine;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      foregroundColor: selected ? retouchOriginalAccent : color,
      disabledForegroundColor: color.withValues(alpha: .4),
      textStyle: const TextStyle(fontSize: 12, height: 1),
    ),
    child: Text(
      label,
      maxLines: singleLine ? 1 : 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

class RetouchOriginalStatus extends StatelessWidget {
  const RetouchOriginalStatus(
    this.text, {
    super.key,
    this.onTap,
    this.overlay = true,
  });
  final String text;
  final VoidCallback? onTap;
  final bool overlay;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Material(
      color: overlay ? const Color(0x7017221e) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            text,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: retouchOriginalMuted),
          ),
        ),
      ),
    ),
  );
}

class RetouchOriginalDock extends StatelessWidget {
  const RetouchOriginalDock({
    super.key,
    required this.controls,
    required this.entries,
    required this.choosingGroup,
  });
  final List<Widget> controls, entries;
  final bool choosingGroup;
  @override
  Widget build(BuildContext context) {
    final scale = math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    return ScrollConfiguration(
      behavior: const ScrollBehavior().copyWith(
        scrollbars: false,
        overscroll: false,
      ),
      child: Column(
        children: [
          if (!choosingGroup)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: controls,
                ),
              ),
            ),
          if (choosingGroup)
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  height: 48 + 20 * scale,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: entries,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Original portrait/body viewport. child lays out in the zoomed image frame;
/// callbacks use original normalized image coordinates and the zoomed image size.
/// Portrait fits the whole stage; BodyCanvas alone reserves and clips 48 dp bars.
class RetouchOriginalPhotoStage extends StatefulWidget {
  const RetouchOriginalPhotoStage({
    super.key,
    required this.imageWidth,
    required this.imageHeight,
    required this.child,
    required this.controller,
    this.drawing = false,
    this.singleFingerPan = false,
    this.navigationEnabled = true,
    this.reserveBars = false,
    this.tapSlop = 20,
    this.onStart,
    this.onUpdate,
    this.onTap,
    this.onEnd,
    this.onCancel,
  });
  final double imageWidth, imageHeight;
  final Widget child;
  final TransformationController controller;
  final bool drawing, singleFingerPan, reserveBars, navigationEnabled;
  final double tapSlop;
  final bool Function(Offset normalized, Size renderedSize)? onStart;
  final ValueChanged<Offset>? onUpdate, onTap;
  final VoidCallback? onEnd, onCancel;
  @override
  State<RetouchOriginalPhotoStage> createState() => _OriginalPhotoStageState();
}

class _OriginalPhotoStageState extends State<RetouchOriginalPhotoStage> {
  final pointers = <int, Offset>{};
  Size size = Size.zero;
  double zoom = 1, lastSpan = 0;
  Offset pan = Offset.zero,
      lastFocus = Offset.zero,
      down = Offset.zero,
      lastPoint = Offset.zero;
  bool tracking = false,
      navigating = false,
      tapPending = false,
      writing = false;
  int? active;
  @override
  void initState() {
    super.initState();
    readController();
    widget.controller.addListener(controllerChanged);
  }

  @override
  void didUpdateWidget(RetouchOriginalPhotoStage old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(controllerChanged);
      widget.controller.addListener(controllerChanged);
      readController();
    }
    if (old.imageWidth != widget.imageWidth ||
        old.imageHeight != widget.imageHeight ||
        old.reserveBars != widget.reserveBars ||
        old.controller != widget.controller) {
      final cancelled = tracking;
      resetGesture();
      pointers.clear();
      clamp();
      if (cancelled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onCancel?.call();
        });
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(controllerChanged);
    super.dispose();
  }

  void readController() {
    final matrix = widget.controller.value;
    final scale = matrix.getMaxScaleOnAxis();
    zoom = scale.isFinite ? scale.clamp(1, 8) : 1;
    final x = matrix.storage[12], y = matrix.storage[13];
    pan = Offset(x.isFinite ? x : 0, y.isFinite ? y : 0);
    clamp();
  }

  void controllerChanged() {
    if (!mounted || writing) return;
    cancelEditing();
    navigating = pointers.isNotEmpty;
    setState(readController);
  }

  Size fitted(Size viewport) {
    if (viewport.isEmpty || widget.imageWidth <= 0 || widget.imageHeight <= 0) {
      return Size.zero;
    }
    final height = widget.reserveBars
        ? math.max(1.0, viewport.height - 96)
        : viewport.height;
    final scale = math.min(
      viewport.width / widget.imageWidth,
      height / widget.imageHeight,
    );
    return Size(widget.imageWidth * scale, widget.imageHeight * scale);
  }

  Rect get frame => Rect.fromCenter(
    center: size.center(Offset.zero) + pan,
    width: fitted(size).width * zoom,
    height: fitted(size).height * zoom,
  );
  void clamp() {
    if (size.isEmpty) return;
    final fit = fitted(size);
    final mx = math.max(0.0, (fit.width * zoom - size.width) / 2);
    final available = widget.reserveBars
        ? math.max(1.0, size.height - 96)
        : size.height;
    final my = math.max(0.0, (fit.height * zoom - available) / 2);
    pan = Offset(pan.dx.clamp(-mx, mx), pan.dy.clamp(-my, my));
  }

  Matrix4 matrix() => Matrix4.identity()
    ..setEntry(0, 0, zoom)
    ..setEntry(1, 1, zoom)
    ..setTranslationRaw(pan.dx, pan.dy, 0);
  void publish() {
    clamp();
    writing = true;
    try {
      widget.controller.value = matrix();
    } finally {
      writing = false;
    }
    if (mounted) setState(() {});
  }

  Offset normalized(Offset point) {
    final rect = frame;
    return Offset(
      ((point.dx - rect.left) / math.max(1, rect.width)).clamp(0, 1),
      ((point.dy - rect.top) / math.max(1, rect.height)).clamp(0, 1),
    );
  }

  bool available(Offset point) =>
      !widget.reserveBars ||
      (point.dy >= 48 && point.dy <= math.max(48, size.height - 48));
  void cancelEditing() {
    final wasTracking = tracking;
    tracking = false;
    tapPending = false;
    active = null;
    if (wasTracking) widget.onCancel?.call();
  }

  void resetGesture() {
    tracking = navigating = tapPending = false;
    active = null;
    lastSpan = 0;
  }

  Offset get focus {
    var sum = Offset.zero;
    for (final point in pointers.values) {
      sum += point;
    }
    return pointers.isEmpty ? lastFocus : sum / pointers.length.toDouble();
  }

  double span(Offset center) {
    var x = 0.0, y = 0.0;
    for (final point in pointers.values) {
      x += (point.dx - center.dx).abs();
      y += (point.dy - center.dy).abs();
    }
    final count = math.max(1, pointers.length);
    return math.sqrt(x * x + y * y) * 2 / count;
  }

  void pointerDown(PointerDownEvent event) {
    pointers[event.pointer] = event.localPosition;
    if (pointers.length > 1) {
      cancelEditing();
      navigating = true;
      lastFocus = focus;
      lastSpan = span(lastFocus);
      return;
    }
    if (navigating) return;
    active = event.pointer;
    down = lastPoint = event.localPosition;
    final inside = available(down) && frame.contains(down);
    tracking =
        inside &&
        widget.drawing &&
        (widget.onStart?.call(normalized(down), frame.size) ?? false);
    tapPending = inside && !tracking;
  }

  void pointerMove(PointerMoveEvent event) {
    if (!pointers.containsKey(event.pointer)) return;
    pointers[event.pointer] = event.localPosition;
    if (pointers.length > 1) {
      if (!widget.navigationEnabled) {
        navigating = true;
        return;
      }
      final currentFocus = focus, currentSpan = span(currentFocus);
      if (lastSpan > 0 && currentSpan > 0) {
        final next = (zoom * currentSpan / lastSpan).clamp(1.0, 8.0),
            ratio = next / zoom;
        final relative = currentFocus - size.center(Offset.zero);
        pan = relative - (relative - pan) * ratio;
        zoom = next;
      }
      pan += currentFocus - lastFocus;
      lastFocus = currentFocus;
      lastSpan = currentSpan;
      navigating = true;
      publish();
      return;
    }
    if (navigating || event.pointer != active) return;
    if (tracking) {
      widget.onUpdate?.call(normalized(event.localPosition));
    } else if (widget.navigationEnabled && widget.singleFingerPan && zoom > 1) {
      pan += event.localPosition - lastPoint;
      tapPending = false;
      publish();
    }
    lastPoint = event.localPosition;
  }

  void pointerUp(PointerUpEvent event) {
    pointers.remove(event.pointer);
    if (!navigating && event.pointer == active) {
      if (tracking) {
        widget.onUpdate?.call(normalized(event.localPosition));
        tracking = false;
        widget.onEnd?.call();
      } else if (tapPending &&
          available(event.localPosition) &&
          frame.contains(event.localPosition) &&
          (event.localPosition - down).distance < widget.tapSlop) {
        widget.onTap?.call(normalized(event.localPosition));
      }
    }
    if (pointers.isEmpty) {
      resetGesture();
    } else {
      lastFocus = focus;
      lastSpan = span(lastFocus);
    }
  }

  void resolveSize(Size next) {
    if (size == next) return;
    final previous = size, oldFrame = frame;
    final cancelled = tracking;
    resetGesture();
    pointers.clear();
    size = next;
    // Original portrait rotation retains the frozen image centre and zoom.
    // BodyCanvas retains its pan, then clamps it against the new fitted bounds.
    if (!widget.reserveBars && !previous.isEmpty && !oldFrame.isEmpty) {
      final centerX = (previous.width / 2 - oldFrame.left) / oldFrame.width;
      final centerY = (previous.height / 2 - oldFrame.top) / oldFrame.height;
      final fit = fitted(size);
      pan = Offset(
        (.5 - centerX) * fit.width * zoom,
        (.5 - centerY) * fit.height * zoom,
      );
    }
    clamp();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || size != next) return;
      if (cancelled) widget.onCancel?.call();
      writing = true;
      try {
        widget.controller.value = matrix();
      } finally {
        writing = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      resolveSize(bounds.biggest);
      final target = frame;
      Widget image = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fromRect(
            rect: target,
            child: SizedBox(
              width: target.width,
              height: target.height,
              child: widget.child,
            ),
          ),
        ],
      );
      image = ClipRect(
        clipper: widget.reserveBars ? const _OriginalStageClip() : null,
        child: image,
      );
      return RawGestureDetector(
        gestures: {
          EagerGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                EagerGestureRecognizer.new,
                (_) {},
              ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: pointerDown,
          onPointerMove: pointerMove,
          onPointerUp: pointerUp,
          onPointerCancel: (event) {
            pointers.remove(event.pointer);
            cancelEditing();
            if (pointers.isEmpty) resetGesture();
          },
          child: SizedBox.expand(child: image),
        ),
      );
    },
  );
}

class _OriginalStageClip extends CustomClipper<Rect> {
  const _OriginalStageClip();
  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    math.min(48, size.height),
    size.width,
    math.max(math.min(48, size.height), size.height - 48),
  );
  @override
  bool shouldReclip(_OriginalStageClip old) => false;
}

class RetouchOriginalLightPad extends StatefulWidget {
  const RetouchOriginalLightPad({
    super.key,
    required this.x,
    required this.y,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.onCancel,
  });
  final double x, y;
  final ValueChanged<Offset>? onChanged;
  final VoidCallback? onChangeStart, onChangeEnd, onCancel;
  @override
  State<RetouchOriginalLightPad> createState() => _OriginalLightPadState();
}

class _OriginalLightPadState extends State<RetouchOriginalLightPad> {
  final pointers = <int>{};
  int? active;
  Offset? pending;
  bool dragging = false;
  void cancel() {
    if (!dragging) return;
    setState(() {
      dragging = false;
      active = null;
      pending = null;
    });
    widget.onCancel?.call();
  }

  void update(Offset point, Size size) {
    final radius = math.max(1.0, math.min(size.width, size.height) * .42);
    var x = ((point.dx - size.width / 2) / radius * 100)
        .clamp(-100, 100)
        .roundToDouble();
    var y = ((point.dy - size.height / 2) / radius * 100)
        .clamp(-100, 100)
        .roundToDouble();
    final magnitude = math.sqrt(x * x + y * y);
    if (magnitude > 100) {
      x = (x * 100 / magnitude).roundToDouble();
      y = (y * 100 / magnitude).roundToDouble();
    }
    final value = Offset(x, y);
    setState(() => pending = value);
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 112,
    child: LayoutBuilder(
      builder: (context, bounds) {
        final value = pending ?? Offset(widget.x, widget.y);
        return Semantics(
          label: '拖动光点调整补光方向，也可使用左右和上下精确调节',
          value: '${value.dx.round()}, ${value.dy.round()}',
          enabled: widget.onChanged != null,
          child: RawGestureDetector(
            gestures: widget.onChanged == null
                ? const {}
                : {
                    EagerGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          EagerGestureRecognizer
                        >(EagerGestureRecognizer.new, (_) {}),
                  },
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                pointers.add(event.pointer);
                if (widget.onChanged == null) return;
                if (pointers.length > 1) {
                  cancel();
                  return;
                }
                active = event.pointer;
                setState(() => dragging = true);
                widget.onChangeStart?.call();
                update(event.localPosition, bounds.biggest);
              },
              onPointerMove: (event) {
                if (dragging &&
                    event.pointer == active &&
                    widget.onChanged != null) {
                  update(event.localPosition, bounds.biggest);
                }
              },
              onPointerUp: (event) {
                pointers.remove(event.pointer);
                if (!dragging || event.pointer != active) return;
                setState(() {
                  dragging = false;
                  active = null;
                  pending = null;
                });
                widget.onChangeEnd?.call();
              },
              onPointerCancel: (event) {
                pointers.remove(event.pointer);
                cancel();
              },
              child: CustomPaint(
                size: bounds.biggest,
                painter: _OriginalLightPosition(value, dragging),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _OriginalLightPosition extends CustomPainter {
  const _OriginalLightPosition(this.value, this.dragging);
  final Offset value;
  final bool dragging;
  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.max(1.0, math.min(size.width, size.height) * .42);
    final center = size.center(Offset.zero);
    final distance = math.max(1.0, value.distance / 100);
    final light = center + value / distance / 100 * radius;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          light,
          radius * 1.8,
          const [Color(0xffb6a28e), Color(0xff51483f), Color(0xff24211e)],
          const [0, .5, 1],
        ),
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xff6e5c4f);
    canvas.drawCircle(center, radius, line);
    canvas.drawLine(
      center - Offset(radius, 0),
      center + Offset(radius, 0),
      line,
    );
    canvas.drawLine(
      center - Offset(0, radius),
      center + Offset(0, radius),
      line,
    );
    canvas.drawCircle(
      light,
      17,
      Paint()
        ..color = dragging ? const Color(0x44ffe335) : const Color(0x22ffe335),
    );
    canvas.drawCircle(light, 6, Paint()..color = retouchOriginalAccent);
  }

  @override
  bool shouldRepaint(_OriginalLightPosition old) =>
      old.value != value || old.dragging != dragging;
}

class RetouchOriginalGlyph extends StatelessWidget {
  const RetouchOriginalGlyph(
    this.name, {
    super.key,
    this.size = 24,
    this.color = retouchOriginalText,
    this.entry = false,
  });
  final String name;
  final double size;
  final Color color;
  final bool entry;
  @override
  Widget build(BuildContext context) {
    final key = name == 'skin'
        ? 'color'
        : name == 'natural'
        ? 'face'
        : name == 'eye-white'
        ? 'eye-clean'
        : name;
    if (!entry &&
        const [
          'add',
          'close',
          'undo',
          'redo',
          'more',
          'eye',
          'brush',
          'fit',
          'compare',
        ].contains(key)) {
      return WorkspaceGlyph(key, size: size, color: color);
    }
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _PortraitGlyph(key, color, entry)),
      ),
    );
  }
}

class _PortraitGlyph extends CustomPainter {
  const _PortraitGlyph(this.name, this.color, this.entry);
  final String name;
  final Color color;
  final bool entry;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = entry ? 1.8 : 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    var path = Path();
    void line(double x, double y, double a, double b) =>
        canvas.drawLine(Offset(x, y), Offset(a, b), ink);
    void stroke() => canvas.drawPath(path, ink);
    if (entry && name == 'color') {
      path
        ..moveTo(12, 2)
        ..cubicTo(10, 7, 4, 11, 5, 16)
        ..cubicTo(6, 24, 19, 24, 19, 16)
        ..cubicTo(19, 11, 14, 6, 12, 2);
      stroke();
    } else if (entry && name == 'face') {
      canvas.drawCircle(const Offset(12, 7.5), 4, ink);
      canvas.drawArc(
        const Rect.fromLTRB(4, 13, 20, 27),
        math.pi,
        math.pi,
        false,
        ink,
      );
      line(4, 20, 20, 20);
    } else {
      switch (name) {
        case 'body':
          path
            ..moveTo(7, 3)
            ..cubicTo(10, 8, 9, 10, 7, 13)
            ..cubicTo(5, 16, 5, 19, 6, 22)
            ..moveTo(17, 3)
            ..cubicTo(14, 8, 15, 10, 17, 13)
            ..cubicTo(19, 16, 19, 19, 18, 22);
          stroke();
          line(2, 11, 5, 11);
          line(19, 11, 22, 11);
          if (entry) {
            line(3, 9, 5, 11);
            line(5, 11, 3, 13);
            line(21, 9, 19, 11);
            line(19, 11, 21, 13);
          }
        case 'legs':
          path
            ..moveTo(5, 3)
            ..lineTo(6, 21)
            ..lineTo(10, 21)
            ..lineTo(12, 9)
            ..lineTo(14, 21)
            ..lineTo(18, 21)
            ..lineTo(19, 3);
          stroke();
          line(5, 3, 19, 3);
        case 'length':
          line(6, 4, 6, 20);
          line(3, 7, 6, 4);
          line(9, 7, 6, 4);
          line(3, 17, 6, 20);
          line(9, 17, 6, 20);
          path
            ..moveTo(14, 3)
            ..lineTo(14, 12)
            ..lineTo(12, 21)
            ..lineTo(18, 21)
            ..lineTo(20, 12)
            ..lineTo(20, 3);
          stroke();
        case 'back':
          line(19, 12, 5, 12);
          line(5, 12, 12, 5);
          line(5, 12, 12, 19);
        case 'check':
          path
            ..moveTo(4, 12)
            ..lineTo(9.5, 17.5)
            ..lineTo(20, 6.5);
          stroke();
        case 'face':
          canvas.drawOval(const Rect.fromLTRB(5, 2.5, 19, 21.5), ink);
          line(8, 10, 9, 10);
          line(15, 10, 16, 10);
          path
            ..moveTo(9, 16)
            ..quadraticBezierTo(12, 18, 15, 16);
          stroke();
        case 'color':
          path
            ..moveTo(12, 2.5)
            ..cubicTo(10, 6, 5, 10.5, 5, 14.5)
            ..cubicTo(5, 23, 19, 23, 19, 14.5)
            ..cubicTo(19, 10.5, 14, 6, 12, 2.5);
          stroke();
          path = Path()
            ..moveTo(8.5, 14)
            ..quadraticBezierTo(8.5, 17, 11, 18);
          stroke();
        case 'smooth':
          path
            ..moveTo(4, 17)
            ..cubicTo(8, 18, 17, 14, 19, 4)
            ..cubicTo(10, 2, 5, 8, 7, 14);
          stroke();
          line(4, 21, 15, 9);
          line(9, 14, 9, 8);
          line(9, 14, 15, 14);
        case 'light':
          canvas.drawCircle(const Offset(12, 12), 4, ink);
          for (var i = 0; i < 8; i++) {
            final a = i * math.pi / 4;
            line(
              12 + math.cos(a) * 7,
              12 + math.sin(a) * 7,
              12 + math.cos(a) * 9.5,
              12 + math.sin(a) * 9.5,
            );
          }
        case 'brightness':
          canvas.drawCircle(const Offset(12, 12), 5, ink);
          line(12, 7, 12, 17);
          line(12, 2, 12, 4);
          line(12, 20, 12, 22);
          line(2, 12, 4, 12);
          line(20, 12, 22, 12);
          line(5, 5, 6.5, 6.5);
          line(17.5, 17.5, 19, 19);
          line(5, 19, 6.5, 17.5);
          line(17.5, 6.5, 19, 5);
        case 'warmth':
          path
            ..moveTo(9, 14)
            ..lineTo(9, 5)
            ..cubicTo(9, 1, 15, 1, 15, 5)
            ..lineTo(15, 14)
            ..cubicTo(22, 20, 12, 26, 7.5, 20)
            ..quadraticBezierTo(5.5, 16.5, 9, 14);
          stroke();
          line(12, 8, 12, 18);
          line(18, 6, 21, 6);
          line(18, 10, 20, 10);
        case 'redness':
          canvas.drawOval(const Rect.fromLTRB(5, 2.5, 19, 21.5), ink);
          canvas.drawCircle(const Offset(8, 13.5), 1.6, ink);
          canvas.drawCircle(const Offset(16, 13.5), 1.6, ink);
          path
            ..moveTo(9, 17)
            ..quadraticBezierTo(12, 19, 15, 17);
          stroke();
        case 'texture':
          for (double y = 6; y <= 18; y += 6) {
            path = Path()
              ..moveTo(3, y)
              ..cubicTo(7, y - 4, 9, y + 4, 13, y)
              ..cubicTo(17, y - 4, 19, y + 4, 22, y);
            stroke();
          }
        case 'shadows':
          path
            ..moveTo(16, 3)
            ..cubicTo(3, 1, 1, 18, 11, 21)
            ..quadraticBezierTo(18, 23, 21, 16)
            ..cubicTo(12, 20, 8, 8, 16, 3);
          stroke();
        case 'heal':
          canvas.save();
          canvas.translate(12, 12);
          canvas.rotate(-math.pi / 4);
          canvas.translate(-12, -12);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTRB(3, 7, 21, 17),
              const Radius.circular(4),
            ),
            ink,
          );
          line(8, 7, 8, 17);
          line(16, 7, 16, 17);
          canvas.drawCircle(const Offset(11, 10), .35, ink);
          canvas.drawCircle(const Offset(13, 14), .35, ink);
          canvas.restore();
        case 'teeth':
          path
            ..moveTo(6, 3)
            ..cubicTo(2, 5, 4, 12, 6, 18)
            ..quadraticBezierTo(8, 24, 10, 16)
            ..quadraticBezierTo(12, 11, 14, 16)
            ..quadraticBezierTo(16, 24, 18, 18)
            ..cubicTo(20, 12, 22, 5, 18, 3)
            ..quadraticBezierTo(15, 1, 12, 4)
            ..quadraticBezierTo(9, 1, 6, 3);
          stroke();
          line(10, 7, 14, 7);
        case 'under-eye':
          path
            ..moveTo(3, 9)
            ..quadraticBezierTo(12, 0, 21, 9)
            ..quadraticBezierTo(12, 18, 3, 9);
          stroke();
          canvas.drawCircle(const Offset(12, 9), 2, ink);
          canvas.drawArc(
            const Rect.fromLTRB(4, 8, 20, 21),
            15 * math.pi / 180,
            150 * math.pi / 180,
            false,
            ink,
          );
        case 'eye-clean':
          path
            ..moveTo(2, 12)
            ..quadraticBezierTo(12, -1, 22, 12)
            ..quadraticBezierTo(12, 25, 2, 12);
          stroke();
          canvas.drawCircle(const Offset(12, 12), 3, ink);
          line(19, 2, 19, 7);
          line(16.5, 4.5, 21.5, 4.5);
        case 'skin-even':
          canvas.drawOval(const Rect.fromLTRB(5, 2, 19, 22), ink);
          line(8, 10, 16, 10);
          line(8, 14, 16, 14);
          line(10, 18, 14, 18);
        case 'shine-control':
          path
            ..moveTo(10, 3)
            ..cubicTo(9, 7, 4, 11, 4, 15)
            ..cubicTo(4, 23, 17, 23, 17, 15)
            ..cubicTo(17, 11, 12, 7, 10, 3);
          stroke();
          line(15, 5, 22, 5);
        case 'erase':
          path
            ..moveTo(3, 14)
            ..lineTo(13, 3)
            ..quadraticBezierTo(14, 2, 15, 3)
            ..lineTo(21, 9)
            ..lineTo(11, 20)
            ..lineTo(8, 20)
            ..close();
          stroke();
          line(8, 9, 16, 16);
          line(11, 20, 21, 20);
        case 'range-options':
          line(3, 6, 7, 6);
          line(11, 6, 21, 6);
          canvas.drawCircle(const Offset(9, 6), 2, ink);
          line(3, 12, 13, 12);
          line(17, 12, 21, 12);
          canvas.drawCircle(const Offset(15, 12), 2, ink);
          line(3, 18, 8, 18);
          line(12, 18, 21, 18);
          canvas.drawCircle(const Offset(10, 18), 2, ink);
        case 'reset':
          canvas.drawArc(
            const Rect.fromLTRB(3.5, 3.5, 20.5, 20.5),
            20 * math.pi / 180,
            280 * math.pi / 180,
            false,
            ink,
          );
          path
            ..moveTo(16.25, 4.64)
            ..lineTo(20.5, 9)
            ..moveTo(20.5, 3.5)
            ..lineTo(20.5, 9)
            ..lineTo(15, 9);
          stroke();
        default:
          // Unrecognised keys stay visibly distinct; callers use the authored keys.
          canvas.drawCircle(const Offset(12, 12), 7, ink);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PortraitGlyph old) =>
      old.name != name || old.color != color || old.entry != entry;
}
