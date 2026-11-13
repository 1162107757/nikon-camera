import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Both surfaces have identical geometry. The divider clips a shared zoomed
/// scene, so switching or dragging never changes the photo's framing.
class SplitCompare extends StatefulWidget {
  const SplitCompare({
    super.key,
    required this.effect,
    this.original,
    this.enabled = false,
    this.onRetry,
    this.selection,
    this.selectionSize,
    this.warning,
    this.warningRect = const Rect.fromLTWH(0, 0, 1, 1),
    this.warningCorner = 0,
  });
  final String effect;
  final String? original;
  final bool enabled;
  final VoidCallback? onRetry;
  final ui.Image? selection;
  final Size? selectionSize;
  final ui.Image? warning;
  final Rect warningRect;
  final double warningCorner;
  @override
  State<SplitCompare> createState() => _SplitCompareState();
}

class _SplitCompareState extends State<SplitCompare> {
  final transform = TransformationController();
  double divider = .5;
  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  Widget image(String path) => Image.file(
    File(path),
    width: double.infinity,
    height: double.infinity,
    fit: BoxFit.contain,
    gaplessPlayback: true,
    excludeFromSemantics: true,
    errorBuilder: (_, _, _) => Center(
      child: TextButton(onPressed: widget.onRetry, child: const Text('重试预览')),
    ),
  );
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      void adjust(double value) =>
          setState(() => divider = value.clamp(0.0, 1.0));
      Widget surface(String path) => InteractiveViewer(
        transformationController: transform,
        minScale: 1,
        maxScale: 8,
        child: SizedBox(
          width: box.maxWidth,
          height: box.maxHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              image(path),
              if (!widget.enabled &&
                  widget.warning != null &&
                  widget.selectionSize != null)
                IgnorePointer(
                  child: ExcludeSemantics(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: widget.selectionSize!.width,
                        height: widget.selectionSize!.height,
                        child: Stack(
                          children: [
                            Positioned.fromRect(
                              rect: Rect.fromLTWH(
                                widget.warningRect.left *
                                    widget.selectionSize!.width,
                                widget.warningRect.top *
                                    widget.selectionSize!.height,
                                widget.warningRect.width *
                                    widget.selectionSize!.width,
                                widget.warningRect.height *
                                    widget.selectionSize!.height,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  widget.warningCorner *
                                      widget.warningRect.width *
                                      widget.selectionSize!.width,
                                ),
                                child: RawImage(
                                  image: widget.warning,
                                  fit: BoxFit.fill,
                                  filterQuality: FilterQuality.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (!widget.enabled &&
                  widget.selection != null &&
                  widget.selectionSize != null)
                IgnorePointer(
                  child: ExcludeSemantics(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: widget.selectionSize!.width,
                        height: widget.selectionSize!.height,
                        child: RawImage(
                          image: widget.selection,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.low,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            image: true,
            label: '照片效果预览',
            child: surface(widget.effect),
          ),
          if (widget.enabled && widget.original != null) ...[
            // Only the effect surface handles pan/zoom; both read the same matrix.
            IgnorePointer(
              child: ClipRect(
                clipper: _FractionClip(divider),
                child: AnimatedBuilder(
                  animation: transform,
                  builder: (_, _) => Transform(
                    transform: transform.value,
                    alignment: Alignment.topLeft,
                    child: image(widget.original!),
                  ),
                ),
              ),
            ),
            Positioned(
              left: (box.maxWidth * divider - 24).clamp(
                -24.0,
                box.maxWidth - 24,
              ),
              top: 0,
              bottom: 0,
              width: 48,
              child: Focus(
                onKeyEvent: (_, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                    adjust(divider - .05);
                  } else if (event.logicalKey ==
                      LogicalKeyboardKey.arrowRight) {
                    adjust(divider + .05);
                  } else {
                    return KeyEventResult.ignored;
                  }
                  return KeyEventResult.handled;
                },
                child: Semantics(
                  label: '拖动分割线，对比原图与效果',
                  slider: true,
                  value: '${(divider * 100).round()}%',
                  increasedValue:
                      '${((divider + .05).clamp(0.0, 1.0) * 100).round()}%',
                  decreasedValue:
                      '${((divider - .05).clamp(0.0, 1.0) * 100).round()}%',
                  onIncrease: () => adjust(divider + .05),
                  onDecrease: () => adjust(divider - .05),
                  child: GestureDetector(
                    key: const ValueKey('compare-divider'),
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) =>
                        adjust(divider + details.delta.dx / box.maxWidth),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(width: 1, color: Colors.white),
                        Container(
                          width: 36,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xd9222925),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white),
                          ),
                          child: const Icon(
                            Icons.unfold_more,
                            color: Colors.white,
                            size: 20,
                          ).applyRotation(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(left: 12, top: 12, child: _CompareLabel('原图')),
            const Positioned(right: 12, bottom: 12, child: _CompareLabel('效果')),
          ],
        ],
      );
    },
  );
}

extension on Widget {
  Widget applyRotation() => RotatedBox(quarterTurns: 1, child: this);
}

class _FractionClip extends CustomClipper<Rect> {
  _FractionClip(this.fraction);
  final double fraction;
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(0, 0, size.width * fraction, size.height);
  @override
  bool shouldReclip(_FractionClip old) => old.fraction != fraction;
}

class _CompareLabel extends StatelessWidget {
  const _CompareLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xb3101412),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    ),
  );
}
