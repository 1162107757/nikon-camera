import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/editing_viewport.dart';
import 'package:huevia/retouch_brush_preview.dart';
import 'package:huevia/retouch_original_controls.dart';

final _pixels = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAYAAABr5z2BAAAAF0lEQVR4nGOQWBD1nxLMMGrAqAHDwwAAqUGM0LHkvF4AAAAASUVORK5CYII=',
);

Matrix4 _pose() =>
    Matrix4.diagonal3Values(1.5, 1.5, 1)..setTranslationRaw(-60, 40.5, 0);

void _rectClose(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 1e-7));
  expect(actual.top, closeTo(expected.top, 1e-7));
  expect(actual.right, closeTo(expected.right, 1e-7));
  expect(actual.bottom, closeTo(expected.bottom, 1e-7));
}

void main() {
  test('Standalone photo bounds remain the default while shared layout can retain an off-center source anchor', () {
    const viewport = Size(400, 480);
    final bounded = retouchOriginalPhotoFrame(
      viewport: viewport,
      imageWidth: 16,
      imageHeight: 12,
      transform: _pose(),
    );
    final shared = retouchOriginalPhotoFrame(
      viewport: viewport,
      imageWidth: 16,
      imageHeight: 12,
      transform: _pose(),
      clampToBounds: false,
    );
    _rectClose(bounded, const Rect.fromLTRB(-160, 15, 440, 465));
    _rectClose(shared, const Rect.fromLTRB(-160, 55.5, 440, 505.5));
    expect(
      (viewport.height / 2 - shared.top) / shared.height,
      closeTo(.41, 1e-8),
    );
    final invalidPan = Matrix4.diagonal3Values(64, 64, 1)
      ..setTranslationRaw(double.infinity, double.nan, 0);
    final finite = retouchOriginalPhotoFrame(
      viewport: viewport,
      imageWidth: 16,
      imageHeight: 12,
      transform: invalidPan,
      clampToBounds: false,
    );
    expect(finite.isFinite, true);
    expect(finite.width, 400 * 32);
  });

  test('Shared ROI and brush project the same unclamped rectangular photo without loosening ROI bounds', () {
    final view = retouchOriginalPhotoViewport(
      viewport: const Size(400, 480),
      imageWidth: 16,
      imageHeight: 12,
      transform: _pose(),
      clampToBounds: false,
    );
    _rectClose(view.imageFrame, const Rect.fromLTRB(-160, 55.5, 440, 505.5));
    _rectClose(
      view.visibleRegion,
      const Rect.fromLTRB(4 / 15, 0, 14 / 15, 283 / 300),
    );
    final guide = RetouchBrushPreviewGeometry.resolve(
      photoFrame: view.imageFrame,
      viewport: view.clip,
      center: const Offset(.6, .41),
      radius: .04,
    )!;
    expect(guide.center.dx, closeTo(200, 1e-8));
    expect(guide.center.dy, closeTo(240, 1e-8));
    expect(guide.radius, closeTo(18, 1e-8));
    expect(guide.normalizedCenter, const Offset(.6, .41));
    expect(view.visibleRegion.left, greaterThanOrEqualTo(0));
    expect(view.visibleRegion.bottom, lessThanOrEqualTo(1));
  });

  testWidgets(
    'A low-zoom rectangular photograph keeps actual paint, ROI and brush aligned as a shared panel grows and shrinks',
    (tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final shared = EditingViewportState();
      final scene = TransformationController(
        Matrix4.diagonal3Values(1.5, 1.5, 1)..setTranslationRaw(-160, -39.5, 0),
      );
      shared.capture(
        scene,
        viewport: const Size(400, 320),
        imageRect: const Rect.fromLTWH(0, 10, 400, 300),
      );
      scene.dispose();
      final local = TransformationController();
      final reports = <RetouchPhotoViewport>[];
      var height = 320.0;
      late StateSetter resize;
      const planeKey = ValueKey('actual-rectangular-photo');
      const viewportKey = ValueKey('shared-stage-bounds');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) {
                resize = update;
                return Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    key: viewportKey,
                    width: 400,
                    height: height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RetouchOriginalPhotoStage(
                          imageWidth: 16,
                          imageHeight: 12,
                          controller: local,
                          viewportState: shared,
                          singleFingerPan: true,
                          onViewportChanged: reports.add,
                          child: Image.memory(
                            _pixels,
                            key: planeKey,
                            fit: BoxFit.fill,
                          ),
                        ),
                        Positioned.fill(
                          child: RetouchBrushPreview(
                            imageWidth: 16,
                            imageHeight: 12,
                            controller: local,
                            radius: .04,
                            center: const Offset(.6, .41),
                            clampToBounds: false,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      final timer = Stopwatch()..start();
      bool decoded() => find
          .descendant(of: find.byKey(planeKey), matching: find.byType(RawImage))
          .evaluate()
          .any((element) => (element.widget as RawImage).image != null);
      while (!decoded() && timer.elapsed < const Duration(seconds: 5)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 12)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        decoded(),
        true,
        reason:
            'The genuine 16x12 photo must decode before geometry is assessed.',
      );

      for (final nextHeight in [320.0, 480.0, 240.0]) {
        resize(() => height = nextHeight);
        await tester.pump();
        await tester.pump();
        final bounds = tester.getRect(find.byKey(viewportKey));
        final actual = tester.getRect(find.byKey(planeKey));
        expect(actual.width, closeTo(600, 1e-7));
        expect(actual.height, closeTo(450, 1e-7));
        expect(
          actual.left + .6 * actual.width,
          closeTo(bounds.center.dx, 1e-7),
        );
        expect(
          actual.top + .41 * actual.height,
          // Panel changes keep the inspected pixel at its original screen
          // position instead of recentering it in each new viewport height.
          closeTo(bounds.top + 160, 1e-7),
        );
        expect(shared.focus.dx, closeTo(.6, 1e-8));
        expect(shared.focus.dy, closeTo(.41, 1e-8));
        final report = reports.last;
        _rectClose(report.imageFrame, actual.shift(-bounds.topLeft));
        final visible = actual.intersect(bounds);
        _rectClose(
          report.visibleRegion,
          Rect.fromLTRB(
            (visible.left - actual.left) / actual.width,
            (visible.top - actual.top) / actual.height,
            (visible.right - actual.left) / actual.width,
            (visible.bottom - actual.top) / actual.height,
          ),
        );
        final paint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byType(RetouchBrushPreview),
            matching: find.byType(CustomPaint),
          ),
        );
        final guide = (paint.painter! as RetouchBrushPreviewPainter).geometry!;
        expect(guide.center.dx + bounds.left, closeTo(bounds.center.dx, 1e-7));
        expect(guide.center.dy + bounds.top, closeTo(bounds.top + 160, 1e-7));
        expect(guide.radius, closeTo(18, 1e-7));
      }

      // This is a real user drag: retaining a source anchor during layout must
      // not remove the existing gesture boundary in publish().
      await tester.drag(
        find.byType(RetouchOriginalPhotoStage),
        const Offset(900, 900),
      );
      await tester.pump();
      expect(local.value.storage[12], closeTo(100, 1e-7));
      expect(local.value.storage[13], closeTo(105, 1e-7));
      final bounded = retouchOriginalPhotoFrame(
        viewport: const Size(400, 240),
        imageWidth: 16,
        imageHeight: 12,
        transform: local.value,
      );
      final bounds = tester.getRect(find.byKey(viewportKey));
      _rectClose(
        tester.getRect(find.byKey(planeKey)),
        bounded.shift(bounds.topLeft),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      local.dispose();
    },
  );
}
