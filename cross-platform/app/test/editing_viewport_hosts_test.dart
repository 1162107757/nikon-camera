import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:huevia/crop_workspace.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editing_detail_preview.dart';
import 'package:huevia/editing_viewport.dart';
import 'package:huevia/legacy_local_workspace.dart';
import 'package:huevia/raw_develop.dart';
import 'package:huevia/selection_mask.dart';
import 'package:huevia/selection_workspace.dart';
import 'package:huevia/theme.dart';

import 'editor_workspace_test.dart' show WorkspaceState;
import 'selection_editor_test.dart' show seed, dot;
import 'selection_workspace_test.dart' show SelectionCore;

// Small compressed, genuinely sized pixels for the HD host contract. Native
// effect correctness and memory gates remain in the separate real fixtures.
Uint8List _solidPng(int width, int height) {
  final pixels = Uint8List((width * 4 + 1) * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final offset = y * (width * 4 + 1) + 1 + x * 4;
      pixels[offset] = 24;
      pixels[offset + 1] = 160;
      pixels[offset + 2] = 90;
      pixels[offset + 3] = 255;
    }
  }
  final result = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> data) {
    final bytes = Uint8List(data.length + 12);
    final header = ByteData.sublistView(bytes)..setUint32(0, data.length);
    bytes.setRange(4, 8, ascii.encode(type));
    bytes.setRange(8, 8 + data.length, data);
    var crc = 0xffffffff;
    for (var i = 4; i < data.length + 8; i++) {
      crc ^= bytes[i];
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
      }
    }
    header.setUint32(data.length + 8, crc ^ 0xffffffff);
    result.add(bytes);
  }

  final ihdr = Uint8List(13);
  ByteData.sublistView(ihdr)
    ..setUint32(0, width)
    ..setUint32(4, height);
  ihdr[8] = 8;
  ihdr[9] = 6;
  chunk('IHDR', ihdr);
  chunk('IDAT', ZLibEncoder().convert(pixels));
  chunk('IEND', []);
  return result.takeBytes();
}

class _Core extends SelectionCore {
  _Core({this.realPixels = false})
    : super(
        Directory(
          Directory.systemTemp
              .createTempSync('huevia-viewport-host-')
              .resolveSymbolicLinksSync(),
        ),
      ) {
    Directory('$root/raw-editor').createSync();
    if (realPixels) source.writeAsBytesSync(_solidPng(1600, 1200));
  }
  final bool realPixels;
  @override
  String copy() => realPixels
      ? (File(
          '$root/previews/preview-${count++}.png',
        )..writeAsBytesSync(_solidPng(800, 600))).path
      : super.copy();
  Completer<Json>? previewGate;
  Completer<Json>? rawPreviewGate, rawDevelopGate;
  String rawSha = 'a' * 64;
  final documents = <String, Json>{};
  final detailPaths = <String>[];
  String detailFile({bool tile = false}) {
    final path =
        '$root/previews/00000000-0000-4000-8000-${(++count).toString().padLeft(12, '0')}.png';
    File(path).writeAsBytesSync(
      tile
          ? base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAYAAABr5z2BAAAAF0lEQVR4nGOQWBD1nxLMMGrAqAHDwwAAqUGM0LHkvF4AAAAASUVORK5CYII=',
            )
          : _solidPng(1600, 1200),
    );
    detailPaths.add(path);
    return path;
  }

  @override
  Stream<dynamic> get operationProgress => const Stream.empty();
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'media.preview' && previewGate != null) {
      calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
      return previewGate!.future;
    }
    if (operation == 'media.rawPreview') {
      calls.add((operation, payload));
      if (rawPreviewGate != null) return rawPreviewGate!.future;
      return {
        'path': copy(),
        'width': 800,
        'height': 600,
        'sourceSha': 'a' * 64,
      };
    }
    if (operation == 'media.rawDevelop') {
      calls.add((operation, payload));
      if (rawDevelopGate != null) return rawDevelopGate!.future;
      final path = source
          .copySync('$root/raw-editor/working-${count++}.png')
          .path;
      return {
        'path': path,
        'sourceSha': rawSha,
        'settings': payload['settings'],
      };
    }
    if (operation == 'source.inspect') {
      calls.add((operation, payload));
      return {'sourceSha': 'a' * 64};
    }
    if (operation == 'media.detailRender') {
      calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
      final path = detailFile();
      final value = <String, dynamic>{
        'path': path,
        'width': 1600,
        'height': 1200,
        'sourceSha': 'a' * 64,
        'detailToken': 'detail-$count',
        'temporary': true,
        'fullResolution': true,
      };
      documents[path] = value;
      return value;
    }
    if (operation == 'media.detailTile') {
      calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
      final full = documents[payload['path']]!;
      return {
        'path': detailFile(tile: true),
        'width': 16,
        'height': 12,
        'sourceWidth': 1600,
        'sourceHeight': 1200,
        'sourceSha': 'a' * 64,
        'detailToken': full['detailToken'],
        'region': payload['region'],
        'temporary': true,
      };
    }
    if (operation == 'local.change' && payload['action'] == 'replaceTools') {
      calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
      final tools = object(payload['value']);
      return {
        'localData': jsonEncode(tools),
        'sha256': 'validated',
        ...tools,
        'regions': [
          {'id': 'preserved'},
        ],
        'opaque': 'preserved',
      };
    }
    if (operation == 'media.localPreview') {
      calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
      return {'path': copy(), 'width': 800, 'height': 600};
    }
    return super.call(operation, payload, jobId);
  }
}

class _RawState extends WorkspaceState {
  _RawState(super.core);
  @override
  Future<Photo> importPhoto(XFile selected, {String? displayName}) async =>
      Photo('${core.root}/working.jpg', displayName ?? 'working.jpg', {
        'raw': false,
        'width': 800,
        'height': 600,
      });
  @override
  Future<Photo> updatePhoto(Photo photo, Json metadata) async =>
      Photo(photo.path, photo.name, {...photo.info, ...metadata});
}

/// A parent photo pane using the public viewport binding after a tool completes.
class _ResultPhoto extends StatefulWidget {
  const _ResultPhoto(this.core, this.viewport, this.geometry);
  final _Core core;
  final EditingViewportState viewport;
  final Json geometry;
  @override
  State<_ResultPhoto> createState() => _ResultPhotoState();
}

class _ResultPhotoState extends State<_ResultPhoto> {
  final transform = TransformationController();
  late final binding = EditingViewportBinding(
    shared: widget.viewport,
    transform: transform,
  );
  @override
  void dispose() {
    binding.dispose();
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final rect = Alignment.center.inscribe(
        applyBoxFit(
          BoxFit.contain,
          const Size(240, 600),
          box.biggest,
        ).destination,
        Offset.zero & box.biggest,
      );
      binding.layout(
        viewport: box.biggest,
        imageRect: rect,
        plane: EditingViewportPlane.fromRecipe({
          'geometry': widget.geometry,
        }, sourceSize: const Size(800, 600)),
      );
      return ClipRect(
        child: Stack(
          children: [
            Positioned.fromRect(
              rect: MatrixUtils.transformRect(transform.value, rect),
              child: Image.file(
                widget.core.source,
                key: const ValueKey('applied-photo'),
                fit: BoxFit.fill,
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _io(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  final timer = Stopwatch()..start();
  while (!ready() && timer.elapsed < const Duration(seconds: 8)) {
    await _io(tester, 1);
  }
  expect(ready(), true, reason: reason);
}

EditingViewportState _seed({
  EditingViewportPlane? plane,
  Size source = const Size(800, 600),
}) {
  final state = EditingViewportState(), tc = TransformationController();
  const viewport = Size(400, 300), focus = Offset(.62, .43);
  final image = Alignment.center.inscribe(
    applyBoxFit(BoxFit.contain, source, viewport).destination,
    Offset.zero & viewport,
  );
  final actual = plane ?? EditingViewportPlane.identity;
  final point = actual.fromSource(focus);
  tc.value = Matrix4.identity()
    ..setEntry(0, 0, 3)
    ..setEntry(1, 1, 3)
    ..setEntry(0, 3, 200 - 3 * (image.left + point.dx * image.width))
    ..setEntry(1, 3, 150 - 3 * (image.top + point.dy * image.height));
  state.capture(tc, viewport: viewport, imageRect: image, plane: actual);
  tc.dispose();
  return state;
}

Widget _layout(BuildContext context, Widget photo, Widget panel) => Column(
  children: [
    SizedBox(
      key: const ValueKey('shared-photo-bounds'),
      height: 300,
      child: photo,
    ),
    Expanded(child: panel),
  ],
);

void _view(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _close(WidgetTester tester, AppState? state) async {
  await tester.pumpWidget(const SizedBox());
  await _io(tester);
  tester.binding.imageCache.clear();
  tester.binding.imageCache.clearLiveImages();
  state?.dispose();
}

Future<void> _pinch(WidgetTester tester, Offset center) async {
  final a = await tester.startGesture(
    center - const Offset(30, 0),
    pointer: 41,
  );
  final b = await tester.startGesture(
    center + const Offset(30, 0),
    pointer: 42,
  );
  await a.moveTo(center - const Offset(50, 0));
  await tester.pump();
  await b.moveTo(center + const Offset(80, 0));
  await tester.pump();
  await a.moveTo(center - const Offset(90, 0));
  await tester.pump();
  await a.up();
  await b.up();
  await tester.pump();
}

void main() {
  testWidgets(
    'Embedded crop shows borrowed frame at the existing source focus and cancels without navigation or deleting it',
    (tester) async {
      _view(tester);
      final core = _Core();
      core.previewGate = Completer<Json>();
      final borrowed = core.copy();
      const content = Rect.fromLTRB(.1, .1, .9, .9);
      final recipe = <String, dynamic>{
        'border': {'template': 1},
      };
      final plane = EditingViewportPlane.fromRecipe(
        recipe,
        sourceSize: const Size(800, 600),
        contentRect: content,
      );
      final viewport = _seed(plane: plane);
      final focus = viewport.focus;
      final results = <Json?>[];
      VoidCallback? back;
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.dark),
          home: Scaffold(
            appBar: AppBar(title: const Text('父编辑器')),
            body: CropWorkspace(
              core: core,
              photo: Photo(core.source.path, 'photo.png', {
                'width': 800,
                'height': 600,
              }),
              owner: '',
              recipe: recipe,
              viewportState: viewport,
              embedded: true,
              embeddedLayoutBuilder: _layout,
              initialFrame: {
                'path': borrowed,
                'width': 800,
                'height': 600,
                'sourceWidth': 800,
                'sourceHeight': 600,
                'recipe': recipe,
                '_viewportContentRect': {
                  'left': .1,
                  'top': .1,
                  'right': .9,
                  'bottom': .9,
                },
              },
              onFinished: results.add,
              onBackReady: (value) => back = value,
            ),
          ),
        ),
      );
      await _io(tester);
      expect(
        find.descendant(
          of: find.byType(CropWorkspace),
          matching: find.byType(Scaffold),
        ),
        findsNothing,
      );
      final image = tester.getRect(
        find.byKey(const ValueKey('crop-image-plane')),
      );
      final sourcePoint = plane.fromSource(focus);
      final painted = Offset(
        image.left + sourcePoint.dx * image.width,
        image.top + sourcePoint.dy * image.height,
      );
      expect(
        (painted -
                tester
                    .getRect(find.byKey(const ValueKey('shared-photo-bounds')))
                    .center)
            .distance,
        lessThan(.1),
      );
      expect(viewport.focus, focus);
      expect(viewport.zoom, 3);
      expect(back, isNotNull);
      back!();
      await tester.pump();
      expect(results, [null]);
      expect(viewport.focus, focus);
      expect(viewport.zoom, 3);
      expect(find.text('父编辑器'), findsOneWidget);
      final late = core.copy();
      core.previewGate!.complete({
        'path': late,
        'width': 800,
        'height': 600,
        'sourceWidth': 800,
        'sourceHeight': 600,
      });
      await _close(tester, null);
      expect(File(borrowed).existsSync(), true);
      expect(
        core.calls.any(
          (c) => c.$1 == 'draft.save' || c.$1.startsWith('version.'),
        ),
        false,
      );
    },
  );

  testWidgets(
    'Applying a crop that excludes the detail focus returns to a visible photo without fitting the viewport',
    (tester) async {
      _view(tester);
      final core = _Core(), viewport = _seed();
      Json? applied;
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.dark),
          home: Scaffold(
            appBar: AppBar(title: const Text('父编辑器')),
            body: StatefulBuilder(
              builder: (context, update) => applied == null
                  ? CropWorkspace(
                      core: core,
                      photo: Photo(core.source.path, 'photo.png', {
                        'width': 800,
                        'height': 600,
                      }),
                      owner: '',
                      recipe: {
                        'geometry': {
                          'left': 0,
                          'top': 0,
                          'right': 300000,
                          'bottom': 1000000,
                        },
                      },
                      viewportState: viewport,
                      embedded: true,
                      embeddedLayoutBuilder: _layout,
                      onFinished: (value) {
                        if (value == null) return;
                        viewport.constrainToPlane(
                          EditingViewportPlane.fromRecipe({
                            'geometry': value,
                          }, sourceSize: const Size(800, 600)),
                        );
                        update(() => applied = value);
                      },
                    )
                  : _layout(
                      context,
                      _ResultPhoto(core, viewport, applied!),
                      const Center(child: Text('已应用裁剪')),
                    ),
            ),
          ),
        ),
      );
      await _until(
        tester,
        () =>
            tester
                .widget<TextButton>(find.widgetWithText(TextButton, '应用'))
                .onPressed !=
            null,
        'The full crop plane is ready before applying',
      );
      expect(viewport.focus.dx, greaterThan(.3));
      await tester.tap(find.text('应用'));
      await tester.pump();
      expect(applied, isNotNull);
      expect(viewport.zoom, greaterThan(1));
      final plane = EditingViewportPlane.fromRecipe({
        'geometry': applied,
      }, sourceSize: const Size(800, 600));
      final point = plane.fromSource(viewport.focus);
      expect(point.dx, inInclusiveRange(0.0, 1.0));
      expect(point.dy, inInclusiveRange(0.0, 1.0));
      final visible = tester
          .getRect(find.byKey(const ValueKey('applied-photo')))
          .intersect(
            tester.getRect(find.byKey(const ValueKey('shared-photo-bounds'))),
          );
      expect(visible.width, greaterThan(0));
      expect(visible.height, greaterThan(0));
      expect(find.text('父编辑器'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _close(tester, null);
    },
  );

  testWidgets(
    'Embedded selection keeps photo bounds and source focus while switching tools and returns the validated result without a route',
    (tester) async {
      _view(tester);
      final core = _Core();
      final actual = WorkspaceState(core),
          viewport = _seed(source: const Size(1200, 800));
      final initial = seed(strokes: [dot()]);
      final results = <SelectionResult?>[];
      VoidCallback? back;
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.dark),
          home: Scaffold(
            appBar: AppBar(title: const Text('父编辑器')),
            body: SelectionWorkspace(
              state: actual,
              photo: Photo(core.source.path, 'photo.png', {}),
              owner: '',
              region: initial,
              localState: {
                'localData': 'base',
                'sha256': 'a' * 64,
                'regions': [initial],
              },
              frame: {
                'path': core.copy(),
                'width': 1200,
                'height': 800,
                'geometryWidth': 1200,
                'geometryHeight': 800,
              },
              maskBuilder: (input) async => buildSelectionMask(input),
              viewportState: viewport,
              embedded: true,
              embeddedLayoutBuilder: _layout,
              onFinished: results.add,
              onBackReady: (value) => back = value,
            ),
          ),
        ),
      );
      await _until(
        tester,
        () =>
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, '完成'))
                .onPressed !=
            null,
        'The existing selection mask is ready',
      );
      expect(
        find.descendant(
          of: find.byType(SelectionWorkspace),
          matching: find.byType(Scaffold),
        ),
        findsNothing,
      );
      final frame = tester.getRect(
            find.byKey(const ValueKey('selection-image-plane')),
          ),
          focus = viewport.focus;
      final bounds = tester.getRect(
        find.byKey(const ValueKey('shared-photo-bounds')),
      );
      await tester.tap(find.text('矩形'));
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('shared-photo-bounds'))),
        bounds,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('selection-image-plane'))),
        frame,
      );
      expect(viewport.focus, focus);
      expect(back, isNotNull);
      await _pinch(tester, bounds.center);
      expect(viewport.zoom, greaterThan(3));
      await _until(
        tester,
        () =>
            tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, '完成'))
                .onPressed !=
            null,
        'Navigation does not leave a tentative selection stroke',
      );
      await tester.tap(find.text('完成'));
      await _until(
        tester,
        () => results.isNotEmpty,
        'Embedded completion returns to the parent',
      );
      expect(results, hasLength(1));
      expect(results.single, isNotNull);
      final value = object(
        (results.single!.localState['regions'] as List).single,
      );
      expect(value['strokes'], initial['strokes']);
      expect(value['shapes'], isEmpty);
      expect(find.text('父编辑器'), findsOneWidget);
      await _close(tester, actual);
      expect(back, isNull);
    },
  );

  for (final embedded in [false, true]) {
    for (final changedSource in [false, true]) {
      testWidgets(
        '${embedded ? 'Embedded' : 'Standalone'} RAW to editor ${changedSource ? 'resets an independently changed source' : 'hands off the actual zoom and source focus'}',
        (tester) async {
          _view(tester);
          final core = _Core()..rawSha = (changedSource ? 'b' : 'a') * 64;
          final state = _RawState(core), viewport = _seed();
          EditingViewportState? received;
          final finishes = <bool>[];
          VoidCallback? back;
          final router = GoRouter(
            initialLocation: '/raw',
            routes: [
              GoRoute(
                path: '/raw',
                builder: (_, _) => Scaffold(
                  body: RawDevelopPage(
                    state: state,
                    photo: Photo('${core.root}/source.nef', 'source.nef', {
                      'raw': true,
                    }),
                    viewportState: viewport,
                    embedded: embedded,
                    embeddedLayoutBuilder: _layout,
                    onBackReady: (value) => back = value,
                    onFinished: finishes.add,
                  ),
                ),
              ),
              GoRoute(
                path: '/photo/:id',
                builder: (_, route) {
                  received = route.extra as EditingViewportState?;
                  return const Scaffold(body: Text('新编辑副本'));
                },
              ),
            ],
          );
          await tester.pumpWidget(
            MaterialApp.router(
              theme: hueviaTheme(Brightness.dark),
              routerConfig: router,
            ),
          );
          await _until(
            tester,
            () => find.byType(InteractiveViewer).evaluate().isNotEmpty,
            'The RAW preview is installed',
          );
          await _io(tester);
          expect(viewport.zoom, 3);
          if (embedded) {
            expect(back, isNotNull);
            expect(
              find.descendant(
                of: find.byType(RawDevelopPage),
                matching: find.byType(Scaffold),
              ),
              findsNothing,
            );
          }
          await _pinch(
            tester,
            tester.getRect(find.byType(InteractiveViewer)).center,
          );
          expect(viewport.zoom, greaterThan(3));
          final focus = viewport.focus, zoom = viewport.zoom;
          await tester.tap(find.text('完成显影，继续编辑'));
          await _until(
            tester,
            () => received != null,
            'The generated working photo carries a viewport handoff',
          );
          if (changedSource) {
            expect(received, isNot(same(viewport)));
            expect(received!.zoom, 1);
          } else {
            expect(received, same(viewport));
            expect(received!.focus, focus);
            expect(received!.zoom, zoom);
          }
          expect(
            core.calls.where((c) => c.$1 == 'media.rawDevelop'),
            hasLength(1),
          );
          expect(core.calls.any((c) => c.$1 == 'draft.save'), false);
          expect(finishes, embedded ? [true] : isEmpty);
          await _close(tester, state);
          expect(back, isNull);
          router.dispose();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'Embedded RAW keeps its borrowed photo while loading and Back retires a late working-file handoff',
    (tester) async {
      _view(tester);
      final core = _Core()
        ..rawPreviewGate = Completer<Json>()
        ..rawDevelopGate = Completer<Json>();
      final state = _RawState(core), viewport = _seed();
      final initial = core.copy(), finishes = <bool>[];
      VoidCallback? back;
      var closed = false, reachedEditor = false;
      late StateSetter parent;
      final router = GoRouter(
        initialLocation: '/raw',
        routes: [
          GoRoute(
            path: '/raw',
            builder: (_, _) => StatefulBuilder(
              builder: (context, set) {
                parent = set;
                return Scaffold(
                  body: Column(
                    children: [
                      const Text('父编辑器'),
                      Expanded(
                        child: closed
                            ? const Text('已返回')
                            : RawDevelopPage(
                                state: state,
                                photo: Photo(
                                  '${core.root}/source.nef',
                                  'source.nef',
                                  {'raw': true},
                                ),
                                viewportState: viewport,
                                embedded: true,
                                embeddedLayoutBuilder: _layout,
                                initialFrame: {
                                  'path': initial,
                                  'width': 800,
                                  'height': 600,
                                  'sourceWidth': 800,
                                  'sourceHeight': 600,
                                  'recipe': <String, dynamic>{},
                                },
                                onBackReady: (value) => back = value,
                                onFinished: (value) {
                                  finishes.add(value);
                                  parent(() => closed = true);
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          GoRoute(
            path: '/photo/:id',
            builder: (_, _) {
              reachedEditor = true;
              return const Scaffold(body: Text('不应跳转'));
            },
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          theme: hueviaTheme(Brightness.dark),
        ),
      );
      await _until(tester, () => back != null, 'The parent receives RAW Back');
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(viewport.focus.dx, closeTo(.62, 1e-6));
      expect(viewport.zoom, 3);
      await tester.tap(find.text('完成显影，继续编辑'));
      await _until(
        tester,
        () => core.calls.any((c) => c.$1 == 'media.rawDevelop'),
        'The real RAW action is held',
      );
      back!();
      await tester.pump();
      expect(finishes, [false]);
      final latePreview = core.copy();
      final lateFull = core.source
          .copySync('${core.root}/raw-editor/late.png')
          .path;
      core.rawPreviewGate!.complete({
        'path': latePreview,
        'width': 800,
        'height': 600,
        'sourceSha': 'a' * 64,
      });
      core.rawDevelopGate!.complete({
        'path': lateFull,
        'sourceSha': 'a' * 64,
        'settings': <String, dynamic>{},
      });
      await _until(
        tester,
        () => !File(latePreview).existsSync() && !File(lateFull).existsSync(),
        'Both late owned RAW results are discarded',
      );
      expect(reachedEditor, false);
      expect(
        File(initial).existsSync(),
        true,
        reason: 'The parent retains its borrowed preview',
      );
      expect(back, isNull);
      expect(core.calls.any((c) => c.$1 == 'draft.save'), false);
      await _close(tester, state);
      router.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Embedded legacy local tools preserve the photo plane, accept current localData HD tiles and navigate with two fingers without a stroke',
    (tester) async {
      _view(tester);
      final core = _Core(realPixels: true);
      final actual = WorkspaceState(core),
          viewport = _seed(),
          results = <Json?>[];
      final initial = core.copy();
      VoidCallback? back;
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.dark),
          home: Scaffold(
            body: Column(
              children: [
                const Text('父编辑器'),
                Expanded(
                  child: LegacyLocalWorkspace(
                    state: actual,
                    photo: Photo(core.source.path, 'own.png', {
                      'width': 1600,
                      'height': 1200,
                    }),
                    owner: '',
                    recipe: const {
                      'localData': 'frozen',
                      'exposure': 13,
                      'geometry': {'turns': 1},
                      'border': {'template': 3},
                    },
                    localState: const {
                      'localData': 'frozen',
                      'sha256': 'base',
                      'masks': [],
                      'clones': [],
                    },
                    frame: {
                      'path': initial,
                      'width': 800,
                      'height': 600,
                      'sourceWidth': 1600,
                      'sourceHeight': 1200,
                    },
                    isCurrent: () => true,
                    viewportState: viewport,
                    embedded: true,
                    embeddedLayoutBuilder: _layout,
                    onFinished: results.add,
                    onBackReady: (value) => back = value,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      EditingDetailPreviewController controller() => tester
          .widget<EditingDetailTileLayer>(find.byType(EditingDetailTileLayer))
          .controller;
      try {
        await _until(
          tester,
          () =>
              find.byType(EditingDetailTileLayer).evaluate().isNotEmpty &&
              controller().tile != null,
          'A genuine small PNG detail tile reaches the original image plane',
        );
      } catch (_) {
        debugPrint(
          'Legacy HD diagnostics: enabled=${controller().enabled}; error=${controller().error}; calls=${jsonEncode(core.calls.map((c) => [c.$1, c.$2]).toList())}',
        );
        rethrow;
      }
      final first = controller().tile!;
      debugPrint('Legacy viewport phase: initial HD installed');
      expect(first.image.width, 16);
      expect(first.image.height, 12);
      expect(first.frameIdentity, initial);
      final full = core.calls
          .firstWhere((c) => c.$1 == 'media.detailRender')
          .$2;
      expect(full['viewMode'], 'local');
      expect(object(full['recipe'])['localData'], 'frozen');
      expect(object(full['recipe'])['exposure'], 13);
      final bounds = tester.getRect(
            find.byKey(const ValueKey('shared-photo-bounds')),
          ),
          imageRect = tester.getRect(find.byType(EditingDetailTileLayer));
      expect(
        imageRect.left + viewport.focus.dx * imageRect.width,
        closeTo(bounds.center.dx, 1e-6),
      );
      expect(
        imageRect.top + viewport.focus.dy * imageRect.height,
        closeTo(bounds.center.dy, 1e-6),
      );
      expect(
        find.descendant(
          of: find.byType(LegacyLocalWorkspace),
          matching: find.byType(Scaffold),
        ),
        findsNothing,
      );
      await tester.tap(find.byTooltip('渐变'));
      await tester.pump();
      expect(tester.getRect(find.byType(EditingDetailTileLayer)), imageRect);
      expect(
        tester.getRect(find.byKey(const ValueKey('shared-photo-bounds'))),
        bounds,
      );
      await _pinch(tester, bounds.center);
      debugPrint('Legacy viewport phase: two-pointer navigation completed');
      expect(viewport.zoom, greaterThan(3));
      await _until(
        tester,
        () => controller().tile != null,
        'Navigation resumes HD without adding a brush stroke',
      );
      final stage = tester.getRect(find.byKey(const ValueKey('legacy-stage')));
      final before = tester.getRect(find.byType(EditingDetailTileLayer));
      final start = stage.center - const Offset(30, 0),
          end = stage.center + const Offset(45, 0);
      await tester.dragFrom(start, end - start);
      debugPrint('Legacy viewport phase: gradient gesture completed');
      await _until(
        tester,
        () =>
            core.calls.any((c) => c.$1 == 'media.localPreview') &&
            controller().tile != null &&
            controller().tile!.frameIdentity != initial,
        'A changed local profile is decoded and receives its own matching HD tile',
      );
      final latest = core.calls
          .lastWhere((c) => c.$1 == 'media.detailRender')
          .$2;
      debugPrint('Legacy viewport phase: changed local HD installed');
      final data = object(
        jsonDecode(object(latest['recipe'])['localData'] as String),
      );
      final masks = (data['masks'] as List).map(object).toList();
      expect(masks, hasLength(1));
      expect(data['clones'], isEmpty);
      expect(masks.single['kind'], 'linear');
      expect(
        masks.single['x0'],
        closeTo((start.dx - before.left) / before.width, .025),
      );
      expect(
        masks.single['x1'],
        closeTo((end.dx - before.left) / before.width, .025),
      );
      final current = controller().tile!;
      final region = editingDetailVisibleRegion(before, stage);
      expect(current.region.contains(region.center), true);
      expect(current.sourceSha, 'a' * 64);
      expect(back, isNotNull);
      await tester.tap(find.byKey(const ValueKey('legacy-apply')));
      await _until(
        tester,
        () => results.isNotEmpty,
        'Legacy Apply returns only the validated final state',
      );
      expect(results.single!['opaque'], 'preserved');
      expect(results.single!['regions'], [
        {'id': 'preserved'},
      ]);
      expect((results.single!['masks'] as List), hasLength(1));
      expect(core.calls.any((c) => c.$1 == 'draft.save'), false);
      await _close(tester, actual);
      await _until(
        tester,
        () =>
            core.detailPaths.every((path) => !File(path).existsSync()) &&
            !File(initial).existsSync(),
        'Transferred ordinary preview and owned HD files retire after close',
      );
      expect(back, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
