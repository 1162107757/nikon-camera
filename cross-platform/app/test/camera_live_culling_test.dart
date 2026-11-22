import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/album_batch.dart';
import 'package:huevia/camera_live.dart';
import 'package:huevia/camera_live_card.dart';
import 'package:huevia/camera_live_culling.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';
import 'package:path/path.dart' as p;

class _CullingCore extends HueviaCore {
  final project = <Photo>[];
  final selected = <String>{};
  final starCalls = <Json>[];
  int projectReads = 0;
  Completer<void>? nextProject;
  Completer<void>? starReply;

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    switch (operation) {
      case 'project.open':
        expectSync(payload['projectId'], 'shoot');
        final rows = [
          for (final photo in project) {'path': photo.path},
        ];
        projectReads++;
        final pending = nextProject;
        nextProject = null;
        await pending?.future;
        return {'photos': rows};
      case 'photo.stars':
        return {'keys': selected.toList()};
      case 'photo.star':
        starCalls.add(payload);
        final photo = project.singleWhere(
          (item) => item.path == payload['path'],
        );
        if (payload['starred'] == true) {
          selected.add(photo.starKey);
        } else {
          selected.remove(photo.starKey);
        }
        await starReply?.future;
        return {'keys': selected.toList()};
      default:
        throw AppFailure('Unexpected operation $operation');
    }
  }
}

class _Live extends CameraLive {
  _Live(super.state);

  void announce(Photo photo) {
    latestPhoto = photo;
    notifyListeners();
  }
}

class _State extends AppState {
  _State(super.core) {
    session = {
      'user': {'id': 'alice'},
    };
    cameraLive
      ..owner = 'alice'
      ..projectId = 'shoot';
  }

  @override
  late final _Live cameraLive = _Live(this);

  void addPhoto(Photo photo) {
    photos = [photo, ...photos];
    notifyListeners();
  }

  void replaceOwner(String owner) {
    session = {
      'user': {'id': owner},
    };
    starredPhotos = {};
    notifyListeners();
  }

  @override
  void dispose() {
    cameraLive.dispose();
    super.dispose();
  }
}

Photo _photo(_CullingCore core, String name) =>
    Photo(p.join(core.root, 'originals', name), name, {});

Widget _app(Widget page, {double scale = 1}) => MaterialApp(
  theme: hueviaTheme(Brightness.dark),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: page,
);

void main() {
  testWidgets(
    'shooting panel opens culling, zooms, swipes and exports only this project',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final root = Directory.systemTemp.createTempSync('huevia-culling-');
      addTearDown(root.deleteSync);
      final core = _CullingCore()..root = root.path;
      final newest = _photo(core, 'DSC_002.jpg');
      final older = _photo(core, 'DSC_001.jpg');
      final unrelated = _photo(core, 'unrelated.jpg');
      core.project.addAll([newest, older]);
      core.selected.add(unrelated.starKey);
      final state = _State(core)..photos = [newest, older, unrelated];
      addTearDown(state.dispose);
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SingleChildScrollView(
              child: CameraLivePanel(state: state, projectId: 'shoot'),
            ),
          ),
          scale: 2,
        ),
      );
      final entry = find.byKey(const Key('live-transfer-culling'));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.text('拍摄选片'), findsOneWidget);
      expect(find.text('1/2  ·  DSC_002.jpg'), findsOneWidget);
      expect(find.text('已选 0'), findsOneWidget);

      final viewer = find.byType(InteractiveViewer);
      final center = tester.getCenter(viewer);
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 55));
      await tester.tapAt(center);
      await tester.pump();
      expect(
        tester
            .widget<InteractiveViewer>(viewer)
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        greaterThan(1),
      );
      await tester.fling(viewer, const Offset(-110, 0), 700);
      await tester.pumpAndSettle();
      expect(find.text('1/2  ·  DSC_002.jpg'), findsOneWidget);
      await tester.tap(find.byTooltip('恢复预览大小'));
      await tester.pump();
      await tester.fling(viewer, const Offset(-110, 0), 700);
      await tester.pumpAndSettle();
      expect(find.text('2/2  ·  DSC_001.jpg'), findsOneWidget);
      await tester.tap(find.byKey(const Key('live-cull-star')));
      await tester.pumpAndSettle();
      expect(core.starCalls.single['path'], older.path);
      expect(
        state.starredPhotos,
        containsAll([older.starKey, unrelated.starKey]),
      );
      await tester.tap(find.text('已选 1'));
      await tester.pumpAndSettle();
      expect(find.text('1/1  ·  DSC_001.jpg'), findsOneWidget);
      await tester.tap(find.byKey(const Key('live-cull-export')));
      await tester.pumpAndSettle();
      final export = tester.widget<BatchExportPage>(
        find.byType(BatchExportPage),
      );
      expect(export.rows.map((row) => row['id']), [older.path]);
      expect(export.currentEffects, isTrue);
      expect(export.saveToGallery, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'receipts during a refresh are coalesced and preserve the current photo',
    (tester) async {
      final core = _CullingCore()..root = 'test-culling';
      final first = _photo(core, 'first.jpg');
      final second = _photo(core, 'second.jpg');
      final third = _photo(core, 'third.jpg');
      core.project.add(first);
      final state = _State(core)..photos = [first];
      addTearDown(state.dispose);
      await tester.pumpWidget(
        _app(CameraLiveCullingPage(state: state, projectId: 'shoot')),
      );
      await tester.pumpAndSettle();
      expect(find.text('1/1  ·  first.jpg'), findsOneWidget);
      final gate = Completer<void>();
      core.nextProject = gate;
      core.project.insert(0, second);
      state.addPhoto(second);
      state.cameraLive.announce(second);
      await tester.pump();
      core.project.insert(0, third);
      state.addPhoto(third);
      state.cameraLive.announce(third);
      await tester.pump();
      expect(core.projectReads, 2);
      gate.complete();
      await tester.pumpAndSettle();
      expect(core.projectReads, 3);
      expect(find.text('3/3  ·  first.jpg'), findsOneWidget);
      await tester.tap(find.byTooltip('上一张'));
      await tester.pumpAndSettle();
      expect(find.text('2/3  ·  second.jpg'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a star reply cannot restore the prior account after a switch', (
    tester,
  ) async {
    final core = _CullingCore()..root = 'test-culling';
    final photo = _photo(core, 'marked.jpg');
    core.project.add(photo);
    final state = _State(core)..photos = [photo];
    addTearDown(state.dispose);
    await tester.pumpWidget(
      _app(CameraLiveCullingPage(state: state, projectId: 'shoot')),
    );
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    core.starReply = gate;
    await tester.tap(find.byKey(const Key('live-cull-star')));
    await tester.pump();
    expect(core.starCalls.single['owner'], 'alice');
    state.replaceOwner('bob');
    state.replaceOwner('alice');
    gate.complete();
    await tester.pumpAndSettle();
    expect(state.starredPhotos, isEmpty);
    expect(find.text('账号已改变，请重新打开拍摄项目。'), findsOneWidget);
    expect(find.byKey(const Key('live-cull-export')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'large selections can export later groups without clearing stars',
    (tester) async {
      final core = _CullingCore()..root = 'test-culling';
      core.project.addAll([
        for (var i = 0; i < 101; i++) _photo(core, 'frame-$i.jpg'),
      ]);
      core.selected.addAll(core.project.map((photo) => photo.starKey));
      final state = _State(core)..photos = List.of(core.project);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        _app(CameraLiveCullingPage(state: state, projectId: 'shoot')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('live-cull-export')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第 101–101 张'));
      await tester.pumpAndSettle();
      final export = tester.widget<BatchExportPage>(
        find.byType(BatchExportPage),
      );
      expect(export.rows.map((row) => row['id']), [core.project.last.path]);
      expect(state.starredPhotos, hasLength(101));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
