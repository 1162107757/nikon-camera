import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/photo_collage.dart';
import 'package:huevia/theme.dart';

class _HeldCollageCore extends HueviaCore {
  _HeldCollageCore(Directory directory) {
    root = directory.path;
  }
  final preview = Completer<Json>(),
      full = Completer<Json>(),
      imported = Completer<String>();
  bool fullStarted = false;
  final cancelled = <String>[];
  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
  }

  @override
  Future<String> importFile(XFile selected, {required bool preset}) =>
      imported.future;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'draft.load') {
      return {'sourceSha': 'a' * 64, 'recipe': Recipe().data};
    }
    if (operation == 'media.reviewPreview') return preview.future;
    if (operation == 'media.detailRender') {
      fullStarted = true;
      return full.future;
    }
    if (operation == 'media.info') return {'width': 10, 'height': 10};
    throw AppFailure(operation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android Back and cancel retire busy collage work without a late commit',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'huevia-collage-back-',
      );
      final core = _HeldCollageCore(directory), state = AppState(core);
      final input = File('${directory.path}/input.png')
        ..writeAsBytesSync([1, 2, 3]);
      state.photos = [Photo(input.path, 'input.png', {})];
      final rows = [
        {'id': input.path, 'name': 'input.png'},
        {'id': input.path, 'name': 'input.png'},
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PhotoCollagePage(state: state, rows: rows),
                  ),
                ),
                child: const Text('打开拼接'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开拼接'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('cancel-collage')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('打开拼接'), findsOneWidget);
      expect(core.cancelled, isNotEmpty);
      final preview = File('${directory.path}/previews/late.png');
      preview.parent.createSync();
      preview.writeAsBytesSync([1, 2, 3]);
      core.preview.complete({'path': preview.path, 'width': 10, 'height': 10});
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      expect(state.photos, hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      tester.binding.imageCache.clear();tester.binding.imageCache.clearLiveImages();
      await tester.runAsync(() async {try{await directory.delete(recursive:true);}on FileSystemException catch(error){if(!Platform.isWindows||error.osError?.errorCode!=32) rethrow;}});
    },
  );
  test('Cancelled generated-file import cannot register a new photo or rename an existing one', () async {
    final directory = await Directory.systemTemp.createTemp(
      'huevia-collage-import-',
    );
    try {
      final core = _HeldCollageCore(directory), state = AppState(core);
      final file = File('${directory.path}/originals/generated.png');
      await file.parent.create();
      await file.writeAsBytes([1, 2, 3]);
      var current = true;
      final pending = state.importPhoto(
        XFile(file.path),
        isCurrent: () => current,
      );
      final rejected = expectLater(pending, throwsA(isA<AppFailure>()));
      await Future<void>.delayed(Duration.zero);
      current = false;
      core.imported.complete(file.path);
      await rejected;
      expect(state.photos, isEmpty);
      expect(await File('${directory.path}/photos-index.json').exists(), false);
      state.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });
  testWidgets(
    'Back during full-size collage saving cancels the native render and prevents import',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'huevia-collage-save-back-',
      );
      final core = _HeldCollageCore(directory), state = AppState(core);
      final input = File('${directory.path}/previews/input.png');
      input.parent.createSync();
      input.writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
        ),
      );
      state.photos = [Photo(input.path, 'input.png', {})];
      core.preview.complete({'path': input.path, 'width': 10, 'height': 10});
      final rows = [
        {'id': input.path, 'name': 'input.png'},
        {'id': input.path, 'name': 'input.png'},
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PhotoCollagePage(state: state, rows: rows),
                  ),
                ),
                child: const Text('打开拼接'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开拼接'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump();
      await tester.tap(find.byKey(const Key('save-collage')));
      await tester.pump();
      expect(core.fullStarted, true);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('打开拼接'), findsOneWidget);
      final late = File('${directory.path}/previews/full.png')
        ..writeAsBytesSync([1, 2, 3]);
      core.full.complete({
        'path': late.path,
        'sourceSha': 'a' * 64,
        'temporary': true,
        'fullResolution': true,
        'width': 10,
        'height': 10,
      });
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump();
      expect(state.photos, hasLength(1));
      expect(core.cancelled, isNotEmpty);
      expect(File('${directory.path}/photos-index.json').existsSync(), false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      tester.binding.imageCache.clear();tester.binding.imageCache.clearLiveImages();
      await tester.runAsync(() async {try{await directory.delete(recursive:true);}on FileSystemException catch(error){if(!Platform.isWindows||error.osError?.errorCode!=32) rethrow;}});
    },
  );
  test('horizontal and vertical layouts preserve input aspect and order', () {
    for (final layout in [CollageLayout.horizontal, CollageLayout.vertical]) {
      final plan = planCollage(
        const [Size(400, 200), Size(100, 200)],
        layout,
        0,
        2048,
      );
      expect(plan.cells[0].width / plan.cells[0].height, closeTo(2, .002));
      expect(plan.cells[1].width / plan.cells[1].height, closeTo(.5, .002));
      expect(plan.cells[0].overlaps(plan.cells[1]), isFalse);
      expect(
        layout == CollageLayout.horizontal
            ? plan.cells[0].left < plan.cells[1].left
            : plan.cells[0].top < plan.cells[1].top,
        isTrue,
      );
    }
  });
  test('all supported counts and layouts stay within the pixel budget', () {
    for (var count = 2; count <= 9; count++) {
      for (final layout in CollageLayout.values) {
        final plan = planCollage(
          List.generate(
            count,
            (i) => i.isEven ? const Size(600, 400) : const Size(400, 600),
          ),
          layout,
          40,
          4096,
        );
        expect(plan.size.longestSide, lessThanOrEqualTo(4096));
        expect(plan.size.width * plan.size.height, lessThanOrEqualTo(12000000));
        expect(plan.cells.length, count);
        for (final cell in plan.cells) {
          expect(cell.width, greaterThan(0));
          expect(cell.height, greaterThan(0));
          expect(
            cell.left >= 0 &&
                cell.top >= 0 &&
                cell.right <= plan.size.width &&
                cell.bottom <= plan.size.height,
            isTrue,
          );
        }
      }
    }
  });
  test('rejects invalid or excessive source selections', () {
    for (final sources in [
      <Size>[],
      [const Size(1, 1)],
      List.filled(10, const Size(10, 10)),
      [const Size(0, 1), const Size(2, 2)],
    ]) {
      expect(
        () => planCollage(sources, CollageLayout.grid, 0, 4096),
        throwsA(isA<AppFailure>()),
      );
    }
  });
  testWidgets('saved pixels follow source order and preserve source files', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp(
        'huevia-collage-',
      );
      try {
        // Real raster files exercise the production decode, fit, PNG and cleanup path.
        final files = <File>[];
        for (final color in [
          const Color(0xffff0000),
          const Color(0xff0000ff),
        ]) {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawColor(color, BlendMode.src);
          final picture = recorder.endRecording();
          final image = await picture.toImage(32, 32);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('${directory.path}/${files.length}.png');
          await file.writeAsBytes(png!.buffer.asUint8List());
          files.add(file);
          image.dispose();
          picture.dispose();
        }
        final before = await files.first.readAsBytes();
        final plan = planCollage(
          const [Size(32, 32), Size(32, 32)],
          CollageLayout.horizontal,
          0,
          256,
        );
        final bytes = await renderCollage(
          files.map((f) => f.path).toList(),
          plan,
          background: Colors.white,
          contain: true,
        );
        final codec = await ui.instantiateImageCodec(bytes),
            frame = await codec.getNextFrame();
        final raw = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final pixels = raw!.buffer.asUint8List();
        final left = (64 * frame.image.width + 64) * 4,
            right = (64 * frame.image.width + 192) * 4;
        expect(pixels[left], greaterThan(240));
        expect(pixels[left + 2], lessThan(20));
        expect(pixels[right + 2], greaterThan(240));
        expect(pixels[right], lessThan(20));
        expect(await files.first.readAsBytes(), before);
        frame.image.dispose();
        codec.dispose();
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
}
