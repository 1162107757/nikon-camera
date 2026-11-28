part of 'camera_remote_settings.dart';

class CameraRemoteRuler extends StatefulWidget {
  const CameraRemoteRuler({
    super.key,
    required this.title,
    required this.values,
    required this.actual,
    required this.formatValue,
    required this.onChanged,
    required this.buildCard,
    this.temperature = false,
  });

  final String title;
  final List<int> values;
  final int? actual;
  final String Function(int value) formatValue;
  final Future<void> Function(int value)? onChanged;
  final Widget Function(Widget ruler, {Widget? readout}) buildCard;
  final bool temperature;

  @override
  State<CameraRemoteRuler> createState() => _CameraRemoteRulerState();
}

class _CameraRemoteRulerState extends State<CameraRemoteRuler>
    with SingleTickerProviderStateMixin {
  static const double _distancePerStep = 30;
  late final AnimationController position;
  bool dragging = false, committing = false;

  bool get editable => widget.onChanged != null && !committing;

  int get coarseStep =>
      widget.temperature ? math.max(1, (widget.values.length / 80).round()) : 1;

  double get spacing => _distancePerStep / coarseStep;

  int get currentIndex {
    final values = widget.values;
    final actual = widget.actual;
    if (actual == null) return 0;
    final upper = values.indexWhere((value) => value >= actual);
    if (upper <= 0) return upper == 0 ? 0 : values.length - 1;
    return actual - values[upper - 1] < values[upper] - actual
        ? upper - 1
        : upper;
  }

  @override
  void initState() {
    super.initState();
    position = AnimationController.unbounded(
      vsync: this,
      value: currentIndex.toDouble(),
    );
  }

  @override
  void didUpdateWidget(CameraRemoteRuler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.values, widget.values)) {
      dragging = false;
      position.value = currentIndex.toDouble();
    } else if (dragging && !editable) {
      dragging = false;
      snap(currentIndex);
    } else if (!dragging && !committing && oldWidget.actual != widget.actual) {
      snap(currentIndex);
    }
  }

  @override
  void dispose() {
    position.dispose();
    super.dispose();
  }

  double bound(double index) =>
      index.clamp(0.0, (widget.values.length - 1).toDouble());

  void snap(int index) {
    final value = index.toDouble();
    if (MediaQuery.disableAnimationsOf(context)) {
      position.value = value;
    } else {
      position.animateTo(
        value,
        duration: const Duration(milliseconds: 195),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void step(int offset) =>
      unawaited(choose((currentIndex + offset).toDouble()));

  void start(DragStartDetails event) {
    if (!editable) return;
    position.stop();
    setState(() => dragging = true);
  }

  void drag(DragUpdateDetails event) {
    if (dragging && editable) {
      position.value = bound(position.value - event.delta.dx / spacing);
    }
  }

  void cancel() {
    if (!dragging) return;
    setState(() => dragging = false);
    snap(currentIndex);
  }

  void end(DragEndDetails event) {
    if (dragging) unawaited(choose(position.value));
  }

  Future<void> choose(double target) async {
    final change = widget.onChanged;
    if (change == null || committing) return;
    final index = bound(target).round();
    final changed = index != currentIndex;
    setState(() {
      dragging = false;
      committing = changed;
    });
    snap(index);
    if (!changed) return;
    try {
      await change(widget.values[index]);
    } finally {
      // The parent publishes its confirmed camera value on the next frame.
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => committing = false);
          snap(currentIndex);
        });
        WidgetsBinding.instance.ensureVisualUpdate();
      }
    }
  }

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (!editable || event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowDown) {
      step(-1);
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp) {
      step(1);
    } else if (key == LogicalKeyboardKey.home) {
      unawaited(choose(0));
    } else if (key == LogicalKeyboardKey.end) {
      unawaited(choose((widget.values.length - 1).toDouble()));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    key: const Key('remote-ruler-motion'),
    animation: position,
    builder: (context, _) {
      final values = widget.values;
      final index = currentIndex;
      final highlighted = bound(position.value).round();
      final selected = dragging || committing
          ? values[highlighted]
          : widget.actual ?? values[index];
      final decrease = editable && index > 0;
      final increase = editable && index < values.length - 1;
      return widget.buildCard(
        Focus(
          onKeyEvent: handleKey,
          child: Semantics(
            label: widget.title,
            value: widget.formatValue(selected),
            decreasedValue: decrease
                ? widget.formatValue(values[index - 1])
                : null,
            increasedValue: increase
                ? widget.formatValue(values[index + 1])
                : null,
            onDecrease: decrease ? () => step(-1) : null,
            onIncrease: increase ? () => step(1) : null,
            child: SizedBox(
              height: 58,
              child: LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  key: const Key('remote-setting-ruler'),
                  behavior: HitTestBehavior.opaque,
                  dragStartBehavior: DragStartBehavior.down,
                  onHorizontalDragStart: editable ? start : null,
                  onHorizontalDragUpdate: editable ? drag : null,
                  onHorizontalDragEnd: editable ? end : null,
                  onHorizontalDragCancel: editable ? cancel : null,
                  onTapUp: editable
                      ? (event) {
                          final offset =
                              event.localPosition.dx - box.maxWidth / 2;
                          unawaited(choose(position.value + offset / spacing));
                        }
                      : null,
                  child: RepaintBoundary(child: track(values)),
                ),
              ),
            ),
          ),
        ),
        readout: ExcludeSemantics(
          child: Text(
            widget.formatValue(selected),
            style: const TextStyle(
              color: _accent,
              fontWeight: FontWeight.w700,
              fontSize: 22,
            ),
          ),
        ),
      );
    },
  );

  Widget track(List<int> values) => Stack(
    alignment: Alignment.topCenter,
    children: [
      Positioned.fill(
        child: CustomPaint(
          painter: _CameraRulerTrack(
            position: position.value,
            spacing: spacing,
            coarseStep: coarseStep,
            values: values,
            format: widget.formatValue,
          ),
        ),
      ),
      if (widget.temperature)
        Positioned(
          top: 35,
          left: 16,
          right: 16,
          child: Container(
            height: 2,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xff74a0cb), _muted, _accent],
              ),
            ),
          ),
        ),
      Positioned(
        top: 3,
        child: SizedBox(
          key: const Key('remote-ruler-marker'),
          width: 8,
          height: 31,
          child: CustomPaint(painter: _CameraRulerMarker()),
        ),
      ),
    ],
  );
}

class _CameraRulerTrack extends CustomPainter {
  const _CameraRulerTrack({
    required this.position,
    required this.spacing,
    required this.coarseStep,
    required this.values,
    required this.format,
  });

  final double position, spacing;
  final int coarseStep;
  final List<int> values;
  final String Function(int) format;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final center = size.width / 2;
    final first = math.max(0, (position - center / spacing).floor());
    final last = math.min(
      values.length - 1,
      (position + center / spacing).ceil(),
    );
    final selected = position.round();
    final paint = Paint()..strokeWidth = 1;
    for (var i = first; i <= last; i++) {
      final x = center + (i - position) * spacing;
      final fades = (math.min(x, size.width - x) / 28).clamp(0.0, 1.0);
      final major = i % (3 * coarseStep) == 0 || i == values.length - 1;
      final step = i % coarseStep == 0;
      final height = major
          ? 23.0
          : step
          ? 14.0
          : 5.0;
      paint.color = _muted.withValues(alpha: fades * (step ? .78 : .37));
      canvas.drawLine(Offset(x, 34 - height), Offset(x, 34), paint);
      if (!major) continue;

      final text = TextPainter(
        text: TextSpan(
          text: format(values[i]),
          style: TextStyle(
            color: (i == selected ? _accent : _muted).withValues(alpha: fades),
            fontSize: 11,
            fontWeight: i == selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 72);
      text.paint(canvas, Offset(x - text.width / 2, 40));
      text.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CameraRulerTrack oldDelegate) =>
      position != oldDelegate.position ||
      spacing != oldDelegate.spacing ||
      coarseStep != oldDelegate.coarseStep ||
      values != oldDelegate.values ||
      format != oldDelegate.format;
}

class _CameraRulerMarker extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _accent;
    final center = size.width / 2;
    canvas.drawRect(Rect.fromLTWH(center - 1, 0, 2, size.height), paint);
    final arrow = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(center, 6)
      ..close();
    canvas.drawPath(arrow, paint);
  }

  @override
  bool shouldRepaint(covariant _CameraRulerMarker oldDelegate) => false;
}
