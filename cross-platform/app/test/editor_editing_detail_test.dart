import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editing_detail_preview.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/split_compare.dart';
import 'package:huevia/theme.dart';

import 'editor_color_workspace_test.dart' show tool;
import 'editor_realtime_preview_test.dart'
    show PreviewCall, RealtimeCore, RealtimeState;

final _ordinary = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAYAAABr5z2BAAAAF0lEQVR4nGOQWBD1nxLMMGrAqAHDwwAAqUGM0LHkvF4AAAAASUVORK5CYII=',
);
final _full = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAYAAACbU/80AAAAK0lEQVR4nO3OIQEAAAgDMEIQkUzUhRg3E/Ornr2kEhAQEBAQEBAQEBBIBx6hdydbj1D+7AAAAABJRU5ErkJggg==',
);

/// UI orchestration bridge: real 16x12/32x24 PNGs, one serial native worker.
/// Native engine pixels and device memory are verified by the platform gate.
class _DetailCore extends RealtimeCore {
  _DetailCore() {
    // Production SharedRuntime exposes a canonical private root. On Apple,
    // systemTemp may spell that same directory through the /var alias.
    root = Directory(root).resolveSymbolicLinksSync();
    source.writeAsBytesSync(_full);
  }
  String get sourcePath => source.resolveSymbolicLinksSync();
  String get sourceSha => sha256.convert(_full).toString();
  final requests = <(String, Json, String?)>[];
  final tokens = <String, String>{};
  Future<void> tail = Future<void>.value();
  bool holdNextFull = false, holdNextTile = false;
  Completer<void>? fullWaiter, tileWaiter;
  String? blockedJob;
  int nativeActive = 0, maxNativeActive = 0;
  Iterable<Json> get fullRequests => requests
      .where((request) => request.$1 == 'media.detailRender')
      .map((request) => request.$2);
  Iterable<Json> get tileRequests => requests
      .where((request) => request.$1 == 'media.detailTile')
      .map((request) => request.$2);

  String file(List<int> pixels) {
    final path =
        '$root/previews/00000000-0000-4000-8000-${(++serial).toString().padLeft(12, '0')}.png';
    File(path).writeAsBytesSync(pixels);
    return path;
  }

  @override
  Json image() => {'path': file(_ordinary), 'width': 16, 'height': 12};

  Future<Json> serialRequest(Future<Json> Function() body) {
    final result = Completer<Json>();
    tail = tail.then((_) async {
      nativeActive++;
      if (nativeActive > maxNativeActive) maxNativeActive = nativeActive;
      try {
        result.complete(await body());
      } catch (failure, stack) {
        result.completeError(failure, stack);
      } finally {
        nativeActive--;
      }
    });
    return result.future;
  }

  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
    if (blockedJob != jobId) return;
    for (final waiter in [fullWaiter, tileWaiter]) {
      if (waiter != null && !waiter.isCompleted) {
        waiter.completeError(const AppFailure('fixture native cancellation'));
      }
    }
  }

  void releaseHeld() {
    for (final waiter in [fullWaiter, tileWaiter]) {
      if (waiter != null && !waiter.isCompleted) waiter.complete();
    }
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) {
    final frozen = object(jsonDecode(jsonEncode(payload)));
    requests.add((operation, frozen, jobId));
    if (operation == 'draft.load' || operation == 'draft.save') {
      return Future.value({'sourceSha': sourceSha});
    }
    if (operation == 'source.inspect') {
      return Future.value({'sourceSha': sourceSha});
    }
    if (operation == 'media.preview' || operation == 'media.reviewPreview') {
      return serialRequest(() async {
        calls.add(
          PreviewCall(
            object(frozen['recipe']),
            frozen['maxEdge'] as int,
            jobId,
          ),
        );
        return image();
      });
    }
    if (operation == 'media.detailRender' || operation == 'media.detailTile') {
      return serialRequest(() async {
        if (cancelled.contains(jobId)) throw const AppFailure('retired job');
        if (frozen['expectedSourceSha'] != sourceSha) {
          throw const AppFailure('fixture source SHA mismatch');
        }
        final hold = operation == 'media.detailRender'
            ? holdNextFull
            : holdNextTile;
        if (hold) {
          final waiter = Completer<void>();
          if (operation == 'media.detailRender') {
            holdNextFull = false;
            fullWaiter = waiter;
          } else {
            holdNextTile = false;
            tileWaiter = waiter;
          }
          blockedJob = jobId;
          try {
            await waiter.future;
          } finally {
            if (blockedJob == jobId) blockedJob = null;
          }
        }
        if (operation == 'media.detailRender') {
          final path = file(_full), token = 'detail-$serial';
          tokens[path] = token;
          return {
            'path': path,
            'width': 32,
            'height': 24,
            'sourceSha': sourceSha,
            'detailToken': token,
            'temporary': true,
            'fullResolution': true,
          };
        }
        return {
          'path': file(_ordinary),
          'width': 16,
          'height': 12,
          'sourceWidth': 32,
          'sourceHeight': 24,
          'sourceSha': sourceSha,
          'detailToken': tokens[frozen['path']],
          'region': frozen['region'],
          'temporary': true,
        };
      });
    }
    return super.call(operation, frozen, jobId);
  }
}

Future<void> _frames(WidgetTester tester, {int count = 24}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 30));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready, {
  required String reason,
  String Function()? diagnostics,
}) async {
  // FileImage and the HD codec finish on real IO, independently of fake time.
  // A fixed number of pumps is not an installation/completion barrier on CI.
  for (var tick = 0; tick < 200; tick++) {
    await tester.pump(const Duration(milliseconds: 30));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    if (ready()) return;
  }
  fail('$reason${diagnostics == null ? '' : ' ${diagnostics()}'}');
}

void _cleanup(WidgetTester tester, _DetailCore core, {RealtimeState? state}) {
  addTearDown(() async {
    core.releaseHeld();
    await tester.pumpWidget(const SizedBox());
    await _frames(tester, count: 5);
    state?.dispose();
    tester.binding.imageCache.clear();
    tester.binding.imageCache.clearLiveImages();
    expect(core.source.readAsBytesSync(), _full);
    await tester.runAsync(() => Directory(core.root).delete(recursive: true));
  });
}

Future<({dynamic editor, RealtimeState state})> _open(
  WidgetTester tester,
  _DetailCore core,
) async {
  tester.view.physicalSize = const Size(400, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final state = RealtimeState(core);
  _cleanup(tester, core, state: state);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('cc.huevia/events'),
        (_) async => null,
      );
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.dark),
      home: EditorPage(
        state: state,
        photo: Photo(core.sourcePath, '高清编辑测试', const {}),
      ),
    ),
  );
  await _frames(tester);
  final dynamic editor = tester.state(find.byType(EditorPage));
  expect(editor.restored, isTrue);
  expect(editor.preview, isNotNull);
  return (editor: editor, state: state);
}

TransformationController _transform(WidgetTester tester, Finder photograph) =>
    tester
        .widget<InteractiveViewer>(
          find.descendant(
            of: photograph,
            matching: find.byType(InteractiveViewer),
          ),
        )
        .transformationController!;

Matrix4 _zoomAtCenter(Size size, double zoom) =>
    Matrix4.diagonal3Values(zoom, zoom, 1)..setTranslationRaw(
      size.width * (1 - zoom) / 2,
      size.height * (1 - zoom) / 2,
      0,
    );

void main() {
  testWidgets(
    'SplitCompare HD uses the zoomed photo plane without moving selection or either source',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final core = _DetailCore();
      _cleanup(tester, core);
      final before = core.image()['path'] as String,
          effect = core.image()['path'] as String;
      final selection = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(_ordinary);
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      });
      final recipe = Recipe()..setValue(1, 35);
      final controllers = List.generate(
        2,
        (i) => EditingDetailPreviewController(
          core: core,
          owner: '',
          sourcePath: core.sourcePath,
          isCurrent: () => true,
          maxTileEdge: 2048,
        ),
      );
      addTearDown(() {
        for (final controller in controllers) {
          controller.dispose();
        }
        selection?.dispose();
      });
      for (var i = 0; i < controllers.length; i++) {
        controllers[i].configure(
          recipe: i == 0 ? recipe.data : Recipe().data,
          revision: 1,
          frameIdentity: i == 0 ? effect : before,
          outputSize: const Size(16, 12),
          expectedSourceSha: core.sourceSha,
        );
      }
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                height: 480,
                child: SplitCompare(
                  effect: effect,
                  original: before,
                  enabled: true,
                  effectSize: const Size(16, 12),
                  selection: selection,
                  selectionSize: const Size(16, 12),
                  detailController: controllers[0],
                  originalDetailController: controllers[1],
                ),
              ),
            ),
          ),
        ),
      );
      final photograph = find.byType(SplitCompare);
      final transform = _transform(tester, photograph);
      final matrix = _zoomAtCenter(const Size(320, 480), 32);
      transform.value = matrix.clone();
      await _until(
        tester,
        () => controllers.every((controller) => controller.tile != null),
        reason: 'Both comparison planes must install decoded tiles before inspection.',
        diagnostics: () => 'errors=${controllers.map((c) => c.error).toList()}',
      );
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .maxScale,
        32,
      );
      expect(
        controllers.map((controller) => controller.tile),
        everyElement(isNotNull),
        reason:
            'viewport=${tester.getSize(photograph)}; errors=${controllers.map((c) => c.error).toList()}; requests=${core.requests.map((r) => r.$1).toList()}',
      );
      final requested = object(core.tileRequests.last['region']);
      expect(requested['left'] as num, lessThanOrEqualTo(.484375));
      expect(requested['right'] as num, greaterThanOrEqualTo(.515625));
      expect(
        (requested['right'] as num) - (requested['left'] as num),
        lessThan(.05),
      );
      expect(transform.value, matrix);
      final displayed = tester.widget<SplitCompare>(photograph);
      expect(
        (displayed.effect, displayed.original, displayed.effectSize),
        (effect, before, const Size(16, 12)),
      );
      expect(displayed.selection, same(selection));
      expect(
        core.fullRequests.map(
          (p) => (object(p['recipe'])['values'] as List)[1],
        ),
        unorderedEquals([35, 0]),
      );
      expect(core.maxNativeActive, 1);
    },
  );

  testWidgets(
    'Editor mutation immediately cancels held full detail and final accepted recipe restores HD',
    (tester) async {
      final core = _DetailCore()..holdNextFull = true;
      final fixture = await _open(tester, core);
      final dynamic editor = fixture.editor;
      expect(core.fullWaiter, isNotNull);
      final details = tester
          .widget<SplitCompare>(find.byType(SplitCompare))
          .detailController!;
      final blocked = core.blockedJob;
      final oldFrame = editor.preview as String;
      editor.change(() => editor.recipe.setValue(1, 45), snapshot: false);
      expect(details.enabled, isFalse);
      expect(core.cancelled, contains(blocked));
      expect(core.fullWaiter!.isCompleted, isTrue);
      await _frames(tester);
      await _until(
        tester,
        () =>
            details.tile?.frameIdentity == editor.preview &&
            !details.loading &&
            core.calls.last.edge == 1280,
        reason: 'The settled native frame must install its own final HD tile.',
        diagnostics: () => 'error=${details.error}; loading=${details.loading}',
      );
      expect(editor.preview, isNot(oldFrame));
      expect(core.calls.last.exposure, 45);
      expect(core.calls.last.edge, 1280);
      expect(
        (object(editor.displayedOverlay)['recipe']['values'] as List)[1],
        45,
      );
      expect(details.enabled, isTrue);
      expect(details.tile, isNotNull);
      final frozen = core.fullRequests.last;
      expect((object(frozen['recipe'])['values'] as List)[1], 45);
      expect(frozen['expectedSourceSha'], core.sourceSha);
      expect(core.maxNativeActive, 1);
    },
  );

  testWidgets(
    'Colour workspace owns its HD viewport while hidden main route and late owner results cannot replace it',
    (tester) async {
      final core = _DetailCore();
      final fixture = await _open(tester, core);
      final dynamic editor = fixture.editor;
      editor.change(() => editor.recipe.setValue(1, 35), snapshot: false);
      await _frames(tester);
      editor.setState(() => editor.compare = true);
      unawaited(editor.render() as Future<void>);
      await _frames(tester);
      final beforeToolFulls = core.fullRequests.toList();
      expect(
        beforeToolFulls.any(
          (p) => (object(p['recipe'])['values'] as List)[1] == 0,
        ),
        isTrue,
      );
      expect(
        beforeToolFulls.any(
          (p) => (object(p['recipe'])['values'] as List)[1] == 35,
        ),
        isTrue,
      );
      await tester.tap(find.text('调节'));
      await tester.pump();
      await tool(tester, '曲线');
      final currentPhoto = find.byType(SplitCompare);
      final transform = _transform(tester, currentPhoto);
      final viewSize = tester.getSize(currentPhoto);
      transform.value = _zoomAtCenter(viewSize, 4);
      await _frames(tester);
      // A fresh accepted tool recipe binds its tile to the currently zoomed
      // workspace, even when the tiny fixture's earlier tile held all pixels.
      await tester.tap(find.text('加点'));
      await _frames(tester);
      final details = tester
          .widget<SplitCompare>(currentPhoto)
          .detailController!;
      await _until(
        tester,
        () =>
            details.tile?.frameIdentity ==
            tester.widget<SplitCompare>(currentPhoto).effect,
        reason: 'The accepted colour-workspace frame must have a decoded current tile.',
        diagnostics: () => 'error=${details.error}; loading=${details.loading}',
      );
      final shownRegion = details.tile!.region;
      expect(shownRegion.width, lessThan(.5));
      final hidden = find
          .byType(SplitCompare, skipOffstage: false)
          .evaluate()
          .where((element) => !ModalRoute.isCurrentOf(element)!)
          .single;
      final dynamic hiddenState = (hidden as StatefulElement).state;
      hiddenState.reportViewport();
      editor.setState(() {});
      editor.panelRevision.value++;
      await _frames(tester);
      await _until(
        tester,
        () => details.tile != null && !details.loading,
        reason: 'Any background-route viewport work must finish before verifying ownership.',
      );
      expect(details.tile!.region, shownRegion);
      expect(transform.value, _zoomAtCenter(viewSize, 4));
      core.holdNextTile = true;
      await tester.tap(find.text('加点'));
      await _until(
        tester,
        () => core.tileWaiter != null,
        reason: 'The changed tool recipe must reach the held tile job.',
      );
      expect(core.tileWaiter, isNotNull);
      fixture.state.changeOwner();
      expect(details.tile, isNull);
      core.releaseHeld();
      await _frames(tester);
      expect(details.tile, isNull);
      expect(core.source.readAsBytesSync(), _full);
    },
  );
}
