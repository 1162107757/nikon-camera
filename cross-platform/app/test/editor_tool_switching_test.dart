import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/editing_viewport.dart';
import 'package:huevia/retouch_workspace.dart';
import 'package:huevia/split_compare.dart';
import 'package:huevia/theme.dart';

import 'editor_color_workspace_test.dart' show ColorWorkspaceCore, tool;
import 'editor_realtime_preview_test.dart' show RealtimeCore, RealtimeState;
import 'retouch_workspace_test.dart' show PortraitMenuCore;

// Navigation and preview reuse only. Actual photo pixels have separate native tests.
class _ToolsCore extends ColorWorkspaceCore {
  _ToolsCore() {
    root = Directory(root).resolveSymbolicLinksSync();
    portrait = PortraitMenuCore(root);
    File('$root/previews/portrait.png').writeAsBytesSync(RealtimeCore.png);
  }
  late final PortraitMenuCore portrait;

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
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
  await _until(
    tester,
    () => editor.restored == true && editor.preview != null,
    'Base editor must accept its first preview',
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
  testWidgets(
    'Filter adjustment and border tabs keep the same zoomed photo and route',
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
        expect(_transform(tester), same(transform));
        expect(
          tester.getRect(find.byKey(const Key('editor-photo-viewport'))),
          photo,
        );
        _sameFocus(h.viewport, focus);
        expect(transform.value.getMaxScaleOnAxis(), closeTo(3, 1e-6));
      }
      expect(tester.takeException(), isNull);
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
    'Curve HSL palette and cleanup replace only controls and retain the zoomed photo viewport',
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
        expect(
          tester.getRect(find.byKey(const Key('editor-photo-viewport'))),
          photo,
        );
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
