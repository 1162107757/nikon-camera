import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/legacy_color_controls.dart';
import 'package:huevia/palette_workspace.dart';

class PaletteFixture extends StatefulWidget {
  const PaletteFixture({super.key, this.scale = 1});
  final double scale;
  @override
  State<PaletteFixture> createState() => PaletteFixtureState();
}

class PaletteFixtureState extends State<PaletteFixture> {
  int color = 24, tone = 12, amount = 80;
  int applies = 0, cancels = 0, resets = 0, photoActions = 0, scopeActions = 0;
  int? openedTool;
  bool enabled = true;
  void disable() => setState(() => enabled = false);

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(widget.scale)),
      child: child!,
    ),
    home: Scaffold(
      appBar: AppBar(title: const Text('照片编辑')),
      body: PaletteWorkspace(
        color: color,
        tone: tone,
        amount: amount,
        enabled: enabled,
        onApply: () => applies++,
        onCancel: () => cancels++,
        onReset: () => setState(() {
          color = tone = 0;
          amount = 100;
          resets++;
        }),
        onTool: (value) => openedTool = value,
        photo: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xff8faaa2)),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                tooltip: '照片对比按钮',
                onPressed: () => photoActions++,
                icon: const Icon(Icons.compare),
              ),
            ),
          ],
        ),
        controls: (height, onGesture, showReadouts) => LegacyPaletteControls(
          color: color,
          tone: tone,
          amount: amount,
          compact: true,
          showReadouts: showReadouts,
          padHeight: height,
          enabled: enabled,
          onStart: () => onGesture(true),
          onEnd: () => onGesture(false),
          onChanged: (c, t, a) => setState(() {
            color = c;
            tone = t;
            amount = a;
          }),
        ),
        onScope: (anchor) => scopeActions++,
        readouts: (onGesture) => LegacyPaletteControls(
          color: color,
          tone: tone,
          amount: amount,
          compact: true,
          onStart: () => onGesture(true),
          onEnd: () => onGesture(false),
          onChanged: (c, t, a) => setState(() {
            color = c;
            tone = t;
            amount = a;
          }),
        ).readouts(context),
      ),
    ),
  );
}

void main() {
  for (final spec in [
    (const Size(320, 640), 1.3),
    (const Size(390, 844), 1.0),
    (const Size(1024, 768), 1.3),
    (const Size(812, 375), 2.0),
  ]) {
    testWidgets('Fixed wide pad hides toolbar and retains values at $spec', (
      tester,
    ) async {
      tester.view.physicalSize = spec.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(PaletteFixture(scale: spec.$2));
      await tester.pumpAndSettle();
      final state = tester.state<PaletteFixtureState>(
        find.byType(PaletteFixture),
      );
      final photo = tester.getRect(
        find.byKey(const Key('palette-photo-stage')),
      );
      expect(find.byKey(const Key('palette-tools-toolbar')), findsNothing);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(
        find.byKey(const Key('palette-scope')).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.widget<LegacyPalettePad>(find.byType(LegacyPalettePad)).wide,
        isTrue,
      );
      expect(
        find.byKey(const Key('palette-panel-toggle')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('palette-apply')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('legacy-palette-pad')).hitTestable(),
        findsOneWidget,
      );
      final applyRect = tester.getRect(find.byKey(const Key('palette-apply')));
      expect(applyRect.right, lessThanOrEqualTo(spec.$1.width - 12));
      expect(applyRect.left, greaterThanOrEqualTo(12));
      await tester.tap(find.byKey(const Key('palette-apply')));
      expect(state.applies, 1);
      state.applies = 0;
      final pad = tester.getCenter(find.byKey(const Key('legacy-palette-pad')));
      await tester.tapAt(pad + const Offset(16, -12));
      await tester.pumpAndSettle();
      final before = (state.color, state.tone, state.amount);
      expect(state.color, inExclusiveRange(0, 100));
      expect(state.tone, inExclusiveRange(0, 100));
      expect(state.amount, 80);
      expect(find.byKey(const Key('palette-tools-toolbar')), findsNothing);
      await tester.tap(find.byKey(const Key('palette-panel-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('legacy-palette-pad')), findsNothing);
      expect(find.byKey(const Key('palette-tools-toolbar')), findsOneWidget);
      expect(find.text('曲线'), findsOneWidget);
      expect(state.applies, 0);
      expect(state.cancels, 0);
      final larger = tester.getRect(
        find.byKey(const Key('palette-photo-stage')),
      );
      expect(
        larger.width * larger.height,
        greaterThan(photo.width * photo.height),
      );
      await tester.tap(find.byKey(const Key('palette-tool-2')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('palette-tools-toolbar')), findsNothing);
      expect((state.color, state.tone, state.amount), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'Photo control taps and escaping pad gestures do not dismiss the pad',
    (tester) async {
      await tester.pumpWidget(const PaletteFixture());
      await tester.pumpAndSettle();
      final state = tester.state<PaletteFixtureState>(
        find.byType(PaletteFixture),
      );
      await tester.tap(find.byTooltip('照片对比按钮'));
      await tester.pumpAndSettle();
      expect(state.photoActions, 1);
      await tester.tap(find.byKey(const Key('palette-scope')));
      await tester.pump();
      expect(state.scopeActions, 1);
      expect(find.byKey(const Key('palette-expanded-panel')), findsOneWidget);
      final pad = tester.getCenter(find.byKey(const Key('legacy-palette-pad')));
      final gesture = await tester.startGesture(pad);
      await gesture.moveBy(const Offset(30, -20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('palette-expanded-panel')), findsOneWidget);
      expect(state.amount, 80);
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('palette-photo-stage'))),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('palette-tools-toolbar')), findsOneWidget);
      expect(state.applies, 0);
      expect(state.resets, 0);
      await tester.tap(find.byKey(const Key('palette-tool-5')));
      await tester.pump();
      expect(state.openedTool, 5);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Disabled state cannot collapse reset or apply', (tester) async {
    await tester.pumpWidget(const PaletteFixture());
    await tester.pumpAndSettle();
    final state = tester.state<PaletteFixtureState>(
      find.byType(PaletteFixture),
    );
    state.disable();
    await tester.pump();
    await tester.tap(find.byKey(const Key('palette-panel-toggle')));
    await tester.tap(find.byKey(const Key('palette-reset')));
    await tester.tap(find.byKey(const Key('palette-apply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('palette-expanded-panel')), findsOneWidget);
    expect(state.applies + state.resets + state.cancels, 0);
    expect((state.color, state.tone, state.amount), (24, 12, 80));
    await tester.pumpWidget(const SizedBox());
  });
}
