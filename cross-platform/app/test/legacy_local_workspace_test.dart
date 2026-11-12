import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/legacy_local_workspace.dart';

import 'editor_workspace_test.dart' show WorkspaceCore, WorkspaceState;

class ToolsWorkspaceCore extends WorkspaceCore {
  ToolsWorkspaceCore(super.directory);
  Completer<Json>? pending;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'local.change') {
      calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
      final tools = object(payload['value']);
      return {
        'localData': jsonEncode(tools),
        'sha256': 'validated',
        ...tools,
        'regions': [
          {'id': 'preserved'},
        ],
        'opaque': 'preserved',
      };
    }
    if (operation == 'media.localPreview') {
      calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
      return pending?.future ?? {'path': copy(), 'width': 800, 'height': 600};
    }
    return super.call(operation, payload, jobId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 30));
    }
  }

  Future<(ToolsWorkspaceCore, WorkspaceState, List<Json?>)> open(
    WidgetTester tester, {
    Size size = const Size(375, 812),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final core = ToolsWorkspaceCore(
      Directory.systemTemp.createTempSync('huevia-local-tools-ui-'),
    );
    final state = WorkspaceState(core), results = <Json?>[];
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      tester.binding.imageCache.clear();
      tester.binding.imageCache.clearLiveImages();
      state.dispose();
      // Keep a temporarily mapped Windows fixture; never delete any user input.
      if (!Platform.isWindows) {
        await tester.runAsync(() async {
          final directory = core.directory;
          if (directory.parent.resolveSymbolicLinksSync() ==
                  Directory.systemTemp.resolveSymbolicLinksSync() &&
              directory.path
                  .split(Platform.pathSeparator)
                  .last
                  .startsWith('huevia-local-tools-ui-')) {
            directory.deleteSync(recursive: true);
          }
        });
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                results.add(
                  await Navigator.of(context).push<Json>(
                    MaterialPageRoute(
                      builder: (_) => LegacyLocalWorkspace(
                        state: state,
                        photo: Photo(core.source.path, 'own.png', const {}),
                        owner: '',
                        recipe: const {
                          'localData': 'frozen',
                          'border': {'template': 3},
                        },
                        localState: const {
                          'localData': 'frozen',
                          'sha256': 'a',
                          'masks': [],
                          'clones': [],
                        },
                        frame: {
                          'path': core.copy(),
                          'width': 800,
                          'height': 600,
                        },
                        isCurrent: () => true,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await settle(tester);
    return (core, state, results);
  }

  Future<void> gradient(WidgetTester tester) async {
    await tester.tap(find.byTooltip('渐变'));
    await tester.pump();
    final rect = tester.getRect(find.byKey(const ValueKey('legacy-stage')));
    await tester.dragFrom(
      Offset(rect.left + rect.width * .3, rect.center.dy),
      Offset(rect.width * .3, 0),
    );
    await settle(tester);
  }

  testWidgets(
    'legacy gradient validates and previews without a draft write, then Apply returns only validated tools',
    (tester) async {
      final (core, _, results) = await open(tester);
      await gradient(tester);
      expect(find.text('渐变 1'), findsOneWidget);
      final changes = core.calls.where((c) => c.$1 == 'local.change').toList();
      expect(changes, isNotEmpty);
      expect(
        changes.every(
          (c) =>
              c.$2['localData'] == 'frozen' && c.$2['action'] == 'replaceTools',
        ),
        isTrue,
      );
      expect(core.calls.where((c) => c.$1 == 'draft.save'), isEmpty);
      await tester.tap(find.byKey(const ValueKey('legacy-apply')));
      await tester.pumpAndSettle();
      expect(results.single!['sha256'], 'validated');
      expect(results.single!['opaque'], 'preserved');
      expect(results.single!['regions'], [
        {'id': 'preserved'},
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cancel discards tentative tools and a late account-owned preview cannot enable Apply',
    (tester) async {
      final (core, state, results) = await open(tester);
      core.pending = Completer<Json>();
      await gradient(tester);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('legacy-apply')))
            .onPressed,
        isNull,
      );
      state.switchOwner();
      await tester.pump();
      expect(find.text('账号已变更，请重新打开照片。'), findsOneWidget);
      core.pending!.complete({
        'path': core.copy(),
        'width': 800,
        'height': 600,
      });
      await settle(tester);
      expect(find.text('渐变 1'), findsNothing);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('legacy-apply')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('取消'));
      await tester.pumpAndSettle();
      expect(results, [null]);
      expect(core.calls.where((c) => c.$1 == 'draft.save'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clone source and target, history and landscape large text retain reachable original controls',
    (tester) async {
      final (core, _, _) = await open(
        tester,
        size: const Size(812, 375),
        scale: 2,
      );
      await tester.tap(find.byTooltip('修复'));
      await tester.pump();
      final rect = tester.getRect(find.byKey(const ValueKey('legacy-stage')));
      await tester.tapAt(Offset(rect.left + rect.width * .3, rect.center.dy));
      await tester.pump();
      expect(find.text('点击选择取样位置'), findsNothing);
      await tester.tapAt(Offset(rect.left + rect.width * .6, rect.center.dy));
      await settle(tester);
      expect(find.text('修复 1'), findsOneWidget);
      final values = core.calls
          .where((c) => c.$1 == 'local.change')
          .map((c) => object(c.$2['value']))
          .toList();
      expect(values.any((v) => (v['clones'] as List).isNotEmpty), isTrue);
      await tester.tap(find.byTooltip('撤销'));
      await settle(tester);
      expect(find.text('修复 1'), findsNothing);
      await tester.tap(find.byTooltip('重做'));
      await settle(tester);
      // The original dialog restores the collection, leaving an absent
      // selection absent. Re-select the restored clone from its chooser.
      final restored = core.calls.lastWhere((c) => c.$1 == 'local.change');
      expect(object(restored.$2['value'])['clones'], hasLength(1));
      await tester.tap(find.text('在照片上拖动新建'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('修复 1'));
      await tester.pumpAndSettle();
      await settle(tester);
      expect(find.text('修复 1'), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const ValueKey('legacy-apply'))).right,
        lessThanOrEqualTo(812),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'two-finger navigation cancels a partial stroke and lifting one finger does not resume painting',
    (tester) async {
      final (core, _, _) = await open(tester);
      final rect = tester.getRect(find.byKey(const ValueKey('legacy-stage')));
      final first = await tester.startGesture(
        rect.center - const Offset(40, 0),
        pointer: 11,
      );
      await first.moveBy(const Offset(15, 0));
      await tester.pump();
      final second = await tester.startGesture(
        rect.center + const Offset(40, 0),
        pointer: 12,
      );
      await tester.pump();
      await first.moveBy(const Offset(-20, 0));
      await second.moveBy(const Offset(20, 0));
      await tester.pump();
      await first.up();
      await second.moveBy(const Offset(20, 10));
      await second.up();
      await settle(tester);
      final last = core.calls.lastWhere((c) => c.$1 == 'local.change');
      expect(object(last.$2['value'])['masks'], isEmpty);
      expect(find.text('画笔 1'), findsNothing);
      expect(core.calls.where((c) => c.$1 == 'draft.save'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
