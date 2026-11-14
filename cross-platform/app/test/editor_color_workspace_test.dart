import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/curve_control.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/legacy_color_controls.dart';
import 'package:huevia/split_compare.dart';
import 'package:huevia/theme.dart';

import 'editor_realtime_preview_test.dart' show RealtimeCore, RealtimeState;

class ColorRequest {
  ColorRequest(this.operation, Json payload)
    : payload = object(jsonDecode(jsonEncode(payload)));
  final String operation;
  final Json payload;
  Json get recipe => object(payload['recipe']);
}

/// Records real Editor operation requests; returned files are tiny PNG fixtures.
/// These widget tests make no claim about native photo pixels or hardware.
class ColorWorkspaceCore extends RealtimeCore {
  final requests = <ColorRequest>[];
  List<ColorRequest> get reviews => requests
      .where((request) => request.operation == 'media.reviewPreview')
      .toList();

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    requests.add(ColorRequest(operation, payload));
    if (operation == 'media.preview' || operation == 'media.reviewPreview') {
      return image();
    }
    if (operation == 'media.cleanupAnalyze') {
      return {'cleanupData': 'analysis-fixture'};
    }
    if (operation == 'draft.save') {
      return {'sourceSha': 'fixture-sha', 'recipe': payload['recipe']};
    }
    return super.call(operation, payload, jobId);
  }
}

Future<void> frames(WidgetTester tester, {int count = 8}) async {
  for (var i = 0; i < count; i++) {
    // Colour entry copies its frame and FileImage performs IO off the fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<({ColorWorkspaceCore core, RealtimeState state})> open(
  WidgetTester tester,
) async {
  tester.view.physicalSize = const Size(375, 667);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final core = ColorWorkspaceCore();
  final current = RealtimeState(core);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('cc.huevia/events'),
        (_) async => null,
      );
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.dark),
      home: EditorPage(
        state: current,
        photo: Photo(core.source.path, '调色测试照片', const {}),
      ),
    ),
  );
  await frames(tester);
  expect(find.byType(SplitCompare), findsOneWidget);
  await tester.tap(find.text('调节'));
  await tester.pump();
  return (core: core, state: current);
}

Future<void> tool(WidgetTester tester, String name) async {
  final label = find.text(name);
  final strip = find
      .ancestor(of: label, matching: find.byType(SingleChildScrollView))
      .first;
  for (var i = 0; i < 8 && label.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(strip, const Offset(-210, 0));
    await tester.pump();
  }
  expect(label.hitTestable(), findsOneWidget);
  await tester.tap(label.hitTestable());
  await frames(tester);
  expect(find.byKey(const Key('legacy-color-controls-scroll')), findsOneWidget);
}

Future<void> close(WidgetTester tester, RealtimeState state) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  state.dispose();
  tester.binding.imageCache.clear();
  tester.binding.imageCache.clearLiveImages();
}

bool undoEnabled(WidgetTester tester) =>
    tester
        .widget<InkWell>(
          find
              .descendant(
                of: find.byTooltip('撤销'),
                matching: find.byType(InkWell),
              )
              .first,
        )
        .onTap !=
    null;

bool neutralCurves(Json recipe) =>
    recipe['curves'] == null ||
    (recipe['curves'] as List).every(
      (row) => jsonEncode(row) == '[0,0,255,255]',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Curve entry retains a large photograph and uses compact controls in both orientations',
    (tester) async {
      final fixture = await open(tester);
      await tool(tester, '曲线');
      final photo = tester.getRect(
        find.byKey(const Key('legacy-color-photo-stage')),
      );
      final controls = tester.getRect(
        find.byKey(const Key('legacy-color-controls-scroll')),
      );
      expect(
        tester.getSize(find.byKey(const Key('legacy-curve-graph'))).height,
        132,
      );
      expect(photo.bottom, lessThanOrEqualTo(controls.top + 1));
      expect(photo.height, greaterThanOrEqualTo((667 - 48) * .4));
      expect(controls.height, lessThanOrEqualTo(330));
      tester.view.physicalSize = const Size(812, 375);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await frames(tester);
      final landscapePhoto = tester.getRect(find.byType(SplitCompare));
      final side = tester.getRect(
        find.byKey(const Key('legacy-color-controls-scroll')),
      );
      expect(landscapePhoto.right, lessThanOrEqualTo(side.left + 1));
      expect(landscapePhoto.width, greaterThan(side.width));
      expect(side.width, lessThanOrEqualTo(330));
      expect(tester.takeException(), isNull);
      await close(tester, fixture.state);
    },
  );

  for (final name in ['曲线', 'HSL']) {
    testWidgets(
      '$name drag sends ongoing read-only frames and a final full-size frame without saving tentative edits',
      (tester) async {
        final fixture = await open(tester), core = fixture.core;
        await tool(tester, name);
        core.requests.clear();
        final target = name == '曲线'
            ? find.byKey(const Key('legacy-curve-graph'))
            : find
                  .descendant(
                    of: find.byType(LegacyHslControls),
                    matching: find.byType(Slider),
                  )
                  .first;
        final gesture = await tester.startGesture(tester.getCenter(target));
        for (var i = 0; i < 3; i++) {
          await gesture.moveBy(
            name == '曲线' ? const Offset(10, -10) : const Offset(15, 0),
          );
          await tester.pump(const Duration(milliseconds: 35));
        }
        expect(
          core.reviews.where((request) => request.payload['maxEdge'] == 640),
          isNotEmpty,
        );
        expect(
          core.requests.where(
            (request) =>
                request.operation == 'draft.save' ||
                request.operation == 'media.preview',
          ),
          isEmpty,
        );
        await gesture.up();
        await frames(tester);
        expect(core.reviews.last.payload['maxEdge'], 1280);
        expect(core.reviews.last.payload['snapshot'], isTrue);
        expect(core.reviews.last.payload['expectedSourceSha'], 'fixture-sha');
        if (name == '曲线') {
          expect(neutralCurves(core.reviews.last.recipe), isFalse);
        } else {
          expect((core.reviews.last.recipe['hsl'] as List)[0], greaterThan(0));
        }
        expect(
          core.requests.where(
            (request) =>
                request.operation == 'draft.save' ||
                request.operation == 'media.preview',
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        await close(tester, fixture.state);
        expect(
          core.requests.where((request) => request.operation == 'draft.save'),
          isEmpty,
        );
      },
    );
  }

  testWidgets(
    'Cancel rolls back tentative curve edits and restores an empty global undo history',
    (tester) async {
      final fixture = await open(tester), core = fixture.core;
      expect(undoEnabled(tester), isFalse);
      await tool(tester, '曲线');
      core.requests.clear();
      await tester.tap(find.text('加点'));
      await tester.pump();
      await tester.drag(
        find.byKey(const Key('legacy-curve-graph')),
        const Offset(20, -20),
      );
      await frames(tester);
      expect(neutralCurves(core.reviews.last.recipe), isFalse);
      await tester.tap(find.text('取消'));
      await frames(tester);
      expect(find.byType(CurveControl), findsNothing);
      final rendered = core.requests
          .where((request) => request.operation == 'media.preview')
          .last;
      expect(neutralCurves(rendered.recipe), isTrue);
      expect(undoEnabled(tester), isFalse);
      expect(
        core.requests.where((request) => request.operation == 'draft.save'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await close(tester, fixture.state);
    },
  );

  testWidgets(
    'System Back rolls back HSL while retaining an existing base-editor undo step',
    (tester) async {
      final fixture = await open(tester), core = fixture.core;
      await tester.drag(find.byType(Slider).first, const Offset(45, 0));
      await frames(tester);
      final exposure =
          (core.requests
                  .where((request) => request.operation == 'media.preview')
                  .last
                  .recipe['values']
              as List)[1];
      expect(exposure, greaterThan(0));
      expect(undoEnabled(tester), isTrue);
      await tool(tester, 'HSL');
      await tester.drag(
        find
            .descendant(
              of: find.byType(LegacyHslControls),
              matching: find.byType(Slider),
            )
            .first,
        const Offset(40, 0),
      );
      await frames(tester);
      await tester.binding.handlePopRoute();
      await frames(tester);
      final restored = core.requests
          .where((request) => request.operation == 'media.preview')
          .last
          .recipe;
      expect((restored['values'] as List)[1], exposure);
      expect(
        restored['hsl'] == null ||
            (restored['hsl'] as List).every((value) => value == 0),
        isTrue,
      );
      await tester.tap(find.byTooltip('撤销'));
      await frames(tester);
      final undone = core.requests
          .where((request) => request.operation == 'media.preview')
          .last
          .recipe;
      expect((undone['values'] as List)[1], 0);
      expect(undoEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
      await close(tester, fixture.state);
    },
  );

  testWidgets(
    'Apply groups several curve changes into one undo step and saves only after acceptance',
    (tester) async {
      final fixture = await open(tester), core = fixture.core;
      await tool(tester, '曲线');
      core.requests.clear();
      await tester.tap(find.text('加点'));
      await tester.pump();
      await tester.drag(
        find.byKey(const Key('legacy-curve-graph')),
        const Offset(20, -25),
      );
      await frames(tester);
      await tester.tap(find.text('加点'));
      await frames(tester);
      expect(
        core.requests.where((request) => request.operation == 'draft.save'),
        isEmpty,
      );
      await tester.tap(find.text('应用'));
      await frames(tester, count: 12);
      expect(find.byType(CurveControl), findsNothing);
      final saves = core.requests
          .where((request) => request.operation == 'draft.save')
          .toList();
      expect(saves, hasLength(1));
      expect(neutralCurves(saves.single.recipe), isFalse);
      expect(undoEnabled(tester), isTrue);
      await tester.tap(find.byTooltip('撤销'));
      await frames(tester);
      expect(
        neutralCurves(
          core.requests
              .where((request) => request.operation == 'media.preview')
              .last
              .recipe,
        ),
        isTrue,
      );
      expect(undoEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
      await close(tester, fixture.state);
    },
  );

  testWidgets(
    'Palette entry preserves dual-axis engine parameters and cancels without committing',
    (tester) async {
      final fixture = await open(tester), core = fixture.core;
      await tool(tester, '调色盘');
      core.requests.clear();
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('legacy-palette-pad'))) +
            const Offset(45, -40),
      );
      await frames(tester);
      final palette = object(core.reviews.last.recipe['palette']);
      expect(palette['color'], greaterThan(0));
      expect(palette['tone'], greaterThan(0));
      expect(palette['amount'], 100);
      expect(
        core.requests.where(
          (request) =>
              request.operation == 'draft.save' ||
              request.operation == 'media.preview',
        ),
        isEmpty,
      );
      await tester.tap(find.text('取消'));
      await frames(tester);
      expect(undoEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
      await close(tester, fixture.state);
    },
  );

  testWidgets(
    'Cleanup entry analyses once automatically and reset returns to the original neutral cleanup',
    (tester) async {
      final fixture = await open(tester), core = fixture.core;
      await tool(tester, '去灰');
      expect(
        core.requests.where(
          (request) => request.operation == 'media.cleanupAnalyze',
        ),
        hasLength(1),
      );
      final controls = tester.widget<LegacyCleanupControls>(
        find.byType(LegacyCleanupControls),
      );
      expect(controls.hasAnalysis, isTrue);
      expect(controls.amount, 100);
      expect(tester.getSize(find.byType(LegacyCleanupControls)).height, 156);
      await tester.tap(find.byTooltip('重置去灰'));
      await frames(tester);
      final reset = core.reviews.last.recipe;
      expect(object(reset['cleanup'])['amount'], 0);
      expect(reset['cleanupData'], isNull);
      expect(
        core.requests.where(
          (request) => request.operation == 'media.cleanupAnalyze',
        ),
        hasLength(1),
      );
      expect(
        core.requests.where((request) => request.operation == 'draft.save'),
        isEmpty,
      );
      await tester.tap(find.text('取消'));
      await frames(tester);
      expect(undoEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
      await close(tester, fixture.state);
    },
  );
}
