import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/editing_viewport.dart';
import 'package:huevia/local_adjustments.dart';
import 'package:huevia/retouch_workspace.dart';
import 'package:huevia/retouch_original_controls.dart';
import 'package:huevia/split_compare.dart';
import 'package:huevia/theme.dart';

import 'editor_color_workspace_test.dart' show ColorWorkspaceCore, tool;
import 'editor_realtime_preview_test.dart' show RealtimeCore, RealtimeState;
import 'retouch_workspace_test.dart' show PortraitMenuCore;

// Navigation and preview reuse only. Actual photo pixels have separate native tests.
class _ToolsCore extends ColorWorkspaceCore {
  _ToolsCore({this.initialRecipe}) {
    root = Directory(root).resolveSymbolicLinksSync();
    portrait = PortraitMenuCore(root);
    File('$root/previews/portrait.png').writeAsBytesSync(RealtimeCore.png);
  }
  late final PortraitMenuCore portrait;
  final Json? initialRecipe;

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'draft.load' && initialRecipe != null) {
      return {'sourceSha': 'fixture-sha', 'recipe': initialRecipe};
    }
    if (operation == 'media.borderInfo') return {'model': 'Nikon Z 6II'};
    if (operation.startsWith('media.retouch') ||
        operation.startsWith('toneCards.') ||
        operation == 'media.localPreview') {
      final result = await portrait.call(operation, payload, jobId);
      if (result['path'] != null) return {...result, 'width': 1, 'height': 1};
      return result;
    }
    return super.call(operation, payload, jobId);
  }
}

// These real 1px PNGs exercise image-handle ownership and host ordering, while
// mocked native dimensions exercise the detail protocol. They are not a device
// photo-quality or native-pixel test.
class _DetailToolsCore extends _ToolsCore {
  _DetailToolsCore()
    : super(
        initialRecipe: {
          ...Recipe().data,
          'localData': 'start',
          'geometry': <String, dynamic>{},
          'border': <String, dynamic>{},
        },
      );

  static const sourceSha =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final details = <(String, Json)>[];
  int detailSerial = 0;

  String detailFile(List<int> bytes) {
    final name =
        '10000000-0000-4000-8000-${(++detailSerial).toString().padLeft(12, '0')}.png';
    return (File('$root/previews/$name')..writeAsBytesSync(bytes)).path;
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'draft.load') {
      return {'sourceSha': sourceSha, 'recipe': initialRecipe};
    }
    if (operation == 'local.describe') {
      return {
        'localData': payload['localData'] ?? '',
        'sha256': payload['localData'] ?? '',
        'regions': [],
      };
    }
    if (operation == 'source.inspect') return {'sourceSha': sourceSha};
    if (operation == 'media.detailRender') {
      details.add((operation, object(payload)));
      return {
        'path': detailFile([1]),
        'width': 4096,
        'height': 4096,
        'sourceSha': sourceSha,
        'detailToken': 'tool-detail-${details.length}',
        'temporary': true,
        'fullResolution': true,
      };
    }
    if (operation == 'media.detailTile') {
      details.add((operation, object(payload)));
      return {
        'path': detailFile(RealtimeCore.png),
        'width': 1,
        'height': 1,
        'sourceWidth': 4096,
        'sourceHeight': 4096,
        'sourceSha': sourceSha,
        'detailToken': payload['detailToken'],
        'temporary': true,
        'region': payload['region'],
      };
    }
    final result = await super.call(operation, payload, jobId);
    if (operation == 'draft.save') return {...result, 'sourceSha': sourceSha};
    if (operation == 'media.preview' ||
        operation == 'media.reviewPreview' ||
        operation == 'media.localPreview') {
      return {
        ...result,
        'sourceSha': sourceSha,
        'sourceWidth': 4096,
        'sourceHeight': 4096,
      };
    }
    return result;
  }
}

class _HeldLocalQueue extends LocalAdjustmentQueue {
  _HeldLocalQueue(HueviaCore core, Json initial)
    : super(
        core: core,
        initial: initial,
        isCurrent: () => true,
        onAccepted: (_) {},
      );
  final gate = Completer<Json>();
  @override
  Future<Json> get settled => gate.future;
}

class _Routes extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  final clock = Stopwatch()..start();
  while (!ready() && clock.elapsed < const Duration(seconds: 10)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 8)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), true, reason: reason);
}

Future<({dynamic editor, EditingViewportState viewport, _Routes routes})> _open(
  WidgetTester tester,
  _ToolsCore core, {
  Size size = const Size(400, 760),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final viewport = EditingViewportState(), routes = _Routes();
  final state = RealtimeState(core);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('cc.huevia/events'),
        (_) async => null,
      );
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.dark),
      navigatorObservers: [routes],
      home: EditorPage(
        state: state,
        photo: Photo(
          core.source.resolveSymbolicLinksSync(),
          '工具切换测试.png',
          const {'width': 1, 'height': 1},
        ),
        viewportState: viewport,
      ),
    ),
  );
  final dynamic editor = tester.state(find.byType(EditorPage));
  final adjustmentTab = find.ancestor(
    of: find.text('调节'),
    matching: find.byType(InkWell),
  );
  await _until(
    tester,
    () =>
        editor.restored == true &&
        editor.preview != null &&
        find.byType(SplitCompare).evaluate().length == 1 &&
        tester.widget<SplitCompare>(find.byType(SplitCompare)).effect ==
            editor.preview &&
        adjustmentTab.evaluate().length == 1 &&
        tester.widget<InkWell>(adjustmentTab).onTap != null,
    'Base editor must display its first accepted photo and enable navigation',
  );
  addTearDown(() async {
    for (final gate in core.portrait.gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    state.dispose();
    tester.binding.imageCache.clear();
    tester.binding.imageCache.clearLiveImages();
    final directory = Directory(core.root).resolveSymbolicLinksSync();
    final temp = Directory.systemTemp.resolveSymbolicLinksSync();
    expect(
      directory.startsWith(
        '$temp${Platform.pathSeparator}huevia-realtime-preview-',
      ),
      true,
    );
    Directory(directory).deleteSync(recursive: true);
  });
  return (editor: editor, viewport: viewport, routes: routes);
}

TransformationController _transform(WidgetTester tester) => tester
    .widget<InteractiveViewer>(
      find
          .descendant(
            of: find.byType(SplitCompare),
            matching: find.byType(InteractiveViewer),
          )
          .first,
    )
    .transformationController!;

void _zoom(WidgetTester tester) {
  final transform = _transform(tester);
  final size = tester.getSize(find.byType(SplitCompare));
  final rect = Alignment.center.inscribe(
    Size.square(size.shortestSide),
    Offset.zero & size,
  );
  final point = Offset(
    rect.left + .62 * rect.width,
    rect.top + .41 * rect.height,
  );
  transform.value = Matrix4.identity()
    ..setEntry(0, 0, 3)
    ..setEntry(1, 1, 3)
    ..setEntry(0, 3, size.width / 2 - 3 * point.dx)
    ..setEntry(1, 3, size.height / 2 - 3 * point.dy);
}

void _sameFocus(EditingViewportState state, Offset expected) {
  expect(state.focus.dx, closeTo(expected.dx, 1e-6));
  expect(state.focus.dy, closeTo(expected.dy, 1e-6));
  expect(state.zoom, greaterThan(1));
}

void main() {
  for (final apply in [false, true]) {
    testWidgets(
      'Accepted HD crosses portrait entry and unchanged ${apply ? 'Apply' : 'Cancel'} without a base render',
      (tester) async {
        final core = _DetailToolsCore();
        final h = await _open(tester, core);
        await tester.tap(find.text('调节').hitTestable());
        await tester.pump();
        _zoom(tester);
        await _until(
          tester,
          () => h.editor.effectDetails?.tile != null,
          'The accepted editor photo must have a decoded HD tile',
        );
        final accepted = h.editor.preview;
        final overlay = h.editor.displayedOverlay;
        final revision = h.editor.revision;
        final generation = h.editor.previewGeneration;
        final fullRenders = core.details
            .where((call) => call.$1 == 'media.detailRender')
            .length;
        final held = _HeldLocalQueue(core, object(h.editor.localState));
        h.editor.localQueue.close();
        h.editor.localQueue = held;
        final describe = Completer<void>();
        core.portrait.gates['media.retouchDescribe/'] = describe;
        addTearDown(() {
          if (!held.gate.isCompleted) held.gate.complete(held.state);
          if (!describe.isCompleted) describe.complete();
        });
        await tester.tap(find.text('人像').hitTestable());
        await tester.pump();
        expect(find.byType(RetouchWorkspace), findsNothing);
        expect(h.editor.retouchDetailHandoffPending, isTrue);
        expect(h.editor.effectDetails.enabled, isTrue);
        expect(
          h.editor.effectDetails.tile,
          isNotNull,
          reason: 'Settling the launcher must keep the accepted HD visible',
        );
        expect(h.editor.revision, revision);
        held.gate.complete(held.state);
        await tester.pump();
        expect(find.byType(RetouchWorkspace), findsOneWidget);
        final dynamic portrait = tester.state(find.byType(RetouchWorkspace));
        final dynamic child = portrait.detailPreviewKey.currentState;
        expect(child, isNotNull);
        expect(
          child.controller.tile,
          isNotNull,
          reason: 'The first child layout must already expose the HD clone',
        );
        expect(child.controller.tile.frameIdentity, accepted);
        expect(child.controller.tile.sourceSha, _DetailToolsCore.sourceSha);
        expect(
          h.editor.effectDetails.enabled,
          isFalse,
          reason: 'The mounted child must own all new detail requests',
        );
        expect(
          core.details.where((call) => call.$1 == 'media.detailRender').length,
          fullRenders,
          reason: 'The same-profile child must borrow the existing full file',
        );
        if (apply) {
          describe.complete();
          await _until(
            tester,
            () => portrait.busy == false && portrait.data != null,
            'The unchanged portrait model must become applicable',
          );
        }
        final completedBeforeExit = core.returnedFrames.length;
        core.requests.clear();
        if (apply) {
          await tester.tap(find.text('应用人像').hitTestable());
        } else {
          // Cancellation keeps its existing immediate semantics even while the
          // child is still waiting for its first model description.
          await tester.tap(find.byTooltip('返回上一级工具'));
        }
        await tester.pump();
        expect(h.editor.embeddedTool, isNull);
        expect(h.editor.preview, accepted);
        expect(h.editor.displayedOverlay, same(overlay));
        expect(h.editor.revision, revision);
        expect(h.editor.previewGeneration, generation);
        expect(
          h.editor.effectDetails.tile,
          isNotNull,
          reason:
              'The returning parent must expose its own independent HD clone',
        );
        expect(h.editor.effectDetails.tile.frameIdentity, accepted);
        expect(core.returnedFrames.length, completedBeforeExit);
        expect(
          core.requests.where(
            (request) =>
                request.operation == 'media.preview' ||
                request.operation == 'media.reviewPreview' ||
                request.operation == 'draft.save',
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final exit in ['取消', '应用']) {
    testWidgets(
      'Unchanged color tools retain accepted pixels and revisions on $exit',
      (tester) async {
        final core = _ToolsCore(
          initialRecipe: {
            ...Recipe().data,
            // Cleanup analysis is an actual recipe change, so seed its result.
            'cleanupData': 'analysis-fixture',
          },
        );
        final h = await _open(tester, core);
        await _until(
          tester,
          () =>
              h.editor.displayedRevision == h.editor.revision &&
              h.editor.detailRefreshPending == false &&
              h.editor.rendering == false,
          'The entry raster must be a settled, accepted photo',
        );
        await tester.tap(find.text('调节').hitTestable());
        await tester.pump();
        expect(
          h.editor.tab,
          1,
          reason: 'The no-op sequence must start on the adjustment strip',
        );
        _zoom(tester);
        final accepted = h.editor.preview;
        final overlay = h.editor.displayedOverlay;
        final revision = h.editor.revision;
        final generation = h.editor.previewGeneration;
        final details = h.editor.effectDetails;
        core.requests.clear();
        for (final name in ['曲线', 'HSL', '调色盘', '去灰']) {
          await tool(tester, name);
          expect(
            tester.widget<SplitCompare>(find.byType(SplitCompare)).effect,
            accepted,
          );
          expect(h.editor.effectDetails, same(details));
          expect(h.editor.detailRefreshPending, isFalse);
          await tester.tap(find.text(exit).hitTestable());
          await _until(
            tester,
            () =>
                h.editor.embeddedTool == null &&
                h.editor.colorToolActive == false &&
                find.byTooltip('返回相册').evaluate().isNotEmpty &&
                find
                    .byKey(const Key('legacy-color-controls-scroll'))
                    .evaluate()
                    .isEmpty,
            '$name must finish without regenerating the photo',
          );
          expect(
            h.editor.tab,
            1,
            reason: '$name must return to the visible adjustment strip',
          );
          expect(h.editor.preview, accepted);
          expect(h.editor.displayedOverlay, same(overlay));
          expect(h.editor.revision, revision);
          expect(h.editor.previewGeneration, generation);
          expect(h.editor.effectDetails, same(details));
          expect(h.editor.undo, isEmpty);
          expect(h.editor.redo, isEmpty);
        }
        expect(
          core.requests.where(
            (request) =>
                request.operation == 'media.preview' ||
                request.operation == 'media.reviewPreview' ||
                request.operation == 'media.cleanupAnalyze' ||
                request.operation == 'draft.save',
          ),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Color entry refreshes a frame whose preset and geometry differ at the same revision',
    (tester) async {
      final core = _ToolsCore();
      final h = await _open(tester, core);
      await _until(
        tester,
        () =>
            h.editor.detailRefreshPending == false &&
            h.editor.rendering == false,
        'The initial photo must finish rendering',
      );
      await tester.tap(find.text('调节').hitTestable());
      await tester.pump();
      final stale = h.editor.preview;
      final revision = h.editor.revision;
      // Revision equality alone cannot certify a frame restored from a snapshot.
      h.editor.recipe.data['presetId'] = 'different-profile';
      h.editor.recipe.data['geometry'] = {
        'left': 100000,
        'top': 0,
        'right': 900000,
        'bottom': 1000000,
      };
      core.requests.clear();
      await tool(tester, '曲线');
      expect(h.editor.preview, isNot(stale));
      expect(core.reviews, hasLength(1));
      expect(core.reviews.single.recipe['presetId'], 'different-profile');
      expect(object(core.reviews.single.recipe['geometry'])['left'], 100000);
      final accepted = h.editor.preview;
      await tester.tap(find.text('取消').hitTestable());
      await _until(
        tester,
        () =>
            h.editor.embeddedTool == null && h.editor.colorToolActive == false,
        'The refreshed entry photo must remain accepted on cancel',
      );
      expect(h.editor.preview, accepted);
      expect(h.editor.revision, revision);
      expect(core.reviews, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Border uses a centered fit without discarding the zoom between other tabs',
    (tester) async {
      final core = _ToolsCore();
      final h = await _open(tester, core);
      _zoom(tester);
      final focus = h.viewport.focus;
      final photo = tester.getRect(
        find.byKey(const Key('editor-photo-viewport')),
      );
      final transform = _transform(tester);
      final routes = h.routes.pushes;
      for (final label in ['调节', '边框', '滤镜', '调节']) {
        await tester.tap(find.text(label).hitTestable());
        await tester.pump();
        expect(h.routes.pushes, routes);
        expect(
          tester.getRect(find.byKey(const Key('editor-photo-viewport'))),
          photo,
        );
        _sameFocus(h.viewport, focus);
        if (label == '边框') {
          expect(_transform(tester), isNot(same(transform)));
          expect(_transform(tester).value, Matrix4.identity());
        } else {
          expect(_transform(tester), same(transform));
        }
        expect(transform.value.getMaxScaleOnAxis(), closeTo(3, 1e-6));
      }
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Border changes keep the full photo clear of information controls',
    (tester) async {
      final core = _ToolsCore();
      final h = await _open(tester, core);
      _zoom(tester);
      final viewport = find.byKey(const Key('editor-photo-viewport'));
      final photo = tester.getRect(viewport);
      final routes = h.routes.pushes;
      await tester.tap(find.text('边框').hitTestable());
      await tester.pump();
      await tester.tap(find.text('白底信息').hitTestable());
      await _until(
        tester,
        () => h.editor.displayedOverlay?['recipe']?['border']?['template'] == 3,
        'The bordered preview must be displayed',
      );
      expect(tester.getRect(viewport), photo);
      expect(_transform(tester).value, Matrix4.identity());

      final infoList = find.byKey(const ValueKey('border-information-list'));
      await tester.scrollUntilVisible(
        find.text('设置'),
        90,
        scrollable: find.descendant(
          of: infoList,
          matching: find.byType(Scrollable),
        ),
      continuous: true,
      );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('设置'));
    await tester.pumpAndSettle();
      await tester.tap(find.text('设置').hitTestable());
      await tester.pump();
      await tester.tap(find.text('信息').hitTestable());
      await tester.pump();
      final controls = find.byKey(const ValueKey('border-settings-body-1'));
      expect(
        tester.getTopLeft(controls).dy,
        greaterThanOrEqualTo(photo.bottom),
      );
      final firstField = find.descendant(
        of: controls,
        matching: find.byType(Checkbox),
      );
      await tester.tap(firstField.first.hitTestable());
      await _until(
        tester,
        () => h.editor.displayedOverlay?['recipe']?['border']?['visible'] == 62,
        'The edited border information must appear in the same fit',
      );
      expect(tester.getRect(viewport), photo);
      expect(_transform(tester).value, Matrix4.identity());
      expect(h.routes.pushes, routes);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('滤镜').hitTestable());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    },
  );
  testWidgets(
    'A near-square window does not change the photograph into a side column when a tool opens',
    (tester) async {
      final core = _ToolsCore();
      final h = await _open(tester, core, size: const Size(600, 630));
      await tester.tap(find.text('调节').hitTestable());
      await tester.pump();
      _zoom(tester);
      final before = tester.getRect(
        find.byKey(const Key('editor-photo-viewport')),
      );
      final focus = h.viewport.focus;
      final routes = h.routes.pushes;
      await tool(tester, '曲线');
      expect(h.routes.pushes, routes);
      expect(
        tester.getRect(find.byKey(const Key('editor-photo-viewport'))),
        before,
      );
      _sameFocus(h.viewport, focus);
      await tester.tap(find.text('取消').hitTestable());
      await _until(
        tester,
        () =>
            h.editor.embeddedTool == null &&
            find.byTooltip('返回相册').evaluate().isNotEmpty,
        'Curve controls must close on the same editor',
      );
      expect(
        tester.getRect(find.byKey(const Key('editor-photo-viewport'))),
        before,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Color tools retain the zoomed photo while the dedicated palette uses its own panel height',
    (tester) async {
      final core = _ToolsCore();
      final h = await _open(tester, core);
      await tester.tap(find.text('调节').hitTestable());
      await tester.pump();
      _zoom(tester);
      final focus = h.viewport.focus;
      final photo = tester.getRect(
        find.byKey(const Key('editor-photo-viewport')),
      );
      final routes = h.routes.pushes;
      for (final name in ['曲线', 'HSL', '调色盘', '去灰']) {
        await tool(tester, name);
        expect(
          h.routes.pushes,
          routes,
          reason: '$name must stay on the editor route',
        );
        final currentPhoto = tester.getRect(
          find.byKey(const Key('editor-photo-viewport')),
        );
        if (name == '调色盘') {
          // The approved dedicated palette hides the lower toolbar and sizes
          // its panel independently. Its photo must stay above that panel,
          // with the same horizontal extent and retained zoom/focus.
          expect(currentPhoto.topLeft, photo.topLeft);
          expect(currentPhoto.width, photo.width);
          expect(currentPhoto.height, greaterThanOrEqualTo(120));
          expect(find.byKey(const Key('palette-workspace')), findsOneWidget);
        } else {
          expect(currentPhoto, photo, reason: name);
        }
        _sameFocus(h.viewport, focus);
        await tester.tap(find.text('取消').hitTestable());
        await _until(
          tester,
          () =>
              h.editor.embeddedTool == null &&
              h.editor.colorToolActive == false &&
              find.byTooltip('返回相册').evaluate().isNotEmpty,
          '$name must return to the same editor',
        );
        _sameFocus(h.viewport, focus);
        expect(_transform(tester).value.getMaxScaleOnAxis(), closeTo(3, 1e-6));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Zoomed exposure enters portrait and patch inline without another prepare or blank photograph',
    (tester) async {
      final core = _ToolsCore();
      final h = await _open(tester, core);
      await tester.tap(find.text('调节').hitTestable());
      await tester.pump();
      _zoom(tester);
      final focus = h.viewport.focus;
      final photo = tester.getRect(
        find.byKey(const Key('editor-photo-viewport')),
      );
      final routes = h.routes.pushes;
      await tester.tap(find.text('人像').hitTestable());
      await _until(
        tester,
        () => find.byType(RetouchWorkspace).evaluate().isNotEmpty,
        'Portrait controls must attach inline',
      );
      final dynamic portrait = tester.state(find.byType(RetouchWorkspace));
      expect(
        portrait.frame,
        isNotNull,
        reason: 'Borrow the accepted editor frame immediately',
      );
      await _until(
        tester,
        () => portrait.busy == false && portrait.data != null,
        'Portrait must finish its first preparation',
      );
      expect(h.routes.pushes, routes);
      final portraitPhoto = tester.getRect(
        find.byKey(const Key('editor-photo-viewport')),
      );
      expect(portraitPhoto.topLeft, photo.topLeft);
      expect(portraitPhoto.width, photo.width);
      expect(portraitPhoto.height, greaterThan(photo.height));
      expect(
        tester.getSize(find.byType(RetouchOriginalDock)).height,
        lessThan(100),
        reason: 'The overview must fit its tool row and return unused panel space to the photograph',
      );
      _sameFocus(h.viewport, focus);
      final describes = core.portrait.calls
          .where((call) => call.$1 == 'media.retouchDescribe')
          .length;
      final accepted = portrait.frame['path'];
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      core.portrait.gates['media.localPreview/'] = gate;
      await tester.tap(find.text('修补').hitTestable());
      await tester.pump();
      expect(find.byType(RetouchWorkspace), findsOneWidget);
      expect(portrait.frame, isNotNull);
      expect(
        portrait.frame['path'],
        accepted,
        reason: 'Keep the accepted photograph while preparing a correct patch source',
      );
      expect(
        core.portrait.calls
            .where((call) => call.$1 == 'media.retouchDescribe')
            .length,
        describes,
      );
      expect(h.routes.pushes, routes);
      _sameFocus(h.viewport, focus);
      gate.complete();
      await _until(
        tester,
        () => portrait.busy == false,
        'Patch source preparation must settle',
      );
      await tester.tap(find.byTooltip('返回上一级工具'));
      await tester.pump();
      await tester.tap(find.byTooltip('返回上一级工具'));
      await _until(
        tester,
        () =>
            h.editor.embeddedTool == null &&
            find.byTooltip('返回相册').evaluate().isNotEmpty &&
            find.byType(SplitCompare).evaluate().isNotEmpty,
        'Parent portrait cancel must return to the same editor',
      );
      _sameFocus(h.viewport, focus);
      expect(_transform(tester).value.getMaxScaleOnAxis(), closeTo(3, 1e-6));
      expect(tester.takeException(), isNull);
    },
  );
}
