import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/crop_workspace.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editing_detail_preview.dart';
import 'package:huevia/selection_mask.dart';
import 'package:huevia/selection_workspace.dart';

import 'editor_workspace_test.dart' show WorkspaceState;
import 'selection_editor_test.dart' show seed;
import 'selection_workspace_test.dart' show SelectionCore;

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _tilePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAYAAABr5z2BAAAAF0lEQVR4nGOQWBD1nxLMMGrAqAHDwwAAqUGM0LHkvF4AAAAASUVORK5CYII=',
);

class _HostCore extends SelectionCore {
  _HostCore(super.directory);
  int detailSerial = 0;
  Completer<void>? holdDetail;
  final gates = <Completer<void>>[];
  String owned(List<int> bytes) {
    final name =
        '00000000-0000-4000-8000-${(++detailSerial).toString().padLeft(12, '0')}.png';
    return (File('$root/previews/$name')..writeAsBytesSync(bytes)).path;
  }

  Completer<void> delayDetail() {
    final next = holdDetail = Completer<void>();
    gates.add(next);
    return next;
  }

  @override
  Future<Json> call(String op, [Json payload = const {}, String? jobId]) async {
    if (op == 'source.inspect' ||
        op == 'media.detailRender' ||
        op == 'media.detailTile') {
      calls.add((op, object(jsonDecode(jsonEncode(payload)))));
      if (op == 'source.inspect') return {'sourceSha': _sha};
      if (op == 'media.detailRender') {
        final gate = holdDetail;
        holdDetail = null;
        if (gate != null) await gate.future;
        return {
          'path': owned([1]),
          'width': 4000,
          'height': 3000,
          'sourceSha': _sha,
          'detailToken': 'host-full',
          'temporary': true,
          'fullResolution': true,
        };
      }
      return {
        'path': owned(_tilePng),
        'width': 16,
        'height': 12,
        'sourceWidth': 4000,
        'sourceHeight': 3000,
        'sourceSha': _sha,
        'detailToken': 'host-full',
        'temporary': true,
        'region': payload['region'],
      };
    }
    return super.call(op, payload, jobId);
  }
}

Future<void> _frames(WidgetTester tester, [int count = 20]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
}

(_HostCore, WorkspaceState) _fixture(WidgetTester tester) {
  final directory = Directory.systemTemp.createTempSync('huevia-detail-host-');
  final core = _HostCore(directory);
  final actual = WorkspaceState(core);
  final original = core.source.readAsBytesSync();
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    for (final gate in core.gates) {
      if (!gate.isCompleted) gate.complete();
    }
    await tester.pumpWidget(const SizedBox());
    await _frames(tester);
    expect(core.source.readAsBytesSync(), original);
    expect(
      core.calls.any(
        (call) => call.$1 == 'draft.save' || call.$1.startsWith('versions.'),
      ),
      false,
    );
    actual.dispose();
    tester.binding.imageCache.clear();
    tester.binding.imageCache.clearLiveImages();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.runAsync(() async {
      expect(
        directory.parent.resolveSymbolicLinksSync().toLowerCase(),
        Directory.systemTemp.resolveSymbolicLinksSync().toLowerCase(),
      );
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
  });
  return (core, actual);
}

Future<void> _pinch(WidgetTester tester, Offset center) async {
  final first = await tester.startGesture(
    center - const Offset(40, 0),
    pointer: 1,
  );
  final second = await tester.startGesture(
    center + const Offset(40, 0),
    pointer: 2,
  );
  await first.moveTo(center - const Offset(60, 0));
  await tester.pump();
  await second.moveTo(center + const Offset(90, 0));
  await tester.pump();
  await first.moveTo(center - const Offset(100, 0));
  await tester.pump();
  await first.up();
  // A remaining finger must stay navigation-only, not start a crop/brush.
  await second.moveBy(const Offset(15, 10));
  await tester.pump();
  await second.up();
  await tester.pump();
}

Finder _detailRaster() => find.descendant(
  of: find.byType(EditingDetailTileLayer),
  matching: find.byType(RawImage),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Crop pinch navigates without editing and a later handle drag maps through the zoomed photo plane',
    (tester) async {
      final (core, _) = _fixture(tester);
      var crop = const Rect.fromLTRB(.35, .35, .65, .65);
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, update) => Scaffold(
              body: CropCanvas(
                image: core.source.path,
                pixels: const Size(4000, 3000),
                crop: crop,
                onChanged: (next) => update(() => crop = next),
              ),
            ),
          ),
        ),
      );
      await _frames(tester);
      final base = tester.getRect(
        find.byKey(const ValueKey('crop-image-plane')),
      );
      final unchanged = crop;
      await _pinch(tester, base.center);
      final zoomed = tester.getRect(
        find.byKey(const ValueKey('crop-image-plane')),
      );
      expect(zoomed.width, greaterThan(base.width));
      expect(crop, unchanged);
      final corner = Offset(
        zoomed.left + crop.left * zoomed.width,
        zoomed.top + crop.top * zoomed.height,
      );
      await tester.dragFrom(corner, const Offset(30, 20));
      await tester.pump();
      expect(crop.left - unchanged.left, closeTo(30 / zoomed.width, .005));
      expect(crop.top - unchanged.top, closeTo(20 / zoomed.height, .005));
      final edited = crop;
      await tester.tap(find.byTooltip('适应照片'));
      await tester.pump();
      expect(
        tester.getRect(find.byKey(const ValueKey('crop-image-plane'))).width,
        closeTo(base.width, .01),
      );
      expect(crop, edited);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Crop detail freezes the uncropped transformation recipe and rejects a late owner-invalid full result',
    (tester) async {
      final (core, state) = _fixture(tester);
      final gate = core.delayDetail();
      await tester.pumpWidget(
        MaterialApp(
          home: CropWorkspace(
            core: core,
            photo: Photo(core.source.path, 'source.png', const {}),
            owner: '',
            recipe: {
              'values': List.filled(17, 0),
              'border': {'template': 3},
              'geometry': {
                'left': 200000,
                'top': 100000,
                'right': 800000,
                'bottom': 900000,
                'mirrored': true,
              },
            },
            isCurrent: () =>
                (state.session['user']?['id'] as String? ?? '').isEmpty,
            invalidation: state,
          ),
        ),
      );
      await _frames(tester);
      await tester.tap(find.text('1:1像素'));
      await _frames(tester);
      final request = core.calls
          .singleWhere((call) => call.$1 == 'media.detailRender')
          .$2;
      expect(request['recipe']['border'], isEmpty);
      expect(request['recipe']['geometry']['left'], 0);
      expect(request['recipe']['geometry']['right'], 1000000);
      expect(request['recipe']['geometry']['mirrored'], true);
      state.switchOwner();
      await tester.pump();
      gate.complete();
      await _frames(tester);
      expect(_detailRaster(), findsNothing);
      expect(find.byKey(const ValueKey('crop-image-plane')), findsNothing);
      expect(
        core.calls.where((call) => call.$1 == 'media.detailTile'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Selection detail uses localView while a zoomed brush still commits source-normalized points',
    (tester) async {
      final (core, state) = _fixture(tester);
      final results = <SelectionResult?>[];
      final recipe = {
        'presetId': 'filter',
        'values': List.filled(17, 0),
        'localData': 'frozen-local',
        'geometry': {'turns': 1},
        'border': {'template': 3},
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => results.add(
                  await Navigator.of(context).push<SelectionResult>(
                    MaterialPageRoute(
                      builder: (_) => SelectionWorkspace(
                        state: state,
                        photo: Photo(core.source.path, 'source.png', const {}),
                        owner: '',
                        region: seed(),
                        localState: const {'localData': '', 'regions': []},
                        frame: {
                          'path': core.copy(),
                          'width': 800,
                          'height': 600,
                          'geometryWidth': 4000,
                          'geometryHeight': 3000,
                        },
                        recipe: recipe,
                        expectedSourceSha: _sha,
                        maskBuilder: (input) async => buildSelectionMask(input),
                      ),
                    ),
                  ),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await _frames(tester);
      final base = tester.getRect(
        find.byKey(const ValueKey('selection-image-plane')),
      );
      await _pinch(tester, base.center);
      await _frames(tester);
      expect(_detailRaster(), findsOneWidget);
      final full = core.calls
          .singleWhere((call) => call.$1 == 'media.detailRender')
          .$2;
      expect(full['viewMode'], 'local');
      expect(full['recipe'], recipe);
      expect(full['expectedSourceSha'], _sha);
      final plane = tester.getRect(
        find.byKey(const ValueKey('selection-image-plane')),
      );
      final brush = await tester.startGesture(plane.center);
      await brush.moveBy(const Offset(20, 10));
      await tester.pump();
      await brush.up();
      await _frames(tester);
      await tester.tap(find.text('完成'));
      await _frames(tester);
      final value = core.calls
          .singleWhere((call) => call.$1 == 'local.change')
          .$2['value'];
      final strokes = value['strokes'] as List;
      expect(
        strokes,
        hasLength(1),
      ); // The preceding two-finger navigation did not draw.
      final points = (strokes.single as Map)['points'] as List;
      expect(points[0], closeTo(.5, .005));
      expect(points[1], closeTo(.5, .005));
      expect(
        (points[points.length - 2] as num).toDouble(),
        closeTo(.5 + 20 / plane.width, .005),
      );
      expect(results, hasLength(1));
      expect(results.single, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Selection owner invalidation masks its photo and cannot install a delayed local detail tile',
    (tester) async {
      final (core, state) = _fixture(tester);
      final gate = core.delayDetail();
      await tester.pumpWidget(
        MaterialApp(
          home: SelectionWorkspace(
            state: state,
            photo: Photo(core.source.path, 'source.png', const {}),
            owner: '',
            region: seed(),
            localState: const {'localData': '', 'regions': []},
            frame: {
              'path': core.copy(),
              'width': 800,
              'height': 600,
              'geometryWidth': 4000,
              'geometryHeight': 3000,
            },
            recipe: {'values': List.filled(17, 0)},
            expectedSourceSha: _sha,
            maskBuilder: (input) async => buildSelectionMask(input),
          ),
        ),
      );
      await _frames(tester);
      await _pinch(
        tester,
        tester.getCenter(find.byKey(const ValueKey('selection-image-plane'))),
      );
      await _frames(tester);
      expect(
        core.calls.where((call) => call.$1 == 'media.detailRender'),
        hasLength(1),
      );
      state.switchOwner();
      await tester.pump();
      gate.complete();
      await _frames(tester);
      expect(find.byKey(const ValueKey('selection-image-plane')), findsNothing);
      expect(_detailRaster(), findsNothing);
      expect(
        core.calls.where((call) => call.$1 == 'media.detailTile'),
        isEmpty,
      );
      expect(core.calls.where((call) => call.$1 == 'local.change'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
