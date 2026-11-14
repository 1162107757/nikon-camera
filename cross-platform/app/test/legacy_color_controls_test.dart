import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/legacy_color_controls.dart';

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(375, 844),
      textScaler: TextScaler.linear(scale),
    ),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 375, child: child),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'HSL keeps three axes compact, edits only its colour and offers both resets',
    (tester) async {
      var values = List<int>.filled(24, 20), band = 4;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (_, update) => LegacyHslControls(
              values: values,
              selectedBand: band,
              onBandChanged: (value) => update(() => band = value),
              onChanged: (value) => update(() => values = value),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(LegacyHslControls)).height, 264);
      expect(find.byType(Slider), findsNWidgets(3));
      await tester.tap(find.text('重置此颜色'));
      await tester.pump();
      expect(values.sublist(12, 15), [0, 0, 0]);
      expect(values.take(12), everyElement(20));
      await tester.tap(find.text('重置 HSL'));
      await tester.pump();
      expect(values, everyElement(0));
      await tester.ensureVisible(find.byKey(const ValueKey('hsl-band-7')));
      await tester.tap(find.byKey(const ValueKey('hsl-band-7')));
      await tester.pump();
      expect(band, 7);
      await tester.drag(find.byType(Slider).first, const Offset(40, 0));
      await tester.pump();
      expect(values[21], greaterThan(0));
      expect(values.take(21), everyElement(0));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Palette pad changes colour and contrast together, preserving amount',
    (tester) async {
      var color = 0, tone = 0, amount = 73, starts = 0, ends = 0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (_, update) => LegacyPaletteControls(
              color: color,
              tone: tone,
              amount: amount,
              onChanged: (c, t, a) => update(() {
                color = c;
                tone = t;
                amount = a;
              }),
              onStart: () => starts++,
              onEnd: () => ends++,
            ),
          ),
        ),
      );
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('legacy-palette-pad'))) +
            const Offset(50, -45),
      );
      await tester.pump();
      expect(color, greaterThan(0));
      expect(tone, greaterThan(0));
      expect(amount, 73);
      expect(starts, 1);
      expect(ends, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A second finger cancels palette edits and the remaining finger cannot resume them',
    (tester) async {
      var color = 0, tone = 0, starts = 0, ends = 0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (_, update) => LegacyPaletteControls(
              color: color,
              tone: tone,
              amount: 100,
              onChanged: (c, t, _) => update(() {
                color = c;
                tone = t;
              }),
              onStart: () => starts++,
              onEnd: () => ends++,
            ),
          ),
        ),
      );
      final center = tester.getCenter(
        find.byKey(const Key('legacy-palette-pad')),
      );
      final first = await tester.startGesture(center, pointer: 1);
      await first.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(color, lessThan(0));
      final second = await tester.startGesture(
        center + const Offset(20, 0),
        pointer: 2,
      );
      await tester.pump();
      expect((color, tone), (0, 0));
      await first.moveBy(const Offset(20, -25));
      await second.up();
      await first.up();
      await tester.pump();
      expect((color, tone), (0, 0));
      expect(starts, 1);
      expect(ends, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cleanup starts with a short pane and gates sliders on real analysis',
    (tester) async {
      var analyzed = false, expanded = false, analyses = 0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (_, update) => LegacyCleanupControls(
              amount: 100,
              haze: 80,
              noise: 60,
              hasAnalysis: analyzed,
              onChanged: (_, _, _) {},
              onAnalyze: () => update(() {
                analyses++;
                analyzed = true;
              }),
              onReset: () {},
              onExpandedChanged: (value) => expanded = value,
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(LegacyCleanupControls)).height, 156);
      expect(find.text('去灰雾'), findsNothing);
      expect(
        tester.widget<Slider>(find.byType(Slider).first).onChanged,
        isNull,
      );
      await tester.tap(find.text('高级'));
      await tester.pump();
      expect(expanded, isTrue);
      expect(find.text('去灰雾'), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(3));
      await tester.tap(find.text('自动分析'));
      await tester.pump();
      expect(analyses, 1);
      expect(find.text('重新分析'), findsOneWidget);
      expect(
        tester.widget<Slider>(find.byType(Slider).first).onChanged,
        isNotNull,
      );
      await tester.tap(find.text('收起高级'));
      await tester.pump();
      expect(expanded, isFalse);
      expect(tester.getSize(find.byType(LegacyCleanupControls)).height, 156);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A second finger interrupts a colour slider without committing a stray value',
    (tester) async {
      var values = List<int>.filled(24, 0), starts = 0, ends = 0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (_, update) => LegacyHslControls(
              values: values,
              selectedBand: 0,
              onBandChanged: (_) {},
              onChanged: (value) => update(() => values = value),
              onStart: () => starts++,
              onEnd: () => ends++,
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(Slider).first);
      final first = await tester.startGesture(center, pointer: 1);
      await first.moveBy(const Offset(45, 0));
      await tester.pump();
      expect(values[0], greaterThan(0));
      final second = await tester.startGesture(
        center + const Offset(15, 0),
        pointer: 2,
      );
      await tester.pump();
      expect(values[0], 0);
      await first.moveBy(const Offset(20, 0));
      await second.up();
      await first.up();
      await tester.pump();
      expect(values[0], 0);
      expect((starts, ends), (1, 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Exact HSL input validates range and commits a single valid value',
    (tester) async {
      var values = List<int>.filled(24, 0), starts = 0, ends = 0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (_, update) => LegacyHslControls(
              values: values,
              selectedBand: 0,
              onBandChanged: (_) {},
              onChanged: (value) => update(() => values = value),
              onStart: () => starts++,
              onEnd: () => ends++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('0').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('legacy-color-exact-input')),
        '101',
      );
      await tester.tap(find.text('应用'));
      await tester.pump();
      expect(find.text('请输入-100至100的整数'), findsOneWidget);
      expect(values, everyElement(0));
      await tester.enterText(
        find.byKey(const Key('legacy-color-exact-input')),
        '-35',
      );
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(values[0], -35);
      expect(values.skip(1), everyElement(0));
      expect((starts, ends), (1, 1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Colour panes remain usable on a narrow phone at large text without horizontal overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        host(
          SingleChildScrollView(
            child: Column(
              children: [
                LegacyHslControls(
                  values: List.filled(24, 0),
                  selectedBand: 0,
                  onBandChanged: (_) {},
                  onChanged: (_) {},
                ),
                LegacyPaletteControls(
                  color: 100,
                  tone: -100,
                  amount: 100,
                  onChanged: (_, _, _) {},
                ),
                LegacyCleanupControls(
                  amount: 100,
                  haze: 100,
                  noise: 100,
                  hasAnalysis: true,
                  onChanged: (_, _, _) {},
                  onAnalyze: () {},
                  onReset: () {},
                ),
              ],
            ),
          ),
          scale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('cleanup-advanced')));
      await tester.tap(find.text('高级'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
