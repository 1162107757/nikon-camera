import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editing_detail_preview.dart';

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAYAAABr5z2BAAAAF0lEQVR4nGOQWBD1nxLMMGrAqAHDwwAAqUGM0LHkvF4AAAAASUVORK5CYII=',
);

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

class _DetailCore extends HueviaCore {
  _DetailCore(this.directory) {
    root = directory.path;
    Directory('$root/previews').createSync();
    Directory('$root/originals').createSync();
    File(source).writeAsStringSync('untouched-original');
  }
  final Directory directory;
  String get source => '$root/originals/source.jpg';
  final calls = <(String, Json)>[];
  final cancelled = <String>[];
  final documents = <String, Json>{};
  final gates = <Completer<void>>[];
  Completer<void>? holdFull, holdTile;
  int serial = 0, active = 0, maximumActive = 0;
  int fullWidth = 4000, fullHeight = 3000;
  bool wrongTileToken = false, wrongDecodedDimensions = false;
  bool emulateNativeTilePixels = false;
  @override
  Future<void> cancel(String jobId) async => cancelled.add(jobId);
  String makeFile(List<int> bytes) {
    final name =
        '00000000-0000-4000-8000-${(++serial).toString().padLeft(12, '0')}.png';
    return (File('$root/previews/$name')..writeAsBytesSync(bytes)).path;
  }

  int count(String op) => calls.where((call) => call.$1 == op).length;
  Completer<void> gateFull() {
    final gate = holdFull = Completer<void>();
    gates.add(gate);
    return gate;
  }

  Completer<void> gateTile() {
    final gate = holdTile = Completer<void>();
    gates.add(gate);
    return gate;
  }

  void finishGates() {
    for (final gate in gates) {
      if (!gate.isCompleted) gate.complete();
    }
  }

  @override
  Future<Json> call(String op, [Json payload = const {}, String? jobId]) async {
    calls.add((op, object(jsonDecode(jsonEncode(payload)))));
    active++;
    if (active > maximumActive) maximumActive = active;
    try {
      if (op == 'source.inspect') return {'sourceSha': _sha};
      if (op == 'media.detailRender' || op == 'media.rawDetail') {
        final gate = holdFull;
        holdFull = null;
        if (gate != null) await gate.future;
        final path = makeFile([
          1,
          2,
          3,
        ]); // Full files are never decoded by Flutter.
        final result = {
          'path': path,
          'width': fullWidth,
          'height': fullHeight,
          'sourceSha': _sha,
          'detailToken': 'token-$serial',
          'temporary': true,
          'fullResolution': true,
        };
        documents[path] = result;
        return result;
      }
      if (op == 'media.detailTile') {
        final gate = holdTile;
        holdTile = null;
        if (gate != null) await gate.future;
        final full = documents[payload['path']]!;
        var width = 16, height = 12;
        var region = object(payload['region']);
        if (emulateNativeTilePixels) {
          final left = ((region['left'] as num) * fullWidth).floor();
          final top = ((region['top'] as num) * fullHeight).floor();
          final right = ((region['right'] as num) * fullWidth).ceil();
          final bottom = ((region['bottom'] as num) * fullHeight).ceil();
          var sample = 1;
          while (math.max(right - left, bottom - top) / sample >
              (payload['maxEdge'] as int)) {
            sample *= 2;
          }
          width = ((right - left) / sample).ceil();
          height = ((bottom - top) / sample).ceil();
          region = {
            'left': left / fullWidth,
            'top': top / fullHeight,
            'right': right / fullWidth,
            'bottom': bottom / fullHeight,
          };
        }
        return {
          'path': makeFile(
            emulateNativeTilePixels ? _solidPng(width, height) : _png,
          ),
          'width': wrongDecodedDimensions ? width + 1 : width,
          'height': height,
          'sourceWidth': fullWidth,
          'sourceHeight': fullHeight,
          'sourceSha': _sha,
          'detailToken': wrongTileToken ? 'wrong-token' : full['detailToken'],
          'region': region,
          'temporary': true,
        };
      }
      throw AppFailure(op);
    } finally {
      active--;
    }
  }
}

class _DetailFixture {
  _DetailFixture(this.core) {
    controller = EditingDetailPreviewController(
      core: core,
      owner: '',
      sourcePath: core.source,
      isCurrent: () => current,
      maxTileEdge: 2048,
      debounce: const Duration(milliseconds: 5),
    );
  }
  final _DetailCore core;
  late final EditingDetailPreviewController controller;
  bool current = true;
  void configure({
    Json? recipe,
    int revision = 1,
    String frame = 'frame-1',
    Size size = const Size(640, 480),
    String sha = _sha,
  }) {
    controller.configure(
      recipe:
          recipe ??
          {
            'values': [1, 2],
            'geometry': {},
          },
      revision: revision,
      frameIdentity: frame,
      outputSize: size,
      expectedSourceSha: sha,
    );
  }

  void viewport({
    Rect region = const Rect.fromLTWH(.25, .25, .5, .5),
    double zoom = 2,
    Size pixels = const Size(800, 600),
  }) {
    controller.setViewport(
      visibleRegion: region,
      zoom: zoom,
      viewportPixelSize: pixels,
    );
  }
}

Future<void> _drain(WidgetTester tester, [int count = 16]) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 4)),
    );
  }
}

_DetailFixture _fixture(WidgetTester tester) {
  final directory = Directory.systemTemp.createTempSync('huevia-detail-test-');
  final fixture = _DetailFixture(_DetailCore(directory));
  addTearDown(() async {
    fixture.controller.dispose();
    fixture.core.finishGates();
    await tester.pumpWidget(const SizedBox());
    await _drain(tester);
    expect(File(fixture.core.source).readAsStringSync(), 'untouched-original');
    expect(
      fixture.core.calls.any(
        (call) => call.$1.contains('draft.') || call.$1.contains('version.'),
      ),
      false,
    );
    assert(
      directory.absolute.path.startsWith(Directory.systemTemp.absolute.path),
    );
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return fixture;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Zooming inside a fit tile acquires denser pixels even when the viewport and maxEdge are unchanged',
    (tester) async {
      final f = _fixture(tester);
      f.core
        ..fullWidth = 8000
        ..fullHeight = 6000
        ..emulateNativeTilePixels = true;
      f.configure(size: const Size(128, 96));
      f.viewport(
        region: const Rect.fromLTWH(0, 0, 1, 1),
        zoom: 1,
        pixels: const Size(400, 300),
      );
      await _drain(tester);
      final first = f.controller.tile!;
      final firstDensity = first.width / first.region.width;
      f.viewport(
        region: const Rect.fromLTWH(.375, .375, .25, .25),
        zoom: 4,
        pixels: const Size(400, 300),
      );
      await _drain(tester);
      final zoomed = f.controller.tile!;
      expect(f.core.count('media.detailRender'), 1);
      expect(f.core.count('media.detailTile'), 2);
      expect(zoomed.width / zoomed.region.width, greaterThan(firstDensity));
      expect(zoomed.requestedMaxEdge, first.requestedMaxEdge);
    },
  );

  testWidgets(
    'An already source-pixel-density tile remains reusable after zooming',
    (tester) async {
      final f = _fixture(tester);
      f.core
        ..fullWidth = 16
        ..fullHeight = 12
        ..emulateNativeTilePixels = true;
      f.configure(size: const Size(8, 6));
      f.viewport(
        region: const Rect.fromLTWH(0, 0, 1, 1),
        zoom: 1,
        pixels: const Size(16, 12),
      );
      await _drain(tester);
      expect(f.controller.tile!.width, 16);
      f.viewport(
        region: const Rect.fromLTWH(.25, .25, .25, .25),
        zoom: 4,
        pixels: const Size(16, 12),
      );
      await _drain(tester);
      expect(f.core.count('media.detailTile'), 1);
      expect(f.core.count('media.detailRender'), 1);
    },
  );

  testWidgets(
    'Generic editing of a real RAW suffix requests rawDetail with the frozen recipe and local view mode',
    (tester) async {
      final f = _fixture(tester);
      final raw = f.core.source.replaceAll('.jpg', '.NEF');
      File(raw).writeAsStringSync('original-nef-unchanged');
      final controller = EditingDetailPreviewController(
        core: f.core,
        owner: '',
        sourcePath: raw,
        isCurrent: () => f.current,
        debounce: const Duration(milliseconds: 5),
      );
      addTearDown(controller.dispose);
      controller.configure(
        recipe: {
          'localData': 'frozen',
          'values': [17],
        },
        revision: 1,
        frameIdentity: 'raw-editor-frame',
        outputSize: const Size(640, 480),
        expectedSourceSha: _sha,
        viewMode: 'local',
      );
      controller.setViewport(
        visibleRegion: const Rect.fromLTWH(.25, .25, .5, .5),
        zoom: 2,
        viewportPixelSize: const Size(800, 600),
      );
      await _drain(tester);
      expect(controller.hasDetail, true);
      expect(f.core.count('media.detailRender'), 0);
      final actual = f.core.calls
          .singleWhere((call) => call.$1 == 'media.rawDetail')
          .$2;
      expect(actual['path'], raw);
      expect(actual['settings'], isEmpty);
      expect(actual['recipe']['localData'], 'frozen');
      expect(actual['viewMode'], 'local');
      expect(actual.containsKey('reference'), false);
      expect(File(raw).readAsStringSync(), 'original-nef-unchanged');
    },
  );
  test(
    'Visible ROI excludes letterboxing and uses the unchanged image plane',
    () {
      expect(
        editingDetailVisibleRegion(
          const Rect.fromLTWH(-100, 25, 600, 400),
          const Rect.fromLTWH(0, 0, 400, 450),
        ),
        const Rect.fromLTRB(1 / 6, 0, 5 / 6, 1),
      );
      expect(
        editingDetailVisibleRegion(
          const Rect.fromLTWH(0, 48, 400, 600),
          const Rect.fromLTRB(0, 48, 400, 552),
        ),
        const Rect.fromLTWH(0, 0, 1, .84),
      );
      expect(
        editingDetailVisibleRegion(
          Rect.zero,
          const Rect.fromLTWH(0, 0, 100, 100),
        ),
        Rect.zero,
      );
    },
  );

  testWidgets(
    'Fit stays ordinary when sufficient and automatically adds bounded detail when physical pixels require it',
    (tester) async {
      final f = _fixture(tester)..configure();
      f.viewport(
        region: const Rect.fromLTWH(0, 0, 1, 1),
        zoom: 1,
        pixels: const Size(320, 240),
      );
      await _drain(tester);
      expect(f.core.calls, isEmpty);
      f.viewport(
        region: const Rect.fromLTWH(0, 0, 1, 1),
        zoom: 1,
        pixels: const Size(1800, 1350),
      );
      await _drain(tester);
      expect(f.controller.hasDetail, true);
      expect(f.controller.tile!.image.width, 16);
      expect(f.core.count('media.detailRender'), 1);
      expect(f.core.maximumActive, 1);
      expect(f.controller.ownedFileCount, 2);
    },
  );

  testWidgets(
    'Panning and same canonical recipe at 640 to 1280 reuse one full file and token',
    (tester) async {
      final f = _fixture(tester)
        ..configure(
          recipe: {
            'values': [1, 2],
            'geometry': {},
          },
        )
        ..viewport();
      await _drain(tester);
      final first = f.controller.tile!;
      f.viewport(region: const Rect.fromLTWH(.02, .02, .25, .25), zoom: 4);
      await _drain(tester);
      expect(f.core.count('media.detailRender'), 1);
      expect(f.core.count('media.detailTile'), 2);
      expect(f.controller.tile!.region.contains(const Offset(.03, .03)), true);
      f.configure(
        recipe: {
          'geometry': {},
          'values': [1, 2],
        },
        revision: 2,
        frame: 'frame-2',
        size: const Size(1280, 960),
      );
      await _drain(tester);
      expect(f.core.count('media.detailRender'), 1);
      expect(f.controller.tile!.revision, 2);
      expect(f.controller.tile!.frameIdentity, 'frame-2');
      expect(File(first.path).existsSync(), false);
      expect(f.controller.ownedFileCount, lessThanOrEqualTo(2));
    },
  );

  testWidgets(
    'Only the latest ROI installs and native requests remain serial while a tile is delayed',
    (tester) async {
      final f = _fixture(tester);
      final gate = f.core.gateTile();
      f.configure();
      f.viewport();
      await _drain(tester);
      expect(f.core.count('media.detailTile'), 1);
      f.viewport(region: const Rect.fromLTWH(.7, .7, .2, .2), zoom: 5);
      await _drain(tester);
      expect(f.core.count('media.detailTile'), 1);
      gate.complete();
      await _drain(tester);
      expect(f.core.count('media.detailRender'), 1);
      expect(f.core.count('media.detailTile'), 2);
      expect(f.controller.tile!.region.contains(const Offset(.8, .8)), true);
      expect(f.core.maximumActive, 1);
    },
  );

  testWidgets(
    'Owner invalidation cancels the active full job and retires its late private file',
    (tester) async {
      final f = _fixture(tester);
      final gate = f.core.gateFull();
      f.configure();
      f.viewport();
      await _drain(tester);
      f.current = false;
      f.controller.invalidate();
      expect(f.core.cancelled, hasLength(1));
      gate.complete();
      await _drain(tester);
      expect(f.controller.tile, isNull);
      expect(f.core.count('media.detailTile'), 0);
      expect(f.controller.ownedFileCount, 0);
      expect(Directory('${f.core.root}/previews').listSync(), isEmpty);
    },
  );

  testWidgets(
    'Pause and fast resume cannot install a tile from the retired interaction epoch',
    (tester) async {
      final f = _fixture(tester);
      final gate = f.core.gateTile();
      f.configure();
      f.viewport();
      await _drain(tester);
      f.controller.setEnabled(false);
      expect(f.controller.tile, isNull);
      f.configure(revision: 2, frame: 'frame-after-gesture');
      f.controller.setEnabled(true);
      await _drain(tester);
      gate.complete();
      await _drain(tester);
      expect(f.controller.tile!.frameIdentity, 'frame-after-gesture');
      expect(f.controller.tile!.revision, 2);
      expect(f.core.count('media.detailRender'), 1);
      expect(f.core.count('media.detailTile'), 2);
    },
  );

  testWidgets(
    'A source no larger than ordinary pixels is remembered without repeated full renders or tiles',
    (tester) async {
      final f = _fixture(tester)
        ..configure(size: const Size(8000, 6000))
        ..viewport(zoom: 8);
      await _drain(tester);
      expect(f.controller.hasDetail, false);
      expect(f.core.count('media.detailRender'), 1);
      expect(f.core.count('media.detailTile'), 0);
      f.viewport(region: const Rect.fromLTWH(.7, .7, .1, .1), zoom: 8);
      await _drain(tester);
      expect(f.core.count('media.detailRender'), 1);
      expect(f.core.count('media.detailTile'), 0);
    },
  );

  testWidgets(
    'RAW freezes structured reference and settings and inspects its SHA only when detail is needed',
    (tester) async {
      final f = _fixture(tester);
      final settings = <String, dynamic>{'exposure': 100};
      final reference = <String, dynamic>{
        'path': 'reference.jpg',
        'crop': {'left': .1},
      };
      f.controller.configureRaw(
        settings: settings,
        reference: reference,
        revision: 3,
        frameIdentity: 'raw-frame',
        outputSize: const Size(640, 480),
      );
      settings['exposure'] = 999;
      reference['path'] = 'changed.jpg';
      expect(f.core.calls, isEmpty);
      f.viewport();
      await _drain(tester);
      expect(f.core.count('source.inspect'), 1);
      expect(f.core.count('media.detailRender'), 0);
      final actual = f.core.calls
          .singleWhere((call) => call.$1 == 'media.rawDetail')
          .$2;
      expect(actual['expectedSourceSha'], _sha);
      expect(actual['settings']['exposure'], 100);
      expect(actual['reference']['path'], 'reference.jpg');
      expect(actual['reference']['crop']['left'], .1);
      expect(f.controller.hasDetail, true);
    },
  );

  testWidgets(
    'Invalid native token and encoded dimensions stay ordinary without leaking temporary tiles',
    (tester) async {
      final f = _fixture(tester);
      f.core.wrongTileToken = true;
      f.configure();
      f.viewport();
      await _drain(tester);
      expect(f.controller.tile, isNull);
      expect(f.controller.error, isNotNull);
      expect(f.controller.ownedFileCount, 1);
      f.core.wrongTileToken = false;
      f.core.wrongDecodedDimensions = true;
      f.viewport(region: const Rect.fromLTWH(.6, .6, .2, .2));
      await _drain(tester);
      expect(f.controller.tile, isNull);
      expect(f.controller.error, isNotNull);
      expect(f.controller.ownedFileCount, 1);
    },
  );

  testWidgets(
    'Decoded tile occupies exactly its normalized photo-plane region and does not consume input',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _drain(tester);
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: GestureDetector(
                onTap: () => taps++,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Colors.black),
                    EditingDetailTileLayer(controller: f.controller),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final plane = tester.getRect(find.byType(Stack).last),
          tile = f.controller.tile!;
      final displayed = tester.getRect(find.byType(RawImage));
      expect(
        displayed.left,
        closeTo(plane.left + tile.region.left * plane.width, .01),
      );
      expect(
        displayed.top,
        closeTo(plane.top + tile.region.top * plane.height, .01),
      );
      expect(displayed.width, closeTo(tile.region.width * plane.width, .01));
      await tester.tapAt(displayed.center);
      await tester.pump();
      expect(taps, 1);
      f.controller.setEnabled(false);
      await tester.pump();
      expect(find.byType(RawImage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
