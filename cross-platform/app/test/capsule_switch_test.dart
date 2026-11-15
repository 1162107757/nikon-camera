import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/theme.dart';

Finder get capsuleIndicator =>
    find.byKey(const ValueKey('capsule-switch-indicator'));
Finder capsuleTab(int index) =>
    find.byKey(ValueKey('capsule-switch-tab-$index'));

Widget capsuleHarness({
  bool sync = false,
  bool enabled = true,
  bool reduceMotion = false,
  double textScale = 1,
  TextDirection direction = TextDirection.ltr,
  ValueChanged<int>? onChoice,
}) {
  var selected = 0;
  return MaterialApp(
    theme: hueviaTheme(Brightness.light),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: Directionality(
          textDirection: direction,
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: StatefulBuilder(
                  builder: (context, setState) => sync
                      ? CapsuleSwitch(
                          labels: const ['相机照片', '边拍边传', '已下载'],
                          selected: selected,
                          enabled: enabled,
                          gap: 8,
                          padding: const EdgeInsets.all(6),
                          height: 60,
                          onSelected: (value) {
                            onChoice?.call(value);
                            setState(() => selected = value);
                          },
                        )
                      : CapsuleSwitch(
                          labels: const ['应用相册', '手机相册'],
                          selected: selected,
                          enabled: enabled,
                          onSelected: (value) {
                            onChoice?.call(value);
                            setState(() => selected = value);
                          },
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

void expectCapsuleRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, .01));
  expect(actual.top, closeTo(expected.top, .01));
  expect(actual.right, closeTo(expected.right, .01));
  expect(actual.bottom, closeTo(expected.bottom, .01));
}

void main() {
  testWidgets(
    'Default capsule keeps its old geometry, font and disabled taps',
    (tester) async {
      final choices = <int>[];
      await tester.pumpWidget(
        capsuleHarness(enabled: false, onChoice: choices.add),
      );
      final outer = tester.getRect(find.byType(CapsuleSwitch));
      final indicator = tester.getRect(capsuleIndicator);
      final first = tester.getRect(capsuleTab(0));
      expect(outer.size, const Size(320, 48));
      expect(first.height, 48);
      expect(indicator.height, 40);
      expect(indicator.left - outer.left, closeTo(4, .01));
      expect(indicator.top - outer.top, closeTo(4, .01));
      expect(indicator.width, closeTo(first.width, .01));
      final labelStyle = DefaultTextStyle.of(tester.element(find.text('应用相册')))
          .style;
      expect(labelStyle.fontSize, 13);
      expect(labelStyle.height, 1.2);
      expect(labelStyle.fontWeight, FontWeight.w700);
      await tester.tapAt(tester.getRect(capsuleTab(1)).center);
      await tester.pump(const Duration(milliseconds: 250));
      expect(choices, isEmpty);
      expectCapsuleRect(tester.getRect(capsuleIndicator), indicator);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Sync capsule keeps six dp edges and eight dp gaps while retargeting its moving pill',
    (tester) async {
      final choices = <int>[];
      await tester.pumpWidget(
        capsuleHarness(sync: true, onChoice: choices.add),
      );
      final outer = tester.getRect(find.byType(CapsuleSwitch));
      final tabs = [for (var i = 0; i < 3; i++) tester.getRect(capsuleTab(i))];
      expect(outer.size, const Size(320, 60));
      expect(tabs.first.left - outer.left, closeTo(6, .01));
      expect(outer.right - tabs.last.right, closeTo(6, .01));
      expect(tabs[1].left - tabs[0].right, closeTo(8, .01));
      expect(tabs[2].left - tabs[1].right, closeTo(8, .01));
      for (final tab in tabs) {
        expect(tab.height, 48);
        expect(tab.width, greaterThanOrEqualTo(48));
      }
      expectCapsuleRect(tester.getRect(capsuleIndicator), tabs[0]);
      await tester.tap(capsuleTab(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      final moving = tester.getRect(capsuleIndicator);
      expect(moving.left, greaterThan(tabs[0].left));
      expect(moving.left, lessThan(tabs[2].left));
      await tester.tap(capsuleTab(1));
      await tester.pump();
      expectCapsuleRect(tester.getRect(capsuleIndicator), moving);
      await tester.pump(const Duration(milliseconds: 220));
      expectCapsuleRect(tester.getRect(capsuleIndicator), tabs[1]);
      expect(choices, [2, 1]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RTL large text stays usable and reduced motion moves immediately',
    (tester) async {
      await tester.pumpWidget(
        capsuleHarness(
          sync: true,
          direction: TextDirection.rtl,
          textScale: 2.5,
          reduceMotion: true,
        ),
      );
      final outer = tester.getRect(find.byType(CapsuleSwitch));
      final first = tester.getRect(capsuleTab(0));
      final second = tester.getRect(capsuleTab(1));
      final last = tester.getRect(capsuleTab(2));
      expect(outer.right - first.right, closeTo(6, .01));
      expect(last.left - outer.left, closeTo(6, .01));
      expect(first.left - second.right, closeTo(8, .01));
      expect(second.left - last.right, closeTo(8, .01));
      expectCapsuleRect(tester.getRect(capsuleIndicator), first);
      for (var i = 0; i < 3; i++) {
        expect(capsuleTab(i).hitTestable(), findsOneWidget);
        expect(tester.getSize(capsuleTab(i)).height, 48);
      }
      await tester.tap(capsuleTab(2));
      await tester.pump();
      expectCapsuleRect(tester.getRect(capsuleIndicator), last);
      expect(tester.takeException(), isNull);
    },
  );
}
