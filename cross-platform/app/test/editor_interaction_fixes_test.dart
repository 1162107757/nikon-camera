import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/split_compare.dart';

import 'editor_color_workspace_test.dart' as editor;
import 'editor_realtime_preview_test.dart' show RealtimeCore;

// Native views resized to logical test sizes retain their platform touch slop.
// Use a continuous multi-event gesture, as a finger would, rather than jumping
// across the threshold only on the final event.
Future<void> dragCompare(WidgetTester tester, double distance) async {
  final grip = find.byKey(const ValueKey('compare-divider'));
  final gesture = await tester.startGesture(tester.getCenter(grip));
  for (var i = 0; i < 12; i++) {
    await gesture.moveBy(Offset(distance / 12, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets(
    'Palette comparison toggles on tap without collapsing or saving',
    (tester) async {
      final fixture = await editor.open(tester);
      tester.view.systemGestureInsets = const FakeViewPadding(
        left: 24,
        right: 24,
      );
      addTearDown(tester.view.resetSystemGestureInsets);
      await editor.tool(tester, '调色盘');
      fixture.core.requests.clear();
      final button = find.byKey(const Key('editor-compare-toggle'));
      expect(button.hitTestable(), findsOneWidget);
      await tester.tap(button);
      await editor.frames(tester);
      var compare = tester.widget<SplitCompare>(find.byType(SplitCompare));
      expect(compare.enabled, isTrue);
      expect(compare.original, isNotNull);
      expect(find.byKey(const Key('palette-expanded-panel')), findsOneWidget);
      expect(find.byKey(const Key('palette-tools-toolbar')), findsNothing);
      expect(
        fixture.core.requests.where(
          (r) => r.operation == 'draft.save' || r.operation == 'media.preview',
        ),
        isEmpty,
      );
      expect(fixture.core.reviews, isNotEmpty);
      final photo = find.byType(SplitCompare);
      await dragCompare(tester, -1000);
      expect((tester.state(photo) as dynamic).divider, 0.0);
      await editor.frames(tester);
      expect((tester.state(photo) as dynamic).divider, 0.0);
      await dragCompare(tester, 180);
      await editor.frames(tester);
      expect((tester.state(photo) as dynamic).divider, greaterThan(0.0));
      await tester.tap(button);
      await editor.frames(tester);
      compare = tester.widget<SplitCompare>(find.byType(SplitCompare));
      expect(compare.enabled, isFalse);
      expect(find.byKey(const Key('palette-expanded-panel')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await editor.close(tester, fixture.state);
    },
  );

  testWidgets(
    'Adjustment strip retains its scrolled position after embedded tools',
    (tester) async {
      final fixture = await editor.open(tester);
      final strip = find.byKey(const PageStorageKey('editor-adjustment-tools'));
      for (final name in ['曲线', 'HSL', '调色盘', '去灰']) {
        await tester.ensureVisible(find.text(name));
        await editor.frames(tester, count: 2);
        final before = tester
            .widget<SingleChildScrollView>(strip)
            .controller!
            .offset;
        expect(before, greaterThan(50));
        await editor.tool(tester, name);
        await tester.tap(find.widgetWithText(TextButton, '取消'));
        await editor.frames(tester, count: 12);
        expect(strip, findsOneWidget);
        final after = tester
            .widget<SingleChildScrollView>(strip)
            .controller!
            .offset;
        expect(after, closeTo(before, 1), reason: name);
        expect(find.text(name).hitTestable(), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await editor.close(tester, fixture.state);
    },
  );

  for (final width in [320.0, 812.0]) {
    testWidgets(
      'Compare grip remains recoverable at both endpoints with back insets at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final core = RealtimeCore();
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 480),
                systemGestureInsets: const EdgeInsets.symmetric(horizontal: 24),
              ),
              child: SplitCompare(
                effect: core.source.path,
                original: core.source.path,
                enabled: true,
              ),
            ),
          ),
        );
        await editor.frames(tester);
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        final matrix = Matrix4.identity()..scaleByDouble(2, 2, 1, 1);
        viewer.transformationController!.value = matrix;
        final grip = find.byKey(const ValueKey('compare-divider'));
        for (final direction in [-1.0, 1.0]) {
          await tester.drag(grip, Offset(direction * width * 2, 0));
          await tester.pump();
          final rect = tester.getRect(grip);
          expect(rect.left, greaterThanOrEqualTo(36));
          expect(rect.right, lessThanOrEqualTo(width - 36));
          expect(rect.width, 48);
          expect(grip.hitTestable(), findsOneWidget);
          final endpoint = tester
              .getTopLeft(find.byKey(const ValueKey('compare-line')))
              .dx;
          expect(endpoint, closeTo(direction < 0 ? 0 : width, 1));
          await tester.drag(grip, Offset(-direction * 70, 0));
          await tester.pump();
          final recovered = tester
              .getTopLeft(find.byKey(const ValueKey('compare-line')))
              .dx;
          expect(recovered, greaterThan(0));
          expect(recovered, lessThan(width));
          expect(viewer.transformationController!.value, matrix);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await editor.frames(tester);
      },
    );
  }
}
