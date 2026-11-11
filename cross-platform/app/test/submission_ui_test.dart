import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/community_activity.dart';
import 'package:huevia/community_state.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/submission_editor.dart';
import 'package:huevia/theme.dart';

import 'community_state_test.dart'
    show CommunityTestCore, CommunityTestState, ownerA, ownerB;

Json envelope(Json draft) => {
  'slot': 'new',
  'draft': {...draft},
  'warning': '',
};

class SubmissionTestCore extends CommunityTestCore {
  Future<Json?> Function(String, String)? picker;
  @override
  Future<Json?> pickSubmission({required String kind, required String owner}) =>
      picker!(kind, owner);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Autosave is serial and old responses cannot replace newer typing',
    (tester) async {
      final core = SubmissionTestCore(),
          state = CommunityTestState(SubmissionTestCore());
      final actualState = CommunityTestState(core);
      final first = Completer<Json>();
      var writes = 0;
      core.handler = (op, p) {
        if (op == 'submission.load') return envelope({'name': '初始'});
        writes++;
        return writes == 1 ? first.future : envelope(object(p['draft']));
      };
      final model = SubmissionModel(actualState);
      await model.load();
      model.edit({'name': '第一次'});
      await tester.pump(const Duration(milliseconds: 350));
      model.edit({'name': '第二次'});
      await tester.pump(const Duration(milliseconds: 350));
      expect(writes, 1);
      first.complete(envelope({'name': '第一次'}));
      await tester.pump();
      expect(model.draft['name'], '第二次');
      expect(writes, 2);
      model.dispose();
      actualState.dispose();
      state.dispose();
    },
  );

  testWidgets(
    'Uncertain save restores native receipt and locks edits until retry',
    (tester) async {
      final core = SubmissionTestCore(),
          native = <String, dynamic>{'name': '我的预设', 'rightsConfirmed': true};
      final state = CommunityTestState(core);
      var saves = 0;
      core.handler = (op, p) {
        if (op == 'submission.load') return envelope(native);
        if (op == 'submission.persist') {
          native.addAll(object(p['draft']));
          return envelope(native);
        }
        saves++;
        if (saves == 1) {
          native['savePending'] = true;
          native['saveIntentSubmit'] = true;
          throw const AppFailure('网络中断');
        }
        native['savePending'] = false;
        native['status'] = 'pending';
        return envelope(native);
      };
      final model = SubmissionModel(state);
      await model.load();
      expect(await model.save(submit: true), false);
      expect(model.uncertain, true);
      model.edit({'name': '不能覆盖'});
      expect(model.draft['name'], '我的预设');
      expect(await model.save(submit: true), true);
      expect(model.locked, true);
      model.dispose();
      state.dispose();
    },
  );

  testWidgets(
    'Picker result from an old account is discarded and private fields clear',
    (tester) async {
      final core = SubmissionTestCore(), picked = Completer<Json?>();
      final state = CommunityTestState(core);
      core.handler = (op, p) => envelope(
        op == 'submission.persist' ? object(p['draft']) : {'name': '私有草稿'},
      );
      core.picker = (kind, owner) {
        expect(owner, ownerA);
        return picked.future;
      };
      final model = SubmissionModel(state);
      await model.load();
      final pending = model.pick('ncp');
      await tester.pump();
      state.setOwner(ownerB);
      picked.complete({'path': '/old/file', 'name': 'old.ncp'});
      expect(await pending, false);
      expect(model.stale, true);
      expect(model.draft, isEmpty);
      expect(core.calls.where((v) => v.$1 == 'submission.attach'), isEmpty);
      model.dispose();
      state.dispose();
    },
  );

  for (final setting in [
    (const Size(375, 812), 1.0),
    (const Size(812, 375), 2.0),
  ]) {
    testWidgets(
      'Submission fields preserve comma input without overflow at $setting',
      (tester) async {
        tester.view.physicalSize = setting.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final core = SubmissionTestCore(),
            state = CommunityTestState(SubmissionTestCore());
        final actualState = CommunityTestState(core);
        core.handler = (op, p) =>
            envelope(op == 'submission.persist' ? object(p['draft']) : {});
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.light, home: false),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(setting.$2)),
              child: child!,
            ),
            home: SubmissionEditor(state: actualState),
          ),
        );
        await tester.pumpAndSettle();
        final name = find.byKey(const ValueKey('submission-name'));
        await tester.enterText(name, '甲${'😀' * 80}');
        expect(tester.widget<TextField>(name).controller!.text.length, 159);
        expect(
          tester.widget<TextField>(name).controller!.text.runes.last,
          0x1f600,
        );
        final models = find.byKey(const ValueKey('submission-models'));
        await tester.ensureVisible(models);
        await tester.enterText(models, 'Nikon Z6，');
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          (tester.widget<TextField>(models).controller!).text,
          'Nikon Z6，',
        );
        expect(tester.takeException(), isNull);
        actualState.setOwner(ownerB);
        await tester.pump();
        expect((tester.widget<TextField>(models).controller!).text, isEmpty);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        actualState.dispose();
        state.dispose();
      },
    );
  }

  testWidgets(
    'Foreground unread polling stops in background and rejects a stale count',
    (tester) async {
      final core = SubmissionTestCore(),
          state = CommunityTestState(SubmissionTestCore());
      final actualState = CommunityTestState(core)..ready = true;
      var polls = 0;
      final first = Completer<Json>();
      core.handler = (op, p) {
        polls++;
        return polls == 1 ? first.future : {'unread': 3};
      };
      await tester.pumpWidget(
        CommunityActivity(
          state: actualState,
          pollInterval: const Duration(seconds: 1),
          child: const SizedBox(),
        ),
      );
      await tester.pump();
      expect(polls, 1);
      final unread = communityUnread(actualState),
          stamp = communityUnread(actualState).begin();
      unread.accept(stamp, 1);
      first.complete({'unread': 9});
      await tester.pump();
      expect(unread.count, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      // Live bindings cannot produce a frame while the app is paused.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      expect(polls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(polls, 2);
      expect(unread.count, 3);
      actualState.setOwner('');
      await tester.pump();
      expect(unread.count, 0);
      await tester.pump(const Duration(milliseconds: 1100));
      expect(polls, 2);
      await tester.pumpWidget(const SizedBox());
      actualState.dispose();
      state.dispose();
    },
  );
}
