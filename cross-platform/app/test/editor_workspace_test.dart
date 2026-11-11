import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/crop_workspace.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/export_preview.dart';
import 'package:huevia/split_compare.dart';

class WorkspaceCore extends HueviaCore {
  WorkspaceCore(this.directory) {
    root = directory.path;
    Directory('$root/previews').createSync();
    source = File('$root/source.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
        ),
      );
  }
  final Directory directory;
  late File source;
  final List<(String, Json)> calls = [];
  int count = 0;
  Size exportSize = const Size(800, 600);
  Completer<Json>? delayFrame;
  String copy() =>
      source.copySync('$root/previews/preview-${count++}.png').path;
  Json frame() => {
    'before': copy(),
    'jpeg': copy(),
    'width': 375,
    'height': 500,
  };
  @override
  Future<void> cancel(String jobId) async {
    calls.add(('cancel', {'job': jobId}));
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
    if (operation == 'media.preview') {
      final turns =
          object(object(payload['recipe'])['geometry'])['turns'] as int? ?? 0;
      return {
        'path': copy(),
        'width': 800,
        'height': 600,
        'geometryWidth': turns.isOdd ? 600 : 800,
        'geometryHeight': turns.isOdd ? 800 : 600,
      };
    }
    if (operation == 'media.exportPreview') {
      return {
        'id': 'session',
        'width': exportSize.width.toInt(),
        'height': exportSize.height.toInt(),
        'bytes': 10000,
        'quality': 95,
        'overview': copy(),
      };
    }
    if (operation == 'media.exportPreviewFrame') {
      return delayFrame?.future ?? Future.value(frame());
    }
    if (operation == 'media.exportPreviewCommit') {
      return {'id': 'saved', 'path': source.path};
    }
    if (operation == 'media.exportPreviewClose') return {};
    throw AppFailure(operation);
  }
}

class WorkspaceState extends AppState {
  WorkspaceState(super.core);
  void switchOwner() {
    session = {
      'user': {'id': 'different'},
    };
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }

  Future<void> cleanup(WidgetTester tester, Directory directory) async {
    tester.binding.imageCache.clear();
    tester.binding.imageCache.clearLiveImages();
    await tester.runAsync(() async {
      expect(
        directory.parent.absolute.path.toLowerCase(),
        Directory.systemTemp.absolute.path.toLowerCase(),
      );
      for (var attempt = 0; attempt < 10; attempt++) {
        try {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
          return;
        } on FileSystemException catch (error) {
          // Windows' engine may retain a mapped image until its process exits.
          // The host runner removes exactly these owned fixtures afterwards.
          if (Platform.isWindows && error.osError?.errorCode == 32) {
            debugPrint(
              'Deferred test fixture cleanup: ${directory.absolute.path}',
            );
            return;
          }
          if (attempt == 9) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
    });
  }

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets('Tentative crop handles, ratio, rotate and cancel at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory.systemTemp.createTempSync('huevia-crop-');
      final core = WorkspaceCore(directory);
      final recipe = <String, dynamic>{
        'geometry': {'left': 0, 'top': 0, 'right': 1000000, 'bottom': 1000000},
        'border': {'template': 1},
      };
      Json? received;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  received = await Navigator.push<Json>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CropWorkspace(
                        core: core,
                        photo: Photo(core.source.path, 'own.png', {}),
                        owner: '',
                        recipe: recipe,
                      ),
                    ),
                  );
                },
                child: const Text('打开构图'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开构图'));
      await settle(tester);
      await tester.pumpAndSettle();
      final request = core.calls.firstWhere((c) => c.$1 == 'media.preview').$2;
      expect(object(request['recipe'])['border'], isEmpty);
      expect(object(object(request['recipe'])['geometry'])['right'], 1000000);
      final rect = tester.getRect(find.byType(Image));
      await tester.dragFrom(
        rect.topLeft + const Offset(2, 2),
        const Offset(45, 30),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('原图'));
      await tester.tap(find.text('原图'));
      await tester.pump();
      // Original PhotoCropDialog expands the chosen ratio around the current
      // center; returning to the source ratio must reveal the complete frame.
      expect(
        tester.widget<CropCanvas>(find.byType(CropCanvas)).crop,
        const Rect.fromLTRB(0, 0, 1, 1),
      );
      await tester.ensureVisible(find.text('1:1'));
      await tester.tap(find.text('1:1'));
      await tester.pump();
      final beforePinch = tester
          .widget<CropCanvas>(find.byType(CropCanvas))
          .crop;
      final center = tester.getCenter(find.byType(Image));
      final first = await tester.startGesture(
        center - const Offset(40, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 2,
      );
      await first.moveTo(center - const Offset(30, 0));
      await tester.pump();
      await second.moveTo(center + const Offset(15, 0));
      await tester.pump();
      await first.moveTo(center - const Offset(15, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pump();
      expect(
        tester.widget<CropCanvas>(find.byType(CropCanvas)).crop.width,
        lessThan(beforePinch.width),
      );
      final beforeStraighten = tester
          .widget<CropCanvas>(find.byType(CropCanvas))
          .crop;
      await tester.drag(
        find.byType(Slider),
        const Offset(100, 0),
        touchSlopX: 64,
      );
      await settle(tester);
      await tester.pumpAndSettle();
      expect(
        object(
          object(
            core.calls.lastWhere((c) => c.$1 == 'media.preview').$2['recipe'],
          )['geometry'],
        )['angle'],
        isNot(0),
      );
      expect(
        tester.widget<CropCanvas>(find.byType(CropCanvas)).crop,
        beforeStraighten,
      );
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(received, isNotNull);
      final w = (received!['right'] as int) - (received!['left'] as int),
          h = (received!['bottom'] as int) - (received!['top'] as int);
      expect((w * 800 - h * 600).abs(), lessThan(2000));
      expect(received!['left'], greaterThan(0));
      expect(object(recipe['geometry'])['left'], 0);
      expect(core.calls.where((c) => c.$1 == 'draft.save'), isEmpty);
      received = {'unexpected': true};
      await tester.tap(find.text('打开构图'));
      await settle(tester);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('旋转 90°'));
      await tester.tap(find.text('旋转 90°'));
      await settle(tester);
      await tester.pumpAndSettle();
      expect(
        object(
          object(
            core.calls.lastWhere((c) => c.$1 == 'media.preview').$2['recipe'],
          )['geometry'],
        )['turns'],
        1,
      );
      await tester.tap(find.byTooltip('返回编辑照片'));
      await tester.pumpAndSettle();
      expect(received, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      await cleanup(tester, directory);
    });
  }
  testWidgets('Split divider clamps and preserves a common zoom transform', (
    tester,
  ) async {
    final semanticsHandle = tester.ensureSemantics();
    final core = WorkspaceCore(
      Directory.systemTemp.createTempSync('huevia-split-data-'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: SplitCompare(
            effect: core.source.path,
            original: core.source.path,
            enabled: true,
          ),
        ),
      ),
    );
    await settle(tester);
    final controller = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    controller.value = Matrix4.identity()
      ..translateByDouble(20, 10, 0, 1)
      ..scaleByDouble(2, 2, 1, 1);
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('compare-divider')),
      const Offset(1200, 0),
    );
    await tester.pump();
    final semantics = tester.getSemantics(
      find.bySemanticsLabel('拖动分割线，对比原图与效果'),
    );
    expect(semantics.value, '100%');
    expect(controller.value.getMaxScaleOnAxis(), 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    await cleanup(tester, core.directory);
    semanticsHandle.dispose();
  });
  for (final commit in [false, true]) {
    testWidgets(
      'Encoded preview ${commit ? 'commits the frozen result' : 'cancel creates no saved version'}',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        final core = WorkspaceCore(
          Directory.systemTemp.createTempSync('huevia-export-preview-'),
        );
        if (!commit) core.exportSize = const Size(1, 1);
        final state = WorkspaceState(core);
        Json? received;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    received = await Navigator.push<Json>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ExportPreviewPage(
                          state: state,
                          photo: Photo(core.source.path, 'own.png', {}),
                          recipe: {'values': List.filled(17, 0)},
                          owner: '',
                          options: {'size': 'full'},
                        ),
                      ),
                    );
                  },
                  child: const Text('预览'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('预览'));
        await settle(tester);
        await settle(tester);
        expect(
          core.calls
              .lastWhere((c) => c.$1 == 'media.exportPreviewFrame')
              .$2['scale'],
          lessThanOrEqualTo(8),
        );
        await tester.tap(find.text('100%'));
        await settle(tester);
        await settle(tester);
        expect(
          core.calls
              .lastWhere((c) => c.$1 == 'media.exportPreviewFrame')
              .$2['scale'],
          1,
        );
        await tester.tap(find.text('编码前'));
        await tester.pump();
        expect(find.bySemanticsLabel('编码前的实际像素'), findsOneWidget);
        if (commit) {
          await tester.tap(find.byTooltip('导出并分享'));
        } else {
          await tester.tap(find.byTooltip('返回导出设置'));
        }
        await settle(tester);
        await tester.pumpAndSettle();
        expect(
          core.calls.where((c) => c.$1 == 'media.exportPreviewCommit').length,
          commit ? 1 : 0,
        );
        expect(received, commit ? isNotNull : isNull);
        expect(core.calls.any((c) => c.$1 == 'media.exportPreviewClose'), true);
        await tester.pumpWidget(const SizedBox());
        await settle(tester);
        state.dispose();
        await cleanup(tester, core.directory);
        semanticsHandle.dispose();
      },
    );
  }
  testWidgets(
    'Account change cancels stale frame work and disables confirmation',
    (tester) async {
      final core = WorkspaceCore(
        Directory.systemTemp.createTempSync('huevia-export-owner-'),
      );
      final state = WorkspaceState(core);
      core.delayFrame = Completer<Json>();
      await tester.pumpWidget(
        MaterialApp(
          home: ExportPreviewPage(
            state: state,
            photo: Photo(core.source.path, 'own.png', {}),
            recipe: {},
            owner: '',
            options: {'size': 'full'},
          ),
        ),
      );
      await settle(tester);
      state.switchOwner();
      await tester.pump();
      expect(find.text('账号已改变，请重新打开成品预览。'), findsOneWidget);
      final stale = core.frame();
      core.delayFrame!.complete(stale);
      await settle(tester);
      await tester.tap(find.byTooltip('导出并分享'));
      await tester.pump();
      expect(
        core.calls.where((c) => c.$1 == 'media.exportPreviewCommit'),
        isEmpty,
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      expect(File(stale['jpeg'] as String).existsSync(), false);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      state.dispose();
      await cleanup(tester, core.directory);
    },
  );
}
