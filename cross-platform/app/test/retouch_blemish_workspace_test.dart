import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/retouch_blemish_review.dart';
import 'package:huevia/retouch_detail_preview.dart';
import 'package:huevia/retouch_workspace.dart';
import 'package:huevia/theme.dart';

import 'retouch_workspace_test.dart'
    show PortraitMenuCore, settleRetouchFixture;

class _BlemishCore extends PortraitMenuCore {
  _BlemishCore(super.directory);

  final candidates = <Json>[
    {
      'sx': .18,
      'sy': .23,
      'tx': .25,
      'ty': .35,
      'radius': .018,
      'feather': .65,
      'enabled': true,
    },
    {
      'sx': .64,
      'sy': .54,
      'tx': .7,
      'ty': .6,
      'radius': .025,
      'feather': .7,
      'enabled': true,
    },
  ];
  Completer<void>? analyzeGate, applyPreviewGate;
  bool added = false;
  final acceptedPreviewOrigins = <String, Json>{};
  String get sourceSha =>
      sha256.convert(File('$root/original.jpg').readAsBytesSync()).toString();

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'media.retouchAnalyze' &&
        payload['mode'] == 'autoBlemish') {
      calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
      final gate = analyzeGate;
      if (gate != null) {
        if (jobId != null) blockedJobs.add(jobId);
        await gate.future;
      }
      return {
        ...snapshots[payload['localData']]!,
        'regionId': regionId,
        'healCandidates': candidates,
      };
    }
    if (operation == 'media.retouchChange' && payload['action'] == 'addHeals') {
      calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
      final next = object(
        jsonDecode(jsonEncode(snapshots[payload['localData']]!)),
      );
      (object(next['portrait'])['heals'] as List).addAll(
        object(payload['value'])['heals'] as List,
      );
      next['localData'] = next['sha256'] = 'blemish-${serial++}';
      next['regionId'] = regionId;
      snapshots[next['localData'] as String] = next;
      added = true;
      return next;
    }
    if (operation == 'media.reviewPreview' &&
        added &&
        applyPreviewGate != null) {
      final gate = applyPreviewGate!;
      applyPreviewGate = null;
      if (jobId != null) blockedJobs.add(jobId);
      await gate.future;
    }
    final result = await super.call(operation, payload, jobId);
    if (operation == 'media.reviewPreview' ||
        operation == 'media.localPreview') {
      acceptedPreviewOrigins[result['path'] as String] = {
        'operation': operation,
        'payload': object(jsonDecode(jsonEncode(payload))),
      };
      return {...result, 'sourceSha': sourceSha};
    }
    return result;
  }
}

void main() {
  late Directory directory;
  late _BlemishCore core;
  late AppState state;
  Json? applied;
  var completed = 0;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('huevia-blemish-review-');
    Directory('${directory.path}/previews').createSync();
    File('${directory.path}/previews/portrait.png').writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAEklEQVR4nGMQWm3yHx9mGBkKAKq5fAFPbl0bAAAAAElFTkSuQmCC',
      ),
    );
    File('${directory.path}/previews/portrait.png')
        .copySync('${directory.path}/original.jpg');
    core = _BlemishCore(directory.path);
    state = AppState(core)
      ..session = {
        'user': {'id': 'alice'},
      };
    applied = null;
    completed = 0;
  });
  tearDown(() async {
    state.dispose();
    for (var attempt = 0; ; attempt++) {
      try {
        await directory.delete(recursive: true);
        break;
      } on FileSystemException catch (error) {
        if (error.osError?.errorCode != 32 || attempt >= 30) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });

  Future<void> settle(WidgetTester tester) =>
      settleRetouchFixture(tester, core);

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                applied = await Navigator.of(context).push<Json>(
                  MaterialPageRoute(
                    builder: (_) => RetouchWorkspace(
                      state: state,
                      photo: Photo(
                        '${directory.path}/original.jpg',
                        '人像',
                        const {},
                      ),
                      owner: 'alice',
                      recipe: {
                        ...Recipe().data,
                        'geometry': {
                          'turns': 1,
                          'left': 100,
                          'top': 200,
                          'right': 800,
                          'bottom': 900,
                        },
                        'border': {'size': 10},
                      },
                      isCurrent: () => true,
                    ),
                  ),
                );
                completed++;
              },
              child: const Text('父编辑器'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('父编辑器'));
    await settle(tester);
    await tester.tap(find.text('皮肤'));
    await settle(tester);
  }

  Future<void> analyze(WidgetTester tester, {bool held = false}) async {
    await tester.ensureVisible(find.text('自动祛痘'));
    await tester.tap(find.text('自动祛痘'));
    if (held) {
      await tester.pump();
    } else {
      await settle(tester);
      final review = find.byType(RetouchBlemishReview);
      if (review.evaluate().isNotEmpty) {
        final confirm = find.byKey(const ValueKey('blemish-confirm'));
        // File IO and native image decoding cross several fake-async turns.
        // Pump each boundary; awaiting its pending stream inside runAsync
        // would deadlock the fake-zone listener that enables confirmation.
        for (var attempt = 0; attempt < 50; attempt++) {
          if (tester.widget<FilledButton>(confirm).onPressed != null) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.text('无法载入定位照片，请取消后重新分析。'), findsNothing);
        expect(
          tester.widget<FilledButton>(confirm).onPressed,
          isNotNull,
          reason: 'The real source-positioned image must decode before confirmation.',
        );
      }
    }
  }

  List<Json> additions() => core.calls
      .where(
        (c) => c.$1 == 'media.retouchChange' && c.$2['action'] == 'addHeals',
      )
      .map((c) => c.$2)
      .toList();

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  testWidgets(
    'Blemish review cancellation leaves staged skin analysis and existing edits uninstalled',
    (tester) async {
      await open(tester);
      (core.snapshots['start']!['portrait'] as Json)['hasSkinMask'] = false;
      await analyze(tester);
      expect(find.byType(RetouchBlemishReview), findsOneWidget);
      expect(
        core.calls.any(
          (c) => c.$1 == 'media.retouchAnalyze' && c.$2['mode'] == 'skin',
        ),
        isTrue,
      );
      await tester.tap(find.text('取消').last);
      await settle(tester);
      expect(additions(), isEmpty);
      await tester.tap(find.text('应用'));
      await settle(tester);
      expect(applied?['localData'], 'start');
      expect(object(applied?['portrait'])['hasSkinMask'], false);
      expect((object(applied?['portrait'])['heals'] as List).length, 2);
      await close(tester);
    },
  );

  testWidgets(
    'Blemish markers use read-only source positioning while selected native heal installs once with all edits',
    (tester) async {
      ((object(core.snapshots['start']!['portrait'])['body'] as List)[0]
              as Json)['amount'] =
          35;
      // SharedRetouch describes every non-neutral body with this flag.
      core.snapshots['start']!['sourcePositioning'] = true;
      core.beforeBodyCopies = true;
      await open(tester);
      final accepted = object(
        jsonDecode(
          jsonEncode(
            tester
                .widget<RetouchDetailPreview>(find.byType(RetouchDetailPreview))
                .frame,
          ),
        ),
      );
      final acceptedPath = accepted['path'] as String;
      final origin = core.acceptedPreviewOrigins[acceptedPath];
      expect(
        origin,
        isNotNull,
        reason: 'The displayed frame must correspond to a real accepted readonly request.',
      );
      expect(origin!['operation'], 'media.reviewPreview');
      final previewCall = object(origin['payload']);
      expect(previewCall['owner'], 'alice');
      expect(previewCall['path'], '${directory.path}/original.jpg');
      expect(accepted['sourceSha'], core.sourceSha);
      expect(accepted['_retouchBeforeBody'], true);
      final callsBefore = core.calls.length;
      await analyze(tester);
      final review = tester.widget<RetouchBlemishReview>(
        find.byType(RetouchBlemishReview),
      );
      expect(review.imagePath, acceptedPath);
      final candidateFrame = tester
          .widget<RetouchDetailPreview>(
            find.descendant(
              of: find.byType(RetouchBlemishReview),
              matching: find.byType(RetouchDetailPreview),
            ),
          )
          .frame;
      expect(candidateFrame['path'], acceptedPath);
      expect(candidateFrame['sourceSha'], core.sourceSha);
      expect(candidateFrame['_detailRecipe'], accepted['_detailRecipe']);
      expect(
        core.calls
            .skip(callsBefore)
            .where((c) => c.$1 == 'media.reviewPreview'),
        isEmpty,
        reason: 'Candidate review reuses the accepted before-body frame.',
      );
      final recipe = object(candidateFrame['_detailRecipe']);
      expect(recipe, object(previewCall['recipe']));
      expect(recipe['geometry'], isEmpty);
      expect(recipe['border'], isEmpty);
      expect(recipe['localData'], startsWith('view-'));
      final positioned = core.snapshots[recipe['localData']]!;
      expect((object(positioned['portrait'])['body'] as List)[0]['amount'], 0);
      await tester.tap(find.byKey(const ValueKey('blemish-checkbox-0')));
      await settle(tester);
      await tester.tap(find.text('修复所选'));
      await settle(tester);
      final added = additions().single;
      expect(added['localData'], 'start');
      expect(object(added['value'])['heals'], [core.candidates[1]]);
      await tester.tap(find.text('应用'));
      await settle(tester);
      expect((object(applied?['portrait'])['body'] as List)[0]['amount'], 35);
      expect(applied?['patchCount'], 1);
      expect((object(applied?['portrait'])['faces'] as List).length, 1);
      expect((object(applied?['portrait'])['heals'] as List).length, 3);
      await close(tester);
    },
  );

  testWidgets(
    'Blemish confirmation is one parent undo and redo restores the whole selected batch',
    (tester) async {
      await open(tester);
      await analyze(tester);
      await tester.tap(find.text('修复所选'));
      await settle(tester);
      expect(object(additions().single['value'])['heals'], core.candidates);
      await tester.tap(find.bySemanticsLabel('撤销'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('重做'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('撤销'));
      await settle(tester);
      await tester.tap(find.text('应用'));
      await settle(tester);
      expect(applied?['localData'], 'start');
      expect((object(applied?['portrait'])['heals'] as List).length, 2);
      expect(additions(), hasLength(1));
      await close(tester);
    },
  );

  testWidgets(
    'Account change during blemish review closes its private image and cannot apply candidates',
    (tester) async {
      await open(tester);
      await analyze(tester);
      expect(find.byType(RetouchBlemishReview), findsOneWidget);
      state.session = {
        'user': {'id': 'bob'},
      };
      state.notifyListeners();
      await settle(tester);
      expect(find.byType(RetouchBlemishReview), findsNothing);
      expect(find.text('修复所选'), findsNothing);
      expect(additions(), isEmpty);
      expect(applied, isNull);
      await close(tester);
    },
  );

  testWidgets(
    'Late blemish analysis cannot reopen review after account leaves and returns',
    (tester) async {
      await open(tester);
      final gate = Completer<void>();
      core.analyzeGate = gate;
      await analyze(tester, held: true);
      state.session = {
        'user': {'id': 'bob'},
      };
      state.notifyListeners();
      state.session = {
        'user': {'id': 'alice'},
      };
      state.notifyListeners();
      gate.complete();
      await settle(tester);
      expect(find.byType(RetouchBlemishReview), findsNothing);
      expect(additions(), isEmpty);
      expect(core.cancelledJobs, isNotEmpty);
      await close(tester);
    },
  );

  testWidgets(
    'Late confirmed blemish rendering cannot return edits after parent cancellation',
    (tester) async {
      await open(tester);
      await analyze(tester);
      final gate = Completer<void>();
      core.applyPreviewGate = gate;
      await tester.tap(find.text('修复所选'));
      await tester.pumpAndSettle();
      expect(additions(), hasLength(1));
      await tester.tap(find.byTooltip('取消人像精修'));
      await tester.pump();
      gate.complete();
      await settle(tester);
      expect(completed, 1);
      expect(applied, isNull);
      expect(find.text('父编辑器'), findsOneWidget);
      expect(core.calls.where((c) => c.$1 == 'draft.save'), isEmpty);
      await close(tester);
    },
  );
}
