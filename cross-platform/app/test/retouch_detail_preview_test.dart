import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editing_detail_preview.dart';
import 'package:huevia/retouch_detail_preview.dart';
import 'package:huevia/retouch_original_controls.dart';

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAYAAABr5z2BAAAAF0lEQVR4nGOQWBD1nxLMMGrAqAHDwwAAqUGM0LHkvF4AAAAASUVORK5CYII=',
);
final _fullPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAYCAYAAACbU/80AAAAK0lEQVR4nO3OIQEAAAgDMEIQkUzUhRg3E/Ornr2kEhAQEBAQEBAQEBBIBx6hdydbj1D+7AAAAABJRU5ErkJggg==',
);

class _DetailCore extends HueviaCore {
  _DetailCore(this.directory) {
    root = directory.path;
    Directory('$root/previews').createSync();
    Directory('$root/originals').createSync();
    File(source).writeAsBytesSync(_fullPng);
    File(preview).writeAsBytesSync(_png);
  }
  final Directory directory;
  String get source => '$root/originals/source.png';
  String get preview => '$root/previews/ordinary.png';
  final calls = <(String, Json)>[];
  final cancelled = <String>[];
  final fullGate = Completer<void>();
  final fullTokens = <String, String>{};
  int serial = 0;
  String file({bool full = false}) {
    final name =
        '00000000-0000-4000-8000-${(++serial).toString().padLeft(12, '0')}.png';
    return (File(
      '$root/previews/$name',
    )..writeAsBytesSync(full ? _fullPng : _png)).path;
  }

  int count(String op) => calls.where((call) => call.$1 == op).length;
  @override
  Future<void> cancel(String jobId) async => cancelled.add(jobId);
  @override
  Future<Json> call(String op, [Json payload = const {}, String? jobId]) async {
    calls.add((op, object(jsonDecode(jsonEncode(payload)))));
    if (op == 'source.inspect') return {'sourceSha': _sha};
    if (op == 'media.detailRender') {
      await fullGate.future;
      final path = file(full: true), token = 'token-$serial';
      fullTokens[path] = token;
      return {
        'path': path,
        'width': 32,
        'height': 24,
        'sourceSha': _sha,
        'detailToken': token,
        'temporary': true,
        'fullResolution': true,
      };
    }
    if (op == 'media.detailTile') {
      return {
        'path': file(),
        'width': 16,
        'height': 12,
        'sourceWidth': 32,
        'sourceHeight': 24,
        'sourceSha': _sha,
        'detailToken': fullTokens[payload['path']],
        'region': payload['region'],
        'temporary': true,
      };
    }
    throw AppFailure(op);
  }
}

class _StageFixture {
  _StageFixture(this.core) {
    transform.value = Matrix4.diagonal3Values(2, 2, 1);
    frame = {
      'path': core.preview,
      'width': 16,
      'height': 12,
      '_detailRevision': 1,
      '_detailRecipe': {
        'localData': 'accepted-before-body',
        'geometry': <String, dynamic>{},
        'border': <String, dynamic>{},
      },
    };
  }
  final _DetailCore core;
  final transform = TransformationController();
  final viewport = ValueNotifier<RetouchPhotoViewport?>(null);
  final invalidation = ValueNotifier<int>(0);
  late Json frame;
  bool current = true, enabled = true;
  int starts = 0, commits = 0, cancels = 0;
  Offset? lastPoint;
  Widget build() => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          height: 600,
          child: RetouchOriginalPhotoStage(
            key: const ValueKey('detail-stage'),
            imageWidth: 16,
            imageHeight: 12,
            controller: transform,
            drawing: true,
            onViewportChanged: (value) => viewport.value = value,
            onStart: (point, size) {
              starts++;
              lastPoint = point;
              return true;
            },
            onUpdate: (point) => lastPoint = point,
            onEnd: () => commits++,
            onCancel: () => cancels++,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.blueGrey),
                RetouchDetailPreview(
                  core: core,
                  owner: 'owner',
                  sourcePath: core.source,
                  frame: frame,
                  viewport: viewport,
                  invalidation: invalidation,
                  isCurrent: () => current,
                  enabled: enabled,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  void dispose() {
    transform.dispose();
    viewport.dispose();
    invalidation.dispose();
  }
}

Future<void> _drain(WidgetTester tester, [int ticks = 28]) async {
  for (var tick = 0; tick < ticks; tick++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 4)),
    );
  }
}

_StageFixture _fixture(WidgetTester tester) {
  final directory = Directory.systemTemp.createTempSync('huevia-retouch-hd-');
  final fixture = _StageFixture(_DetailCore(directory));
  addTearDown(() async {
    fixture.current = false;
    if (!fixture.core.fullGate.isCompleted) fixture.core.fullGate.complete();
    await tester.pumpWidget(const SizedBox());
    await _drain(tester, 4);
    fixture.dispose();
    expect(File(fixture.core.source).readAsBytesSync(), _fullPng);
    expect(
      fixture.core.calls.map((call) => call.$1),
      everyElement(
        isIn(['source.inspect', 'media.detailRender', 'media.detailTile']),
      ),
    );
    await tester.runAsync(() => directory.delete(recursive: true));
  });
  return fixture;
}

void main() {
  test(
    'portrait and body viewport report exact normalized visible image regions',
    () {
      final fit = retouchOriginalPhotoViewport(
        viewport: const Size(400, 600),
        imageWidth: 1600,
        imageHeight: 1200,
        transform: Matrix4.identity(),
      );
      expect(fit.imageFrame, const Rect.fromLTWH(0, 150, 400, 300));
      expect(fit.visibleRegion, const Rect.fromLTWH(0, 0, 1, 1));
      final zoom = retouchOriginalPhotoViewport(
        viewport: const Size(400, 600),
        imageWidth: 1600,
        imageHeight: 1200,
        transform: Matrix4.diagonal3Values(2, 2, 1)
          ..setTranslationRaw(100, 0, 0),
      );
      expect(zoom.imageFrame, const Rect.fromLTWH(-100, 0, 800, 600));
      expect(zoom.visibleRegion, const Rect.fromLTRB(.125, 0, .625, 1));
      final body = retouchOriginalPhotoViewport(
        viewport: const Size(400, 600),
        imageWidth: 1200,
        imageHeight: 1600,
        transform: Matrix4.diagonal3Values(2, 2, 1),
        reserveBars: true,
      );
      expect(body.clip, const Rect.fromLTRB(0, 48, 400, 552));
      expect(body.visibleRegion.top, closeTo(.25, 1e-12));
      expect(body.visibleRegion.bottom, closeTo(.75, 1e-12));
      final point =
          body.imageFrame.topLeft +
          Offset(body.imageFrame.width * .5, body.imageFrame.height * .5);
      expect(point, const Offset(200, 300));
    },
  );

  test(
    'high megapixel zoom uses a 32 times plane with bounded normalized ROI',
    () {
      final value = retouchOriginalPhotoViewport(
        viewport: const Size(400, 600),
        imageWidth: 8256,
        imageHeight: 5504,
        transform: Matrix4.diagonal3Values(24, 24, 1),
      );
      expect(value.zoom, 24);
      expect(value.imageFrame.width, 9600);
      expect(value.visibleRegion.width, closeTo(1 / 24, 1e-12));
      expect(value.visibleRegion.center, const Offset(.5, .5));
    },
  );

  testWidgets(
    'HD arrival preserves a held repair stroke and its original plane',
    (tester) async {
      final fixture = _fixture(tester);
      await tester.pumpWidget(fixture.build());
      await _drain(tester, 9);
      expect(fixture.core.count('media.detailRender'), 1);
      final matrix = fixture.transform.value.clone();
      final stage = find.byKey(const ValueKey('detail-stage'));
      final stroke = await tester.startGesture(
        tester.getCenter(stage),
        pointer: 1,
      );
      await stroke.moveBy(const Offset(35, 0));
      expect(fixture.starts, 1);
      fixture.core.fullGate.complete();
      await _drain(tester);
      final tileLayer = tester.widget<EditingDetailTileLayer>(
        find.byType(EditingDetailTileLayer),
      );
      expect(
        tileLayer.controller.tile,
        isNotNull,
        reason:
            'error=${tileLayer.controller.error}; calls=${fixture.core.calls.map((c) => c.$1).toList()}',
      );
      expect(fixture.cancels, 0);
      expect(fixture.transform.value, matrix);
      final original = tester.widget<RetouchOriginalPhotoStage>(stage);
      expect(original.imageWidth, 16);
      expect(original.imageHeight, 12);
      final request = fixture.core.calls
          .firstWhere((call) => call.$1 == 'media.detailRender')
          .$2;
      expect(object(request['recipe'])['localData'], 'accepted-before-body');
      expect(request['expectedSourceSha'], _sha);
      expect(fixture.core.calls.last.$2['maxEdge'], lessThanOrEqualTo(2048));
      await stroke.up();
      expect(fixture.commits, 1);
      final first = await tester.startGesture(
        tester.getCenter(stage),
        pointer: 2,
      );
      await first.moveBy(const Offset(35, 0));
      final second = await tester.startGesture(
        tester.getCenter(stage) + const Offset(50, 0),
        pointer: 3,
      );
      expect(fixture.cancels, 1);
      await second.up();
      await first.moveBy(const Offset(20, 0));
      await first.up();
      expect(fixture.commits, 1);
    },
  );

  testWidgets(
    'mutation pauses HD synchronously and late owner result cannot install',
    (tester) async {
      final fixture = _fixture(tester);
      await tester.pumpWidget(fixture.build());
      await _drain(tester, 9);
      final layer = tester.widget<EditingDetailTileLayer>(
        find.byType(EditingDetailTileLayer),
      );
      expect(fixture.core.count('media.detailRender'), 1);
      fixture.enabled = false;
      fixture.invalidation.value++;
      expect(layer.controller.enabled, isFalse);
      expect(fixture.core.cancelled, hasLength(1));
      fixture.current = false;
      fixture.core.fullGate.complete();
      await _drain(tester);
      expect(layer.controller.tile, isNull);
      expect(fixture.core.count('media.detailTile'), 0);
      expect(fixture.core.count('media.detailRender'), 1);
    },
  );
}
