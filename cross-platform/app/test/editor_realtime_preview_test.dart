import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/theme.dart';

class PreviewCall {
  PreviewCall(this.recipe, this.edge, this.job);
  final Json recipe;
  final int edge;
  final String? job;
  final result = Completer<Json>();
  int get exposure => (recipe['values'] as List)[1] as int;
}

class RealtimeCore extends HueviaCore {
  RealtimeCore() {
    root = Directory.systemTemp.createTempSync('huevia-realtime-preview-').path;
    Directory('$root/previews').createSync();
    source = File('$root/source.png')..writeAsBytesSync(png);
    schema = {
      'parameters': List.generate(
        17,
        (i) => {
          'index': i,
          'name': i == 1 ? 'EXPOSURE' : 'BRIGHTNESS',
          'label': i == 1 ? '曝光' : '参数$i',
          'min': -100,
          'max': 100,
          'help': '参数说明',
        },
      ),
    };
  }
  static final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
  );
  late final File source;
  bool gate = false;
  Completer<Json>? atmosphereGate;
  int atmosphereRequests = 0;
  int serial = 0, active = 0, maximumActive = 0;
  final calls = <PreviewCall>[];
  final cancelled = <String>[];
  Json image() {
    final path = '$root/previews/frame-${serial++}.png';
    File(path).writeAsBytesSync(png);
    return {'path': path, 'width': 1, 'height': 1};
  }

  @override
  Future<void> cancel(String jobId) async => cancelled.add(jobId);

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'editor.catalog') return {'status': 'ok', 'items': []};
    if (operation == 'draft.load') return {'sourceSha': 'fixture-sha'};
    if (operation == 'draft.save') return {'sourceSha': 'fixture-sha'};
    if (operation == 'local.describe') {
      return {'localData': '', 'sha256': 'empty', 'regions': []};
    }
    if (operation == 'media.preview') {
      final pending = PreviewCall(
        object(jsonDecode(jsonEncode(payload['recipe']))),
        payload['maxEdge'] as int,
        jobId,
      );
      calls.add(pending);
      if (!gate) return image();
      active++;
      if (active > maximumActive) maximumActive = active;
      try {
        return await pending.result.future;
      } finally {
        active--;
      }
    }
    if (operation == 'media.atmosphere') {
      atmosphereRequests++;
      final held = atmosphereGate;
      return held == null ? image() : await held.future;
    }
    if (operation == 'media.reviewPreview' ||
        operation == 'media.originalPreview') {
      return image();
    }
    throw AppFailure(operation);
  }
}

class RealtimeState extends AppState {
  RealtimeState(super.core);
  void changeOwner() {
    session = {
      'user': {'id': 'another-owner'},
    };
    notifyListeners();
  }

  void restoreOwner() {
    session = {};
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<({RealtimeCore core, RealtimeState state, dynamic editor})> open(
    WidgetTester tester, {
    RealtimeCore? suppliedCore,
  }) async {
    final core = suppliedCore ?? RealtimeCore();
    final current = RealtimeState(core);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('cc.huevia/events'),
          (_) async => null,
        );
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.dark),
        home: EditorPage(
          state: current,
          photo: Photo(core.source.path, '测试照片', const {}),
        ),
      ),
    );
    // FileImage performs real IO outside the test clock.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    final dynamic editor = tester.state(find.byType(EditorPage));
    expect(editor.restored, isTrue);
    expect(editor.preview, isNotNull);
    core.gate = true;
    return (core: core, state: current, editor: editor);
  }

  Future<void> close(WidgetTester tester, RealtimeState state) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    state.dispose();
    tester.binding.imageCache.clear();
    tester.binding.imageCache.clearLiveImages();
  }

  testWidgets(
    'Editor displays native drag frames before quiet time and settles the latest full preview',
    (tester) async {
      final fixture = await open(tester), core = fixture.core;
      final dynamic editor = fixture.editor;
      final initialPath = editor.preview as String;
      void change(int value) => editor.change(
        () => editor.recipe.setValue(1, value),
        snapshot: false,
      );
      change(10);
      await tester.pump(const Duration(milliseconds: 30));
      final first = core.calls.last;
      expect(first.exposure, 10);
      expect(first.edge, 640);
      change(20);
      await tester.pump(const Duration(milliseconds: 30));
      final firstImage = core.image();
      first.result.complete(firstImage);
      await tester.pump();
      expect(editor.preview, firstImage['path']);
      expect(editor.preview, isNot(initialPath));
      expect(core.calls.last.exposure, 20);
      change(30);
      await tester.pump(const Duration(milliseconds: 30));
      final second = core.calls.last, secondImage = core.image();
      second.result.complete(secondImage);
      await tester.pump();
      expect(editor.preview, secondImage['path']);
      final slowThird = core.calls.last;
      expect(slowThird.exposure, 30);
      change(40);
      await tester.pump(const Duration(milliseconds: 181));
      final staleImage = core.image();
      slowThird.result.complete(staleImage);
      await tester.pump();
      // Once release/quiet has requested the final frame, a slow drag frame
      // cannot overwrite the last accepted display while final rendering waits.
      expect(editor.preview, secondImage['path']);
      for (var i = 0; i < 4 && core.calls.last.edge != 1280; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      final finalCall = core.calls.last;
      expect(finalCall.exposure, 40);
      expect(finalCall.edge, 1280);
      final finalImage = core.image();
      finalCall.result.complete(finalImage);
      await tester.pump();
      expect(editor.preview, finalImage['path']);
      expect(core.maximumActive, 1);
      expect(core.cancelled, isEmpty);
      expect(tester.takeException(), isNull);
      await close(tester, fixture.state);
    },
  );

  testWidgets(
    'Owner change discards a late native frame and never starts pending adjustments',
    (tester) async {
      final fixture = await open(tester), core = fixture.core;
      final dynamic editor = fixture.editor;
      editor.change(() => editor.recipe.setValue(1, 10), snapshot: false);
      await tester.pump(const Duration(milliseconds: 20));
      final pending = core.calls.last;
      editor.change(() => editor.recipe.setValue(1, 20), snapshot: false);
      fixture.state.changeOwner();
      final count = core.calls.length;
      pending.result.complete(core.image());
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(editor.preview, isNull);
      expect(core.calls.length, count);
      expect(core.cancelled, contains(pending.job));
      expect(tester.takeException(), isNull);
      await close(tester, fixture.state);
    },
  );

  testWidgets('Leaving the editor drops in-flight and pending previews', (
    tester,
  ) async {
    final fixture = await open(tester), core = fixture.core;
    final dynamic editor = fixture.editor;
    editor.change(() => editor.recipe.setValue(1, 10), snapshot: false);
    await tester.pump(const Duration(milliseconds: 20));
    final pending = core.calls.last;
    editor.change(() => editor.recipe.setValue(1, 20), snapshot: false);
    final count = core.calls.length;
    await close(tester, fixture.state);
    pending.result.complete(core.image());
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(core.calls.length, count);
    expect(core.cancelled, contains(pending.job));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Atmosphere responses retire across owner changes and cannot clear a newer loading request',
    (tester) async {
      final first = Completer<Json>();
      final core = RealtimeCore()..atmosphereGate = first;
      final fixture = await open(tester, suppliedCore: core);
      final dynamic editor = fixture.editor;
      core.gate = false;
      expect(core.atmosphereRequests, 1);
      expect(editor.atmosphereLoading, isTrue);
      fixture.state.changeOwner();
      expect(editor.atmosphereLoading, isFalse);
      final retiredFirst = core.image();
      first.complete(retiredFirst);
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(editor.atmosphere, isNull);

      fixture.state.restoreOwner();
      final second = Completer<Json>();
      core.atmosphereGate = second;
      editor.change(() => editor.recipe.setValue(1, 10), snapshot: false);
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(core.atmosphereRequests, 2);
      expect(editor.atmosphereLoading, isTrue);
      fixture.state.changeOwner();
      fixture.state.restoreOwner();
      final latest = Completer<Json>();
      core.atmosphereGate = latest;
      editor.change(() => editor.recipe.setValue(1, 20), snapshot: false);
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(core.atmosphereRequests, 3);
      second.complete(core.image());
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(editor.atmosphere, isNull);
      expect(editor.atmosphereLoading, isTrue);
      final accepted = core.image();
      latest.complete(accepted);
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(editor.atmosphere, accepted['path']);
      expect(editor.atmosphereLoading, isFalse);
      expect(tester.takeException(), isNull);
      await close(tester, fixture.state);
    },
  );
}
