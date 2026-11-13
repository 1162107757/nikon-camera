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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('A received photo is exposed only after project commit and clears after a stopped-owner change', () async {
    final core = PanelCore()
      ..usePreset = false
      ..commitGate = Completer<void>();
    final state = fixtures.LiveState(core);
    addTearDown(() async {
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
      final directory = Directory.systemTemp.createTempSync(
        'huevia-live-panel-220-',
      );
      final originals = Directory(p.join(directory.path, 'originals'))
        ..createSync();
      final copied = File(p.join(originals.path, '${fixtures.sha(2)}.jpg'));
      File('../../app/src/main/assets/preset-showcase/portrait-smile.jpg')
          .copySync(copied.path);
      final core = PanelCore()
        ..root = directory.path
        ..usePreset = false;
      final state = fixtures.LiveState(core);
      addTearDown(() async {
        await state.controller.stop();
        state.dispose();
        await core.events.close();
        try {
          copied.deleteSync();
          originals.deleteSync();
          directory.deleteSync();
        } on FileSystemException {
          /* The Windows image decoder may release its file after the process exits. */
        }
      });
      await state.controller.start('project-one', '拍摄');
      core.visible = [fixtures.shot(2)];
      await state.controller.pollOnce();
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
      await tester.tap(find.byTooltip('放大当前照片'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('DSC_2.JPG'), findsOneWidget);
      state.changeOwner();
      await tester.pump();
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.text('DSC_2.JPG'), findsNothing);
      expect(find.text('账号已改变，请重新打开拍摄项目。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
