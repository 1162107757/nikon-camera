import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/retouch_more.dart';
import 'package:huevia/retouch_original_controls.dart';

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(body: child),
  ),
);

void main() {
  testWidgets(
    'sibling slider-first release cannot revive a disabled photo tap',
    (tester) async {
      final probe = _SiblingEditingProbe();
      await tester.pumpWidget(host(probe.build()));
      final slider = find.descendant(
        of: find.byKey(const ValueKey('sibling-size')),
        matching: find.byType(Slider),
      );
      final sizing = await tester.startGesture(
        tester.getRect(slider).center,
        pointer: 1,
      );
      await sizing.moveBy(const Offset(25, 0));
      expect(probe.editing.value, isFalse);
      final photo = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sibling-photo'))),
        pointer: 2,
      );
      await sizing.up();
      expect(probe.editing.value, isTrue);
      await photo.up();
      await tester.pump();
      expect(probe.taps, 0);
      expect(probe.commits, 0);
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('sibling-photo'))),
      );
      await tester.pump();
      expect(probe.taps, 1);
      await tester.pumpWidget(const SizedBox());
      probe.dispose();
    },
  );

  testWidgets(
    'sibling photo-first then slider cannot revive its old tap even within one frame',
    (tester) async {
      final probe = _SiblingEditingProbe();
      await tester.pumpWidget(host(probe.build()));
      final photo = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('sibling-photo'))),
        pointer: 1,
      );
      final slider = find.descendant(
        of: find.byKey(const ValueKey('sibling-size')),
        matching: find.byType(Slider),
      );
      final sizing = await tester.startGesture(
        tester.getRect(slider).center,
        pointer: 2,
      );
      await sizing.moveBy(const Offset(25, 0));
      expect(probe.editing.value, isFalse);
      await sizing.up();
      expect(probe.editing.value, isTrue);
      // No pump between disable and enable: a rebuilt bool alone misses this cycle.
      await photo.up();
      await tester.pump();
      expect(probe.taps, 0);
      expect(probe.commits, 0);
      await tester.tapAt(
        tester.getCenter(find.byKey(const ValueKey('sibling-photo'))),
      );
      await tester.pump();
      expect(probe.taps, 1);
      await tester.pumpWidget(const SizedBox());
      probe.dispose();
    },
  );

  testWidgets(
    'sibling slider interruption cancels a drawing stroke until all-up',
    (tester) async {
      final probe = _SiblingEditingProbe(drawing: true);
      await tester.pumpWidget(host(probe.build()));
      final center = tester.getCenter(
        find.byKey(const ValueKey('sibling-photo')),
      );
      final photo = await tester.startGesture(center, pointer: 1);
      await photo.moveBy(const Offset(20, 0));
      expect(probe.pending, isNotEmpty);
      final slider = find.descendant(
        of: find.byKey(const ValueKey('sibling-size')),
        matching: find.byType(Slider),
      );
      final sizing = await tester.startGesture(
        tester.getRect(slider).center,
        pointer: 2,
      );
      await sizing.moveBy(const Offset(25, 0));
      expect(probe.cancels, 1);
      expect(probe.pending, isEmpty);
      await sizing.up();
      await photo.moveBy(const Offset(20, 0));
      await photo.up();
      await tester.pump();
      expect(probe.commits, 0);
      expect(probe.taps, 0);
      expect(probe.pending, isEmpty);
      final fresh = await tester.startGesture(center, pointer: 3);
      await fresh.moveBy(const Offset(20, 0));
      await fresh.up();
      await tester.pump();
      expect(probe.commits, 1);
      expect(probe.cancels, 1);
      await tester.pumpWidget(const SizedBox());
      probe.dispose();
    },
  );

  testWidgets(
    'disabled editing freezes taps at down yet keeps pinch navigation available',
    (tester) async {
      final controller = TransformationController();
      var allowed = false, taps = 0;
      late StateSetter update;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return SizedBox(
                width: 400,
                height: 300,
                child: RetouchOriginalPhotoStage(
                  key: const ValueKey('disabled-photo'),
                  imageWidth: 800,
                  imageHeight: 600,
                  controller: controller,
                  editingEnabled: allowed,
                  onTap: (_) => taps++,
                  child: const ColoredBox(color: Colors.black),
                ),
              );
            },
          ),
        ),
      );
      final center = tester.getCenter(
        find.byKey(const ValueKey('disabled-photo')),
      );
      var photo = await tester.startGesture(center, pointer: 1);
      update(() => allowed = true);
      await tester.pump();
      await photo.up();
      expect(taps, 0);
      photo = await tester.startGesture(center, pointer: 2);
      update(() => allowed = false);
      await tester.pump();
      update(() => allowed = true);
      await tester.pump();
      await photo.up();
      expect(taps, 0);
      await tester.tapAt(center);
      expect(taps, 1);
      update(() => allowed = false);
      await tester.pump();
      final left = await tester.startGesture(
        center - const Offset(30, 0),
        pointer: 3,
      );
      final right = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 4,
      );
      await right.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
      await right.up();
      await left.up();
      expect(taps, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'repair pinch cancels the whole stroke and residual fingers cannot submit or resume it',
    (tester) async {
      final controller = TransformationController(),
          probe = _RepairGestureProbe();
      await tester.pumpWidget(
        host(SizedBox(width: 400, height: 400, child: probe.stage(controller))),
      );
      final origin = tester.getTopLeft(find.byType(RetouchOriginalPhotoStage));
      final first = await tester.startGesture(
        origin + const Offset(150, 200),
        pointer: 1,
      );
      await first.moveTo(origin + const Offset(170, 210));
      expect(probe.pending, hasLength(2));
      final second = await tester.startGesture(
        origin + const Offset(250, 200),
        pointer: 2,
      );
      await tester.pump();
      expect(probe.cancels, 1);
      expect(probe.pending, isEmpty);
      expect(probe.requests, isEmpty);
      final updatesBeforeNavigation = probe.updates;
      await first.moveTo(origin + const Offset(130, 200));
      await second.moveTo(origin + const Offset(280, 230));
      await first.moveTo(origin + const Offset(160, 220));
      await second.moveTo(origin + const Offset(310, 250));
      await tester.pump();
      expect(controller.value.getMaxScaleOnAxis(), inExclusiveRange(1, 8));
      expect(
        controller.value.storage[12].abs() + controller.value.storage[13].abs(),
        greaterThan(1),
      );
      expect(probe.updates, updatesBeforeNavigation);
      expect(probe.requests, isEmpty);
      await second.up();
      await first.moveTo(origin + const Offset(190, 270));
      final third = await tester.startGesture(
        origin + const Offset(300, 260),
        pointer: 3,
      );
      await third.moveTo(origin + const Offset(320, 270));
      await third.up();
      await first.moveTo(origin + const Offset(210, 260));
      await tester.pump();
      expect(probe.starts, 1);
      expect(probe.cancels, 1);
      expect(probe.pending, isEmpty);
      expect(probe.updates, updatesBeforeNavigation);
      expect(probe.requests, isEmpty);
      expect(probe.taps, 0);
      await first.up();
      final fresh = await tester.startGesture(
        origin + const Offset(200, 200),
        pointer: 4,
      );
      await fresh.moveTo(origin + const Offset(220, 210));
      await fresh.up();
      await tester.pump();
      expect(probe.starts, 2);
      expect(probe.requests, hasLength(1));
      expect(probe.taps, 0);
      expect(
        probe.requests.single.every(
          (point) =>
              point.dx >= 0 && point.dx <= 1 && point.dy >= 0 && point.dy <= 1,
        ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'repair after zoom and after fit commits the same original-image coordinates',
    (tester) async {
      final controller = TransformationController(
        Matrix4.identity()
          ..setEntry(0, 0, 2)
          ..setEntry(1, 1, 2)
          ..setTranslationRaw(50, -20, 0),
      );
      final probe = _RepairGestureProbe();
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 400,
            height: 300,
            child: probe.stage(controller, imageWidth: 800, imageHeight: 600),
          ),
        ),
      );
      const target = Offset(.3, .6), viewport = Size(400, 300);
      final origin = tester.getTopLeft(find.byType(RetouchOriginalPhotoStage));
      var frame = retouchOriginalPhotoFrame(
        viewport: viewport,
        imageWidth: 800,
        imageHeight: 600,
        transform: controller.value,
      );
      expect(frame, const Rect.fromLTWH(-150, -170, 800, 600));
      var gesture = await tester.startGesture(
        origin +
            frame.topLeft +
            Offset(target.dx * frame.width, target.dy * frame.height),
      );
      await gesture.up();
      await tester.pump();
      controller.value = Matrix4.identity();
      await tester.pump();
      frame = retouchOriginalPhotoFrame(
        viewport: viewport,
        imageWidth: 800,
        imageHeight: 600,
        transform: controller.value,
      );
      expect(frame, const Rect.fromLTWH(0, 0, 400, 300));
      gesture = await tester.startGesture(
        origin +
            frame.topLeft +
            Offset(target.dx * frame.width, target.dy * frame.height),
      );
      await gesture.up();
      await tester.pump();
      expect(probe.requests, hasLength(2));
      expect(probe.renderedSizes, [const Size(800, 600), const Size(400, 300)]);
      for (final request in probe.requests) {
        expect(request.last.dx, closeTo(.3, 1e-9));
        expect(request.last.dy, closeTo(.6, 1e-9));
        expect((request.last.dx * 800).round(), 240);
        expect((request.last.dy * 600).round(), 360);
      }
      expect(probe.taps, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'repair rotation cancellation retains held pointers until a genuinely new gesture',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(300, 500);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = TransformationController(),
          probe = _RepairGestureProbe();
      Widget page() =>
          host(probe.stage(controller, imageWidth: 600, imageHeight: 1000));
      await tester.pumpWidget(page());
      final first = await tester.startGesture(
        const Offset(150, 250),
        pointer: 1,
      );
      await first.moveTo(const Offset(155, 255));
      tester.view.physicalSize = const Size(500, 300);
      await tester.pumpWidget(page());
      await tester.pump();
      expect(probe.cancels, 1);
      expect(probe.pending, isEmpty);
      final second = await tester.startGesture(
        const Offset(270, 170),
        pointer: 2,
      );
      await second.moveTo(const Offset(290, 180));
      await second.up();
      await first.moveTo(const Offset(260, 180));
      await tester.pump();
      expect(probe.starts, 1);
      expect(probe.requests, isEmpty);
      expect(probe.pending, isEmpty);
      await first.up();
      final fresh = await tester.startGesture(
        const Offset(250, 150),
        pointer: 3,
      );
      await fresh.moveTo(const Offset(260, 160));
      await fresh.up();
      await tester.pump();
      expect(probe.starts, 2);
      expect(probe.requests, hasLength(1));
      expect(probe.cancels, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'body assistive compare tap restores after 650ms while portrait keeps its toggle',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var comparing = false;
        final states = <bool>[];
        Widget page(bool body) => host(
          StatefulBuilder(
            builder: (context, setState) => RetouchOriginalUtilityButton(
              icon: 'compare',
              semanticLabel: '对比',
              selected: comparing,
              bodyCompareTransient: body,
              onCompare: (value) {
                states.add(value);
                setState(() => comparing = value);
              },
            ),
          ),
        );
        await tester.pumpWidget(page(true));
        var node = tester.getSemantics(
          find.byType(RetouchOriginalUtilityButton),
        );
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pump();
        expect(states, [true]);
        await tester.pump(const Duration(milliseconds: 649));
        expect(comparing, isTrue);
        await tester.pump(const Duration(milliseconds: 1));
        expect(states, [true, false]);
        states.clear();
        await tester.pumpWidget(page(false));
        node = tester.getSemantics(find.byType(RetouchOriginalUtilityButton));
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pump(const Duration(milliseconds: 700));
        expect(states, [true]);
        expect(comparing, isTrue);
        node = tester.getSemantics(find.byType(RetouchOriginalUtilityButton));
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pump();
        expect(states, [true, false]);
        states.clear();
        await tester.pumpWidget(page(true));
        node = tester.getSemantics(find.byType(RetouchOriginalUtilityButton));
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpWidget(page(false));
        node = tester.getSemantics(find.byType(RetouchOriginalUtilityButton));
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pump(const Duration(milliseconds: 700));
        expect(states, [
          true,
          false,
        ]); // The old body timer cannot turn off the parent again.
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'body compare restores when dragged out or a second finger arrives',
    (tester) async {
      final states = <bool>[];
      await tester.pumpWidget(
        host(
          RetouchOriginalUtilityButton(
            icon: 'compare',
            semanticLabel: '对比',
            bodyCompareTransient: true,
            onCompare: states.add,
          ),
        ),
      );
      final center = tester.getCenter(
        find.byType(RetouchOriginalUtilityButton),
      );
      var first = await tester.startGesture(center, pointer: 1);
      await first.moveTo(center + const Offset(60, 0));
      await first.moveTo(center);
      await first.up();
      await tester.pump();
      expect(states, [true, false]);
      first = await tester.startGesture(center, pointer: 2);
      final second = await tester.startGesture(
        center + const Offset(1, 0),
        pointer: 3,
      );
      await second.up();
      await first.up();
      await tester.pump();
      expect(states, [true, false, true, false]);
    },
  );

  testWidgets('body hardware compare releases on key-up and focus loss', (
    tester,
  ) async {
    final states = <bool>[];
    await tester.pumpWidget(
      host(
        RetouchOriginalUtilityButton(
          icon: 'compare',
          semanticLabel: '对比',
          bodyCompareTransient: true,
          onCompare: states.add,
        ),
      ),
    );
    final context = tester.element(find.byType(Tooltip));
    Focus.of(context).requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(states, [true]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(states, [true, false]);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    Focus.of(context).unfocus();
    await tester.pump();
    expect(states, [true, false, true, false]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(states, [true, false, true, false]);
  });

  testWidgets(
    'viewport completes one accepted drawing stroke without also selecting a face',
    (tester) async {
      final controller = TransformationController();
      var starts = 0, ends = 0, taps = 0;
      final points = <Offset>[];
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            height: 300,
            child: RetouchOriginalPhotoStage(
              imageWidth: 200,
              imageHeight: 100,
              controller: controller,
              drawing: true,
              onStart: (point, size) {
                starts++;
                expect(size, const Size(300, 150));
                return true;
              },
              onUpdate: points.add,
              onEnd: () => ends++,
              onTap: (_) => taps++,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(RetouchOriginalPhotoStage));
      final gesture = await tester.startGesture(center);
      await gesture.moveTo(center + const Offset(30, 10));
      await gesture.up();
      await tester.pump();
      expect(starts, 1);
      expect(ends, 1);
      expect(taps, 0);
      expect(points.last.dx, closeTo(.6, .001));
      expect(points.last.dy, closeTo(.5667, .001));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'second viewport finger cancels drawing and becomes bounded navigation',
    (tester) async {
      final controller = TransformationController();
      var cancelled = 0, ended = 0, tapped = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            height: 300,
            child: RetouchOriginalPhotoStage(
              imageWidth: 100,
              imageHeight: 100,
              controller: controller,
              drawing: true,
              onStart: (_, _) => true,
              onCancel: () => cancelled++,
              onEnd: () => ended++,
              onTap: (_) => tapped++,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(RetouchOriginalPhotoStage));
      final first = await tester.startGesture(
        center - const Offset(30, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 2,
      );
      await second.moveTo(center + const Offset(100, 0));
      await tester.pump();
      expect(cancelled, 1);
      expect(controller.value.getMaxScaleOnAxis(), greaterThan(1));
      await second.up();
      await first.moveTo(center);
      await first.up();
      await tester.pump();
      expect(ended, 0);
      expect(tapped, 0);
      expect(controller.value.getMaxScaleOnAxis(), lessThanOrEqualTo(8));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'viewport hit coordinates follow actual zoom and fit restores the centre',
    (tester) async {
      final controller = TransformationController(
        Matrix4.identity()
          ..setEntry(0, 0, 2)
          ..setEntry(1, 1, 2)
          ..setTranslationRaw(80, 0, 0),
      );
      Offset? picked;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            height: 300,
            child: RetouchOriginalPhotoStage(
              imageWidth: 200,
              imageHeight: 100,
              controller: controller,
              onTap: (point) => picked = point,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );
      await tester.tapAt(
        tester.getCenter(find.byType(RetouchOriginalPhotoStage)),
      );
      await tester.pump();
      expect(picked!.dx, closeTo(220 / 600, .001));
      expect(picked!.dy, closeTo(.5, .001));
      controller.value = Matrix4.identity();
      await tester.pump();
      await tester.tapAt(
        tester.getCenter(find.byType(RetouchOriginalPhotoStage)),
      );
      await tester.pump();
      expect(picked, const Offset(.5, .5));
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'body viewport reserves its bars and only body permits one-finger pan',
    (tester) async {
      final controller = TransformationController();
      Widget stage(bool body) => host(
        SizedBox(
          width: 300,
          height: 300,
          child: RetouchOriginalPhotoStage(
            imageWidth: 100,
            imageHeight: 200,
            controller: controller,
            reserveBars: body,
            singleFingerPan: body,
            child: const ColoredBox(
              key: ValueKey('photo'),
              color: Colors.black,
            ),
          ),
        ),
      );
      await tester.pumpWidget(stage(false));
      expect(
        tester.getSize(find.byKey(const ValueKey('photo'))),
        const Size(150, 300),
      );
      await tester.pumpWidget(stage(true));
      await tester.pump();
      expect(
        tester.getSize(find.byKey(const ValueKey('photo'))),
        const Size(102, 204),
      );
      controller.value = Matrix4.identity()
        ..setEntry(0, 0, 2)
        ..setEntry(1, 1, 2);
      await tester.pump();
      await tester.drag(
        find.byType(RetouchOriginalPhotoStage),
        const Offset(0, 30),
      );
      await tester.pump();
      expect(controller.value.storage[13], greaterThan(0));
      controller.value = Matrix4.identity()
        ..setEntry(0, 0, 2)
        ..setEntry(1, 1, 2);
      await tester.pumpWidget(stage(false));
      await tester.pump();
      await tester.drag(
        find.byType(RetouchOriginalPhotoStage),
        const Offset(0, 30),
      );
      await tester.pump();
      expect(controller.value.storage[13], 0);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'viewport rotation cancels an unfinished stroke and preserves zoom',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(300, 500);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final controller = TransformationController();
      var cancelled = 0, ended = 0;
      Widget page() => host(
        RetouchOriginalPhotoStage(
          imageWidth: 100,
          imageHeight: 200,
          controller: controller,
          drawing: true,
          onStart: (_, _) => true,
          onCancel: () => cancelled++,
          onEnd: () => ended++,
          child: const ColoredBox(color: Colors.black),
        ),
      );
      await tester.pumpWidget(page());
      controller.value = Matrix4.identity()
        ..setEntry(0, 0, 2)
        ..setEntry(1, 1, 2);
      await tester.pump();
      final stroke = await tester.startGesture(
        tester.getCenter(find.byType(RetouchOriginalPhotoStage)),
      );
      tester.view.physicalSize = const Size(500, 300);
      await tester.pumpWidget(page());
      await tester.pump();
      await stroke.up();
      await tester.pump();
      expect(cancelled, 1);
      expect(ended, 0);
      expect(controller.value.getMaxScaleOnAxis(), 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'slider pointer cancellation restores tentative state without a normal commit',
    (tester) async {
      var committed = 0, cancelled = 0;
      double value = 0;
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => RetouchOriginalSlider(
              label: '提亮',
              value: value,
              min: 0,
              max: 100,
              onChanged: (next) => setState(() => value = next),
              onChangeEnd: (_) => committed++,
              onChangeCancel: () {
                cancelled++;
                setState(() => value = 0);
              },
            ),
          ),
        ),
      );
      final slider = find.byType(Slider),
          center = tester.getCenter(find.byType(Slider));
      final gesture = await tester.startGesture(center);
      await gesture.moveTo(center + const Offset(60, 0));
      await tester.pump();
      expect(value, greaterThan(0));
      await gesture.cancel();
      await tester.pump();
      expect(cancelled, 1);
      expect(committed, 0);
      expect(value, 0);
      expect(tester.widget<Slider>(slider).value, 0);
    },
  );

  testWidgets(
    'light pad clamps a real drag to the source circle and commits once',
    (tester) async {
      var start = 0, end = 0;
      Offset value = Offset.zero;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            child: RetouchOriginalLightPad(
              x: 0,
              y: 0,
              onChangeStart: () => start++,
              onChangeEnd: () => end++,
              onChanged: (next) => value = next,
            ),
          ),
        ),
      );
      final rect = tester.getRect(find.byType(RetouchOriginalLightPad));
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveTo(rect.bottomRight - const Offset(1, 1));
      await tester.pump();
      expect(value.dx, greaterThan(0));
      expect(value.dy, greaterThan(0));
      expect(value.distance, closeTo(100, 1));
      expect(end, 0);
      await gesture.up();
      await tester.pump();
      expect(start, 1);
      expect(end, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'light pad second pointer cancels tentative light without committing it',
    (tester) async {
      var cancelled = 0, committed = 0;
      Offset value = Offset.zero;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 300,
            child: RetouchOriginalLightPad(
              x: 20,
              y: -10,
              onChanged: (next) => value = next,
              onCancel: () {
                cancelled++;
                value = const Offset(20, -10);
              },
              onChangeEnd: () => committed++,
            ),
          ),
        ),
      );
      final center = tester.getCenter(find.byType(RetouchOriginalLightPad));
      final first = await tester.startGesture(
        center + const Offset(20, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(-20, 0),
        pointer: 2,
      );
      await tester.pump();
      expect(cancelled, 1);
      expect(value, const Offset(20, -10));
      await second.up();
      await first.up();
      await tester.pump();
      expect(committed, 0);
    },
  );

  testWidgets(
    'slider drag remains editable and commits its actual signed value once',
    (tester) async {
      double value = 0;
      final starts = <double>[], commits = <double>[];
      await tester.pumpWidget(
        host(
          StatefulBuilder(
            builder: (context, setState) => RetouchOriginalSlider(
              label: '亮度',
              value: value,
              min: -100,
              max: 100,
              onChanged: (next) => setState(() => value = next),
              onChangeStart: starts.add,
              onChangeEnd: commits.add,
            ),
          ),
        ),
      );
      final slider = find.byType(Slider);
      final rect = tester.getRect(slider);
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveTo(Offset(rect.right - 15, rect.center.dy));
      await tester.pump();
      expect(value, greaterThan(90));
      expect(commits, isEmpty);
      expect(find.textContaining('+'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect(starts, hasLength(1));
      expect(commits, hasLength(1));
      expect(commits.single, value);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disabled slider rejects input and rebuilding shows authoritative state',
    (tester) async {
      var called = false;
      await tester.pumpWidget(
        host(
          RetouchOriginalSlider(
            label: '大小',
            value: 22,
            min: 2,
            max: 120,
            valueLabel: '2.2%',
            onChanged: null,
          ),
        ),
      );
      await tester.drag(find.byType(Slider), const Offset(100, 0));
      await tester.pump();
      expect(find.text('2.2%'), findsOneWidget);
      await tester.pumpWidget(
        host(
          RetouchOriginalSlider(
            label: '大小',
            value: 50,
            min: 2,
            max: 120,
            valueLabel: '5.0%',
            onChanged: (_) => called = true,
          ),
        ),
      );
      expect(find.text('5.0%'), findsOneWidget);
      await tester.tapAt(tester.getRect(find.byType(Slider)).center);
      await tester.pump();
      expect(called, isTrue);
    },
  );

  testWidgets(
    'face bar exposes actual selection, automatic, add and anchored more actions',
    (tester) async {
      var selected = 0, detected = 0, added = 0;
      await tester.pumpWidget(
        host(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: RetouchOriginalFaceBar(
                selectionLabel: '人脸 1 · 另有很长的选区说明',
                onSelect: () => selected++,
                onDetect: () => detected++,
                onAdd: () => added++,
                onMore: (context) => showRetouchMoreMenu(
                  context,
                  state: const RetouchMoreState(
                    selectedFace: 0,
                    faceEnabled: true,
                    heals: [],
                    hasPortrait: true,
                    skinMode: false,
                    tonePerFace: false,
                    toneCardCount: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('人脸 1 · 另有很长的选区说明'));
      await tester.tap(find.text('自动选脸'));
      await tester.tap(find.byTooltip('手动添加人脸'));
      await tester.tap(find.byTooltip('更多人像操作'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(detected, 1);
      expect(added, 1);
      expect(find.text('重置人像精修'), findsOneWidget);
      expect(
        tester
            .getRect(find.byType(PopupMenuItem<RetouchMoreAction>).first)
            .left,
        lessThan(320),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compare hold restores baseline on release and pointer cancellation',
    (tester) async {
      final states = <bool>[];
      await tester.pumpWidget(
        host(
          RetouchOriginalUtilityButton(
            icon: 'compare',
            semanticLabel: '按住查看处理前',
            onCompare: states.add,
          ),
        ),
      );
      var gesture = await tester.startGesture(
        tester.getCenter(find.byType(RetouchOriginalUtilityButton)),
      );
      await tester.pump();
      expect(states, [true]);
      await gesture.up();
      await tester.pump();
      expect(states, [true, false]);
      gesture = await tester.startGesture(
        tester.getCenter(find.byType(RetouchOriginalUtilityButton)),
      );
      await gesture.cancel();
      await tester.pump();
      expect(states, [true, false, true, false]);
    },
  );

  testWidgets(
    'disabled tool never invokes edit and selected tool remains actionable',
    (tester) async {
      var edits = 0;
      await tester.pumpWidget(
        host(
          Row(
            children: [
              const RetouchOriginalToolButton(
                label: '肤色',
                icon: 'color',
                selected: true,
              ),
              RetouchOriginalToolButton(
                label: '眼白净化',
                icon: 'eye-clean',
                selected: true,
                onPressed: () => edits++,
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('肤色'));
      await tester.tap(find.text('眼白净化'));
      await tester.pump();
      expect(edits, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mode dock scrolls to live controls rather than clipping actions',
    (tester) async {
      var edits = 0;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 211,
            height: 132,
            child: RetouchOriginalDock(
              choosingGroup: false,
              entries: const [],
              controls: [
                for (var i = 0; i < 12; i++)
                  RetouchOriginalTextButton('参数 $i', () => edits++),
              ],
            ),
          ),
        ),
      );
      await tester.scrollUntilVisible(
        find.text('参数 11'),
        160,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('参数 11'));
      await tester.pump();
      expect(edits, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'portrait to landscape rotation preserves reachable group actions and a photo stage',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var group = '皮肤';
      Widget page() => host(
        LayoutBuilder(
          builder: (context, bounds) {
            final metrics = RetouchOriginalMetrics.resolve(
              bounds.biggest,
              1,
              mode: 0,
              choosingGroup: true,
            );
            final dock = SizedBox(
              width: metrics.dockWidth,
              height: metrics.dockHeight,
              child: RetouchOriginalDock(
                controls: const [],
                choosingGroup: true,
                entries: [
                  for (final name in ['皮肤', '面部', '塑形', '自然精修'])
                    RetouchOriginalToolButton(
                      label: name,
                      icon: name == '塑形' ? 'body' : 'face',
                      entry: true,
                      onPressed: () => group = name,
                    ),
                ],
              ),
            );
            final stage = Expanded(
              child: Container(key: const ValueKey('photo-stage')),
            );
            return metrics.side
                ? Row(children: [stage, dock])
                : Column(children: [stage, dock]);
          },
        ),
      );
      await tester.pumpWidget(page());
      await tester.tap(find.text('面部'));
      expect(group, '面部');
      final portraitStage = tester.getRect(
        find.byKey(const ValueKey('photo-stage')),
      );
      expect(portraitStage.height, greaterThan(500));
      tester.view.physicalSize = const Size(900, 420);
      await tester.pumpWidget(page());
      await tester.pump();
      final landscapeStage = tester.getRect(
        find.byKey(const ValueKey('photo-stage')),
      );
      expect(landscapeStage.width, greaterThan(500));
      await tester.tap(find.text('塑形'));
      expect(group, '塑形');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'large text group rail remains horizontally scrollable and usable in a short panel',
    (tester) async {
      var invoked = false;
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 260,
            height: 60,
            child: RetouchOriginalDock(
              choosingGroup: true,
              controls: const [],
              entries: [
                for (final name in ['皮肤', '面部', '塑形', '自然精修'])
                  RetouchOriginalToolButton(
                    label: name,
                    icon: 'face',
                    entry: true,
                    onPressed: () {
                      if (name == '自然精修') invoked = true;
                    },
                  ),
              ],
            ),
          ),
          scale: 2.5,
        ),
      );
      final horizontal = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.right,
      );
      await tester.scrollUntilVisible(
        find.text('自然精修'),
        150,
        scrollable: horizontal,
      );
      await tester.tap(find.text('自然精修'));
      await tester.pump();
      expect(invoked, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        host(
          Row(
            children: [
              RetouchOriginalToolButton(
                label: '自然精修',
                icon: 'face',
                onPressed: () {},
              ),
            ],
          ),
          scale: 3.2,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'old choice and confirmation dialogs return cancellation and real selection',
    (tester) async {
      int? chosen;
      bool? confirmed;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () async {
                    chosen = await showRetouchOriginalChoices(
                      context,
                      title: '选择人脸',
                      items: ['人脸 1', '人脸 2'],
                      selected: 0,
                    );
                  },
                  child: const Text('选脸'),
                ),
                TextButton(
                  onPressed: () async {
                    confirmed = await confirmRetouchOriginalAction(
                      context,
                      title: '重新识别人脸？',
                      message: '会替换已有的人脸选区和对应调节，保留祛痘。可撤销。',
                      positive: '重新识别',
                    );
                  },
                  child: const Text('识别'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('选脸'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('人脸 2'));
      await tester.pumpAndSettle();
      expect(chosen, 1);
      await tester.tap(find.text('识别'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(confirmed, isFalse);
      await tester.tap(find.text('识别'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新识别'));
      await tester.pumpAndSettle();
      expect(confirmed, isTrue);
    },
  );
}

/// Models the workspace boundary: previews change onUpdate, requests only onEnd.
class _RepairGestureProbe {
  final pending = <Offset>[];
  final requests = <List<Offset>>[];
  final renderedSizes = <Size>[];
  int starts = 0, updates = 0, cancels = 0, taps = 0;
  Widget stage(
    TransformationController controller, {
    double imageWidth = 800,
    double imageHeight = 800,
  }) => RetouchOriginalPhotoStage(
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    controller: controller,
    drawing: true,
    onStart: (point, size) {
      starts++;
      renderedSizes.add(size);
      pending
        ..clear()
        ..add(point);
      return true;
    },
    onUpdate: (point) {
      updates++;
      pending.add(point);
    },
    onEnd: () {
      requests.add(List.of(pending));
      pending.clear();
    },
    onCancel: () {
      cancels++;
      pending.clear();
    },
    onTap: (_) => taps++,
    child: const ColoredBox(color: Colors.black),
  );
}

class _SiblingEditingProbe {
  _SiblingEditingProbe({this.drawing = false});
  final bool drawing;
  final editing = ValueNotifier<bool>(true);
  final controller = TransformationController();
  final pending = <Offset>[];
  int taps = 0, commits = 0, cancels = 0;
  Widget build() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 400,
        height: 300,
        child: RetouchOriginalPhotoStage(
          key: const ValueKey('sibling-photo'),
          imageWidth: 800,
          imageHeight: 600,
          controller: controller,
          drawing: drawing,
          editingSignal: editing,
          onStart: (point, size) {
            pending
              ..clear()
              ..add(point);
            return true;
          },
          onUpdate: pending.add,
          onEnd: () {
            commits++;
            pending.clear();
          },
          onCancel: () {
            cancels++;
            pending.clear();
          },
          onTap: (_) => taps++,
          child: const ColoredBox(color: Colors.black),
        ),
      ),
      SizedBox(
        width: 400,
        child: RetouchOriginalSlider(
          key: const ValueKey('sibling-size'),
          label: '大小',
          value: 22,
          min: 5,
          max: 100,
          onChanged: (_) {},
          onChangeStart: (_) => editing.value = false,
          onChangeEnd: (_) => editing.value = true,
          onChangeCancel: () => editing.value = true,
        ),
      ),
    ],
  );
  void dispose() {
    editing.dispose();
    controller.dispose();
  }
}
