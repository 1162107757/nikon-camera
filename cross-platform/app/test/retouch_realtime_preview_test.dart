import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/retouch_original_controls.dart';
import 'package:huevia/retouch_workspace.dart';
import 'package:huevia/theme.dart';

import 'retouch_workspace_test.dart' show PortraitMenuCore;

class RetouchFrameCall {
  RetouchFrameCall(this.edge, this.local, this.path);
  final int edge;
  final String local, path;
  final gate = Completer<void>();
}

class RealtimePortraitCore extends PortraitMenuCore {
  RealtimePortraitCore(super.directory);
  Completer<Json>? atmosphereGate;
  bool hold = false;
  int active = 0, maximumActive = 0;
  final frames = <RetouchFrameCall>[];
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'media.atmosphere' && atmosphereGate != null) {
      calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
      return atmosphereGate!.future;
    }
    if (operation != 'media.reviewPreview' &&
        operation != 'media.localPreview') {
      return super.call(operation, payload, jobId);
    }
    calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
    final path = '$root/previews/realtime-${frames.length}.png';
    File('$root/previews/portrait.png').copySync(path);
    final pending = RetouchFrameCall(
      payload['maxEdge'] as int,
      object(payload['recipe'])['localData'] as String,
      path,
    );
    frames.add(pending);
    active++;
    if (active > maximumActive) maximumActive = active;
    try {
      if (hold) await pending.gate.future;
      return {'path': path, 'width': 8, 'height': 8};
    } finally {
      active--;
    }
  }
}

class RealtimePortraitState extends AppState {
  RealtimePortraitState(super.core);
  void owner(String value) {
    session = {
      'user': {'id': value},
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

  Future<
    ({RealtimePortraitCore core, RealtimePortraitState state, dynamic editor})
  >
  open(WidgetTester tester, {bool holdAtmosphere = false}) async {
    final directory = Directory.systemTemp.createTempSync(
      'huevia-retouch-realtime-',
    );
    Directory('${directory.path}/previews').createSync();
    File('${directory.path}/previews/portrait.png').writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAEklEQVR4nGMQWm3yHx9mGBkKAKq5fAFPbl0bAAAAAElFTkSuQmCC',
      ),
    );
    final core = RealtimePortraitCore(directory.path);
    if (holdAtmosphere) core.atmosphereGate = Completer<Json>();
    final state = RealtimePortraitState(core)..owner('alice');
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.dark),
        home: RetouchWorkspace(
          state: state,
          photo: Photo('${directory.path}/original.jpg', '人像样片', const {}),
          owner: 'alice',
          recipe: Recipe().data,
          isCurrent: () => true,
        ),
      ),
    );
    await pumpIo(tester);
    await tester.tap(find.text('面部'));
    await pumpIo(tester);
    await tester.tap(find.text('提亮').first);
    await tester.pump();
    final dynamic editor = tester.state(find.byType(RetouchWorkspace));
    expect(editor.busy, isFalse);
    core.hold = true;
    return (core: core, state: state, editor: editor);
  }

  RetouchOriginalSlider scalar(WidgetTester tester) =>
      tester.widget<RetouchOriginalSlider>(
        find.byWidgetPredicate(
          (widget) => widget is RetouchOriginalSlider && widget.label == '提亮',
        ),
      );
  Future<void> close(WidgetTester tester, RealtimePortraitState state) async {
    await tester.pumpWidget(const SizedBox());
    await pumpIo(tester);
    state.dispose();
    tester.binding.imageCache.clear();
    tester.binding.imageCache.clearLiveImages();
  }

  testWidgets(
    'Portrait slider publishes continuous native candidates and records only one final undo',
    (tester) async {
      final f = await open(tester), core = f.core;
      final dynamic editor = f.editor;
      final slider = scalar(tester);
      slider.onChangeStart!(0);
      slider.onChanged!(10);
      await tester.pump();
      final first = core.frames.last;
      expect(first.edge, 640);
      slider.onChanged!(20);
      first.gate.complete();
      await pumpIo(tester);
      expect(editor.frame['path'], first.path);
      expect(editor.undo, isEmpty);
      final second = core.frames.last;
      expect(second, isNot(same(first)));
      slider.onChanged!(30);
      slider.onChangeEnd!(30);
      second.gate.complete();
      await pumpIo(tester);
      expect(editor.frame['path'], second.path);
      final third = core.frames.last;
      expect(third.edge, 640);
      third.gate.complete();
      await pumpIo(tester);
      final finalFrame = core.frames.last;
      expect(finalFrame.edge, 1280);
      expect(editor.undo, isEmpty);
      // A fresh pointer while final refinement is pending must not start a second
      // gesture using the old gesture's callbacks or issue concurrent commands.
      slider.onChangeStart!(30);
      slider.onChanged!(70);
      slider.onChangeEnd!(70);
      finalFrame.gate.complete();
      await pumpIo(tester);
      expect(editor.frame['path'], finalFrame.path);
      expect(editor.chosen['brightness'], 30);
      expect(editor.undo, hasLength(1));
      expect(editor.scalarStart, isNull);
      expect(core.maximumActive, 1);
      core.hold = false;
      final history = editor.history(false) as Future<void>;
      await pumpIo(tester);
      await history;
      expect(editor.chosen['brightness'], 0);
      expect(editor.redo, hasLength(1));
      expect(core.cancelledJobs, isEmpty);
      expect(tester.takeException(), isNull);
      await close(tester, f.state);
    },
  );

  testWidgets(
    'Portrait cancel restores the gesture start and discards the held candidate without history',
    (tester) async {
      final f = await open(tester), core = f.core;
      final dynamic editor = f.editor;
      final start = editor.frame['path'];
      final slider = scalar(tester);
      slider.onChangeStart!(0);
      slider.onChanged!(10);
      await tester.pump();
      final first = core.frames.last;
      first.gate.complete();
      await pumpIo(tester);
      expect(editor.chosen['brightness'], 10);
      slider.onChanged!(20);
      await tester.pump();
      final late = core.frames.last;
      slider.onChangeCancel!();
      late.gate.complete();
      await pumpIo(tester);
      expect(editor.chosen['brightness'], 0);
      expect(editor.frame['path'], start);
      expect(editor.undo, isEmpty);
      expect(editor.scalarStart, isNull);
      expect(core.frames.last, same(late));
      expect(tester.takeException(), isNull);
      await close(tester, f.state);
    },
  );

  testWidgets(
    'Portrait light pad previews continuously and settles one exact full-quality result',
    (tester) async {
      final f = await open(tester), core = f.core;
      final dynamic editor = f.editor;
      editor.refreshPortrait(() => editor.faceParameter = 'LIGHT_X');
      await tester.pump();
      final pad = tester.widget<RetouchOriginalLightPad>(
        find.byType(RetouchOriginalLightPad),
      );
      pad.onChangeStart!();
      pad.onChanged!(const Offset(10, 15));
      await tester.pump();
      final first = core.frames.last;
      expect(first.edge, 640);
      pad.onChanged!(const Offset(25, 35));
      first.gate.complete();
      await pumpIo(tester);
      expect(editor.frame['path'], first.path);
      final second = core.frames.last;
      pad.onChangeEnd!();
      second.gate.complete();
      await pumpIo(tester);
      final finalFrame = core.frames.last;
      expect(finalFrame.edge, 1280);
      expect(editor.undo, isEmpty);
      finalFrame.gate.complete();
      await pumpIo(tester);
      expect(editor.chosen['LIGHT_X'], 25);
      expect(editor.chosen['LIGHT_Y'], 35);
      expect(editor.undo, hasLength(1));
      expect(core.maximumActive, 1);
      expect(tester.takeException(), isNull);
      await close(tester, f.state);
    },
  );

  testWidgets(
    'Late portrait atmosphere cannot revive after the account leaves and returns',
    (tester) async {
      final f = await open(tester, holdAtmosphere: true), core = f.core;
      final dynamic editor = f.editor;
      expect(
        core.calls.where((call) => call.$1 == 'media.atmosphere'),
        hasLength(1),
      );
      expect(editor.atmosphere, isNull);
      final latePath = '${core.root}/previews/late-atmosphere.png';
      File('${core.root}/previews/portrait.png').copySync(latePath);
      addTearDown(() {
        if (!core.atmosphereGate!.isCompleted) {
          core.atmosphereGate!.complete({'path': latePath});
        }
      });
      f.state.owner('bob');
      f.state.owner('alice');
      core.atmosphereGate!.complete({'path': latePath});
      await pumpIo(tester);
      expect(editor.atmosphere, isNull);
      expect(editor.frame, isNull);
      expect(editor.data, isNull);
      expect(File(latePath).existsSync(), isFalse);
      expect(tester.takeException(), isNull);
      await close(tester, f.state);
    },
  );

  testWidgets(
    'Portrait owner leave and return cannot revive a held gesture or its pending sample',
    (tester) async {
      final f = await open(tester), core = f.core;
      final dynamic editor = f.editor;
      final slider = scalar(tester);
      slider.onChangeStart!(0);
      slider.onChanged!(10);
      await tester.pump();
      final late = core.frames.last;
      slider.onChanged!(20);
      f.state.owner('bob');
      f.state.owner('alice');
      late.gate.complete();
      await pumpIo(tester);
      expect(editor.frame, isNull);
      expect(editor.data, isNull);
      expect(editor.undo, isEmpty);
      expect(core.frames.last, same(late));
      expect(core.cancelledJobs, isNotEmpty);
      expect(tester.takeException(), isNull);
      await close(tester, f.state);
    },
  );
}
