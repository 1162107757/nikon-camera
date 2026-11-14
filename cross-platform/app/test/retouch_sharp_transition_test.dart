import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/retouch_detail_preview.dart';
import 'package:huevia/retouch_original_controls.dart';
import 'package:huevia/retouch_workspace.dart';
import 'package:huevia/editing_viewport.dart';
import 'package:huevia/theme.dart';

import 'retouch_workspace_test.dart' show PortraitMenuCore;

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _red = [208, 56, 56, 255], _green = [56, 208, 96, 255];
const _blue = [56, 96, 208, 255];
Json _copy(Object? value) => object(jsonDecode(jsonEncode(value)));

Uint8List _png(int width, int height, List<int> color) {
  final rows = Uint8List((width * 4 + 1) * height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      rows.setRange(
        y * (width * 4 + 1) + 1 + x * 4,
        y * (width * 4 + 1) + 5 + x * 4,
        color,
      );
    }
  }
  final output = BytesBuilder()..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> data) {
    final bytes = Uint8List(data.length + 12);
    final view = ByteData.sublistView(bytes)..setUint32(0, data.length);
    bytes.setRange(4, 8, ascii.encode(type));
    bytes.setRange(8, data.length + 8, data);
    var crc = 0xffffffff;
    for (var i = 4; i < data.length + 8; i++) {
      crc ^= bytes[i];
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >> 1) : crc >> 1;
      }
    }
    view.setUint32(data.length + 8, crc ^ 0xffffffff);
    output.add(bytes);
  }

  final header = Uint8List(13);
  ByteData.sublistView(header)
    ..setUint32(0, width)
    ..setUint32(4, height);
  header[8] = 8;
  header[9] = 6;
  chunk('IHDR', header);
  chunk('IDAT', ZLibEncoder().convert(rows));
  chunk('IEND', []);
  return output.takeBytes();
}

class _Core extends PortraitMenuCore {
  _Core(super.directory) {
    beforeBodyCopies = true;
  }
  final held = <Completer<void>>[];
  final created = <String>{};
  final changedProfileFiles = <String>{};
  final fulls = <String, Json>{};
  final ordinaryRecipes = <String, Json>{};
  var fileSerial = 0, active = 0;
  int count(String op) => calls.where((c) => c.$1 == op).length;
  Completer<void> hold(String op) {
    final gate = Completer<void>();
    held.add(gate);
    gates['$op/'] = gate;
    return gate;
  }

  String file(int width, int height, List<int> color) {
    final path =
        '$root/previews/00000000-0000-4000-8000-${(++fileSerial).toString().padLeft(12, '0')}.png';
    File(path).writeAsBytesSync(_png(width, height, color));
    created.add(path);
    if (color[0] == _green[0] &&
        color[1] == _green[1] &&
        color[2] == _green[2]) {
      changedProfileFiles.add(path);
    }
    return path;
  }

  List<int> color(Json recipe) {
    final snapshot = snapshots[recipe['localData']];
    if ((snapshot?['patchCount'] as int? ?? 1) <= 1) return _red;
    final body = object(snapshot?['portrait'] ?? {})['body'] as List? ?? [];
    return body.any((area) => (object(area)['amount'] as num? ?? 0) != 0)
        ? _blue
        : _green;
  }

  Future<void> wait(String op, Json payload, String? job) async {
    calls.add((op, _copy(payload)));
    final gate = gates.remove('$op/${payload['mode'] ?? ''}');
    if (gate != null) {
      if (job != null) blockedJobs.add(job);
      await gate.future;
    }
  }

  @override
  Future<Json> call(String op, [Json payload = const {}, String? jobId]) async {
    active++;
    try {
      if (op == 'source.inspect') {
        await wait(op, payload, jobId);
        return {'sourceSha': _sha};
      }
      if (op == 'media.localPreview' || op == 'media.reviewPreview') {
        await wait(op, payload, jobId);
        final recipe = object(payload['recipe']);
        final path = file(16, 12, color(recipe));
        previewPaths.add(path);
        previewLocalData[path] = recipe['localData'] as String;
        ordinaryRecipes[path] = _copy(recipe);
        // Match the actual ordinary native DTO: sourceSha is absent. HD
        // preparation must carry its verified identity through the base commit.
        return {
          'path': path,
          'width': 16,
          'height': 12,
          'sourceWidth': 32,
          'sourceHeight': 24,
        };
      }
      if (op == 'media.detailRender') {
        await wait(op, payload, jobId);
        final recipe = object(payload['recipe']);
        final path = file(32, 24, color(recipe));
        final result = <String, dynamic>{
          'path': path,
          'width': 32,
          'height': 24,
          'sourceSha': _sha,
          'detailToken': 'token-$fileSerial',
          'temporary': true,
          'fullResolution': true,
          'recipe': _copy(recipe),
        };
        fulls[path] = result;
        return result;
      }
      if (op == 'media.detailTile') {
        await wait(op, payload, jobId);
        final full = fulls[payload['path']]!;
        if (!File(full['path'] as String).existsSync()) {
          throw const AppFailure(
            'The full document was deleted during a held read',
          );
        }
        final region = object(payload['region']);
        final left = ((region['left'] as num) * 32).floor();
        final top = ((region['top'] as num) * 24).floor();
        final right = ((region['right'] as num) * 32).ceil();
        final bottom = ((region['bottom'] as num) * 24).ceil();
        var sample = 1;
        while ((math.max(right - left, bottom - top) + sample - 1) ~/ sample >
            (payload['maxEdge'] as int)) {
          sample *= 2;
        }
        final width = (right - left + sample - 1) ~/ sample;
        final height = (bottom - top + sample - 1) ~/ sample;
        return {
          'path': file(width, height, color(object(full['recipe']))),
          'width': width,
          'height': height,
          'sourceWidth': 32,
          'sourceHeight': 24,
          'sourceSha': _sha,
          'detailToken': full['detailToken'],
          'temporary': true,
          'region': {
            'left': left / 32,
            'top': top / 24,
            'right': right / 32,
            'bottom': bottom / 24,
          },
        };
      }
      if (op == 'media.atmosphere') {
        await wait(op, payload, jobId);
        return {'path': file(8, 6, _red)};
      }
      return await super.call(op, payload, jobId);
    } finally {
      active--;
    }
  }
}

class _State extends AppState {
  _State(super.core);
  void owner(String id) {
    session = {
      'user': {'id': id},
    };
    notifyListeners();
  }
}

class _Fixture {
  _Fixture({bool inheritedGeometry = false, bool sourcePositioning = false}) {
    final temp = Directory.systemTemp.createTempSync(
      'huevia-sharp-transition-',
    );
    root = Directory(temp.resolveSymbolicLinksSync());
    Directory('${root.path}/previews').createSync();
    Directory('${root.path}/originals').createSync();
    original = File('${root.path}/originals/portrait.png')
      ..writeAsBytesSync(_png(32, 24, _red));
    File('${root.path}/previews/portrait.png')
        .writeAsBytesSync(_png(16, 12, _red));
    core = _Core(root.path);
    if (sourcePositioning) {
      final start = core.snapshots['start']!;
      start['sourcePositioning'] = true;
      final portrait = object(start['portrait']);
      final body = (portrait['body'] as List).map(object).toList();
      body.first['amount'] = 35;
      portrait['body'] = body;
      start['portrait'] = portrait;
    }
    state = _State(core)..owner('alice');
    recipe = {
      ...Recipe().data,
      'localData': 'start',
      if (inheritedGeometry)
        'geometry': {'turns': 1, 'left': 100000, 'right': 900000},
    };
    final plane = EditingViewportPlane.fromRecipe(
      recipe,
      sourceSize: const Size(32, 24),
    );
    final fit = inheritedGeometry
        ? const Rect.fromLTWH(100, 0, 200, 320)
        : const Rect.fromLTWH(0, 10, 400, 300);
    final point = plane.fromSource(const Offset(.6, .4));
    final location =
        fit.topLeft + Offset(fit.width * point.dx, fit.height * point.dy);
    final scene = TransformationController(
      Matrix4.diagonal3Values(4, 4, 1)
        ..setTranslationRaw(200 - location.dx * 4, 160 - location.dy * 4, 0),
    );
    viewport.capture(
      scene,
      viewport: const Size(400, 320),
      imageRect: fit,
      plane: plane,
    );
    scene.dispose();
  }
  late Directory root;
  late File original;
  late _Core core;
  late _State state;
  late Json recipe;
  final viewport = EditingViewportState();
  final finished = <Json?>[];
  VoidCallback? back;
  dynamic page;
  RetouchDetailPreviewState details(WidgetTester tester) => tester
      .state<RetouchDetailPreviewState>(find.byType(RetouchDetailPreview));
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  final elapsed = Stopwatch()..start();
  while (!ready() && elapsed.elapsed < const Duration(seconds: 10)) {
    await tester.pump(const Duration(milliseconds: 25));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 6)),
    );
  }
  expect(ready(), true, reason: reason);
}

Future<_Fixture> _open(
  WidgetTester tester, {
  bool inheritedGeometry = false,
  bool standalonePatch = true,
  bool sourcePositioning = false,
}) async {
  tester.view.physicalSize = const Size(400, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final f = _Fixture(
    inheritedGeometry: inheritedGeometry,
    sourcePositioning: sourcePositioning,
  );
  final originalBytes = f.original.readAsBytesSync();
  addTearDown(() async {
    for (final gate in f.core.held) {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.pumpWidget(const SizedBox());
    await _until(
      tester,
      () => f.core.active == 0,
      'Held native work must finish at teardown',
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 8)),
      );
    }
    expect(f.original.readAsBytesSync(), originalBytes);
    expect(
      f.core.calls.any(
        (c) => c.$1.startsWith('draft.') || c.$1.startsWith('version.'),
      ),
      false,
    );
    f.state.dispose();
    tester.binding.imageCache.clear();
    tester.binding.imageCache.clearLiveImages();
    await tester.runAsync(() => f.root.delete(recursive: true));
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.dark),
      home: StatefulBuilder(
        builder: (context, refresh) => Scaffold(
          appBar: AppBar(
            title: const Text('父编辑器'),
            leading: IconButton(
              tooltip: '返回父编辑器',
              onPressed: () => f.back?.call(),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: f.finished.isNotEmpty
              ? const Text('已返回父编辑器')
              : RetouchWorkspace(
                  state: f.state,
                  photo: Photo(f.original.path, '测试人像', const {
                    'width': 32,
                    'height': 24,
                  }),
                  owner: 'alice',
                  recipe: f.recipe,
                  isCurrent: () => true,
                  patch: standalonePatch,
                  embedded: true,
                  viewportState: f.viewport,
                  onBackReady: (value) => f.back = value,
                  onFinished: (value) => refresh(() => f.finished.add(value)),
                  embeddedLayoutBuilder: (_, photo, panel) => Column(
                    children: [
                      SizedBox(height: 320, child: photo),
                      Expanded(child: panel),
                    ],
                  ),
                ),
        ),
      ),
    ),
  );
  f.page = tester.state(find.byType(RetouchWorkspace));
  await _until(
    tester,
    () =>
        f.page.busy == false &&
        f.page.frame != null &&
        find
            .descendant(
              of: find.byType(RetouchDetailPreview),
              matching: find.byType(RawImage),
            )
            .evaluate()
            .isNotEmpty,
    'The real workspace must display an accepted decoded sharp tile',
  );
  expect(
    f.details(tester).controller.tile!.frameIdentity,
    f.page.frame['path'],
  );
  return f;
}

Finder _raw() => find.descendant(
  of: find.byType(RetouchDetailPreview),
  matching: find.byType(RawImage),
);
Future<List<int>> _paintedPixel(WidgetTester tester) async {
  expect(_raw(), findsOneWidget);
  final painted = tester.renderObject<RenderImage>(_raw()).image!;
  final bytes = await tester.runAsync(
    () => painted.toByteData(format: ui.ImageByteFormat.rawRgba),
  );
  expect(bytes, isNotNull);
  final data = bytes!;
  return data.buffer.asUint8List(data.offsetInBytes, 4).toList();
}

Future<void> _stroke(WidgetTester tester) async {
  final stage = find.byType(RetouchOriginalPhotoStage);
  final mounted = tester.widget<RetouchOriginalPhotoStage>(stage);
  expect(mounted.drawing, true, reason: 'A real repair stage must be mounted');
  expect(mounted.editingEnabled, true);
  expect(mounted.editingSignal?.value ?? true, true);
  final area = tester.getRect(stage);
  final gesture = await tester.startGesture(area.center - const Offset(20, 20));
  await tester.pump();
  await gesture.moveBy(const Offset(24, 10));
  await tester.pump();
  await gesture.up();
}

Future<void> _openInlineRepair(WidgetTester tester, _Fixture f) async {
  await tester.ensureVisible(find.text('修补'));
  await tester.tap(find.text('修补'));
  await _until(
    tester,
    () =>
        f.page.patchChildOpen == true &&
        f.page.busy == false &&
        _raw().evaluate().length == 1 &&
        find.byTooltip('取消修补并返回人像').evaluate().length == 1 &&
        tester
            .widget<RetouchOriginalPhotoStage>(
              find.byType(RetouchOriginalPhotoStage),
            )
            .drawing &&
        f.details(tester).controller.tile?.frameIdentity ==
            f.page.frame['path'],
    'The real inline repair stage must finish its accepted sharp layout',
  );
}

Future<void> _sameSharpFrame(
  WidgetTester tester,
  _Fixture f,
  String frame,
  List<int> color,
) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 30));
    expect(f.page.frame['path'], frame);
    expect(f.details(tester).widget.frame['path'], frame);
    expect(f.details(tester).controller.tile?.frameIdentity, frame);
    expect(f.details(tester).controller.tile?.sourceSha, _sha);
    expect(await _paintedPixel(tester), color);
  }
}

Future<void> _held(
  WidgetTester tester,
  _Fixture f,
  String oldFrame,
  ui.Image oldImage,
) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 30));
    expect(f.page.frame['path'], oldFrame);
    expect(f.details(tester).widget.frame['path'], oldFrame);
    expect(tester.widget<RawImage>(_raw()).image, same(oldImage));
    expect(await _paintedPixel(tester), _red);
  }
}

void main() {
  testWidgets(
    'Applying an inline repair returns its accepted sharp profile without another base render',
    (tester) async {
      final f = await _open(tester, standalonePatch: false);
      await _openInlineRepair(tester, f);
      final before = f.page.frame['path'];
      final mutations = f.core.count('media.retouchPatch');
      await _stroke(tester);
      await _until(
        tester,
        () =>
            f.core.count('media.retouchPatch') == mutations + 1 &&
            f.page.busy == false &&
            f.page.frame['path'] != before &&
            f.details(tester).controller.tile?.frameIdentity ==
                f.page.frame['path'],
        'The real patch mutation must commit its accepted sharp green profile',
      );
      final applied = f.page.frame['path'] as String;
      final data = f.page.data['localData'];
      final fulls = f.core.count('media.detailRender');
      final previews =
          f.core.count('media.localPreview') +
          f.core.count('media.reviewPreview');
      expect(await _paintedPixel(tester), _green);
      await tester.tap(find.text('应用修补').hitTestable());
      await _until(
        tester,
        () =>
            f.page.patchChildOpen == false &&
            f.page.toolIntent == 'overview' &&
            f.page.busy == false &&
            find.byTooltip('取消修补并返回人像').evaluate().isEmpty,
        'Apply must repaint the same portrait with the accepted repair profile',
      );
      expect(f.finished, isEmpty);
      expect(f.page.data['localData'], data);
      expect(f.page.data['patchCount'], 2);
      expect(f.page.undo, hasLength(1));
      expect(f.details(tester).controller.tile?.frameIdentity, applied);
      expect(await _paintedPixel(tester), _green);
      await _sameSharpFrame(tester, f, applied, _green);
      expect(f.core.count('media.detailRender'), fulls);
      expect(
        f.core.count('media.localPreview') +
            f.core.count('media.reviewPreview'),
        previews,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Applying a source-positioned repair keeps sharp source pixels until the real portrait plane is ready',
    (tester) async {
      final f = await _open(
        tester,
        standalonePatch: false,
        sourcePositioning: true,
      );
      await _openInlineRepair(tester, f);
      final before = f.page.frame['path'];
      final mutations = f.core.count('media.retouchPatch');
      await _stroke(tester);
      await _until(
        tester,
        () =>
            f.core.count('media.retouchPatch') == mutations + 1 &&
            f.page.busy == false &&
            f.page.frame['path'] != before &&
            f.details(tester).controller.tile?.frameIdentity ==
                f.page.frame['path'],
        'The source-positioned patch must commit a real accepted sharp frame',
      );
      final applied = f.page.frame['path'] as String;
      final sourceProfile = f.page.frame['_detailRecipe']['localData'];
      final portraitProfile = f.page.data['localData'];
      expect(sourceProfile, isNot(portraitProfile));
      expect(f.page.frame['_retouchBeforeBody'], true);
      expect(f.page.data['sourcePositioning'], true);
      expect(await _paintedPixel(tester), _green);
      final ordinary = f.core.hold('media.reviewPreview');
      final previews = f.core.count('media.reviewPreview');
      await tester.tap(find.text('应用修补').hitTestable());
      await _until(
        tester,
        () => f.core.count('media.reviewPreview') == previews + 1,
        'Returning to the portrait must request its real composed profile',
      );
      expect(ordinary.isCompleted, false);
      expect(f.page.patchChildOpen, false);
      expect(f.page.busy, true);
      await _sameSharpFrame(tester, f, applied, _green);
      final full = f.core.hold('media.detailRender');
      final fulls = f.core.count('media.detailRender');
      ordinary.complete();
      await _until(
        tester,
        () => f.core.count('media.detailRender') == fulls + 1,
        'The real portrait profile must enter the held full-resolution render',
      );
      expect(full.isCompleted, false);
      final target = f.core.calls
          .lastWhere((call) => call.$1 == 'media.detailRender')
          .$2;
      expect(target['expectedSourceSha'], _sha);
      expect(target['recipe']['localData'], portraitProfile);
      expect(target['recipe']['geometry'], isEmpty);
      expect(target['recipe']['border'], isEmpty);
      expect(
        object(
          f.core.snapshots[portraitProfile]!['portrait'],
        )['body'][0]['amount'],
        35,
      );
      await _sameSharpFrame(tester, f, applied, _green);
      final tile = f.core.hold('media.detailTile');
      final tiles = f.core.count('media.detailTile');
      full.complete();
      await _until(
        tester,
        () => f.core.count('media.detailTile') == tiles + 1,
        'The composed profile must reach its held native ROI read',
      );
      expect(tile.isCompleted, false);
      final roi = f.core.calls
          .lastWhere((call) => call.$1 == 'media.detailTile')
          .$2;
      expect(roi['expectedSourceSha'], _sha);
      expect(
        f.core.fulls[roi['path']]!['recipe']['localData'],
        portraitProfile,
      );
      await _sameSharpFrame(tester, f, applied, _green);
      tile.complete();
      await _until(
        tester,
        () =>
            f.page.busy == false &&
            f.page.frame['path'] != applied &&
            f.page.frame['_retouchBeforeBody'] == false &&
            f.details(tester).controller.tile?.frameIdentity ==
                f.page.frame['path'],
        'The composed base frame and its own sharp pixels must commit together',
      );
      final committed = f.page.frame['path'] as String;
      expect(f.page.frame['_detailRecipe']['localData'], portraitProfile);
      expect(f.page.frame['sourceSha'], _sha);
      expect(
        f.details(tester).controller.tile?.revision,
        f.page.frame['_detailRevision'],
      );
      expect(await _paintedPixel(tester), _blue);
      await _sameSharpFrame(tester, f, committed, _blue);
      expect(f.core.count('media.detailRender'), fulls + 1);
      expect(f.page.data['patchCount'], 2);
      expect(f.page.undo, hasLength(1));
      expect(f.finished, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A real repair stroke keeps its painted sharp frame through every held computation and commits once',
    (tester) async {
      final f = await _open(tester);
      final oldFrame = f.page.frame['path'] as String;
      final oldLocal = f.page.data['localData'];
      final oldImage = tester.widget<RawImage>(_raw()).image!;
      final baselineFull = f.core.count('media.detailRender'),
          baselineTile = f.core.count('media.detailTile');
      final mutation = f.core.hold('media.retouchPatch');
      final ordinary = f.core.hold('media.localPreview');
      final full = f.core.hold('media.detailRender');
      final tile = f.core.hold('media.detailTile');
      await _stroke(tester);
      await _until(
        tester,
        () => f.core.count('media.retouchPatch') == 1,
        'The brush must invoke native mutation',
      );
      await _held(tester, f, oldFrame, oldImage);
      expect(f.page.data['localData'], oldLocal);
      mutation.complete();
      await _until(
        tester,
        () => f.core.gates['media.localPreview/'] == null,
        'Normal preview must start',
      );
      await _held(tester, f, oldFrame, oldImage);
      ordinary.complete();
      await _until(
        tester,
        () => f.core.count('media.detailRender') == baselineFull + 1,
        'Next full detail must start',
      );
      await _held(tester, f, oldFrame, oldImage);
      full.complete();
      await _until(
        tester,
        () => f.core.count('media.detailTile') == baselineTile + 1,
        'Next tile must start',
      );
      await _held(tester, f, oldFrame, oldImage);
      tile.complete();
      await _until(
        tester,
        () => f.page.busy == false && f.page.frame['path'] != oldFrame,
        'Tile-ready must release the base-frame commit',
      );
      final newFrame = f.page.frame['path'] as String;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(f.details(tester).controller.tile!.frameIdentity, newFrame);
        expect(f.details(tester).widget.frame['path'], newFrame);
        expect(await _paintedPixel(tester), _green);
      }
      expect(f.page.frame['sourceSha'], _sha);
      expect(f.page.data['patchCount'], 2);
      expect(f.page.undo, hasLength(1));
      expect(f.core.count('media.detailRender'), baselineFull + 1);
      expect(f.core.count('media.detailTile'), baselineTile + 1);
      expect(
        f.core.calls
            .lastWhere((c) => c.$1 == 'media.detailRender')
            .$2['recipe']['localData'],
        f.page.frame['_detailRecipe']['localData'],
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Canceling an inline repair during held full work returns to the same portrait and retires the canceled profile',
    (tester) async {
      final f = await _open(tester, standalonePatch: false);
      final portraitFrame = f.page.frame['path'];
      final portraitData = f.page.data['localData'];
      final portraitUndo = List<Object?>.of(f.page.undo as List);
      final portraitRedo = List<Object?>.of(f.page.redo as List);
      await tester.ensureVisible(find.text('修补'));
      await tester.tap(find.text('修补'));
      await _until(
        tester,
        () =>
            f.page.patchChildOpen == true &&
            f.page.busy == false &&
            _raw().evaluate().length == 1 &&
            find.byTooltip('取消修补并返回人像').evaluate().length == 1 &&
            tester
                .widget<RetouchOriginalPhotoStage>(
                  find.byType(RetouchOriginalPhotoStage),
                )
                .drawing &&
            f.details(tester).controller.tile?.frameIdentity ==
                f.page.frame['path'],
        'The real portrait repair child must open with its accepted sharp frame',
      );
      expect(f.finished, isEmpty);
      final full = f.core.hold('media.detailRender');
      final count = f.core.count('media.detailRender');
      final mutations = f.core.count('media.retouchPatch');
      await _stroke(tester);
      await _until(
        tester,
        () => f.core.count('media.retouchPatch') == mutations + 1,
        'The mounted repair canvas must send the actual native patch mutation',
      );
      await _until(
        tester,
        () => f.core.count('media.detailRender') == count + 1,
        'Full replacement must actually be held',
      );
      expect(full.isCompleted, false);
      await tester.tap(find.byTooltip('取消修补并返回人像'));
      await _until(
        tester,
        () =>
            f.page.patchChildOpen == false &&
            f.page.toolIntent == 'overview' &&
            f.page.busy == false &&
            find.text('修补').evaluate().isNotEmpty &&
            find.byTooltip('取消修补并返回人像').evaluate().isEmpty,
        'Cancel must repaint the same portrait panel without waiting for held native work',
      );
      expect(full.isCompleted, false);
      expect(f.finished, isEmpty);
      expect(find.byType(RetouchWorkspace), findsOneWidget);
      expect(
        identical(tester.state(find.byType(RetouchWorkspace)), f.page),
        true,
      );
      expect(f.page.frame['path'], portraitFrame);
      expect(f.page.data['localData'], portraitData);
      expect(f.page.undo, portraitUndo);
      expect(f.page.redo, portraitRedo);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        expect(full.isCompleted, false);
        expect(_raw(), findsOneWidget);
        expect(f.details(tester).controller.tile?.frameIdentity, portraitFrame);
        expect(f.details(tester).controller.tile?.sourceSha, _sha);
        expect(await _paintedPixel(tester), _red);
      }
      full.complete();
      await _until(
        tester,
        () =>
            f.core.active == 0 &&
            f.core.changedProfileFiles.every((p) => !File(p).existsSync()),
        'The canceled green-profile full and prepared ordinary frame must not leak',
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 6)),
        );
        expect(f.finished, isEmpty);
        expect(f.page.data['localData'], portraitData);
        expect(f.page.frame['path'], portraitFrame);
      }
      await _until(
        tester,
        () =>
            _raw().evaluate().length == 1 &&
            f.details(tester).controller.tile?.frameIdentity == portraitFrame,
        'The retained portrait must regain only its own accepted sharp profile',
      );
      expect(await _paintedPixel(tester), _red);
      expect(f.core.changedProfileFiles, isNotEmpty);
      expect(
        f.core.changedProfileFiles.every((p) => !File(p).existsSync()),
        true,
      );
      expect(f.core.cancelledJobs, isNotEmpty);
    },
  );

  testWidgets(
    'Owner leave and return cannot install a held repair tile or expose its prepared frame',
    (tester) async {
      final f = await _open(tester);
      final before = Set<String>.of(f.core.created);
      final tile = f.core.hold('media.detailTile');
      final count = f.core.count('media.detailTile');
      await _stroke(tester);
      await _until(
        tester,
        () => f.core.count('media.detailTile') == count + 1,
        'Replacement tile must actually be held',
      );
      f.state.owner('bob');
      await tester.pump();
      f.state.owner('alice');
      await tester.pump();
      expect(find.byType(RetouchDetailPreview), findsNothing);
      tile.complete();
      await _until(
        tester,
        () =>
            f.core.active == 0 &&
            f.core.created
                .difference(before)
                .every((p) => !File(p).existsSync()),
        'Late owner-scoped tile and ordinary frame must be retired',
      );
      expect(f.page.frame, isNull);
      expect(f.page.data, isNull);
      expect(find.byType(RetouchDetailPreview), findsNothing);
    },
  );

  testWidgets(
    'Inherited crop and rotation use the accepted source plane for the next repair ROI',
    (tester) async {
      final f = await _open(tester, inheritedGeometry: true);
      expect(object(f.recipe['geometry'])['turns'], 1);
      expect(object(f.page.frame['_detailRecipe']['geometry']), isEmpty);
      final element = find.byType(RetouchDetailPreview).evaluate().single;
      final actual = element
          .getInheritedWidgetOfExactType<RetouchPhotoViewportScope>()!
          .value;
      final focus = f.viewport.focus;
      final full = f.core.hold('media.detailRender');
      final count = f.core.count('media.detailRender');
      await _stroke(tester);
      await _until(
        tester,
        () => f.core.count('media.detailRender') == count + 1,
        'Next accepted full profile must start',
      );
      final profile = f.core.calls
          .lastWhere((c) => c.$1 == 'media.detailRender')
          .$2;
      expect(object(profile['recipe']['geometry']), isEmpty);
      expect(object(profile['recipe']['border']), isEmpty);
      final tile = f.core.hold('media.detailTile');
      final tileCount = f.core.count('media.detailTile');
      full.complete();
      await _until(
        tester,
        () => f.core.count('media.detailTile') == tileCount + 1,
        'Candidate ROI must be requested',
      );
      final roi = object(
        f.core.calls.lastWhere((c) => c.$1 == 'media.detailTile').$2['region'],
      );
      final visible = actual.visibleRegion;
      expect(
        roi['left'],
        closeTo(math.max(0, visible.left - visible.width * .12), 1e-8),
      );
      expect(
        roi['top'],
        closeTo(math.max(0, visible.top - visible.height * .12), 1e-8),
      );
      expect(
        roi['right'],
        closeTo(math.min(1, visible.right + visible.width * .12), 1e-8),
      );
      expect(
        roi['bottom'],
        closeTo(math.min(1, visible.bottom + visible.height * .12), 1e-8),
      );
      tile.complete();
      await _until(
        tester,
        () => f.page.busy == false,
        'Repair must commit after its correct ROI',
      );
      expect(f.viewport.focus.dx, closeTo(focus.dx, 1e-8));
      expect(f.viewport.focus.dy, closeTo(focus.dy, 1e-8));
      expect(await _paintedPixel(tester), _green);
    },
  );
}
