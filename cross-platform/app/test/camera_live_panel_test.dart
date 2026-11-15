import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:huevia/camera_live_card.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';

import 'camera_live_test.dart' as fixtures;

class PanelCore extends fixtures.LiveCore {
  Completer<void>? commitGate;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'project.live.commit') await commitGate?.future;
    return super.call(operation, payload, jobId);
  }
}

Future<void> runPanelAsync(
  WidgetTester tester,
  String stage,
  Future<void> Function() action,
) async {
  Object? failure;
  StackTrace? failureStack;
  await tester.runAsync(() async {
    try {
      await action().timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw TimeoutException('Live panel fixture: $stage'),
      );
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
  });
  if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
}

Future<void> pumpPanelUntil(
  WidgetTester tester,
  String stage,
  bool Function() ready,
) async {
  for (var i = 0; i < 80 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
  expect(ready(), true, reason: 'Live panel fixture readiness: $stage');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('A received photo is exposed only after project commit and clears after a stopped-owner change', () async {
    final core = PanelCore()
      ..usePreset = false
      ..commitGate = Completer<void>();
    final state = fixtures.LiveState(core);
    addTearDown(() async {
      final commit = core.commitGate;
      if (commit != null && !commit.isCompleted) commit.complete();
      core.releaseHeldOperations();
      await state.controller.stop();
      state.dispose();
      await core.events.close();
    });
    final live = state.controller;
    await live.start('project-one', '拍摄');
    core.visible = [fixtures.shot(2)];
    final receiving = live.pollOnce();
    for (var i = 0; i < 30 && state.registered.isEmpty; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(state.registered, hasLength(1));
    expect(live.latestPhoto, isNull);
    core.commitGate!.complete();
    await receiving;
    expect(live.latestPhoto?.name, 'DSC_2.JPG');
    await live.stop();
    state.changeOwner();
    expect(live.latestPhoto, isNull);
  });
  testWidgets(
    'Expanded committed live photo hides pixels and filename immediately when owner changes',
    (tester) async {
      late Directory directory, originals;
      late File copied;
      await runPanelAsync(tester, 'copy actual JPEG', () async {
        directory = await Directory.systemTemp.createTemp(
          'huevia-live-panel-227-',
        );
        originals = await Directory(p.join(directory.path, 'originals'))
            .create();
        copied = await File(
          '../../app/src/main/assets/preset-showcase/portrait-smile.jpg',
        ).copy(p.join(originals.path, '${fixtures.sha(2)}.jpg'));
      });
      final core = PanelCore()
        ..root = directory.path
        ..usePreset = false;
      final state = fixtures.LiveState(core);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        tester.binding.imageCache.clear();
        tester.binding.imageCache.clearLiveImages();
        final commit = core.commitGate;
        if (commit != null && !commit.isCompleted) commit.complete();
        core.releaseHeldOperations();
        try {
          await runPanelAsync(tester, 'drain soft-stop', state.controller.stop);
        } finally {
          state.dispose();
          await runPanelAsync(tester, 'close progress stream', () async {
            await core.events.close();
          });
          await runPanelAsync(tester, 'delete temporary JPEG', () async {
            try {
              await copied.delete();
              await originals.delete();
              await directory.delete();
            } on FileSystemException {
              /* The Windows image decoder may release its file after the process exits. */
            }
          });
        }
      });
      await runPanelAsync(tester, 'start live controller', () async {
        await state.controller.start('project-one', '拍摄');
      });
      core.visible = [fixtures.shot(2)];
      await runPanelAsync(
        tester,
        'receive and commit photo',
        state.controller.pollOnce,
      );
      expect(state.controller.latestPhoto?.path, copied.path);
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CameraLiveCard(
                state: state,
                projectId: 'project-one',
                projectName: '拍摄',
                hasPreset: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('放大当前照片'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final decodedDialogImage = find.descendant(
        of: find.byType(InteractiveViewer),
        matching: find.byWidgetPredicate(
          (widget) => widget is RawImage && widget.image != null,
        ),
      );
      await pumpPanelUntil(
        tester,
        'expanded real photo has decoded pixels',
        () => decodedDialogImage.evaluate().length == 1,
      );
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(decodedDialogImage, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('DSC_2.JPG'),
        ),
        findsOneWidget,
      );
      await runPanelAsync(tester, 'initiate owner change', () async {
        state.changeOwner();
        expect(state.controller.latestPhoto, isNull);
      });
      await tester.pump();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.text('DSC_2.JPG'), findsNothing);
      expect(find.text('账号已改变，请重新打开拍摄项目。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
