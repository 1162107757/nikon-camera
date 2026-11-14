import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editing_viewport.dart';
import 'package:huevia/retouch_original_controls.dart';
import 'package:huevia/retouch_workspace.dart';
import 'package:huevia/retouch_blemish_review.dart';
import 'package:huevia/selection_workspace.dart';
import 'package:huevia/theme.dart';

import 'retouch_workspace_test.dart' show PortraitMenuCore;
import 'selection_editor_test.dart' show seed, box;

Json _copy(Object? value) => object(jsonDecode(jsonEncode(value)));

class _Core extends PortraitMenuCore {
  _Core(super.root);
  int skinAnalysisPixels = 100;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'local.describe') {
      calls.add((operation, _copy(payload)));
      return {
        ...snapshots[payload['localData']]!,
        'regions': snapshots[payload['localData']]!['regions'] ?? [],
      };
    }
    if (operation == 'local.seedRegion') {
      calls.add((operation, _copy(payload)));
      return {
        'seed': seed(shapes: [box()]),
      };
    }
    if (operation == 'local.change') {
      calls.add((operation, _copy(payload)));
      final next = _copy(snapshots[payload['localData']]);
      final region = _copy(payload['value']);
      next['regions'] = [
        for (final old in (next['regions'] as List? ?? []))
          if (object(old)['id'] != region['id']) old,
        region,
      ];
      next['localData'] = 'region-${serial++}';
      snapshots[next['localData'] as String] = next;
      return next;
    }
    if (operation == 'media.retouchAnalyze' &&
        payload['mode'] == 'autoBlemish') {
      calls.add((operation, _copy(payload)));
      return {
        ...snapshots[payload['localData']]!,
        'regionId': payload['regionId'] ?? '',
        'healCandidates': [
          {
            'sx': .3,
            'sy': .2,
            'tx': .4,
            'ty': .6,
            'radius': .03,
            'feather': .2,
            'enabled': true,
          },
          {
            'sx': .7,
            'sy': .2,
            'tx': .65,
            'ty': .55,
            'radius': .04,
            'feather': .2,
            'enabled': true,
          },
        ],
      };
    }
    if (operation == 'media.retouchChange' && payload['action'] == 'addHeals') {
      calls.add((operation, _copy(payload)));
      final next = _copy(snapshots[payload['localData']]);
      final portrait = object(next['portrait']);
      portrait['heals'] = [
        ...portrait['heals'] as List,
        ...object(payload['value'])['heals'] as List,
      ];
      next['portrait'] = portrait;
      next['localData'] = 'heals-${serial++}';
      snapshots[next['localData'] as String] = next;
      return {...next, 'regionId': payload['regionId'] ?? ''};
    }
    final result = await super.call(operation, payload, jobId);
    if (operation == 'media.retouchAnalyze' && payload['mode'] == 'skin') {
      final next = _copy(result);
      final portrait = object(next['portrait']);
      portrait['skinPixels'] = skinAnalysisPixels;
      next['portrait'] = portrait;
      snapshots[next['localData'] as String] = next;
      return {...next, 'regionId': payload['regionId'] ?? ''};
    }
    return operation.startsWith('media.retouch')
        ? {...result, 'regionId': payload['regionId'] ?? ''}
        : result;
  }
}

class _Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

class _Fixture {
  _Fixture() {
    final temp = Directory.systemTemp.createTempSync('huevia-inline-portrait-');
    root = Directory(temp.resolveSymbolicLinksSync());
    Directory('${root.path}/previews').createSync();
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAEklEQVR4nGMQWm3yHx9mGBkKAKq5fAFPbl0bAAAAAElFTkSuQmCC',
    );
    File('${root.path}/previews/portrait.png').writeAsBytesSync(bytes);
    borrowed = File('${root.path}/previews/editor-borrowed.png')
      ..writeAsBytesSync(bytes);
    original = File('${root.path}/original.png')..writeAsBytesSync(bytes);
    core = _Core(root.path);
    state = AppState(core)
      ..session = {
        'user': {'id': 'alice'},
      };
    recipe = {...Recipe().data, 'localData': 'start'};
    final scene = TransformationController(
      Matrix4.diagonal3Values(4, 4, 1)..setTranslationRaw(-632, -312, 0),
    );
    viewport.capture(
      scene,
      viewport: const Size(400, 400),
      imageRect: const Rect.fromLTWH(0, 0, 400, 400),
    );
    scene.dispose();
  }
  late Directory root;
  late File borrowed, original;
  late _Core core;
  late AppState state;
  late Json recipe;
  final viewport = EditingViewportState();
  final routes = _Routes();
  final finished = <Json?>[];
  final held = <Completer<void>>[];
  VoidCallback? back;
  dynamic page;
  Completer<void> hold(String key) {
    final gate = Completer<void>();
    held.add(gate);
    core.gates[key] = gate;
    return gate;
  }

  int count(String op) => core.calls.where((call) => call.$1 == op).length;
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String message,
) async {
  for (var tick = 0; tick < 180; tick++) {
    await tester.pump(const Duration(milliseconds: 25));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    if (ready()) return;
  }
  fail(message);
}

Future<_Fixture> _open(
  WidgetTester tester, {
  void Function(_Fixture fixture)? configure,
}) async {
  tester.view.physicalSize = const Size(400, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final f = _Fixture();
  configure?.call(f);
  addTearDown(() async {
    for (final gate in f.held) {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    f.state.dispose();
    tester.binding.imageCache.clear();
    tester.binding.imageCache.clearLiveImages();
    await tester.runAsync(() => f.root.delete(recursive: true));
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.dark),
      navigatorObservers: [f.routes],
      home: StatefulBuilder(
        builder: (context, refresh) => Scaffold(
          appBar: AppBar(title: const Text('同一张照片')),
          body: f.finished.isNotEmpty
              ? const SizedBox()
              : RetouchWorkspace(
                  state: f.state,
                  photo: Photo(f.original.path, '人像', const {
                    'width': 8,
                    'height': 8,
                  }),
                  owner: 'alice',
                  recipe: f.recipe,
                  isCurrent: () => true,
                  embedded: true,
                  viewportState: f.viewport,
                  initialFrame: {
                    'path': f.borrowed.path,
                    'width': 8,
                    'height': 8,
                    'sourceWidth': 8,
                    'sourceHeight': 8,
                    'recipe': f.recipe,
                    '_detailRecipe': f.recipe,
                    '_borrowedEditorFrame': true,
                  },
                  onBackReady: (value) => f.back = value,
                  onFinished: (value) => refresh(() => f.finished.add(value)),
                  embeddedLayoutBuilder: (_, photo, panel) => Column(
                    children: [
                      SizedBox(height: 320, child: photo),
                      Expanded(child: panel),
                    ],
                  ),
                ),
        ),
      ),
    ),
  );
  f.page = tester.state(find.byType(RetouchWorkspace));
  expect(f.back, isNotNull);
  await _until(
    tester,
    () => f.page.busy == false && f.page.data != null,
    'Initial portrait never became ready.',
  );
  return f;
}

Future<void> _tool(WidgetTester tester, _Fixture f, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await _until(
    tester,
    () => f.page.busy == false && f.page.toolIntent != 'overview',
    'Tool $label did not become ready.',
  );
}

List<Json> _skinAnalyses(_Fixture fixture) => fixture.core.calls
    .where(
      (call) => call.$1 == 'media.retouchAnalyze' && call.$2['mode'] == 'skin',
    )
    .map((call) => call.$2)
    .toList();

Future<void> _backToTools(WidgetTester tester, _Fixture fixture) async {
  fixture.back!();
  await _until(
    tester,
    () => fixture.page.toolIntent == 'overview' && fixture.page.busy == false,
    'Back must return to the same portrait tool panel.',
  );
  expect(fixture.finished, isEmpty);
}

Future<void> _ioFrames(WidgetTester tester) async {
  for (var tick = 0; tick < 5; tick++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets(
    'Allocated empty skin masks auto-analyze before a pending personal tone-card request',
    (tester) async {
      final f = await _open(
        tester,
        configure: (fixture) {
          (fixture.core.snapshots['start']!['portrait'] as Json)['skinPixels'] =
              0;
          fixture.core.skinAnalysisPixels = 64;
        },
      );
      final cards = f.hold('toneCards.list/');
      await _tool(tester, f, '皮肤');
      await _until(
        tester,
        () => f.count('toneCards.list') == 1,
        'The unrelated personal tone-card request must actually be pending.',
      );
      expect(cards.isCompleted, false);
      expect(_skinAnalyses(f), hasLength(1));
      expect(object(f.page.data['portrait'])['hasSkinMask'], true);
      expect(object(f.page.data['portrait'])['skinPixels'], 64);
      expect(f.page.busy, false);
      expect(f.page.toolIntent, 'skin');
      expect(f.routes.pushes, 1);
      expect(f.finished, isEmpty);
      expect(f.core.calls.where((call) => call.$1 == 'draft.save'), isEmpty);
      cards.complete();
      await _ioFrames(tester);
      expect(_skinAnalyses(f), hasLength(1));
    },
  );

  testWidgets(
    'A skin mask at the native minimum is reused while switching and re-entering tools',
    (tester) async {
      final f = await _open(
        tester,
        configure: (fixture) {
          (fixture.core.snapshots['start']!['portrait'] as Json)['skinPixels'] =
              32;
        },
      );
      await _tool(tester, f, '皮肤');
      await _backToTools(tester, f);
      await _tool(tester, f, '面部');
      await _backToTools(tester, f);
      await _tool(tester, f, '皮肤');
      expect(_skinAnalyses(f), isEmpty);
      expect(object(f.page.data['portrait'])['skinPixels'], 32);
      expect(f.routes.pushes, 1);
    },
  );

  testWidgets(
    'One empty skin result does not loop on rebuild and explicit re-entry can retry',
    (tester) async {
      final f = await _open(
        tester,
        configure: (fixture) {
          (fixture.core.snapshots['start']!['portrait'] as Json)['skinPixels'] =
              0;
          fixture.core.skinAnalysisPixels = 0;
        },
      );
      await _tool(tester, f, '皮肤');
      expect(_skinAnalyses(f), hasLength(1));
      expect(object(f.page.data['portrait'])['hasSkinMask'], true);
      expect(object(f.page.data['portrait'])['skinPixels'], 0);
      expect(f.page.notice, contains('未找到可用的皮肤范围'));
      await _ioFrames(tester);
      expect(
        _skinAnalyses(f),
        hasLength(1),
        reason:
            'A completed empty result must not schedule itself from builds.',
      );
      await _backToTools(tester, f);
      await _tool(tester, f, '皮肤');
      expect(_skinAnalyses(f), hasLength(2));
      await _ioFrames(tester);
      expect(_skinAnalyses(f), hasLength(2));
      expect(f.finished, isEmpty);
    },
  );

  testWidgets(
    'Cancelling automatic skin analysis permits a new entry and rejects the late first result',
    (tester) async {
      final f = await _open(
        tester,
        configure: (fixture) {
          (fixture.core.snapshots['start']!['portrait'] as Json)['skinPixels'] =
              0;
          fixture.core.skinAnalysisPixels = 64;
        },
      );
      final first = f.hold('media.retouchAnalyze/skin');
      await tester.ensureVisible(find.text('皮肤'));
      await tester.tap(find.text('皮肤'));
      await _until(
        tester,
        () => _skinAnalyses(f).length == 1 && f.page.busy,
        'The first automatic analysis must be genuinely held.',
      );
      final blocked = f.core.blockedJobs.single;
      await _backToTools(tester, f);
      expect(first.isCompleted, false);
      expect(f.core.cancelledJobs, contains(blocked));
      await _tool(tester, f, '皮肤');
      expect(_skinAnalyses(f), hasLength(2));
      expect(object(f.page.data['portrait'])['skinPixels'], 64);
      final accepted = f.page.data['localData'];
      first.complete();
      await _ioFrames(tester);
      expect(f.page.data['localData'], accepted);
      expect(f.page.toolIntent, 'skin');
      expect(f.finished, isEmpty);
      expect(f.routes.pushes, 1);
    },
  );

  testWidgets(
    'Single-finger overview skin and face navigation moves the zoomed photograph without editing it',
    (tester) async {
      final f = await _open(tester);
      for (final tool in ['overview', '皮肤', '面部']) {
        if (tool != 'overview') await _tool(tester, f, tool);
        final before = f.viewport.focus;
        final scale = f.page.viewport.value.getMaxScaleOnAxis() as double;
        final mutations = f.core.calls
            .where(
              (call) =>
                  call.$1 == 'media.retouchChange' ||
                  call.$1 == 'media.retouchHeal' ||
                  call.$1 == 'media.retouchPatch',
            )
            .length;
        await tester.drag(
          find.byType(RetouchOriginalPhotoStage),
          const Offset(36, 20),
        );
        await _ioFrames(tester);
        expect(
          (f.viewport.focus - before).distance,
          greaterThan(.001),
          reason: tool,
        );
        expect(f.page.viewport.value.getMaxScaleOnAxis(), closeTo(scale, 1e-8));
        expect(
          f.core.calls
              .where(
                (call) =>
                    call.$1 == 'media.retouchChange' ||
                    call.$1 == 'media.retouchHeal' ||
                    call.$1 == 'media.retouchPatch',
              )
              .length,
          mutations,
          reason: tool,
        );
        if (tool != 'overview') await _backToTools(tester, f);
      }
      expect(f.routes.pushes, 1);
      expect(f.finished, isEmpty);
    },
  );

  testWidgets(
    'A face-selection brush stroke keeps priority over zoomed single-finger panning',
    (tester) async {
      final f = await _open(tester);
      await _tool(tester, f, '面部');
      await tester.ensureVisible(find.text('选区'));
      await tester.tap(find.text('选区'));
      await tester.pump();
      await tester.tap(find.text('补选'));
      await tester.pump();
      final before = f.viewport.focus;
      final scale = f.page.viewport.value.getMaxScaleOnAxis() as double;
      final stage = find.byType(RetouchOriginalPhotoStage);
      await tester.dragFrom(
        tester.getRect(stage).center - const Offset(30, 0),
        const Offset(60, 20),
      );
      await _until(
        tester,
        () =>
            f.page.busy == false &&
            f.core.calls.any(
              (call) =>
                  call.$1 == 'media.retouchChange' &&
                  call.$2['action'] == 'faceStroke',
            ),
        'The real canvas stroke must submit its selected face brush command.',
      );
      final stroke = f.core.calls
          .singleWhere(
            (call) =>
                call.$1 == 'media.retouchChange' &&
                call.$2['action'] == 'faceStroke',
          )
          .$2;
      expect(stroke['index'], 0);
      expect(object(stroke['value'])['erase'], false);
      expect(
        (object(stroke['value'])['points'] as List).length,
        greaterThanOrEqualTo(4),
      );
      expect(f.viewport.focus.dx, closeTo(before.dx, 1e-8));
      expect(f.viewport.focus.dy, closeTo(before.dy, 1e-8));
      expect(f.page.viewport.value.getMaxScaleOnAxis(), closeTo(scale, 1e-8));
      expect(
        f.core.calls.where(
          (call) =>
              call.$1 == 'media.retouchHeal' || call.$1 == 'media.retouchPatch',
        ),
        isEmpty,
      );
      expect(f.finished, isEmpty);
    },
  );

  testWidgets(
    'Natural intent and Back are immediate while native work is held and never exit the parent portrait',
    (tester) async {
      final f = await _open(tester);
      final frame = f.page.frame['path'], data = f.page.data['localData'];
      final gate = f.hold('media.retouchChange/');
      await tester.tap(find.text('自然精修'));
      await _until(
        tester,
        () => f.core.blockedJobs.isNotEmpty,
        'Natural native operation was not reached.',
      );
      expect(f.page.toolIntent, 'natural');
      expect(find.byTooltip('返回人像工具'), findsOneWidget);
      f.back!();
      await tester.pump();
      expect(f.finished, isEmpty);
      expect(f.page.toolIntent, 'overview');
      expect(f.page.data['localData'], data);
      expect(f.page.frame['path'], frame);
      expect(f.core.cancelledJobs, contains(f.core.blockedJobs.single));
      gate.complete();
      await _until(
        tester,
        () => f.page.job == null,
        'Late natural result was not retired.',
      );
      expect(f.page.data['localData'], data);
      expect(f.page.frame['path'], frame);
      expect(f.routes.pushes, 1);
      f.back!();
      await tester.pump();
      expect(f.finished, [null]);
      expect(f.borrowed.existsSync(), isTrue);
      expect(f.recipe['localData'], 'start');
    },
  );

  testWidgets(
    'Skin face body and repair switch only panels while retaining the same source detail and cached photograph',
    (tester) async {
      final f = await _open(tester);
      final initialState = f.page;
      final pose = f.viewport.focus;
      final frame = f.page.frame['path'];
      final previews =
          f.count('media.reviewPreview') + f.count('media.localPreview');
      for (final tool in ['皮肤', '面部', '塑形', '修补']) {
        await _tool(tester, f, tool);
        expect(
          identical(tester.state(find.byType(RetouchWorkspace)), initialState),
          isTrue,
        );
        expect(f.page.frame['path'], frame);
        expect(f.viewport.focus.dx, closeTo(pose.dx, 1e-8));
        expect(f.viewport.focus.dy, closeTo(pose.dy, 1e-8));
        f.back!();
        await _until(
          tester,
          () => f.page.toolIntent == 'overview' && !f.page.busy,
          'Back did not return to the parent tool panel.',
        );
        expect(f.finished, isEmpty);
        expect(f.viewport.focus.dx, closeTo(pose.dx, 1e-8));
        expect(f.viewport.focus.dy, closeTo(pose.dy, 1e-8));
      }
      expect(f.count('media.retouchDescribe'), 1);
      expect(
        f.count('media.reviewPreview') + f.count('media.localPreview'),
        previews,
      );
      expect(f.routes.pushes, 1);
      expect(f.page.viewport.value.getMaxScaleOnAxis(), greaterThan(3.9));
    },
  );

  testWidgets(
    'Inline repair owns one child transaction and final Apply leaves the original and borrowed frame untouched',
    (tester) async {
      final f = await _open(tester);
      await _tool(tester, f, '修补');
      final stage = find.byType(RetouchOriginalPhotoStage);
      final stroke = await tester.startGesture(tester.getCenter(stage));
      await stroke.moveBy(const Offset(25, 15));
      await stroke.up();
      await _until(
        tester,
        () => !f.page.busy && f.page.data['patchCount'] == 2,
        'The repair was not accepted.',
      );
      await tester.tap(find.text('应用修补'));
      await _until(
        tester,
        () => f.page.patchChildOpen == false,
        'Repair child did not merge.',
      );
      expect(f.page.undo, hasLength(1));
      expect(f.finished, isEmpty);
      expect(f.count('media.retouchDescribe'), 1);
      await _tool(tester, f, '修补');
      final held = f.hold('media.retouchPatch/');
      final second = await tester.startGesture(tester.getCenter(stage));
      await second.moveBy(const Offset(30, 10));
      await second.up();
      await _until(
        tester,
        () => f.core.blockedJobs.isNotEmpty,
        'The pending repair was not held.',
      );
      f.back!();
      await tester.pump();
      held.complete();
      await _until(
        tester,
        () => f.page.job == null && !f.page.busy,
        'Cancelled repair did not retire.',
      );
      expect(f.page.data['patchCount'], 2);
      expect(f.page.undo, hasLength(1));
      await tester.tap(find.text('应用人像'));
      await tester.pump();
      expect(f.finished.single!['patchCount'], 2);
      expect(f.recipe['localData'], 'start');
      expect(f.borrowed.existsSync(), isTrue);
      expect(f.original.readAsBytesSync(), f.borrowed.readAsBytesSync());
      expect(f.count('draft.save'), 0);
      expect(f.routes.pushes, 1);
    },
  );

  testWidgets(
    'Mask selection and regional refinement remain inline and merge a single complete parent undo',
    (tester) async {
      final f = await _open(tester);
      await _tool(tester, f, '面部');
      await tester.tap(find.bySemanticsLabel('涂抹范围'));
      await _until(
        tester,
        () => find.byType(SelectionWorkspace).evaluate().isNotEmpty,
        'Selection was not embedded.',
      );
      final selection = tester.widget<SelectionWorkspace>(
        find.byType(SelectionWorkspace),
      );
      expect(selection.embedded, isTrue);
      expect(selection.viewportState, same(f.viewport));
      expect(selection.frame['path'], isNot(f.borrowed.path));
      final finish = find
          .ancestor(of: find.text('完成'), matching: find.byType(FilledButton))
          .first;
      await _until(
        tester,
        () => tester.widget<FilledButton>(finish).onPressed != null,
        'Real selection mask never became confirmable.',
      );
      await tester.tap(finish);
      await _until(
        tester,
        () => f.page.regionStart != null && !f.page.busy,
        'Regional portrait did not accept the mask.',
      );
      expect(find.byType(RetouchWorkspace), findsOneWidget);
      expect(find.byType(SelectionWorkspace), findsNothing);
      expect(f.page.editingRegionId, 'fixed-region');
      expect(f.routes.pushes, 1);
      await tester.tap(find.text('应用局部'));
      await _until(
        tester,
        () => f.page.regionStart == null && !f.page.busy,
        'Regional child did not merge into the parent.',
      );
      expect(f.page.editingRegionId, isNull);
      expect(f.page.data['regions'], hasLength(1));
      expect(f.page.undo, hasLength(1));
      expect(f.finished, isEmpty);
      expect(f.borrowed.existsSync(), isTrue);
      expect(f.count('draft.save'), 0);
    },
  );

  testWidgets(
    'Blemish review shares the photograph and only confirmed candidate indices install one heal batch',
    (tester) async {
      final f = await _open(tester);
      await _tool(tester, f, '皮肤');
      Future<void> review() async {
        await tester.ensureVisible(find.text('自动祛痘'));
        await tester.tap(find.text('自动祛痘'));
        await _until(
          tester,
          () => find.byType(RetouchBlemishReview).evaluate().isNotEmpty,
          'Blemish review never appeared inline.',
        );
        await _until(
          tester,
          () =>
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('blemish-confirm')),
                  )
                  .onPressed !=
              null,
          'The actual candidate photograph never decoded.',
        );
      }

      await review();
      final config = tester.widget<RetouchBlemishReview>(
        find.byType(RetouchBlemishReview),
      );
      expect(config.embedded, isTrue);
      expect(config.viewportState, same(f.viewport));
      await tester.tap(find.byKey(const ValueKey('blemish-checkbox-0')));
      expect(f.core.calls.where((c) => c.$2['action'] == 'addHeals'), isEmpty);
      expect(f.routes.pushes, 1);
      f.back!();
      await _until(
        tester,
        () => f.page.inlineBlemishes == null && !f.page.busy,
        'Candidate cancellation did not restore the same skin panel.',
      );
      expect(object(f.page.data['portrait'])['heals'], hasLength(2));
      expect(f.page.undo, isEmpty);
      await review();
      await tester.tap(find.byKey(const ValueKey('blemish-checkbox-0')));
      await tester.tap(find.byKey(const ValueKey('blemish-confirm')));
      await _until(
        tester,
        () =>
            f.page.inlineBlemishes == null &&
            !f.page.busy &&
            (object(f.page.data['portrait'])['heals'] as List).length == 3,
        'The confirmed candidate did not install its single batch.',
      );
      final applied = f.core.calls.singleWhere(
        (c) => c.$2['action'] == 'addHeals',
      );
      expect(object(applied.$2['value'])['heals'], [
        {
          'sx': .7,
          'sy': .2,
          'tx': .65,
          'ty': .55,
          'radius': .04,
          'feather': .2,
          'enabled': true,
        },
      ]);
      expect(f.page.undo, hasLength(1));
      expect(f.finished, isEmpty);
      expect(f.routes.pushes, 1);
      expect(f.borrowed.existsSync(), isTrue);
    },
  );
}
