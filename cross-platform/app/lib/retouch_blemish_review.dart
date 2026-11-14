import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'editing_viewport.dart';

import 'retouch_original_controls.dart'
    show
        RetouchOriginalPhotoStage,
        RetouchPhotoViewport,
        retouchOriginalPhotoFrame;

const _accent = Color(0xffffe335);
const _background = Color(0xff17221e);

@immutable
class RetouchBlemishCandidate {
  const RetouchBlemishCandidate({
    required this.index,
    required this.x,
    required this.y,
    required this.radius,
  });

  final int index;
  final double x, y, radius;
  bool get isValid =>
      index >= 0 &&
      x.isFinite &&
      y.isFinite &&
      radius.isFinite &&
      x >= 0 &&
      x <= 1 &&
      y >= 0 &&
      y <= 1 &&
      radius > 0 &&
      radius <= 1;

  @override
  bool operator ==(Object other) =>
      other is RetouchBlemishCandidate &&
      other.index == index &&
      other.x == x &&
      other.y == y &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(index, x, y, radius);
}

/// A real candidate target and a separate numbered locator, in rendered-photo
/// coordinates. The locator does not change the candidate's repair radius.
@immutable
class RetouchBlemishMarkerGeometry {
  const RetouchBlemishMarkerGeometry({
    required this.candidate,
    required this.target,
    required this.radius,
    required this.badge,
  });
  final RetouchBlemishCandidate candidate;
  final Offset target;
  final double radius;
  final Rect badge;

  static List<RetouchBlemishMarkerGeometry> project(
    List<RetouchBlemishCandidate> candidates,
    Size renderedSize,
  ) {
    if (!renderedSize.isFinite || renderedSize.isEmpty) return const [];
    return [
      for (final candidate in candidates)
        if (candidate.isValid)
          (() {
            final target = Offset(
              candidate.x * renderedSize.width,
              candidate.y * renderedSize.height,
            );
            final radius = candidate.radius * renderedSize.shortestSide;
            final gap = math.max(20.0, radius + 16);
            final bx = renderedSize.width >= 28
                ? (target.dx + gap).clamp(14.0, renderedSize.width - 14)
                : renderedSize.width / 2;
            final by = renderedSize.height >= 28
                ? (target.dy - gap).clamp(14.0, renderedSize.height - 14)
                : renderedSize.height / 2;
            return RetouchBlemishMarkerGeometry(
              candidate: candidate,
              target: target,
              radius: radius,
              badge: Rect.fromCircle(center: Offset(bx, by), radius: 13),
            );
          })(),
    ];
  }

  /// Mirrors the painter's z order; small targets have a 44dp touch area.
  static int? hitTest({
    required List<RetouchBlemishCandidate> candidates,
    required Size renderedSize,
    required Offset normalizedPoint,
    int? focusedIndex,
  }) {
    if (!normalizedPoint.isFinite) return null;
    final point = Offset(
      normalizedPoint.dx * renderedSize.width,
      normalizedPoint.dy * renderedSize.height,
    );
    final markers = project(candidates, renderedSize);
    final ordered = [
      ...markers.where((m) => m.candidate.index != focusedIndex),
      ...markers.where((m) => m.candidate.index == focusedIndex),
    ];
    for (final marker in ordered.reversed) {
      if (marker.badge.contains(point)) return marker.candidate.index;
    }
    int? index;
    var distance = double.infinity;
    for (final marker in markers) {
      final next = (point - marker.target).distance;
      if (next <= math.max(22.0, marker.radius + 8) && next < distance) {
        distance = next;
        index = marker.candidate.index;
      }
    }
    return index;
  }
}

/// Decorative only: the photo stage owns taps and two-finger navigation.
/// Stable anchor keys also identify the actual numbered positions in tests.
class RetouchBlemishMarkers extends StatelessWidget {
  const RetouchBlemishMarkers({
    super.key,
    required this.candidates,
    required this.selected,
    this.focusedIndex,
  });
  final List<RetouchBlemishCandidate> candidates;
  final Set<int> selected;
  final int? focusedIndex;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final markers = RetouchBlemishMarkerGeometry.project(
            candidates,
            constraints.biggest,
          );
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: RetouchBlemishMarkerPainter(
                    candidates: candidates,
                    selected: selected,
                    focusedIndex: focusedIndex,
                  ),
                ),
              ),
              for (final marker in markers)
                Positioned.fromRect(
                  rect: marker.badge,
                  child: SizedBox(
                    key: ValueKey('blemish-marker-${marker.candidate.index}'),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}

class RetouchBlemishMarkerPainter extends CustomPainter {
  RetouchBlemishMarkerPainter({
    required List<RetouchBlemishCandidate> candidates,
    required Set<int> selected,
    this.focusedIndex,
  }) : candidates = List.unmodifiable(candidates),
       selected = Set.unmodifiable(selected);

  final List<RetouchBlemishCandidate> candidates;
  final Set<int> selected;
  final int? focusedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final markers = RetouchBlemishMarkerGeometry.project(candidates, size);
    for (final marker in [
      ...markers.where((m) => m.candidate.index != focusedIndex),
      ...markers.where((m) => m.candidate.index == focusedIndex),
    ]) {
      final checked = selected.contains(marker.candidate.index);
      final focused = marker.candidate.index == focusedIndex;
      final color = checked ? _accent : const Color(0xffd5dbd7);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..color = const Color(0xdd000000)
        ..strokeWidth = focused ? 5 : 4;
      canvas.drawCircle(marker.target, marker.radius, ring);
      canvas.drawCircle(
        marker.target,
        marker.radius,
        ring
          ..color = color
          ..strokeWidth = focused ? 2.5 : 1.5,
      );
      if (focused) {
        canvas.drawCircle(
          marker.target,
          marker.radius + 4,
          ring
            ..color = Colors.white
            ..strokeWidth = 1.2,
        );
      }
      final vector = marker.badge.center - marker.target;
      final distance = vector.distance;
      if (distance > marker.radius + 14) {
        final direction = vector / distance;
        canvas.drawLine(
          marker.target + direction * (marker.radius + 2),
          marker.badge.center - direction * 13,
          ring
            ..color = color
            ..strokeWidth = 1,
        );
      }
      canvas.drawCircle(
        marker.badge.center,
        13,
        Paint()..color = checked ? _accent : _background,
      );
      canvas.drawCircle(
        marker.badge.center,
        13,
        ring
          ..color = focused ? Colors.white : const Color(0xcc000000)
          ..strokeWidth = focused ? 2 : 1,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${marker.candidate.index + 1}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: checked ? _background : Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        marker.badge.center - Offset(label.width, label.height) / 2,
      );
      label.dispose();
    }
  }

  @override
  bool shouldRepaint(RetouchBlemishMarkerPainter oldDelegate) =>
      !listEquals(oldDelegate.candidates, candidates) ||
      !setEquals(oldDelegate.selected, selected) ||
      oldDelegate.focusedIndex != focusedIndex;
}

Future<List<int>?> showRetouchBlemishReview(
  BuildContext context, {
  required String imagePath,
  required int imageWidth,
  required int imageHeight,
  required List<RetouchBlemishCandidate> candidates,
  required ValueListenable<bool> isCurrent,
}) {
  if (!isCurrent.value) return Future.value(null);
  return Navigator.of(context).push<List<int>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => RetouchBlemishReview(
        imagePath: imagePath,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        candidates: candidates,
        isCurrent: isCurrent,
      ),
    ),
  );
}

/// Read-only source-space review. Only the returned indices can authorize the
/// owning workspace's existing addHeals transaction; this page never edits.
class RetouchBlemishReview extends StatefulWidget {
  const RetouchBlemishReview({
    super.key,
    this.photo,
    this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.candidates,
    required this.isCurrent,
    this.embedded = false,
    this.onFinished,
    this.onBackReady,
    this.viewportState,
    this.viewportPlane,
    this.embeddedLayoutBuilder,
    this.detailOverlay,
    this.onViewportChanged,
  }) : assert(photo != null || imagePath != null);
  final Widget? photo;
  final String? imagePath;
  final int imageWidth, imageHeight;
  final List<RetouchBlemishCandidate> candidates;
  final ValueListenable<bool> isCurrent;
  final bool embedded;
  final ValueChanged<List<int>?>? onFinished;
  final ValueChanged<VoidCallback?>? onBackReady;
  final EditingViewportState? viewportState;
  final EditingViewportPlane? viewportPlane;
  final EditingWorkspaceLayoutBuilder? embeddedLayoutBuilder;
  final Widget? detailOverlay;
  final ValueChanged<RetouchPhotoViewport>? onViewportChanged;

  @override
  State<RetouchBlemishReview> createState() => _BlemishReviewState();
}

class _BlemishReviewState extends State<RetouchBlemishReview> {
  final controller = TransformationController();
  final listController = ScrollController();
  late final List<RetouchBlemishCandidate> candidates;
  late Set<int> selected;
  int? focusedIndex;
  Size viewport = Size.zero;
  double rowExtent = 72;
  bool closing = false;
  bool photoReady = false;

  @override
  void initState() {
    super.initState();
    photoReady =
        widget.photo != null && widget.imageWidth > 0 && widget.imageHeight > 0;
    final indices = <int>{};
    candidates = [
      for (final candidate in widget.candidates)
        if (candidate.isValid && indices.add(candidate.index)) candidate,
    ];
    selected = {for (final c in candidates) c.index};
    focusedIndex = candidates.isEmpty ? null : candidates.first.index;
    widget.isCurrent.addListener(validityChanged);
    widget.onBackReady?.call(cancel);
    validityChanged();
  }

  @override
  void didUpdateWidget(RetouchBlemishReview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCurrent != widget.isCurrent) {
      oldWidget.isCurrent.removeListener(validityChanged);
      widget.isCurrent.addListener(validityChanged);
      validityChanged();
    }
  }

  @override
  void dispose() {
    widget.onBackReady?.call(null);
    widget.isCurrent.removeListener(validityChanged);
    controller.dispose();
    listController.dispose();
    super.dispose();
  }

  void validityChanged() {
    if (widget.isCurrent.value || closing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || closing || widget.isCurrent.value) return;
      closing = true;
      if (widget.embedded) {
        widget.onFinished?.call(null);
        return;
      }
      final route = ModalRoute.of(context);
      final navigator = Navigator.of(context);
      if (route != null && route.isActive && !route.isCurrent) {
        navigator.removeRoute(route);
      } else if (route?.isCurrent == true && navigator.canPop()) {
        navigator.pop();
      } else {
        setState(() {});
      }
    });
  }

  void cancel() {
    if (closing) return;
    closing = true;
    if (widget.embedded) {
      widget.onFinished?.call(null);
    } else {
      Navigator.of(context).pop();
    }
  }

  void confirm() {
    if (closing || !widget.isCurrent.value || !photoReady || selected.isEmpty) {
      return;
    }
    closing = true;
    final value = [
      for (final candidate in candidates)
        if (selected.contains(candidate.index)) candidate.index,
    ];
    if (widget.embedded) {
      widget.onFinished?.call(value);
    } else {
      Navigator.of(context).pop(value);
    }
  }

  void focus(RetouchBlemishCandidate candidate, {bool zoom = true}) {
    if (closing || !widget.isCurrent.value) return;
    setState(() => focusedIndex = candidate.index);
    if (listController.hasClients) {
      final position = candidates.indexOf(candidate) * rowExtent;
      final visible = listController.position;
      if (position < visible.pixels ||
          position + rowExtent > visible.pixels + visible.viewportDimension) {
        listController.jumpTo(
          (position - (visible.viewportDimension - rowExtent) / 2).clamp(
            visible.minScrollExtent,
            visible.maxScrollExtent,
          ),
        );
      }
    }
    if (!zoom || viewport.isEmpty) return;
    final fit = retouchOriginalPhotoFrame(
      viewport: viewport,
      imageWidth: widget.imageWidth.toDouble(),
      imageHeight: widget.imageHeight.toDouble(),
      transform: Matrix4.identity(),
    );
    final scale = math
        .max(4.0, controller.value.getMaxScaleOnAxis())
        .clamp(1.0, 8.0);
    controller.value = Matrix4.identity()
      ..scaleByDouble(scale, scale, 1, 1)
      ..setTranslationRaw(
        (.5 - candidate.x) * fit.width * scale,
        (.5 - candidate.y) * fit.height * scale,
        0,
      );
  }

  void toggle(RetouchBlemishCandidate candidate, bool checked) {
    if (closing || !widget.isCurrent.value) return;
    setState(() {
      selected = {...selected};
      if (checked) {
        selected.add(candidate.index);
      } else {
        selected.remove(candidate.index);
      }
    });
    focus(candidate);
  }

  Widget photo() => ValueListenableBuilder<bool>(
    valueListenable: widget.isCurrent,
    builder: (context, current, _) => !current
        ? const ColoredBox(color: _background)
        : LayoutBuilder(
            builder: (context, constraints) {
              viewport = constraints.biggest;
              return RetouchOriginalPhotoStage(
                imageWidth: widget.imageWidth.toDouble(),
                imageHeight: widget.imageHeight.toDouble(),
                controller: controller,
                viewportState: widget.viewportState,
                viewportPlane: widget.viewportPlane,
                viewportActive: widget.isCurrent.value && !closing,
                onViewportChanged: widget.onViewportChanged,
                editingEnabled: widget.isCurrent.value && !closing,
                editingSignal: widget.isCurrent,
                singleFingerPan: true,
                onTap: (point) {
                  final frame = retouchOriginalPhotoFrame(
                    viewport: viewport,
                    imageWidth: widget.imageWidth.toDouble(),
                    imageHeight: widget.imageHeight.toDouble(),
                    transform: controller.value,
                  );
                  final index = RetouchBlemishMarkerGeometry.hitTest(
                    candidates: candidates,
                    renderedSize: frame.size,
                    normalizedPoint: point,
                    focusedIndex: focusedIndex,
                  );
                  if (index != null) {
                    focus(
                      candidates.firstWhere((c) => c.index == index),
                      zoom: false,
                    );
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    photoImage(),
                    if (widget.detailOverlay != null) widget.detailOverlay!,
                    RetouchBlemishMarkers(
                      candidates: candidates,
                      selected: selected,
                      focusedIndex: focusedIndex,
                    ),
                  ],
                ),
              );
            },
          ),
  );

  void imageStatus(bool ready) {
    if (photoReady == ready) return;
    photoReady = ready;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !closing) setState(() {});
    });
  }

  Widget photoImage() =>
      widget.photo ??
      Image.file(
        File(widget.imagePath!),
        fit: BoxFit.fill,
        semanticLabel: '塑形前的候选定位照片',
        frameBuilder: (_, child, frame, synchronouslyLoaded) {
          if (frame != null || synchronouslyLoaded) imageStatus(true);
          return child;
        },
        errorBuilder: (_, _, _) {
          imageStatus(false);
          return const Center(child: Text('无法载入定位照片，请取消后重新分析。'));
        },
      );

  Widget choices() {
    rowExtent = math.max(72, MediaQuery.textScalerOf(context).scale(44) + 24);
    return ListView.builder(
      key: const ValueKey('blemish-list'),
      controller: listController,
      itemExtent: rowExtent,
      itemCount: candidates.length,
      itemBuilder: (context, index) {
        final candidate = candidates[index],
            checked = selected.contains(candidate.index);
        final focused = candidate.index == focusedIndex;
        return ListTile(
          key: ValueKey('blemish-row-${candidate.index}'),
          tileColor: focused ? _accent.withValues(alpha: .1) : null,
          textColor: Colors.white,
          selected: focused,
          selectedColor: Colors.white,
          onTap: () => focus(candidate),
          leading: Checkbox(
            key: ValueKey('blemish-checkbox-${candidate.index}'),
            value: checked,
            activeColor: _accent,
            checkColor: _background,
            side: const BorderSide(color: Color(0xffc8cdca)),
            semanticLabel: '修复第 ${candidate.index + 1} 处',
            onChanged: (value) => toggle(candidate, value == true),
          ),
          title: Text(
            '第 ${candidate.index + 1} 处',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${(candidate.x * 100).round()}%, ${(candidate.y * 100).round()}%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xffc8cdca)),
          ),
          trailing: IconButton(
            key: ValueKey('blemish-locate-${candidate.index}'),
            tooltip: '定位第 ${candidate.index + 1} 处',
            onPressed: () => focus(candidate),
            icon: Icon(
              Icons.my_location,
              color: focused ? _accent : Colors.white,
            ),
          ),
        );
      },
    );
  }

  bool get canConfirm =>
      selected.isNotEmpty && photoReady && widget.isCurrent.value && !closing;

  Widget compactPanel() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          '已选 ${selected.length} / ${candidates.length} 处',
          maxLines: 1,
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TextButton(
            key: const ValueKey('blemish-select-all'),
            onPressed: () {
              if (widget.isCurrent.value && !closing) {
                setState(
                  () => selected = {for (final c in candidates) c.index},
                );
              }
            },
            child: const Text('全选'),
          ),
          TextButton(
            key: const ValueKey('blemish-select-none'),
            onPressed: () {
              if (widget.isCurrent.value && !closing) {
                setState(() => selected = {});
              }
            },
            child: const Text('全不选'),
          ),
          IconButton(
            key: const ValueKey('blemish-fit'),
            tooltip: '查看全部候选',
            onPressed: () => controller.value = Matrix4.identity(),
            icon: const Icon(Icons.fit_screen),
          ),
        ],
      ),
      Expanded(child: choices()),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            TextButton(
              key: const ValueKey('blemish-cancel'),
              onPressed: cancel,
              child: const Text('取消'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const ValueKey('blemish-confirm'),
                onPressed: canConfirm ? confirm : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: _background,
                  minimumSize: const Size(0, 48),
                ),
                child: const Text('修复所选'),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget embeddedBody(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final photograph = photo();
      final panel = Column(
        children: [
          SizedBox(
            height: 48,
            child: Row(
              children: [
                IconButton(
                  key: const ValueKey('blemish-close'),
                  tooltip: '取消候选修复',
                  onPressed: cancel,
                  icon: const Icon(Icons.arrow_back),
                ),
                const Expanded(
                  child: Text(
                    '修复疑似小瑕疵',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '塑形前定位 · 点编号查看位置，勾选后修复',
              style: TextStyle(fontSize: 12),
            ),
          ),
          Expanded(child: compactPanel()),
        ],
      );
      final builder = widget.embeddedLayoutBuilder;
      if (builder != null) return builder(context, photograph, panel);
      return Column(
        children: [
          Expanded(child: photograph),
          SizedBox(height: math.min(320, bounds.maxHeight * .5), child: panel),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: _accent,
        surface: _background,
      ),
    ),
    child: widget.embedded
        ? embeddedBody(context)
        : PopScope<List<int>>(
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) closing = true;
            },
            child: Scaffold(
              backgroundColor: _background,
              appBar: AppBar(
                backgroundColor: _background,
                foregroundColor: Colors.white,
                leading: IconButton(
                  key: const ValueKey('blemish-close'),
                  tooltip: '取消候选修复',
                  onPressed: cancel,
                  icon: const Icon(Icons.close),
                ),
                title: const Text(
                  '修复疑似小瑕疵',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              body: SafeArea(
                top: false,
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      constraints.maxWidth > constraints.maxHeight &&
                          constraints.maxHeight < 450
                      ? Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Text(
                                      '塑形前定位 · 点编号查看位置，勾选后修复',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  Expanded(child: photo()),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: math.min(
                                360,
                                math.max(220, constraints.maxWidth * .45),
                              ),
                              child: compactPanel(),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                              child: Text(
                                '塑形前定位 · 点编号查看位置，勾选后修复',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(child: photo()),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '已选 ${selected.length} / ${candidates.length} 处',
                                    ),
                                  ),
                                  TextButton(
                                    key: const ValueKey('blemish-select-all'),
                                    onPressed: () {
                                      if (widget.isCurrent.value && !closing) {
                                        setState(
                                          () => selected = {
                                            for (final c in candidates) c.index,
                                          },
                                        );
                                      }
                                    },
                                    child: const Text('全选'),
                                  ),
                                  TextButton(
                                    key: const ValueKey('blemish-select-none'),
                                    onPressed: () {
                                      if (widget.isCurrent.value && !closing) {
                                        setState(() => selected = {});
                                      }
                                    },
                                    child: const Text('全不选'),
                                  ),
                                  IconButton(
                                    key: const ValueKey('blemish-fit'),
                                    tooltip: '查看全部候选',
                                    onPressed: () =>
                                        controller.value = Matrix4.identity(),
                                    icon: const Icon(Icons.fit_screen),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: math.min(
                                196,
                                math.max(72, constraints.maxHeight * .26),
                              ),
                              child: choices(),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      key: const ValueKey('blemish-cancel'),
                                      onPressed: cancel,
                                      child: const Text('取消'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton(
                                      key: const ValueKey('blemish-confirm'),
                                      onPressed:
                                          selected.isEmpty ||
                                              !photoReady ||
                                              !widget.isCurrent.value ||
                                              closing
                                          ? null
                                          : confirm,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _accent,
                                        foregroundColor: _background,
                                        minimumSize: const Size(0, 48),
                                      ),
                                      child: const Text('修复所选'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
  );
}
