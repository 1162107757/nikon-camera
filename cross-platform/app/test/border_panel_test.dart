import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/border_panel.dart';
import 'package:huevia/domain.dart';

import 'editor_workspace_test.dart' show WorkspaceCore, WorkspaceState;

class BorderCore extends WorkspaceCore {
  BorderCore(super.directory);
  Completer<Json>? delayedPreview;
  final previewJobs = <String?>[];
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'media.preview') previewJobs.add(jobId);
    if (operation == 'media.borderInfo') {
      calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
      return {
        'brand': 'NIKON',
        'model': 'NIKON Z 6_3',
        'fields': ['50mm', 'F1.8', '1/125s', 'ISO200', '2026-11-11 12:34:56'],
      };
    }
    if (operation == 'media.preview' && delayedPreview != null) {
      calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
      return delayedPreview!.future;
    }
    return super.call(operation, payload, jobId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 60)),
    );
    await tester.pump();
  }

  Future<void> cleanup(WidgetTester tester, Directory dir) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await settle(tester);
    tester.binding.imageCache.clear();
    tester.binding.imageCache.clearLiveImages();
    await tester.runAsync(() async {
      expect(
        dir.parent.absolute.path.toLowerCase(),
        Directory.systemTemp.absolute.path.toLowerCase(),
      );
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException catch (e) {
        if (Platform.isWindows && e.osError?.errorCode == 32) {
          debugPrint('Deferred test fixture cleanup: ${dir.absolute.path}');
        } else {
          rethrow;
        }
      }
    });
  }

  for (final setting in [
    (const Size(375, 812), 1.0),
    (const Size(812, 375), 2.0),
  ]) {
    testWidgets(
      'Original border strip, fields, settings and camera at $setting',
      (tester) async {
        tester.view.physicalSize = setting.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final core = BorderCore(
          Directory.systemTemp.createTempSync('huevia-border-'),
        );
        final state = WorkspaceState(core),
            recipe = <String, dynamic>{
              'schema': 1,
              'border': <String, dynamic>{'template': 0},
              'geometry': {'left': 123456, 'right': 900000},
              'values': List.filled(17, 0),
            };
        final mutations = <Json>[];
        var checkpoints = 0;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(setting.$2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: SafeArea(
                child: StatefulBuilder(
                  builder: (context, refresh) => Align(
                    alignment: Alignment.bottomCenter,
                    child: SizedBox(
                      height: setting.$1.width > setting.$1.height ? 160 : 184,
                      child: BorderPanel(
                        state: state,
                        photo: Photo(core.source.path, 'own.png', {}),
                        owner: '',
                        recipe: recipe,
                        enabled: true,
                        canUndo: true,
                        canRedo: true,
                        onUndo: () =>
                            refresh(() => recipe['border'] = {'template': 0}),
                        onRedo: () {},
                        onDragStart: () => checkpoints++,
                        onChanged: (border, snapshot) => refresh(() {
                          recipe['border'] = border;
                          mutations.add(object(jsonDecode(jsonEncode(border))));
                          if (snapshot) checkpoints++;
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await settle(tester);
        await settle(tester);
        final previews = core.calls
            .where((c) => c.$1 == 'media.preview')
            .toList();
        expect(previews, hasLength(4));
        expect(
          previews.map(
            (c) => object(object(c.$2['recipe'])['border'])['template'],
          ),
          orderedEquals([0, 1, 2, 3]),
        );
        expect(previews.every((c) => c.$2['maxEdge'] == 256), true);
        expect(core.previewJobs.every((job) => job != null), true);
        expect(core.previewJobs.toSet(), hasLength(4));
        expect(find.text('Nikon Z6 III'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('模糊居中'));
        await settle(tester);
        expect(object(recipe['border'])['template'], 1);
        expect(core.calls.where((c) => c.$1 == 'media.preview'), hasLength(4));
        expect(object(recipe['geometry'])['left'], 123456);

        expect(
          find.byKey(const ValueKey('border-information-list')),
          findsOneWidget,
        );

        final scroll = find
            .descendant(
              of: find.byKey(const ValueKey('border-information-list')),
              matching: find.byWidgetPredicate((w) => w is Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('ISO'),
          80,
          scrollable: scroll,
          continuous: true,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('ISO'));
        await tester.pumpAndSettle();
        expect(find.text('原图值：ISO200'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'ISO500');
        await tester.tap(find.text('应用'));
        await tester.pumpAndSettle();
        await settle(tester);
        expect((object(recipe['border'])['fields'] as List)[3], 'ISO500');

        await tester.scrollUntilVisible(
          find.text('设置'),
          100,
          scrollable: scroll,
          continuous: true,
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('设置'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        await settle(tester);
        expect(find.text('边框设置'), findsOneWidget);
        final appearanceScroll = find
            .descendant(
              of: find.byKey(const ValueKey('border-settings-body-2')),
              matching: find.byType(Scrollable),
            )
            .first;
        for (final key in ['margin', 'corner', 'shadow', 'blur']) {
          await tester.scrollUntilVisible(
            find.byKey(ValueKey('border-appearance-$key')),
            80,
            scrollable: appearanceScroll,
            continuous: true,
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(ValueKey('border-appearance-$key')),
            findsOneWidget,
          );
        }
        final margin = find.byKey(const ValueKey('border-appearance-margin'));
        await tester.scrollUntilVisible(
          margin,
          -100,
          scrollable: appearanceScroll,
          continuous: true,
        );
        await tester.pumpAndSettle();
        await tester.drag(margin, const Offset(120, 0), touchSlopX: 64);
        await settle(tester);
        expect(object(recipe['border'])['margin'], isNot(100));
        await tester.scrollUntilVisible(
          find.text('Logo · 跟随模板'),
          100,
          scrollable: appearanceScroll,
          continuous: true,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Logo · 跟随模板'));
        await tester.pumpAndSettle();
        // The editor stays dark even when its owning MaterialApp is light.
        // Native Logo choices are 48dp rows with readable, regular-weight text.
        expect(
          Theme.of(tester.element(find.text('Logo 样式'))).brightness,
          Brightness.dark,
        );
        expect(
          tester.widget<Dialog>(find.byType(Dialog).last).backgroundColor,
          const Color(0xff292724),
        );
        expect(
          tester.widget<Text>(find.text('白色')).style?.color,
          const Color(0xfff6f1eb),
        );
        expect(
          tester.widget<Text>(find.text('白色')).style?.fontWeight,
          FontWeight.w400,
        );
        final transmission = tester
            .widgetList<ModalBarrier>(find.byType(ModalBarrier))
            .fold<double>(
              1,
              (value, barrier) => value * (1 - (barrier.color?.a ?? 0)),
            );
        expect(1 - transmission, closeTo(.42, .01));
        if (setting.$2 == 1) {
          expect(
            tester
                .getSize(
                  find
                      .ancestor(
                        of: find.text('白色'),
                        matching: find.byType(InkWell),
                      )
                      .first,
                )
                .height,
            48,
          );
        }
        await tester.ensureVisible(find.text('白色'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('白色'));
        await tester.pumpAndSettle();
        await settle(tester);
        expect(object(recipe['border'])['logo'], 2);
        await tester.tap(find.text('信息'));
        await tester.pumpAndSettle();
        final showIso = find.byWidgetPredicate(
          (w) => w is Checkbox && w.semanticLabel == '显示ISO',
        );
        final informationScroll = find
            .descendant(
              of: find.byKey(const ValueKey('border-settings-body-1')),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          showIso,
          100,
          scrollable: informationScroll,
          continuous: true,
        );
        await tester.pumpAndSettle();
        await tester.tap(showIso);
        await settle(tester);
        expect((object(recipe['border'])['visible'] as int) & (1 << 4), 0);
        await tester.tap(find.byTooltip('撤销边框调整'));
        await settle(tester);
        expect(object(recipe['border'])['template'], 0);
        await tester.tap(find.byTooltip('关闭边框设置'));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('机型'),
          -100,
          scrollable: scroll,
          continuous: true,
        );
        await settle(tester);
        await tester.tap(find.text('机型'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('手动'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'Z6 III');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Nikon Z6 III').last);
        await tester.tap(find.text('Nikon Z6 III').last);
        await tester.ensureVisible(find.text('使用机型'));
        await tester.tap(find.text('使用机型'));
        await tester.pumpAndSettle();
        await settle(tester);
        expect(object(recipe['border'])['automatic'], false);
        expect(object(recipe['border'])['model'], 'NIKON Z 6_3');
        expect(object(recipe['border'])['brand'], 'NIKON');
        expect(checkpoints, greaterThanOrEqualTo(3));
        expect(mutations, isNotEmpty);
        final exception = tester.takeException();
        if (exception is FlutterError) {
          debugPrint(
            exception.diagnostics.map((d) => d.toStringDeep()).join('\n'),
          );
        }
        expect(exception, isNull);
        await cleanup(tester, core.directory);
        state.dispose();
      },
    );
  }
  testWidgets('Border thumbnails resume after a temporary busy operation', (
    tester,
  ) async {
    final core = BorderCore(
      Directory.systemTemp.createTempSync('huevia-border-resume-'),
    );
    final state = WorkspaceState(core);
    final pending = Completer<Json>();
    core.delayedPreview = pending;
    var enabled = true;
    StateSetter refresh = (_) {};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 184,
            child: StatefulBuilder(
              builder: (context, update) {
                refresh = update;
                return BorderPanel(
                  state: state,
                  photo: Photo(core.source.path, 'own.png', {}),
                  owner: '',
                  recipe: {'border': {}, 'geometry': {}},
                  enabled: enabled,
                  canUndo: false,
                  canRedo: false,
                  onUndo: () {},
                  onRedo: () {},
                  onDragStart: () {},
                  onChanged: (_, _) {},
                );
              },
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    expect(core.previewJobs, hasLength(1));
    refresh(() => enabled = false);
    await tester.pump();
    // An unrelated application notification while exporting is not an account
    // change and must not erase the already identified capture information.
    state.notifyListeners();
    await tester.pump();
    expect(find.text('Nikon Z6 III'), findsOneWidget);
    final abandoned = core.copy();
    core.delayedPreview = null;
    pending.complete({'path': abandoned});
    await settle(tester);
    refresh(() => enabled = true);
    await settle(tester);
    await settle(tester);
    expect(find.textContaining('边框预览失败'), findsNothing);
    expect(core.previewJobs, hasLength(5));
    expect(core.previewJobs.toSet(), hasLength(5));
    expect(find.byType(Image), findsNWidgets(4));
    expect(File(abandoned).existsSync(), false);
    expect(tester.takeException(), isNull);
    await cleanup(tester, core.directory);
    state.dispose();
  });

  testWidgets(
    'Account changes reject pending border thumbnails and field commits',
    (tester) async {
      final core = BorderCore(
        Directory.systemTemp.createTempSync('huevia-border-owner-'),
      );
      final state = WorkspaceState(core);
      core.delayedPreview = Completer<Json>();
      var changes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 184,
              child: BorderPanel(
                state: state,
                photo: Photo(core.source.path, 'own.png', {}),
                owner: '',
                recipe: {'border': {}},
                enabled: true,
                canUndo: false,
                canRedo: false,
                onUndo: () {},
                onRedo: () {},
                onDragStart: () {},
                onChanged: (_, _) => changes++,
              ),
            ),
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('机型'));
      // The native thumbnail future is deliberately still pending.
      await settle(tester);
      state.switchOwner();
      await tester.pump();
      final stale = core.copy();
      core.delayedPreview!.complete({'path': stale});
      await settle(tester);
      await settle(tester);
      await tester.tap(find.text('使用识别结果'));
      await tester.pump();
      expect(changes, 0);
      await tester.tap(find.byTooltip('关闭机型选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('模糊居中'));
      await tester.pump();
      expect(changes, 0);
      expect(File(stale).existsSync(), false);
      expect(core.calls.where((c) => c.$1 == 'media.preview'), hasLength(1));
      await cleanup(tester, core.directory);
      state.dispose();
    },
  );
}
