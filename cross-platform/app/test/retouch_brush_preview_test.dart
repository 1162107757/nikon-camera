import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/retouch_brush_preview.dart';
import 'package:huevia/retouch_original_controls.dart';

RetouchBrushPreviewPainter guide(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<RetouchBrushPreviewPainter>()
    .single;

Widget host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 300, height: 300, child: child)),
  ),
);

void main() {
  test('radius follows the image short edge, not the square viewport', () {
    final frame = retouchOriginalPhotoFrame(
      viewport: const Size(300, 300),
      imageWidth: 1000,
      imageHeight: 500,
      transform: Matrix4.identity(),
    );
    final result = RetouchBrushPreviewGeometry.resolve(
      photoFrame: frame,
      viewport: const Rect.fromLTWH(0, 0, 300, 300),
      radius: .1,
    )!;
    expect(frame, const Rect.fromLTWH(0, 75, 300, 150));
    expect(result.center, const Offset(150, 150));
    expect(result.normalizedCenter, const Offset(.5, .5));
    expect(result.radius, 15);
    expect(result.clip, frame);
  });

  test('no recent point uses the center of the visible photo intersection', () {
    final result = RetouchBrushPreviewGeometry.resolve(
      photoFrame: const Rect.fromLTWH(-200, -100, 600, 400),
      viewport: const Rect.fromLTWH(0, 0, 300, 250),
      radius: .05,
    )!;
    expect(result.center, const Offset(150, 125));
    expect(result.normalizedCenter.dx, closeTo(350 / 600, .000001));
    expect(result.normalizedCenter.dy, closeTo(225 / 400, .000001));
    expect(result.radius, 20);
  });

  test(
    'a recent image point stays anchored when panning moves it offscreen',
    () {
      final result = RetouchBrushPreviewGeometry.resolve(
        photoFrame: const Rect.fromLTWH(-250, 0, 600, 300),
        viewport: const Rect.fromLTWH(0, 0, 300, 300),
        radius: .1,
        center: const Offset(.25, .5),
      )!;
      expect(result.center, const Offset(-100, 150));
      expect(result.normalizedCenter, const Offset(.25, .5));
      expect(result.radius, 30);
      expect(result.clip, const Rect.fromLTWH(0, 0, 300, 300));
    },
  );

  test('sizing an offscreen brush keeps the requested image point', () {
    final result = RetouchBrushPreviewGeometry.resolve(
      photoFrame: const Rect.fromLTWH(-250, 0, 600, 300),
      viewport: const Rect.fromLTWH(0, 0, 300, 300),
      radius: .1,
      center: const Offset(.25, .5),
      keepVisible: true,
    )!;
    expect(result.center, const Offset(150, 150));
    expect(result.normalizedCenter, const Offset(.25, .5));
    expect(result.radius, 30);
  });

  test(
    'sizing near an edge shows the whole ring when the true radius fits',
    () {
      final result = RetouchBrushPreviewGeometry.resolve(
        photoFrame: const Rect.fromLTWH(0, 0, 300, 300),
        viewport: const Rect.fromLTWH(0, 0, 300, 300),
        radius: .1,
        center: const Offset(.01, .99),
        keepVisible: true,
      )!;
      expect(result.center, const Offset(32, 268));
      expect(result.normalizedCenter, const Offset(.01, .99));
      expect(result.radius, 30);
      expect(
        result.clip.contains(result.center - const Offset(31.75, 31.75)),
        isTrue,
      );
      expect(
        result.clip.contains(result.center + const Offset(31.75, 31.75)),
        isTrue,
      );
    },
  );

  test('an oversized sizing guide retains its radius and shows a real arc', () {
    final result = RetouchBrushPreviewGeometry.resolve(
      photoFrame: const Rect.fromLTWH(-160, -160, 400, 400),
      viewport: const Rect.fromLTWH(0, 0, 80, 80),
      radius: .3,
      center: const Offset(.5, .5),
      keepVisible: true,
    )!;
    expect(result.radius, 120);
    expect(result.normalizedCenter, const Offset(.5, .5));
    expect(result.center, const Offset(-42, 40));
    expect(result.center.dx + result.radius, 78);
  });

  test(
    'invalid points use the visible center and invalid geometry is hidden',
    () {
      for (final point in [
        const Offset(-.1, .5),
        const Offset(.5, 1.1),
        const Offset(double.nan, .5),
      ]) {
        expect(
          RetouchBrushPreviewGeometry.resolve(
            photoFrame: const Rect.fromLTWH(0, 50, 200, 100),
            viewport: const Rect.fromLTWH(0, 0, 200, 200),
            radius: .1,
            center: point,
          )!.center,
          const Offset(100, 100),
        );
      }
      for (final radius in [0.0, -.1, double.infinity, double.nan]) {
        expect(
          RetouchBrushPreviewGeometry.resolve(
            photoFrame: const Rect.fromLTWH(0, 0, 200, 100),
            viewport: const Rect.fromLTWH(0, 0, 200, 200),
            radius: radius,
          ),
          isNull,
        );
      }
      expect(
        RetouchBrushPreviewGeometry.resolve(
          photoFrame: const Rect.fromLTWH(400, 0, 200, 100),
          viewport: const Rect.fromLTWH(0, 0, 200, 200),
          radius: .1,
        ),
        isNull,
      );
    },
  );

  testWidgets('controlled size changes repaint every intermediate radius', (
    tester,
  ) async {
    final controller = TransformationController();
    final radius = ValueNotifier(.01);
    addTearDown(controller.dispose);
    addTearDown(radius.dispose);
    await tester.pumpWidget(
      host(
        ValueListenableBuilder<double>(
          valueListenable: radius,
          builder: (context, value, _) => RetouchBrushPreview(
            imageWidth: 1000,
            imageHeight: 500,
            controller: controller,
            radius: value,
          ),
        ),
      ),
    );
    expect(guide(tester).geometry!.radius, 1.5);
    for (final value in [.025, .08, .04]) {
      final previous = guide(tester);
      radius.value = value;
      await tester.pump();
      expect(guide(tester).geometry!.radius, closeTo(value * 150, .000001));
      expect(guide(tester).shouldRepaint(previous), isTrue);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('controller pan and zoom reproject the same normalized point', (
    tester,
  ) async {
    final controller = TransformationController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        RetouchBrushPreview(
          imageWidth: 1000,
          imageHeight: 500,
          controller: controller,
          radius: .1,
          center: const Offset(.75, .4),
        ),
      ),
    );
    expect(guide(tester).geometry!.center, const Offset(225, 135));
    expect(guide(tester).geometry!.radius, 15);
    controller.value = Matrix4.identity()
      ..scaleByDouble(2, 2, 1, 1)
      ..setTranslationRaw(-100, 0, 0);
    await tester.pump();
    expect(guide(tester).geometry!.center, const Offset(200, 120));
    expect(guide(tester).geometry!.normalizedCenter, const Offset(.75, .4));
    expect(guide(tester).geometry!.radius, 30);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('body preview respects the real reserved photo viewport', (
    tester,
  ) async {
    final controller = TransformationController(
      Matrix4.identity()..scaleByDouble(2, 2, 1, 1),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        RetouchBrushPreview(
          imageWidth: 800,
          imageHeight: 1200,
          controller: controller,
          radius: .1,
          reserveBars: true,
        ),
      ),
    );
    final geometry = guide(tester).geometry!;
    expect(geometry.center, const Offset(150, 150));
    expect(geometry.clip.top, 48);
    expect(geometry.clip.bottom, 252);
    expect(geometry.radius, closeTo(.1 * (204 / 1200 * 800 * 2), .000001));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'paint clips to photo and viewport and leaves the center unfilled',
    (tester) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = RetouchBrushPreviewPainter(
        geometry: RetouchBrushPreviewGeometry.resolve(
          photoFrame: const Rect.fromLTWH(-20, 20, 100, 100),
          viewport: const Rect.fromLTWH(0, 0, 80, 80),
          radius: .3,
          center: const Offset(.2, .2),
        ),
      );
      painter.paint(canvas, const Size(80, 80));
      final picture = recorder.endRecording();
      final rgba = await tester.runAsync(() async {
        final image = await picture.toImage(80, 80);
        try {
          return (await image.toByteData())!;
        } finally {
          image.dispose();
        }
      });
      try {
        expect(rgba, isNotNull);
        int alpha(int x, int y) => rgba!.getUint8((y * 80 + x) * 4 + 3);
        expect(alpha(30, 40), greaterThan(0), reason: 'Actual radius is 30dp');
        expect(
          alpha(10, 40),
          0,
          reason: 'The guide cannot look like a filled edit',
        );
        var escaped = 0;
        for (var y = 0; y < 20; y++) {
          for (var x = 0; x < 80; x++) {
            if (alpha(x, y) != 0) escaped++;
          }
        }
        expect(escaped, 0, reason: 'The ring cannot paint over letterboxing');
      } finally {
        picture.dispose();
      }
    },
  );

  testWidgets('the guide passes canvas pointers and slider drags through', (
    tester,
  ) async {
    final controller = TransformationController();
    addTearDown(controller.dispose);
    var pointerDowns = 0, sliderStarts = 0, sliderEnds = 0;
    var value = .2;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => pointerDowns++,
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Slider(
                  value: value,
                  onChangeStart: (_) => sliderStarts++,
                  onChanged: (next) => setState(() => value = next),
                  onChangeEnd: (_) => sliderEnds++,
                ),
              ),
              Positioned.fill(
                child: RetouchBrushPreview(
                  imageWidth: 300,
                  imageHeight: 300,
                  controller: controller,
                  radius: value / 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byType(RetouchBrushPreview));
    final first = await tester.startGesture(origin + const Offset(70, 80));
    final second = await tester.startGesture(
      origin + const Offset(140, 80),
      pointer: 2,
    );
    await first.moveBy(const Offset(-10, 0));
    await second.moveBy(const Offset(10, 0));
    await first.up();
    await second.up();
    expect(pointerDowns, 2);
    final slider = tester.getRect(find.byType(Slider));
    await tester.dragFrom(
      Offset(slider.left + 60, slider.center.dy),
      const Offset(150, 0),
    );
    await tester.pumpAndSettle();
    expect(sliderStarts, 1);
    expect(sliderEnds, 1);
    expect(value, greaterThan(.6));
    expect(guide(tester).geometry!.radius, closeTo(value * 30, .000001));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden preview has no painting or animation lifecycle', (
    tester,
  ) async {
    final controller = TransformationController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      host(
        RetouchBrushPreview(
          imageWidth: 1000,
          imageHeight: 500,
          controller: controller,
          radius: .1,
          visible: false,
        ),
      ),
    );
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where((widget) => widget.painter is RetouchBrushPreviewPainter),
      isEmpty,
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an oversized radius still paints a visible true circle arc', (
    tester,
  ) async {
    final recorder = ui.PictureRecorder();
    RetouchBrushPreviewPainter(
      geometry: RetouchBrushPreviewGeometry.resolve(
        photoFrame: const Rect.fromLTWH(-160, -160, 400, 400),
        viewport: const Rect.fromLTWH(0, 0, 80, 80),
        radius: .3,
        center: const Offset(.5, .5),
        keepVisible: true,
      ),
    ).paint(Canvas(recorder), const Size(80, 80));
    final picture = recorder.endRecording();
    final rgba = await tester.runAsync(() async {
      final image = await picture.toImage(80, 80);
      try {
        return (await image.toByteData())!;
      } finally {
        image.dispose();
      }
    });
    try {
      expect(rgba, isNotNull);
      var visibleRows = 0;
      for (var y = 0; y < 80; y++) {
        var painted = false;
        for (var x = 0; x < 80; x++) {
          if (rgba!.getUint8((y * 80 + x) * 4 + 3) > 0) painted = true;
        }
        if (painted) visibleRows++;
      }
      expect(visibleRows, greaterThan(70));
      expect(rgba!.getUint8((40 * 80 + 77) * 4 + 3), greaterThan(0));
    } finally {
      picture.dispose();
    }
  });

  testWidgets('radius drag shows a panned-away brush and hides it on release', (
    tester,
  ) async {
    final controller = TransformationController(
      Matrix4.identity()
        ..scaleByDouble(2, 2, 1, 1)
        ..setTranslationRaw(-100, 0, 0),
    );
    addTearDown(controller.dispose);
    var sizing = false, radius = .05;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.black)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Slider(
                  value: radius,
                  min: .01,
                  max: .2,
                  onChangeStart: (_) => setState(() => sizing = true),
                  onChanged: (value) => setState(() => radius = value),
                  onChangeEnd: (_) => setState(() => sizing = false),
                ),
              ),
              Positioned.fill(
                child: RetouchBrushPreview(
                  imageWidth: 1000,
                  imageHeight: 500,
                  controller: controller,
                  center: const Offset(.05, .5),
                  radius: radius,
                  visible: sizing,
                  keepVisible: sizing,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final slider = tester.getRect(find.byType(Slider));
    final drag = await tester.startGesture(
      Offset(slider.left + 70, slider.center.dy),
    );
    await drag.moveBy(const Offset(30, 0));
    await tester.pump();
    expect(sizing, isTrue);
    expect(guide(tester).geometry!.center, const Offset(150, 150));
    expect(guide(tester).geometry!.normalizedCenter, const Offset(.05, .5));
    expect(guide(tester).geometry!.radius, closeTo(radius * 300, .000001));
    final previous = guide(tester).geometry!.radius;
    await drag.moveBy(const Offset(80, 0));
    await tester.pump();
    expect(guide(tester).geometry!.radius, greaterThan(previous));
    expect(guide(tester).geometry!.center, const Offset(150, 150));
    await drag.up();
    await tester.pumpAndSettle();
    expect(sizing, isFalse);
    expect(
      tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where((widget) => widget.painter is RetouchBrushPreviewPainter),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
