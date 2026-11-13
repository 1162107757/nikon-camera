import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/retouch_blemish_review.dart';
import 'package:huevia/retouch_original_controls.dart';

const entries = [
  RetouchBlemishCandidate(index: 0, x: .2, y: .3, radius: .01),
  RetouchBlemishCandidate(index: 1, x: .7, y: .6, radius: .02),
];

RetouchBlemishMarkerPainter markers(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((widget) => widget.painter)
    .whereType<RetouchBlemishMarkerPainter>()
    .single;

Future<({Future<List<int>?> result, NavigatorState navigator})> open(
  WidgetTester tester,
  ValueNotifier<bool> current, {
  List<RetouchBlemishCandidate> candidates = entries,
  bool missingFile = false,
  double textScale = 1,
}) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const Scaffold(body: Text('root')),
    ),
  );
  navigator.currentState!.push(
    MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('parent remains')),
    ),
  );
  await tester.pumpAndSettle();
  final result = navigator.currentState!.push<List<int>>(
    MaterialPageRoute(
      builder: (_) => RetouchBlemishReview(
        photo: missingFile ? null : const ColoredBox(color: Color(0xff957a65)),
        imagePath: missingFile ? 'nonexistent-blemish-review.png' : null,
        imageWidth: 1000,
        imageHeight: 500,
        candidates: candidates,
        isCurrent: current,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (result: result, navigator: navigator.currentState!);
}

void main() {
  test('targets use true normalized positions and image-short-edge radii', () {
    final result = RetouchBlemishMarkerGeometry.project(
      entries,
      const Size(400, 200),
    );
    expect(result[0].target, const Offset(80, 60));
    expect(result[0].radius, 2);
    expect(result[1].target, const Offset(280, 120));
    expect(result[1].radius, 4);
    expect(result[0].badge.contains(result[0].target), isFalse);
    final zoomed = RetouchBlemishMarkerGeometry.project(
      entries,
      const Size(800, 400),
    );
    expect(zoomed[0].target, result[0].target * 2);
    expect(zoomed[0].radius, result[0].radius * 2);
  });

  test(
    'badge hits and small-target touch areas return authoritative indices',
    () {
      final projected = RetouchBlemishMarkerGeometry.project(
        entries,
        const Size(400, 200),
      );
      final badge = projected[1].badge.center;
      expect(
        RetouchBlemishMarkerGeometry.hitTest(
          candidates: entries,
          renderedSize: const Size(400, 200),
          normalizedPoint: Offset(badge.dx / 400, badge.dy / 200),
        ),
        1,
      );
      expect(
        RetouchBlemishMarkerGeometry.hitTest(
          candidates: entries,
          renderedSize: const Size(400, 200),
          normalizedPoint: const Offset(.2 - .04, .3),
        ),
        0,
      );
      expect(
        RetouchBlemishMarkerGeometry.hitTest(
          candidates: entries,
          renderedSize: const Size(400, 200),
          normalizedPoint: const Offset(.95, .05),
        ),
        isNull,
      );
    },
  );

  test('painter snapshots selection and repaints a changed checkbox state', () {
    final selected = {0, 1};
    final before = RetouchBlemishMarkerPainter(
      candidates: entries,
      selected: selected,
    );
    selected.remove(0);
    final after = RetouchBlemishMarkerPainter(
      candidates: entries,
      selected: selected,
      focusedIndex: 1,
    );
    expect(before.selected, {0, 1});
    expect(after.selected, {1});
    expect(after.shouldRepaint(before), isTrue);
  });

  testWidgets(
    'actual marker pixels show selection without filling the blemish',
    (tester) async {
      const candidate = RetouchBlemishCandidate(
        index: 0,
        x: .5,
        y: .5,
        radius: .04,
      );
      Future<List<int>> sample(Set<int> selected) async {
        final recorder = ui.PictureRecorder();
        RetouchBlemishMarkerPainter(
          candidates: const [candidate],
          selected: selected,
        ).paint(Canvas(recorder), const Size(200, 100));
        final picture = recorder.endRecording();
        try {
          return (await tester.runAsync(() async {
            final image = await picture.toImage(200, 100);
            try {
              final bytes = (await image.toByteData())!;
              return [
                bytes.getUint8((50 * 200 + 100) * 4 + 3),
                bytes.getUint8((50 * 200 + 104) * 4 + 3),
                for (var channel = 0; channel < 4; channel++)
                  bytes.getUint8((30 * 200 + 128) * 4 + channel),
              ];
            } finally {
              image.dispose();
            }
          }))!;
        } finally {
          picture.dispose();
        }
      }

      final checked = await sample({0}), unchecked = await sample({});
      expect(
        checked[0],
        0,
        reason: 'Location markers never fill or repair photo pixels',
      );
      expect(
        checked[1],
        greaterThan(0),
        reason: 'The true 4dp target radius is visible',
      );
      expect(checked.sublist(2), [255, 227, 53, 255]);
      expect(unchecked.sublist(2), [23, 34, 30, 255]);
    },
  );

  testWidgets(
    'photo markers and checkboxes agree and confirm only checked indices',
    (tester) async {
      final current = ValueNotifier(true);
      final page = await open(tester, current);
      expect(find.text('塑形前定位 · 点编号查看位置，勾选后修复'), findsOneWidget);
      expect(find.text('已选 2 / 2 处'), findsOneWidget);
      expect(markers(tester).selected, {0, 1});
      await tester.tap(find.byKey(const ValueKey('blemish-checkbox-0')));
      await tester.pumpAndSettle();
      expect(markers(tester).selected, {1});
      expect(markers(tester).focusedIndex, 0);
      expect(find.text('已选 1 / 2 处'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('blemish-confirm')));
      await tester.pumpAndSettle();
      expect(await page.result, [1]);
      current.value = false;
      await tester.pumpAndSettle();
      expect(find.text('parent remains'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();
    },
  );

  testWidgets(
    'tapping a numbered photo marker focuses its matching list item',
    (tester) async {
      final current = ValueNotifier(true);
      final page = await open(tester, current);
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('blemish-marker-1'))),
      );
      await tester.pump();
      expect(markers(tester).focusedIndex, 1);
      expect(markers(tester).selected, {
        0,
        1,
      }, reason: 'Locating cannot silently uncheck a repair');
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('blemish-locate-1')),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.color, const Color(0xffffe335));
      await tester.tap(find.byKey(const ValueKey('blemish-cancel')));
      await tester.pumpAndSettle();
      expect(await page.result, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();
    },
  );

  testWidgets(
    'list location zooms the same source target and fit restores all markers',
    (tester) async {
      final current = ValueNotifier(true);
      await open(tester, current);
      await tester.tap(find.byKey(const ValueKey('blemish-locate-1')));
      await tester.pump();
      var stage = tester.widget<RetouchOriginalPhotoStage>(
        find.byType(RetouchOriginalPhotoStage),
      );
      expect(stage.controller.value.getMaxScaleOnAxis(), 4);
      expect(markers(tester).focusedIndex, 1);
      final frame = retouchOriginalPhotoFrame(
        viewport: tester.getSize(find.byType(RetouchOriginalPhotoStage)),
        imageWidth: 1000,
        imageHeight: 500,
        transform: stage.controller.value,
      );
      final target = Offset(
        frame.left + .7 * frame.width,
        frame.top + .6 * frame.height,
      );
      expect(
        (Offset.zero & tester.getSize(find.byType(RetouchOriginalPhotoStage)))
            .contains(target),
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('blemish-fit')));
      await tester.pump();
      stage = tester.widget<RetouchOriginalPhotoStage>(
        find.byType(RetouchOriginalPhotoStage),
      );
      expect(stage.controller.value.getMaxScaleOnAxis(), 1);
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();
    },
  );

  testWidgets(
    'none disables confirmation and all restores the default selection',
    (tester) async {
      final current = ValueNotifier(true);
      await open(tester, current);
      await tester.tap(find.byKey(const ValueKey('blemish-select-none')));
      await tester.pump();
      expect(markers(tester).selected, isEmpty);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('blemish-confirm')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('blemish-select-all')));
      await tester.pump();
      expect(markers(tester).selected, {0, 1});
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('blemish-confirm')))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();
    },
  );

  testWidgets('invalid ownership hides the private photo and cannot confirm', (
    tester,
  ) async {
    final current = ValueNotifier(true);
    final page = await open(tester, current);
    current.value = false;
    // Invoke the stale callback before rebuilding: the synchronous gate rejects it.
    tester
        .widget<FilledButton>(find.byKey(const ValueKey('blemish-confirm')))
        .onPressed!();
    await tester.pump();
    expect(find.byType(RetouchBlemishMarkers), findsNothing);
    await tester.pumpAndSettle();
    expect(await page.result, isNull);
    expect(find.text('parent remains'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    current.dispose();
  });

  testWidgets(
    'normal back then invalidation during exit never pops the parent',
    (tester) async {
      final current = ValueNotifier(true);
      final page = await open(tester, current);
      page.navigator.pop();
      current.value = false;
      await tester.pumpAndSettle();
      expect(await page.result, isNull);
      expect(find.text('parent remains'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();
    },
  );

  testWidgets('a missing positioning image cannot authorize repairs', (
    tester,
  ) async {
    final current = ValueNotifier(true);
    await open(tester, current, missingFile: true);
    for (
      var i = 0;
      i < 20 && find.text('无法载入定位照片，请取消后重新分析。').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(find.text('无法载入定位照片，请取消后重新分析。'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('blemish-confirm')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    current.dispose();
  });

  testWidgets(
    'two fingers navigate the photo without changing selected repairs',
    (tester) async {
      final current = ValueNotifier(true);
      await open(tester, current);
      final center = tester.getCenter(find.byType(RetouchOriginalPhotoStage));
      final first = await tester.startGesture(
        center - const Offset(30, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 2,
      );
      await first.moveBy(const Offset(-30, 0));
      await second.moveBy(const Offset(30, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pump();
      final stage = tester.widget<RetouchOriginalPhotoStage>(
        find.byType(RetouchOriginalPhotoStage),
      );
      expect(stage.controller.value.getMaxScaleOnAxis(), greaterThan(1));
      expect(markers(tester).selected, {0, 1});
      await tester.pumpWidget(const SizedBox.shrink());
      current.dispose();
    },
  );

  testWidgets('compact landscape and large text keep review controls usable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final current = ValueNotifier(true);
    await open(tester, current, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('blemish-confirm')), findsOneWidget);
    expect(
      tester.getSize(find.byType(RetouchOriginalPhotoStage)).height,
      greaterThan(48),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    current.dispose();
  });
}
