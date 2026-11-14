import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editing_detail_preview.dart';
import 'package:huevia/raw_develop.dart';
import 'package:huevia/theme.dart';
import 'package:path/path.dart' as p;

import 'raw_realtime_preview_test.dart' show RealtimeRawCore, RealtimeRawState;

class _DetailCall {
  _DetailCall(this.operation, this.payload, this.job);
  final String operation;
  final Json payload;
  final String? job;
  final result = Completer<Json>();
}

/// Native pixels are mocked; the actual RAW widget, transform, queue and shared
/// HD controller run. Device integration separately verifies native ROI pixels.
class _DetailRawCore extends RealtimeRawCore {
  final details = <_DetailCall>[];
  bool holdFull = false;
  int detailSerial = 0;

  @override
  Json image() => {
    ...super.image(),
    'width': 1280,
    'height': 960,
    'sourceSha': 'a' * 64,
  };

  Json full() {
    final path = ownedImage();
    return {
      'path': path,
      'width': 6000,
      'height': 4500,
      'sourceSha': 'a' * 64,
      'detailToken': 'token-$detailSerial',
      'temporary': true,
      'fullResolution': true,
    };
  }

  String ownedImage() {
    final name = (++detailSerial).toString().padLeft(12, '0');
    final path = '$root/previews/00000000-0000-4000-8000-$name.png';
    File(path).writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
      ),
    );
    return path;
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation != 'media.rawDetail' && operation != 'media.detailTile') {
      return super.call(operation, payload, jobId);
    }
    operations.add(operation);
    final request = _DetailCall(
      operation,
      object(jsonDecode(jsonEncode(payload))),
      jobId,
    );
    details.add(request);
    if (operation == 'media.rawDetail') {
      return holdFull ? request.result.future : full();
    }
    return {
      'path': ownedImage(),
      'width': 1,
      'height': 1,
      'sourceWidth': 6000,
      'sourceHeight': 4500,
      'sourceSha': payload['expectedSourceSha'],
      'detailToken': payload['detailToken'],
      'region': payload['region'],
      'temporary': true,
    };
  }
}

Future<void> _io(WidgetTester tester, [int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<({_DetailRawCore core, RealtimeRawState state})> _open(
  WidgetTester tester, {
  bool withReference = false,
}) async {
  tester.view.physicalSize = const Size(500, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final core = _DetailRawCore();
  final current = RealtimeRawState(core)..owner('alice');
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.dark),
      home: RawDevelopPage(
        state: current,
        photo: Photo('${core.root}/source.nef', '高清.NEF', {
          'raw': true,
          if (withReference)
            'rawJpegReference': {
              'relativePath': 'originals/reference.jpg',
              'sha256': 'b' * 64,
              'sourceSha': 'a' * 64,
              'name': '同次拍摄.jpg',
            },
        }),
      ),
    ),
  );
  await _io(tester);
  expect(find.byType(EditingDetailTileLayer), findsOneWidget);
  return (core: core, state: current);
}

Future<void> _close(WidgetTester tester, RealtimeRawState state) async {
  await tester.pumpWidget(const SizedBox());
  await _io(tester);
  state.dispose();
  tester.binding.imageCache.clear();
  tester.binding.imageCache.clearLiveImages();
}

Future<void> _zoom(
  WidgetTester tester,
  double factor, {
  double x = 0,
  double y = 0,
}) async {
  final viewer = tester.widget<InteractiveViewer>(
    find.byType(InteractiveViewer),
  );
  viewer.transformationController!.value = Matrix4.identity()
    ..translateByDouble(x, y, 0, 1)
    ..scaleByDouble(factor, factor, 1, 1);
  await _io(tester);
}

void main() {
  testWidgets(
    'RAW real viewport requests ROI detail, preserves the ordinary frame and reuses the full file while panning',
    (tester) async {
      final f = await _open(tester, withReference: true), core = f.core;
      expect(
        core.details,
        isEmpty,
        reason: 'Fit preview has sufficient actual pixels at DPR 1',
      );
      final ordinaryFinder = find.byWidgetPredicate(
        (widget) => widget is Image && widget.semanticLabel == 'RAW 显影预览',
      );
      final ordinary = tester.widget<Image>(ordinaryFinder).image;
      await _zoom(tester, 2, x: -180);
      expect(
        core.details.where((call) => call.operation == 'media.rawDetail'),
        hasLength(1),
      );
      final firstTile = core.details.last;
      expect(firstTile.operation, 'media.detailTile');
      final region = object(firstTile.payload['region']);
      expect(region['left'], greaterThan(0));
      expect(region['right'], lessThan(1));
      expect(firstTile.payload['maxEdge'], lessThanOrEqualTo(2048));
      expect(tester.widget<Image>(ordinaryFinder).image, ordinary);
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        2,
      );
      await _zoom(tester, 2, x: -350);
      expect(
        core.details.where((call) => call.operation == 'media.rawDetail'),
        hasLength(1),
      );
      expect(
        core.details.last.payload['region'],
        isNot(firstTile.payload['region']),
      );
      expect(
        tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .maxScale,
        32,
      );
      await _zoom(tester, 32, x: -6400, y: -5000);
      final closeRegion = object(core.details.last.payload['region']);
      expect(
        (closeRegion['right'] as num) - (closeRegion['left'] as num),
        lessThan(.06),
      );
      expect(
        core.details.where((call) => call.operation == 'media.rawDetail'),
        hasLength(1),
      );
      expect(core.operations, isNot(contains('media.rawDevelop')));
      expect(core.operations, isNot(contains('draft.save')));
      expect(tester.takeException(), isNull);
      await _close(tester, f.state);
    },
  );

  testWidgets(
    'RAW changing settings cancels held HD immediately and resumes only after its final frozen preview',
    (tester) async {
      final f = await _open(tester, withReference: true), core = f.core;
      core.holdFull = true;
      await _zoom(tester, 2, x: -180);
      final initialFull = core.details.single;
      expect(object(initialFull.payload['settings'])['exposure'], 0);
      expect(initialFull.payload['reference'], {
        'path': p.join(core.root, 'originals', 'reference.jpg'),
        'sha256': 'b' * 64,
        'sourceSha': 'a' * 64,
      });
      final sliderFinder = find.byWidgetPredicate(
        (widget) => widget is Slider && widget.min == -50 && widget.max == 50,
      );
      await tester.scrollUntilVisible(sliderFinder, 180);
      final slider = tester.widget<Slider>(sliderFinder);
      core.hold = true;
      slider.onChanged!(10);
      expect(
        core.cancelled,
        contains(initialFull.job),
        reason: 'Cancel precedes waiting for the next ordinary native frame',
      );
      await tester.pump();
      final interactive = core.calls.last;
      slider.onChangeEnd!(10);
      interactive.result.complete(core.image());
      await _io(tester);
      expect(core.details, hasLength(1));
      final finalPreview = core.calls.last;
      expect(finalPreview.exposure, 10);
      final staleFull = core.full();
      initialFull.result.complete(staleFull);
      await _io(tester);
      expect(
        core.details,
        hasLength(1),
        reason: 'A cancelled full result cannot install while final preview is pending',
      );
      core.holdFull = false;
      finalPreview.result.complete(core.image());
      await _io(tester, 14);
      final latest = core.details.lastWhere(
        (call) => call.operation == 'media.rawDetail',
      );
      expect(object(latest.payload['settings'])['exposure'], 10);
      expect(latest.payload['reference'], initialFull.payload['reference']);
      expect(latest.payload['expectedSourceSha'], 'a' * 64);
      expect(
        find.byType(LinearProgressIndicator),
        findsNothing,
        reason: 'Ordinary previews with an installed frame keep the progress bar hidden',
      );
      expect(tester.takeException(), isNull);
      await _close(tester, f.state);
    },
  );

  testWidgets(
    'RAW owner leave and return rejects held HD and disposes its late private file',
    (tester) async {
      final f = await _open(tester), core = f.core;
      core.holdFull = true;
      await _zoom(tester, 2);
      final held = core.details.single;
      f.state.owner('bob');
      f.state.owner('alice');
      expect(core.cancelled, contains(held.job));
      final late = core.full();
      held.result.complete(late);
      await _io(tester, 14);
      expect(core.details, hasLength(1));
      expect(find.byType(EditingDetailTileLayer), findsNothing);
      expect(File(late['path'] as String).existsSync(), isFalse);
      expect(tester.takeException(), isNull);
      await _close(tester, f.state);
    },
  );
}
