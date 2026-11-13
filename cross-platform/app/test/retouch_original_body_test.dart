import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/retouch_original_body.dart';
import 'package:huevia/retouch_original_controls.dart';

const area = <String, dynamic>{
  'left': .2,
  'top': .1,
  'right': .8,
  'bottom': .9,
  'amount': 25,
};
Widget host(Widget child, {double scale = 1}) => MaterialApp(
  theme: ThemeData.dark(),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets(
    'body tools change the current target and keep single-leg exclusive to legs',
    (tester) async {
      var tool = 0, single = false, resetTool = -1;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 360,
              height: 180,
              child: RetouchOriginalDock(
                choosingGroup: false,
                entries: const [],
                controls: [
                  RetouchOriginalBodyControls(
                    tool: tool,
                    area: area,
                    protection: 0,
                    singleLeg: single,
                    expanded: false,
                    busy: false,
                    onTool: (value) => setState(() => tool = value),
                    onSingleLeg: () => setState(() => single = !single),
                    onReset: () => resetTool = tool,
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('双腿'), findsNothing);
      await tester.tap(find.text('瘦腿').last);
      await tester.pump();
      expect(tool, 1);
      expect(find.text('双腿'), findsOneWidget);
      await tester.tap(find.text('双腿'));
      await tester.pump();
      expect(single, isTrue);
      await tester.tap(find.text('拉长'));
      await tester.pump();
      expect(tool, 2);
      expect(find.text('腿部拉长'), findsOneWidget);
      expect(find.text('单腿'), findsNothing);
      await tester.tap(find.text('重置'));
      expect(resetTool, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'precise strength rejects invalid values, preserves cancel and submits an integer',
    (tester) async {
      int? exact;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 360,
            height: 180,
            child: RetouchOriginalDock(
              choosingGroup: false,
              entries: const [],
              controls: [
                RetouchOriginalBodyControls(
                  tool: 0,
                  area: area,
                  protection: 0,
                  singleLeg: false,
                  expanded: false,
                  busy: false,
                  onExact: (value) => exact = value,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('25'));
      await tester.pumpAndSettle();
      expect(find.text('瘦身 · 0—100'), findsOneWidget);
      final input = find.byKey(const ValueKey('retouch-exact-value'));
      for (final invalid in ['101', '-1', '3.5', '']) {
        await tester.enterText(input, invalid);
        await tester.tap(find.text('确定'));
        await tester.pumpAndSettle();
        expect(find.text('请输入0至100的整数'), findsOneWidget);
        expect(exact, isNull);
      }
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(exact, isNull);
      await tester.tap(find.text('25'));
      await tester.pumpAndSettle();
      await tester.enterText(input, '100');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(exact, 100);
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets(
    'expanded range sliders emit normalized values and one transaction per drag',
    (tester) async {
      var expanded = false;
      final starts = <int>[], ends = <int>[];
      final changes = <(int, double)>[];
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 360,
              height: retouchOriginalBodyDockHeight(
                const Size(360, 900),
                1,
                expanded: expanded,
              ),
              child: RetouchOriginalDock(
                choosingGroup: false,
                entries: const [],
                controls: [
                  RetouchOriginalBodyControls(
                    tool: 0,
                    area: area,
                    protection: 0,
                    singleLeg: false,
                    expanded: expanded,
                    busy: false,
                    onExpanded: (value) => setState(() => expanded = value),
                    onAxisStart: starts.add,
                    onAxisEnd: ends.add,
                    onAxis: (axis, value) => changes.add((axis, value)),
                    onChanged: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('左边'), findsNothing);
      await tester.tap(find.text('范围'));
      await tester.pump();
      expect(find.text('左边'), findsOneWidget);
      expect(find.text('高度'), findsOneWidget);
      final slider = find.descendant(
        of: find.byKey(const ValueKey('body-box-0')),
        matching: find.byType(Slider),
      );
      final center = tester.getCenter(slider),
          gesture = await tester.startGesture(center);
      await gesture.moveTo(center + const Offset(30, 0));
      await gesture.up();
      await tester.pump();
      expect(starts, [0]);
      expect(ends, [0]);
      expect(changes, isNotEmpty);
      expect(changes.last.$1, 0);
      expect(changes.last.$2, inInclusiveRange(0, 1));
      expect(
        changes.last.$2 * 1000,
        closeTo((changes.last.$2 * 1000).roundToDouble(), 1e-8),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'background protection and automatic location use separate controlled actions',
    (tester) async {
      var protection = 0, located = 0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => SizedBox(
              width: 360,
              height: 180,
              child: RetouchOriginalDock(
                choosingGroup: false,
                entries: const [],
                controls: [
                  RetouchOriginalBodyControls(
                    tool: 0,
                    area: area,
                    protection: protection,
                    singleLeg: false,
                    expanded: false,
                    busy: false,
                    onProtection: () =>
                        setState(() => protection = protection == 0 ? 100 : 0),
                    onLocate: () => located++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('背景保护'));
      await tester.pump();
      expect(protection, 100);
      expect(find.text('背景保护 · 开'), findsOneWidget);
      expect(located, 0);
      await tester.tap(find.text('自动定位'));
      expect(located, 1);
      await tester.tap(find.text('背景保护 · 开'));
      await tester.pump();
      expect(protection, 0);
    },
  );

  testWidgets(
    'busy body controls block edits and range reset while work is pending',
    (tester) async {
      var called = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 360,
            height: 372,
            child: RetouchOriginalDock(
              choosingGroup: false,
              entries: const [],
              controls: [
                RetouchOriginalBodyControls(
                  tool: 1,
                  area: area,
                  protection: 100,
                  singleLeg: false,
                  expanded: true,
                  busy: true,
                  onTool: (_) => called++,
                  onSingleLeg: () => called++,
                  onReset: () => called++,
                  onLocate: () => called++,
                  onProtection: () => called++,
                  onChanged: (_) => called++,
                  onExact: (_) => called++,
                  onAxis: (_, _) => called++,
                ),
              ],
            ),
          ),
        ),
      );
      for (final label in ['双腿', '重置', '自动定位', '背景保护 · 开', '25']) {
        await tester.tap(find.text(label));
      }
      expect(called, 0);
      expect(
        tester
            .widgetList<Slider>(find.byType(Slider))
            .every((slider) => slider.onChanged == null),
        isTrue,
      );
    },
  );

  testWidgets(
    'large-text body panel keeps all five tools and range fields reachable',
    (tester) async {
      var reset = 0, axisChanged = -1;
      final height = retouchOriginalBodyDockHeight(
        const Size(360, 900),
        2,
        expanded: true,
      );
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 360,
            height: height,
            child: RetouchOriginalDock(
              choosingGroup: false,
              entries: const [],
              controls: [
                RetouchOriginalBodyControls(
                  tool: 1,
                  area: area,
                  protection: 0,
                  singleLeg: false,
                  expanded: true,
                  busy: false,
                  onReset: () => reset++,
                  onAxis: (axis, _) => axisChanged = axis,
                ),
              ],
            ),
          ),
          scale: 2,
        ),
      );
      await tester.tap(find.text('重置'));
      expect(reset, 1);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('body-box-3')),
        100,
        scrollable: find.byType(Scrollable),
      );
      final slider = find.descendant(
        of: find.byKey(const ValueKey('body-box-3')),
        matching: find.byType(Slider),
      );
      await tester.tapAt(tester.getRect(slider).center);
      await tester.pump();
      expect(axisChanged, 3);
      expect(tester.takeException(), isNull);
    },
  );
}
