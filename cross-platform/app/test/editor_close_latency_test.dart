import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/theme.dart';

import 'editor_realtime_preview_test.dart' show RealtimeCore, RealtimeState;

class _ClosingCore extends RealtimeCore {
  final writes = <Json>[];
  int readCount = 0;
  Json? persisted;
  Completer<void>? saveReply;

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'draft.load') {
      readCount++;
      return {'sourceSha': 'fixture-sha', 'recipe': persisted};
    }
    if (operation == 'draft.save') {
      final snapshot = object(payload['recipe']);
      writes.add(snapshot);
      await saveReply?.future;
      persisted = snapshot;
      return {'sourceSha': 'fixture-sha', 'recipe': snapshot};
    }
    return super.call(operation, payload, jobId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'closing returns before native replies and writes one final draft',
    (tester) async {
      final core = _ClosingCore(), state = RealtimeState(core);
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final events = const MethodChannel('cc.huevia/events');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(events, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(events, null));
      addTearDown(state.dispose);

      final navigator = GlobalKey<NavigatorState>();
      const album = Key('close-test-album');
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: hueviaTheme(Brightness.dark),
          home: const Scaffold(key: album),
        ),
      );
      void openPhoto() {
        unawaited(
          navigator.currentState!.push<void>(
            PageRouteBuilder<void>(
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
              pageBuilder: (_, _, _) => EditorPage(
                state: state,
                photo: Photo(core.source.path, '快速关闭测试', const {}),
              ),
            ),
          ),
        );
      }

      openPhoto();
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(core.readCount, 1);
      core.gate = true;
      core.saveReply = Completer<void>();
      final dynamic editor = tester.state(find.byType(EditorPage));
      editor.change(() => editor.recipe.setValue(1, 35), snapshot: false);
      await tester.pump();
      final heldPreview = core.calls.last;
      expect(heldPreview.exposure, 35);

      final close = find.byTooltip('返回相册');
      await tester.tap(close);
      await tester.tap(close);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(album), findsOneWidget);
      expect(find.byType(EditorPage), findsNothing);
      expect(core.cancelled, contains(heldPreview.job));
      expect((core.writes.single['values'] as List)[1], 35);
      expect(core.persisted, isNull);

      // A quick reopen must join just this pending write before restoring.
      openPhoto();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(EditorPage), findsOneWidget);
      expect(core.readCount, 1);
      core.gate = false;
      heldPreview.result.complete(core.image());
      core.saveReply!.complete();
      await tester.pumpAndSettle();
      expect(core.readCount, 2);
      expect(core.calls.last.exposure, 35);
      expect(core.writes, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  test('pending close draft does not block other photos or accounts', () async {
    final core = HueviaCore();
    final writes = Completer<void>();
    var reads = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(HueviaCore.channel, (request) async {
      final arguments = object(request.arguments);
      expect(arguments['operation'], 'draft.load');
      reads++;
      return '{}';
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(HueviaCore.channel, null),
    );

    final pending = core.queueClosingDraft(
      'photo-a',
      'owner-a',
      () => writes.future,
    );
    final same = core.call('draft.load', {
      'path': 'photo-a',
      'owner': 'owner-a',
    });
    await core.call('draft.load', {'path': 'photo-b', 'owner': 'owner-a'});
    await core.call('draft.load', {'path': 'photo-a', 'owner': 'owner-b'});
    expect(reads, 2);
    writes.complete();
    await pending;
    await same;
    expect(reads, 3);
  });
}
