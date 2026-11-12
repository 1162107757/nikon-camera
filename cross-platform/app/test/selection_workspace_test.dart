import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/selection_mask.dart';
import 'package:huevia/selection_workspace.dart';
import 'package:huevia/theme.dart';

import 'editor_workspace_test.dart' show WorkspaceCore, WorkspaceState;
import 'selection_editor_test.dart' show seed, dot;

class SelectionCore extends WorkspaceCore {
  SelectionCore(super.directory);
  Completer<Json>? pending;
  Json result(Json value) => {
    'localData': 'validated-tentative-local-data',
    'sha256': 'c' * 64,
    'regions': [value],
  };
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'local.change') {
      calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
      return pending?.future ?? Future.value(result(object(payload['value'])));
    }
    return super.call(operation, payload, jobId);
  }
}

class SelectionHarness {
  SelectionHarness(this.core, this.state, this.frame);
  final SelectionCore core;
  final WorkspaceState state;
  final String frame;
  final results = <SelectionResult?>[];
  bool closed = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<void> cleanup(WidgetTester tester, SelectionHarness h) async {
    if (h.closed) return;
    h.closed = true;
    if (h.core.pending != null && !h.core.pending!.isCompleted) {
      h.core.pending!.complete({});
    }
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    tester.binding.imageCache.clear();
    tester.binding.imageCache.clearLiveImages();
    await tester.runAsync(() async {
      final root = h.core.directory;
      expect(
        root.parent.resolveSymbolicLinksSync().toLowerCase(),
        Directory.systemTemp.resolveSymbolicLinksSync().toLowerCase(),
      );
      expect(
        root.path.replaceAll('\\', '/').split('/').last,
        startsWith('huevia-selection-ui-'),
      );
      for (var i = 0; i < 10; i++) {
        try {
          root.deleteSync(recursive: true);
          break;
        } on FileSystemException catch (failure) {
          if (!Platform.isWindows ||
              failure.osError?.errorCode != 32 ||
              i == 9) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }
    });
    h.state.dispose();
  }

  Future<SelectionHarness> open(
    WidgetTester tester, {
    Size size = const Size(375, 812),
    double scale = 1,
    bool existing = false,
    Future<Json> Function(Json)? maskBuilder,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final core = SelectionCore(
      Directory.systemTemp.createTempSync('huevia-selection-ui-'),
    );
    final state = WorkspaceState(core);
    final h = SelectionHarness(core, state, core.copy());
    addTearDown(() => cleanup(tester, h));
    final region = seed(strokes: existing ? [dot()] : []);
    final local = {
      'localData': existing ? 'frozen-native-local-data' : '',
      'sha256': 'a' * 64,
      'regions': existing ? [region] : [],
      'hasBodyShape': false,
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const Text('测试宿主'),
                TextButton(
                  onPressed: () async {
                    final result = await Navigator.of(context)
                        .push<SelectionResult>(
                          MaterialPageRoute(
                            builder: (_) => SelectionWorkspace(
                              state: h.state,
                              photo: Photo(core.source.path, 'own.png', {}),
                              owner: '',
                              region: region,
                              localState: local,
                              frame: {
                                'path': h.frame,
                                'width': 1200,
                                'height': 800,
                                'geometryWidth': 1200,
                                'geometryHeight': 800,
                              },
                              maskBuilder:
                                  maskBuilder ??
                                  (input) async => buildSelectionMask(input),
                            ),
                          ),
                        );
                    h.results.add(result);
                  },
                  child: const Text('打开选区'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开选区'));
    await tester.pumpAndSettle();
    await settle(tester);
    return h;
  }

  Rect photoRect(WidgetTester tester) {
    final box = tester.getRect(find.byKey(const ValueKey('selection-canvas')));
    final fitted = applyBoxFit(
      BoxFit.contain,
      const Size(1200, 800),
      box.size,
    ).destination;
    return Alignment.center.inscribe(fitted, box);
  }

  FilledButton done(WidgetTester tester) =>
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, '完成'));
  for (final setting in [
    (const Size(375, 812), 1.0),
    (const Size(812, 375), 2.0),
  ]) {
    testWidgets('Original selection page draws and confirms once at $setting', (
      tester,
    ) async {
      final h = await open(tester, size: setting.$1, scale: setting.$2);
      expect(
        tester.getSize(find.widgetWithText(FilledButton, '完成')),
        const Size(76, 52),
      );
      expect(done(tester).onPressed, isNull);
      await tester.tap(find.text('圆形'));
      await tester.pump();
      final photo = photoRect(tester);
      final gesture = await tester.startGesture(
        photo.topLeft + Offset(photo.width * .2, photo.height * .2),
      );
      await gesture.moveTo(
        photo.topLeft + Offset(photo.width * .75, photo.height * .75),
      );
      await tester.pump();
      await gesture.up();
      await settle(tester);
      expect(done(tester).onPressed, isNotNull);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await settle(tester);
      final changes = h.core.calls
          .where((c) => c.$1 == 'local.change')
          .toList();
      expect(changes, hasLength(1));
      expect(changes.single.$2['action'], 'addRegion');
      final value = object(changes.single.$2['value']);
      expect((value['shapes'] as List).single['kind'], 'ellipse');
      expect(h.results.single!.regionId, 'fixed-region');
      expect(h.core.calls.where((c) => c.$1 == 'draft.save'), isEmpty);
      expect(h.core.source.existsSync(), true);
      expect(File(h.frame).existsSync(), false);
      expect(tester.takeException(), isNull);
      await cleanup(tester, h);
    });
  }
  testWidgets(
    'Pinch cancels a partial stroke and a later tap can still draw a single dot',
    (tester) async {
      final h = await open(tester);
      final photo = photoRect(tester);
      final first = await tester.startGesture(
        photo.center - const Offset(60, 0),
        pointer: 1,
      );
      await first.moveBy(const Offset(30, 20));
      await tester.pump();
      final second = await tester.startGesture(
        photo.center + const Offset(60, 0),
        pointer: 2,
      );
      await tester.pump();
      await first.moveBy(const Offset(-30, 0));
      await second.moveBy(const Offset(30, 0));
      await tester.pump();
      await second.up();
      await first.up();
      await settle(tester);
      expect(done(tester).onPressed, isNull);
      await tester.tapAt(photo.center);
      await settle(tester);
      expect(done(tester).onPressed, isNotNull);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      await settle(tester);
      final command = h.core.calls
          .singleWhere((c) => c.$1 == 'local.change')
          .$2;
      final strokes = object(command['value'])['strokes'] as List;
      expect(strokes, hasLength(1));
      expect(strokes.single['points'], hasLength(2));
      await cleanup(tester, h);
    },
  );
  testWidgets(
    'Account change purges the image and prevents a late selection result from popping another page',
    (tester) async {
      final h = await open(tester, existing: true);
      h.core.pending = Completer<Json>();
      await tester.tap(find.text('完成'));
      await tester.pump();
      h.state.switchOwner();
      await settle(tester);
      expect(find.text('账号或照片已改变，请返回后重新打开。'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('区域 1'), findsNothing);
      h.core.pending!.complete({});
      await settle(tester);
      expect(h.results, isEmpty);
      await tester.tap(find.byTooltip('取消本次选区编辑'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.text('测试宿主'), findsOneWidget);
      expect(h.results.single, isNull);
      expect(h.core.calls.where((c) => c.$1 == 'cancel'), isNotEmpty);
      await cleanup(tester, h);
    },
  );
  testWidgets(
    'System back discards an in-flight confirmation without popping the editor behind it',
    (tester) async {
      final h = await open(tester, existing: true);
      h.core.pending = Completer<Json>();
      await tester.tap(find.text('完成'));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      h.core.pending!.complete({});
      await settle(tester);
      expect(find.text('测试宿主'), findsOneWidget);
      expect(h.results, hasLength(1));
      expect(h.results.single, isNull);
      expect(h.core.source.existsSync(), true);
      await cleanup(tester, h);
    },
  );
  testWidgets(
    'The mask worker coalesces updates and never renders two masks concurrently',
    (tester) async {
      final first = Completer<Json>(), inputs = <Json>[];
      var active = 0, maximum = 0;
      Future<Json> render(Json input) async {
        inputs.add(input);
        active++;
        if (active > maximum) maximum = active;
        try {
          return inputs.length == 1
              ? await first.future
              : buildSelectionMask(input);
        } finally {
          active--;
        }
      }

      addTearDown(() {
        if (!first.isCompleted) {
          first.complete(buildSelectionMask(inputs.first));
        }
      });
      final h = await open(tester, maskBuilder: render);
      final photo = photoRect(tester);
      await tester.tapAt(photo.center);
      await tester.pump();
      await tester.tapAt(photo.center + const Offset(35, 15));
      await tester.pump();
      expect(inputs, hasLength(1));
      first.complete(buildSelectionMask(inputs.first));
      await settle(tester);
      expect(maximum, 1);
      expect(inputs, hasLength(2));
      expect(object(inputs.last['region'])['strokes'], hasLength(2));
      expect(done(tester).onPressed, isNotNull);
      await tester.tap(find.byTooltip('取消本次选区编辑'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(h.core.calls.where((c) => c.$1 == 'local.change'), isEmpty);
      await cleanup(tester, h);
    },
  );
}
