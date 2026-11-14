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
    root = directory.resolveSymbolicLinksSync();
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
        if (!File(payload['path'] as String).existsSync()) {
          throw const AppFailure(
            'The native full document was deleted while being read',
          );
        }
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

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String reason, {
  String Function()? diagnostic,
}) async {
  final deadline = Stopwatch()..start();
  while (!ready() && deadline.elapsed < const Duration(seconds: 10)) {
    await _drain(tester, 1);
  }
  expect(
    ready(),
    true,
    reason: diagnostic == null ? reason : '$reason: ${diagnostic()}',
  );
}

_DetailFixture _fixture(WidgetTester tester) {
  final directory = Directory.systemTemp.createTempSync('huevia-detail-test-');
  final fixture = _DetailFixture(_DetailCore(directory));
  addTearDown(() async {
    fixture.controller.dispose();
    fixture.core.finishGates();
    await tester.pumpWidget(const SizedBox());
    await _drain(tester);
    await _until(
      tester,
      () => fixture.controller.ownedFileCount == 0,
      'Disposed detail controller must retire every private file',
    );
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

EditingDetailPreviewController _receiver(
  _DetailFixture fixture, {
  Json? recipe,
  Size size = const Size(640, 480),
  String expectedSha = _sha,
  String owner = '',
  String? sourcePath,
}) {
  final controller = EditingDetailPreviewController(
    core: fixture.core,
    owner: owner,
    sourcePath: sourcePath ?? fixture.core.source,
    isCurrent: () => fixture.current,
    maxTileEdge: 2048,
    debounce: const Duration(milliseconds: 5),
  );
  addTearDown(controller.dispose);
  controller.configure(
    recipe:
        recipe ??
        {
          'values': [1, 2],
          'geometry': {},
        },
    revision: 2,
    frameIdentity: 'child-frame',
    outputSize: size,
    expectedSourceSha: expectedSha,
  );
  return controller;
}

void _receiverViewport(
  EditingDetailPreviewController controller, {
  Rect region = const Rect.fromLTWH(.25, .25, .5, .5),
}) => controller.setViewport(
  visibleRegion: region,
  zoom: 2,
  viewportPixelSize: const Size(800, 600),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Handoff clones sharp pixels and borrows one full document for a new partial viewport',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Parent tile must decode',
      );
      final original = f.controller.tile!;
      final handoff = f.controller.captureHandoff()!;
      final child = _receiver(f);
      _receiverViewport(child, region: const Rect.fromLTWH(.7, .7, .2, .2));
      final gate = f.core.gateTile();
      expect(child.adoptHandoff(handoff), true);
      expect(child.adoptHandoff(handoff), false);
      handoff.dispose();
      expect(child.tile!.frameIdentity, 'child-frame');
      expect(child.tile!.revision, 2);
      expect(identical(child.tile!.image, original.image), false);
      expect(child.tile!.region.right, lessThan(.9));
      f.controller.setEnabled(false);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: EditingDetailTileLayer(controller: child),
          ),
        ),
      );
      expect(tester.widget<RawImage>(find.byType(RawImage)).image!.width, 16);
      await _until(
        tester,
        () => f.core.count('media.detailTile') == 2,
        'The uncovered ROI must request a new tile',
      );
      expect(child.tile!.path, original.path);
      expect(f.core.count('media.detailRender'), 1);
      expect(child.ownedFileCount, 0);
      final request = f.core.calls
          .where((c) => c.$1 == 'media.detailTile')
          .last
          .$2;
      expect(request['path'], f.core.documents.keys.single);
      expect(request['expectedSourceSha'], _sha);
      gate.complete();
      await _until(
        tester,
        () => child.tile != null && child.tile!.path != original.path,
        'The borrowed full must supply the latest viewport',
      );
      expect(child.tile!.region.contains(const Offset(.8, .8)), true);
      expect(f.core.count('media.detailRender'), 1);
      expect(
        child.ownedFileCount,
        1,
      ); // Only its newly generated tile, not the loan.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Adoption retires a same-profile full job that was already in flight without losing its document loan',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Parent tile must decode',
      );
      final fullPath = f.core.documents.keys.single;
      final handoff = f.controller.captureHandoff()!;
      final gate = f.core.gateFull();
      final child = _receiver(f);
      _receiverViewport(child);
      await _until(
        tester,
        () => f.core.count('media.detailRender') == 2,
        'Child full work must actually start before adoption',
      );
      expect(child.adoptHandoff(handoff), true);
      f.controller.dispose();
      expect(File(fullPath).existsSync(), true);
      gate.complete();
      await _until(
        tester,
        () => f.core.active == 0 && child.ownedFileCount == 0,
        'Late redundant full work must be retired rather than replace the loan',
      );
      expect(child.tile!.frameIdentity, 'child-frame');
      expect(File(fullPath).existsSync(), true);
      child.dispose();
      await _until(
        tester,
        () => f.controller.ownedFileCount == 0,
        'The original document loan must still release on child disposal',
      );
      expect(File(fullPath).existsSync(), false);
    },
  );

  testWidgets(
    'Parent disposal and child profile cancellation wait for an active borrowed native read',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Parent tile must decode',
      );
      final fullPath = f.core.documents.keys.single;
      final child = _receiver(f);
      _receiverViewport(child);
      expect(child.adoptHandoff(f.controller.captureHandoff()), true);
      f.controller.dispose();
      await _drain(tester, 2);
      expect(File(fullPath).existsSync(), true);
      final gate = f.core.gateTile();
      _receiverViewport(child, region: const Rect.fromLTWH(.7, .7, .2, .2));
      await _until(
        tester,
        () => f.core.count('media.detailTile') == 2,
        'The borrowed native read must start',
      );
      child.configure(
        recipe: {
          'values': [7],
        },
        revision: 3,
        frameIdentity: 'new-profile',
        outputSize: const Size(640, 480),
        expectedSourceSha: _sha,
      );
      await _drain(tester, 2);
      expect(gate.isCompleted, false);
      expect(File(fullPath).existsSync(), true);
      gate.complete();
      await _until(
        tester,
        () =>
            child.tile?.frameIdentity == 'new-profile' &&
            !File(fullPath).existsSync() &&
            f.controller.ownedFileCount == 0,
        'Only completion of the active read may release the parent full file',
      );
      expect(f.core.count('media.detailRender'), 2);
      expect(child.ownedFileCount, 2);
    },
  );

  testWidgets(
    'Independent unconsumed captures keep the parent file until each handle is disposed',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Parent tile must decode',
      );
      final fullPath = f.core.documents.keys.single;
      final first = f.controller.captureHandoff()!,
          second = f.controller.captureHandoff()!;
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      f.controller.dispose();
      await _drain(tester, 2);
      expect(File(fullPath).existsSync(), true);
      first.dispose();
      await _drain(tester, 2);
      expect(File(fullPath).existsSync(), true);
      second.dispose();
      second.dispose();
      await _until(
        tester,
        () => f.controller.ownedFileCount == 0,
        'The final independent capture must release its parent lease',
      );
      expect(File(fullPath).existsSync(), false);
    },
  );

  testWidgets(
    'Owner source SHA profile and ordinary output mismatch consume without exposing captured pixels',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Parent tile must decode',
      );
      final receivers = [
        _receiver(f, owner: 'other-owner'),
        _receiver(f, sourcePath: '${f.core.source}.other'),
        _receiver(f, expectedSha: _sha.replaceAll('a', 'b')),
        _receiver(
          f,
          recipe: {
            'values': [9],
          },
        ),
        _receiver(f, size: const Size(1280, 960)),
      ];
      for (final child in receivers) {
        final handoff = f.controller.captureHandoff()!;
        expect(child.adoptHandoff(handoff), false);
        expect(child.adoptHandoff(handoff), false);
        handoff.dispose();
        expect(child.tile, isNull);
        expect(child.handoffPending, false);
        expect(child.ownedFileCount, 0);
      }
      f.controller.dispose();
      await _until(
        tester,
        () => f.controller.ownedFileCount == 0,
        'Rejected captures must not retain any parent document lease',
      );
      expect(f.core.count('media.detailRender'), 1);
    },
  );

  testWidgets(
    'A consumed handoff waits for actual layout and survives disposal of the original handle',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Parent tile must decode',
      );
      final fullPath = f.core.documents.keys.single;
      final handoff = f.controller.captureHandoff()!;
      final child = _receiver(f);
      expect(child.adoptHandoff(handoff), true);
      expect(child.handoffPending, true);
      expect(child.tile, isNull);
      handoff.dispose();
      f.controller.dispose();
      expect(File(fullPath).existsSync(), true);
      _receiverViewport(child);
      expect(child.handoffPending, false);
      expect(child.tile!.frameIdentity, 'child-frame');
      await _drain(tester);
      expect(f.core.count('media.detailRender'), 1);
      expect(f.core.count('media.detailTile'), 1);
      child.dispose();
      await _until(
        tester,
        () => f.controller.ownedFileCount == 0,
        'Child disposal must release its borrowed parent document',
      );
    },
  );

  testWidgets(
    'Changing profile before first layout retires a deferred handoff without displaying it',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Parent tile must decode',
      );
      final child = _receiver(f);
      expect(child.adoptHandoff(f.controller.captureHandoff()), true);
      f.controller.dispose();
      child.configure(
        recipe: {
          'values': [9],
        },
        revision: 3,
        frameIdentity: 'changed-before-layout',
        outputSize: const Size(640, 480),
        expectedSourceSha: _sha,
      );
      expect(child.handoffPending, false);
      expect(child.tile, isNull);
      await _until(
        tester,
        () => f.controller.ownedFileCount == 0,
        'Unshown deferred data must release its parent lease after profile change',
      );
      expect(f.core.count('media.detailRender'), 1);
    },
  );

  testWidgets(
    'Return capture reclaims its own retired document and borrowed documents cannot form a cycle',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Parent tile must decode',
      );
      final fullPath = f.core.documents.keys.single;
      final childEntry = f.controller.captureHandoff()!,
          parentReturn = f.controller.captureHandoff()!;
      final child = _receiver(f);
      _receiverViewport(child);
      expect(child.adoptHandoff(childEntry), true);
      final borrowedReturn = child
          .captureHandoff()!; // Image-only; never re-lends its loan.
      addTearDown(borrowedReturn.dispose);
      f.configure(
        recipe: {
          'values': [9],
        },
        revision: 3,
        frame: 'temporary-parent',
      );
      f.controller.setEnabled(false);
      child.dispose();
      f.configure(revision: 4, frame: 'restored-parent');
      f.controller.setEnabled(true);
      expect(f.controller.adoptHandoff(parentReturn), true);
      expect(f.controller.tile!.frameIdentity, 'restored-parent');
      await _drain(tester);
      expect(File(fullPath).existsSync(), true);
      expect(f.core.count('media.detailRender'), 1);
      f.controller.invalidate();
      await _until(
        tester,
        () => f.controller.ownedFileCount == 0,
        'A retained return image must not hold a transitive document lease',
      );
      expect(File(fullPath).existsSync(), false);
    },
  );

  testWidgets(
    'Replacement holds sharp pixels through full and tile work then commits one matching paint',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Initial tile must decode',
      );
      final old = f.controller.tile!;
      var baseFrame = old.frameIdentity;
      StateSetter? updateBase;
      final painted = <(String, String?)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateBase = setState;
              final base = baseFrame;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                painted.add((base, f.controller.tile?.frameIdentity));
              });
              return SizedBox(
                width: 400,
                height: 300,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Text(base),
                    EditingDetailTileLayer(controller: f.controller),
                  ],
                ),
              );
            },
          ),
        ),
      );
      final full = f.core.gateFull(), tileGate = f.core.gateTile();
      var sawEmpty = false;
      final acceptedPaths = <String>{old.path};
      f.controller.addListener(() {
        final tile = f.controller.tile;
        if (tile == null) sawEmpty = true;
        if (tile != null) acceptedPaths.add(tile.path);
      });
      final recipe = <String, dynamic>{
        'values': [9],
        'geometry': {},
      };
      bool? accepted;
      final ready = f.controller.prepareReplacement(
        recipe: recipe,
        revision: 2,
        frameIdentity: 'frame-2',
        outputSize: const Size(640, 480),
        expectedSourceSha: _sha,
        viewMode: 'local',
      );
      recipe['values'][0] = 99;
      unawaited(
        ready.then((value) {
          accepted = value;
          if (value) updateBase!(() => baseFrame = 'frame-2');
        }),
      );
      await _until(
        tester,
        () => f.core.count('media.detailRender') == 2,
        'Replacement full work must start',
      );
      expect(accepted, isNull);
      expect(f.controller.tile!.path, old.path);
      expect(f.controller.captureHandoff(), isNull);
      expect(File(old.path).existsSync(), true);
      full.complete();
      await _until(
        tester,
        () => f.core.count('media.detailTile') == 2,
        'Replacement tile work must start',
      );
      expect(accepted, isNull);
      expect(f.controller.tile!.path, old.path);
      expect(f.controller.replacementPending, true);
      tileGate.complete();
      await _until(
        tester,
        () => accepted == true,
        'Replacement must resolve ready',
      );
      await tester.pump();
      expect(f.controller.tile!.frameIdentity, 'frame-2');
      expect(f.controller.tile!.revision, 2);
      expect(f.controller.replacementPending, false);
      expect(find.text('frame-2'), findsOneWidget);
      expect(sawEmpty, false);
      expect(acceptedPaths, hasLength(2));
      expect(painted, contains(('frame-2', 'frame-2')));
      expect(painted.every((pair) => pair.$1 == pair.$2), true);
      final frozen = f.core.calls
          .where((c) => c.$1 == 'media.detailRender')
          .last
          .$2;
      expect(frozen['recipe']['values'], [9]);
      expect(frozen['viewMode'], 'local');
      expect(frozen['expectedSourceSha'], _sha);
      expect(f.core.maximumActive, 1);
      expect(f.controller.ownedFileCount, lessThanOrEqualTo(4));
    },
  );

  testWidgets(
    'Replacement with no tile or no detail requirement leaves the accepted configuration unchanged',
    (tester) async {
      final f = _fixture(tester)..configure();
      expect(
        await f.controller.prepareReplacement(
          recipe: {
            'values': [9],
          },
          revision: 2,
          frameIdentity: 'unused',
          outputSize: const Size(640, 480),
          expectedSourceSha: _sha,
        ),
        false,
      );
      f.viewport(zoom: 1, pixels: const Size(800, 600));
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Accepted fit tile must decode',
      );
      final old = f.controller.tile!;
      expect(
        f.core.calls
            .singleWhere((c) => c.$1 == 'media.detailRender')
            .$2['recipe']['values'],
        [1, 2],
      );
      expect(
        await f.controller.prepareReplacement(
          recipe: {
            'values': [8],
          },
          revision: 3,
          frameIdentity: 'unneeded',
          outputSize: const Size(4000, 3000),
          expectedSourceSha: _sha,
        ),
        false,
      );
      await _drain(tester);
      expect(f.controller.tile!.path, old.path);
      expect(f.core.count('media.detailRender'), 1);

      // A zoomed request can discover only after native inspection that its
      // ordinary raster already contains every source pixel. It still resolves.
      f.viewport(zoom: 2);
      bool? result;
      unawaited(
        f.controller
            .prepareReplacement(
              recipe: {
                'values': [7],
              },
              revision: 4,
              frameIdentity: 'source-ceiling',
              outputSize: const Size(8000, 6000),
              expectedSourceSha: _sha,
            )
            .then<void>((value) {
              result = value;
            }),
      );
      await _until(
        tester,
        () => result != null,
        'Source ceiling must not leave a pending replacement',
      );
      expect(result, false);
      expect(f.controller.tile, isNull);
      expect(f.controller.replacementPending, false);
    },
  );

  testWidgets(
    'A rejected replacement releases sharp pixels and cannot resume the rejected profile',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Initial tile must decode',
      );
      f.core.wrongTileToken = true;
      bool? result;
      unawaited(
        f.controller
            .prepareReplacement(
              recipe: {
                'values': [9],
              },
              revision: 2,
              frameIdentity: 'rejected',
              outputSize: const Size(640, 480),
              expectedSourceSha: _sha,
            )
            .then<void>((value) {
              result = value;
            }),
      );
      await _until(
        tester,
        () => result != null,
        'Rejected native identity must resolve false',
      );
      expect(result, false);
      expect(f.controller.tile, isNull);
      expect(f.controller.error, isNotNull);
      f.core.wrongTileToken = false;
      f.controller.setEnabled(false);
      f.controller.setEnabled(true);
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Resumed accepted profile must decode',
        diagnostic: () =>
            'error=${f.controller.error}; enabled=${f.controller.enabled}; '
            'owned=${f.controller.ownedFileCount}; calls=${f.core.calls.map((c) => c.$1).toList()}',
      );
      expect(f.controller.tile!.frameIdentity, 'frame-1');
      expect(f.controller.tile!.revision, 1);
    },
  );

  for (final action in ['pause', 'invalidate', 'dispose', 'invalid viewport']) {
    testWidgets(
      'A $action releases a replacement before held native work completes',
      (tester) async {
        final f = _fixture(tester)
          ..configure()
          ..viewport();
        await _until(
          tester,
          () => f.controller.hasDetail,
          'Initial tile must decode',
        );
        final gate = f.core.gateFull();
        bool? result;
        unawaited(
          f.controller
              .prepareReplacement(
                recipe: {
                  'values': [9],
                },
                revision: 2,
                frameIdentity: 'abandoned',
                outputSize: const Size(640, 480),
                expectedSourceSha: _sha,
              )
              .then<void>((value) {
                result = value;
              }),
        );
        await _until(
          tester,
          () => f.core.count('media.detailRender') == 2,
          'Held replacement full work must start',
        );
        switch (action) {
          case 'pause':
            f.controller.setEnabled(false);
            break;
          case 'invalidate':
            f.controller.invalidate();
            break;
          case 'dispose':
            f.controller.dispose();
            break;
          case 'invalid viewport':
            f.viewport(region: Rect.zero);
            break;
        }
        await tester.pump();
        expect(result, false);
        expect(gate.isCompleted, false);
        expect(f.controller.tile, isNull);
        expect(f.controller.replacementPending, false);
        expect(f.core.cancelled, isNotEmpty);
        gate.complete();
        await _until(
          tester,
          () => f.core.active == 0 && f.controller.ownedFileCount == 0,
          'Late abandoned full and old sharp files must retire',
        );
        expect(f.controller.tile, isNull);
      },
    );
  }

  testWidgets(
    'An owner change retires held replacement pixels and returning owner cannot install the late target',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Initial tile must decode',
      );
      final gate = f.core.gateFull();
      bool? result;
      unawaited(
        f.controller
            .prepareReplacement(
              recipe: {
                'values': [9],
              },
              revision: 2,
              frameIdentity: 'old-owner-target',
              outputSize: const Size(640, 480),
              expectedSourceSha: _sha,
            )
            .then<void>((value) {
              result = value;
            }),
      );
      await _until(
        tester,
        () => f.core.count('media.detailRender') == 2,
        'Held replacement must start',
      );
      f.current = false;
      expect(f.controller.tile, isNull);
      await tester.pump(const Duration(milliseconds: 121));
      expect(result, false);
      expect(gate.isCompleted, false);
      f.current = true;
      gate.complete();
      await _until(
        tester,
        () => f.core.active == 0 && f.controller.ownedFileCount == 0,
        'Returning owner must not retain late private pixels',
      );
      expect(f.controller.tile, isNull);
      expect(f.controller.replacementPending, false);
    },
  );

  testWidgets(
    'Ordinary configuration cancels a staged target and preserves immediate invalidation semantics',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Initial tile must decode',
      );
      final gate = f.core.gateFull();
      bool? result;
      unawaited(
        f.controller
            .prepareReplacement(
              recipe: {
                'values': [9],
              },
              revision: 2,
              frameIdentity: 'staged',
              outputSize: const Size(640, 480),
              expectedSourceSha: _sha,
            )
            .then<void>((value) {
              result = value;
            }),
      );
      await _until(
        tester,
        () => f.core.count('media.detailRender') == 2,
        'Held replacement must start',
      );
      f.configure(
        recipe: {
          'values': [3],
        },
        revision: 3,
        frame: 'ordinary',
      );
      await tester.pump();
      expect(result, false);
      expect(f.controller.tile, isNull);
      gate.complete();
      await _until(
        tester,
        () => f.controller.tile?.frameIdentity == 'ordinary',
        'Only the ordinary target may install after cancellation',
      );
      expect(f.controller.tile!.revision, 3);
      expect(f.core.maximumActive, 1);
    },
  );

  testWidgets(
    'A different frozen profile cannot reuse the old tile even if frame labels are equal',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Initial tile must decode',
      );
      final old = f.controller.tile!;
      bool? result;
      unawaited(
        f.controller
            .prepareReplacement(
              recipe: {
                'values': [9],
              },
              revision: 1,
              frameIdentity: 'frame-1',
              outputSize: const Size(640, 480),
              expectedSourceSha: _sha,
            )
            .then<void>((value) {
              result = value;
            }),
      );
      await _until(
        tester,
        () => result == true,
        'New profile must acquire its own tile',
      );
      expect(f.controller.tile!.path, isNot(old.path));
      expect(f.core.count('media.detailRender'), 2);
      expect(f.core.count('media.detailTile'), 2);
    },
  );

  testWidgets(
    'A changed expected source rejects staging and immediately retires old source pixels',
    (tester) async {
      final f = _fixture(tester)
        ..configure()
        ..viewport();
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Initial tile must decode',
      );
      expect(
        await f.controller.prepareReplacement(
          recipe: {
            'values': [9],
          },
          revision: 2,
          frameIdentity: 'other-source',
          outputSize: const Size(640, 480),
          expectedSourceSha: _sha.replaceAll('a', 'b'),
        ),
        false,
      );
      expect(f.controller.tile, isNull);
      expect(f.controller.replacementPending, false);
      await _until(
        tester,
        () => f.controller.ownedFileCount == 0,
        'Old source files must be removed',
      );
      expect(f.core.count('media.detailRender'), 1);
    },
  );

  testWidgets(
    'Medium zoom fills physical pixels with native source detail and reuses the accepted request',
    (tester) async {
      final f = _fixture(tester);
      f.core
        ..fullWidth = 6000
        ..fullHeight = 4000
        ..emulateNativeTilePixels = true;
      const region = Rect.fromLTWH(.25, .25, .5, .5);
      const pixels = Size(1080, 720);
      f.configure(size: const Size(1200, 800));
      f.viewport(region: region, pixels: pixels);
      await _until(
        tester,
        () => f.controller.hasDetail,
        'The bounded native-sized tile must finish decoding',
      );
      final tile = f.controller.tile!;
      expect(
        tile.width * region.width / tile.region.width,
        greaterThanOrEqualTo(pixels.width),
      );
      expect(
        tile.height * region.height / tile.region.height,
        greaterThanOrEqualTo(pixels.height),
      );
      expect(tile.image.width, tile.width);
      expect(tile.image.height, tile.height);
      expect(tile.width, lessThanOrEqualTo(2048));
      expect(tile.width * tile.height, lessThanOrEqualTo(4 * 1024 * 1024));
      final request = f.core.calls
          .singleWhere((call) => call.$1 == 'media.detailTile')
          .$2;
      expect(request['maxEdge'], 2048);
      expect(request['region']['left'], closeTo(.19, 1e-9));
      expect(request['expectedSourceSha'], _sha);
      expect(request['owner'], '');
      expect(request['path'], f.core.documents.keys.single);
      expect(
        request['detailToken'],
        f.core.documents.values.single['detailToken'],
      );
      expect(tile.sourceSha, _sha);
      expect(tile.sourceSize, const Size(6000, 4000));

      // Parent rebuilds may configure the same frame again. A satisfied native
      // request is cached rather than repeatedly trying to exceed its ceiling.
      f.configure(size: const Size(1200, 800));
      f.viewport(region: region, pixels: pixels);
      await _drain(tester);
      expect(f.core.count('media.detailRender'), 1);
      expect(f.core.count('media.detailTile'), 1);
      expect(f.controller.tile!.path, tile.path);
    },
  );

  testWidgets(
    'Overscan shrinks through six percent and zero at native power-of-two boundaries',
    (tester) async {
      final f = _fixture(tester);
      f.core
        ..fullWidth = 8192
        ..fullHeight = 6144
        ..emulateNativeTilePixels = true;
      f.configure(size: const Size(1280, 960));
      const firstRegion = Rect.fromLTWH(.28, .28, .44, .44);
      f.viewport(
        region: firstRegion,
        zoom: 1 / .44,
        pixels: const Size(1700, 1275),
      );
      await _until(
        tester,
        () => f.controller.hasDetail,
        'First ROI must decode',
      );
      final firstRequest = f.core.calls
          .singleWhere((call) => call.$1 == 'media.detailTile')
          .$2;
      expect(firstRequest['region']['left'], closeTo(.2536, 1e-9));
      expect(firstRequest['region']['right'], closeTo(.7464, 1e-9));
      final first = f.controller.tile!;
      expect(
        first.width * firstRegion.width / first.region.width,
        greaterThanOrEqualTo(1700),
      );
      expect(
        first.height * firstRegion.height / first.region.height,
        greaterThanOrEqualTo(1275),
      );

      const nextRegion = Rect.fromLTWH(.25, .25, .5, .5);
      f.viewport(region: nextRegion, zoom: 2, pixels: const Size(900, 675));
      await _until(
        tester,
        () =>
            f.controller.tile != null && f.controller.tile!.path != first.path,
        'The wider ROI must replace the previous overscan tile',
      );
      final overscan = f.controller.tile!;
      expect(overscan.region.left, lessThan(.2));
      expect(
        overscan.width * nextRegion.width / overscan.region.width,
        greaterThanOrEqualTo(900),
      );

      // A higher physical display size needs denser pixels even though the
      // normalized viewport and the native maximum edge have not changed.
      f.viewport(region: nextRegion, zoom: 2, pixels: const Size(1800, 1350));
      await _until(
        tester,
        () =>
            f.controller.tile != null &&
            f.controller.tile!.path != overscan.path,
        'The same ROI must acquire sufficient physical-pixel density',
      );
      final nextRequest = f.core.calls
          .where((call) => call.$1 == 'media.detailTile')
          .last
          .$2;
      expect(nextRequest['region'], {
        'left': .25,
        'top': .25,
        'right': .75,
        'bottom': .75,
      });
      final next = f.controller.tile!;
      expect(next.width, 2048);
      expect(next.height, 1536);
      expect(
        next.width * nextRegion.width / next.region.width,
        greaterThanOrEqualTo(1800),
      );
      expect(
        next.height * nextRegion.height / next.region.height,
        greaterThanOrEqualTo(1350),
      );
      expect(f.core.count('media.detailRender'), 1);
      expect(f.core.count('media.detailTile'), 3);
      expect(f.core.maximumActive, 1);
    },
  );

  testWidgets(
    'Zoom seven retains original source pixels when the source cannot fill the screen',
    (tester) async {
      final f = _fixture(tester);
      f.core
        ..fullWidth = 6000
        ..fullHeight = 4000
        ..emulateNativeTilePixels = true;
      f.configure(size: const Size(1200, 800));
      final region = Rect.fromLTWH(.5 - .5 / 7, .5 - .5 / 7, 1 / 7, 1 / 7);
      f.viewport(region: region, zoom: 7, pixels: const Size(1080, 720));
      await _until(
        tester,
        () => f.controller.hasDetail,
        'Source-pixel ROI must decode',
      );
      final tile = f.controller.tile!;
      expect(tile.width / tile.region.width, closeTo(6000, 1e-6));
      expect(tile.height / tile.region.height, closeTo(4000, 1e-6));
      expect(tile.width * region.width / tile.region.width, lessThan(1080));
      expect(tile.height * region.height / tile.region.height, lessThan(720));
      expect(tile.image.width, tile.width);
      expect(tile.image.height, tile.height);
      expect(tile.width, lessThanOrEqualTo(2048));
      expect(tile.width * tile.height, lessThanOrEqualTo(4 * 1024 * 1024));
      f.configure(size: const Size(1200, 800));
      await _drain(tester);
      expect(f.core.count('media.detailRender'), 1);
      expect(f.core.count('media.detailTile'), 1);
    },
  );

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
      await _until(
        tester,
        () => !File(first.path).existsSync(),
        'Replaced tile must be deleted after its image lease is released',
      );
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
      await _until(
        tester,
        () => f.controller.ownedFileCount == 0,
        'Invalidated owner must retire its late full file',
      );
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
      await _until(
        tester,
        () => f.controller.ownedFileCount == 1,
        'Rejected tile must be removed while the reusable full file remains',
      );
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
