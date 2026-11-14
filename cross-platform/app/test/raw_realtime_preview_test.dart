import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/raw_develop.dart';
import 'package:huevia/theme.dart';

class RawPreviewCall {
  RawPreviewCall(this.payload, this.job);
  final Json payload;
  final String? job;
  final result = Completer<Json>();
  int get exposure => object(payload['settings'])['exposure'] as int;
}

class RealtimeRawCore extends HueviaCore {
  RealtimeRawCore() {
    root = Directory.systemTemp.createTempSync('huevia-raw-realtime-').path;
    Directory('$root/previews').createSync();
  }
  final calls = <RawPreviewCall>[];
  final operations = <String>[];
  final cancelled = <String>[];
  bool hold = false;
  int serial = 0, active = 0, maximumActive = 0;
  Json image() {
    final path = '$root/previews/frame-${serial++}.png';
    File(path).writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
      ),
    );
    return {'path': path, 'rawColorStatus': 'fixture-neutral'};
  }

  @override
  Stream<dynamic> get operationProgress => const Stream.empty();
  @override
  Future<void> cancel(String jobId) async => cancelled.add(jobId);
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    operations.add(operation);
    if (operation != 'media.rawPreview') throw AppFailure(operation);
    final request = RawPreviewCall(
      object(jsonDecode(jsonEncode(payload))),
      jobId,
    );
    calls.add(request);
    if (!hold) return image();
    active++;
    if (active > maximumActive) maximumActive = active;
    try {
      return await request.result.future;
    } finally {
      active--;
    }
  }
}

class RealtimeRawState extends AppState {
  RealtimeRawState(super.core);
  void owner(String id) {
    session = {
      'user': {'id': id},
    };
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> pumpIo(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await tester.pump();
    }
  }

  Future<({RealtimeRawCore core, RealtimeRawState state, dynamic editor})> open(
    WidgetTester tester,
  ) async {
    final core = RealtimeRawCore();
    final current = RealtimeRawState(core)..owner('alice');
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.dark),
        home: RawDevelopPage(
          state: current,
          photo: Photo('${core.root}/source.nef', '测试.NEF', const {
            'raw': true,
          }),
        ),
      ),
    );
    await pumpIo(tester);
    final dynamic editor = tester.state(find.byType(RawDevelopPage));
    expect(editor.preview, isNotNull, reason: 'preview error: ${editor.error}');
    core.hold = true;
    return (core: core, state: current, editor: editor);
  }

  Future<void> close(WidgetTester tester, RealtimeRawState state) async {
    await tester.pumpWidget(const SizedBox());
    await pumpIo(tester);
    state.dispose();
    tester.binding.imageCache.clear();
    tester.binding.imageCache.clearLiveImages();
  }

  testWidgets(
    'RAW drag publishes native previews continuously and release renders the latest original settings',
    (tester) async {
      final f = await open(tester), core = f.core;
      final dynamic editor = f.editor;
      await tester.scrollUntilVisible(find.text('显影曝光'), 200);
      await tester.pump();
      final slider = tester.widget<Slider>(
        find.byWidgetPredicate(
          (widget) => widget is Slider && widget.min == -50 && widget.max == 50,
        ),
      );
      slider.onChanged!(1);
      await tester.pump(const Duration(milliseconds: 20));
      final first = core.calls.last;
      slider.onChanged!(2);
      final firstImage = core.image();
      first.result.complete(firstImage);
      await pumpIo(tester);
      expect(editor.preview, firstImage['path']);
      final second = core.calls.last;
      expect(second.exposure, 2);
      slider.onChanged!(3);
      final secondImage = core.image();
      second.result.complete(secondImage);
      await pumpIo(tester);
      expect(editor.preview, secondImage['path']);
      final third = core.calls.last;
      slider.onChanged!(4);
      slider.onChangeEnd!(4);
      third.result.complete(core.image());
      await pumpIo(tester);
      expect(editor.preview, secondImage['path']);
      final finalCall = core.calls.last;
      expect(finalCall.exposure, 4);
      expect(object(finalCall.payload['settings'])['quality'], 3);
      expect(finalCall.payload.containsKey('maxEdge'), isFalse);
      final finalImage = core.image();
      finalCall.result.complete(finalImage);
      await pumpIo(tester);
      expect(editor.preview, finalImage['path']);
      expect(core.maximumActive, 1);
      expect(core.cancelled, isEmpty);
      expect(core.operations.every((op) => op == 'media.rawPreview'), isTrue);
      expect(tester.takeException(), isNull);
      await close(tester, f.state);
    },
  );

  testWidgets(
    'RAW account leave and return never installs a late frame or starts pending work',
    (tester) async {
      final f = await open(tester), core = f.core;
      final dynamic editor = f.editor;
      editor.changed('exposure', 1);
      await tester.pump();
      final late = core.calls.last;
      editor.changed('exposure', 2);
      final count = core.calls.length;
      f.state.owner('bob');
      f.state.owner('alice');
      late.result.complete(core.image());
      await pumpIo(tester);
      expect(editor.preview, isNull);
      expect(core.calls.length, count);
      expect(core.cancelled, contains(late.job));
      expect(tester.takeException(), isNull);
      await close(tester, f.state);
    },
  );

  testWidgets(
    'RAW leaving cancels its own in-flight preview and drops pending settings',
    (tester) async {
      final f = await open(tester), core = f.core;
      final dynamic editor = f.editor;
      editor.changed('exposure', 1);
      await tester.pump();
      final late = core.calls.last;
      editor.changed('exposure', 2);
      final count = core.calls.length;
      await close(tester, f.state);
      late.result.complete(core.image());
      await pumpIo(tester);
      expect(core.calls.length, count);
      expect(core.cancelled, contains(late.job));
      expect(tester.takeException(), isNull);
    },
  );
}
