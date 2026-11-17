import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/collage_composition.dart';
import 'package:huevia/collage_workspace.dart';
import 'package:huevia/collage_viewport.dart';
import 'package:huevia/collage_chrome.dart';
import 'package:huevia/photo_collage.dart' show renderCollage;

class CollageHarness extends StatefulWidget {
  const CollageHarness({super.key, required this.paths});
  final List<String> paths;
  @override
  State<CollageHarness> createState() => CollageHarnessState();
}

class CollageHarnessState extends State<CollageHarness> {
  CollageStyle style = const CollageStyle();
  CollageTool tool = CollageTool.layout;
  int? selected;
  late final paths = List<String>.from(widget.paths);
  late final transforms = List.filled(paths.length, const CollageTransform());
  @override
  Widget build(BuildContext context) => CollageWorkspace(
    paths: paths,
    sizes: List.filled(paths.length, const Size(128, 64)),
    transforms: transforms,
    style: style,
    tool: tool,
    selectedPhoto: selected,
    busy: false,
    enabled: true,
    error: null,
    onClose: () {},
    onEdit: () async {},
    onDownload: () async {},
    onAdd: () async {},
    onStyle: (v) => setState(() => style = v),
    onTool: (v) => setState(() => tool = v),
    onSelected: (v) => setState(() => selected = v),
    onTransform: (i, v) => setState(() => transforms[i] = v),
    onMove: (old, next) => setState(() {
      paths.insert(next, paths.removeAt(old));
      transforms.insert(next, transforms.removeAt(old));
    }),
    onRemove: (i) => setState(() {
      paths.removeAt(i);
      transforms.removeAt(i);
    }),
    onReplace: (_) async {},
  );
}

Future<File> collageFixture(
  Directory directory,
  String name, {
  bool split = false,
  Color color = Colors.black,
}) async {
  final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
  canvas.drawColor(color, BlendMode.src);
  if (split) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 64, 64),
      Paint()..color = Colors.red,
    );
    canvas.drawRect(
      const Rect.fromLTWH(64, 0, 64, 64),
      Paint()..color = Colors.blue,
    );
  }
  final picture = recorder.endRecording(),
      image = await picture.toImage(128, 64);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${directory.path}/$name.png');
  await file.writeAsBytes(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return file;
}

Future<(int, int, Uint8List)> decodeCollage(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png),
      frame = await codec.getNextFrame();
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final result = (
    frame.image.width,
    frame.image.height,
    Uint8List.fromList(data!.buffer.asUint8List()),
  );
  frame.image.dispose();
  codec.dispose();
  return result;
}

void main() {
  test('all reference partitions cover the canvas once and stay within the pixel budget', () {
    expect(collagePatterns(4), hasLength(19));
    for (var count = 2; count <= 9; count++) {
      final sizes = List.generate(count, (i) => Size(100 + i * 40, 200));
      final patterns = collagePatterns(count);
      for (var pattern = 0; pattern < patterns.length; pattern++) {
        final cells = patterns[pattern];
        expect(cells, hasLength(count));
        expect(
          cells.fold<double>(0, (sum, r) => sum + r.width * r.height),
          closeTo(1, .00001),
        );
        for (var i = 0; i < count; i++) {
          expect(
            cells[i].left >= -.00001 &&
                cells[i].top >= -.00001 &&
                cells[i].right <= 1.00001 &&
                cells[i].bottom <= 1.00001,
            isTrue,
          );
          for (var j = i + 1; j < count; j++) {
            expect(
              cells[i].deflate(.000001).overlaps(cells[j].deflate(.000001)),
              isFalse,
            );
          }
        }
        for (var ratio = 0; ratio < 8; ratio++) {
          final plan = composeCollage(
            sizes,
            CollageStyle(pattern: pattern, ratio: ratio, gap: 40),
            4096,
          );
          expect(plan.size.aspectRatio, closeTo(collageRatios[ratio], .002));
          expect(
            plan.size.longestSide <= 4096 &&
                plan.size.width * plan.size.height <= 12000000,
            isTrue,
          );
          for (final cell in plan.cells) {
            expect(
              cell.width > 0 &&
                  cell.height > 0 &&
                  cell.left >= 0 &&
                  cell.top >= 0 &&
                  cell.right <= plan.size.width &&
                  cell.bottom <= plan.size.height,
              isTrue,
            );
          }
        }
      }
    }
  });

  test('long stitching respects source rotation and keeps the original source aspect', () {
    final plan = composeCollage(
      const [Size(400, 200), Size(300, 200)],
      const CollageStyle(mode: CollageMode.longImage),
      2048,
      transforms: const [CollageTransform(turns: 1), CollageTransform()],
    );
    expect(plan.cells.first.width / plan.cells.first.height, closeTo(.5, .002));
    expect(plan.cells.last.width / plan.cells.last.height, closeTo(1.5, .002));
    expect(plan.cells.first.bottom <= plan.cells.last.top, isTrue);
  });

  testWidgets(
    'saved crop, rotation, filter and text change pixels without rewriting source files',
    (tester) async {
      await tester.runAsync(() async {
        final directory = await Directory.systemTemp.createTemp(
          'huevia-collage237-pixels-',
        );
        try {
          final file = await collageFixture(directory, 'split', split: true),
              blank = await collageFixture(directory, 'black');
          final before = await file.readAsBytes();
          final plan = composeCollage(
            const [Size(128, 64), Size(128, 64)],
            const CollageStyle(ratio: 1, pattern: 2),
            256,
          );
          Future<(int, int, Uint8List)> output(
            CollageTransform transform, [
            CollageStyle style = const CollageStyle(),
          ]) async => decodeCollage(
            await renderCollage(
              [file.path, blank.path],
              plan,
              background: Colors.black,
              contain: false,
              style: style,
              transforms: [transform, const CollageTransform()],
            ),
          );
          final normal = await output(
                const CollageTransform(scale: 2, offset: Offset(1, 0)),
              ),
              moved = await output(
                const CollageTransform(scale: 2, offset: Offset(-1, 0)),
              );
          final center = (128 * normal.$1 + 64) * 4;
          expect(normal.$3[center], greaterThan(240));
          expect(moved.$3[center + 2], greaterThan(240));
          final gray = await output(
            const CollageTransform(),
            const CollageStyle(filter: 5),
          );
          expect((gray.$3[center] - gray.$3[center + 1]).abs(), lessThan(2));
          expect(
            (gray.$3[center + 1] - gray.$3[center + 2]).abs(),
            lessThan(2),
          );
          final rotated = await output(const CollageTransform(turns: 1));
          expect(
            rotated.$3,
            isNot(orderedEquals((await output(const CollageTransform())).$3)),
          );
          final text = await output(
            const CollageTransform(),
            const CollageStyle(
              texts: [
                CollageText(value: 'TEST', position: Offset(.75, .5), size: 48),
              ],
            ),
          );
          var white = 0;
          for (var y = 70; y < 190; y++) {
            for (var x = 135; x < 250; x++) {
              final pixel = (y * text.$1 + x) * 4;
              if (text.$3[pixel] > 200 &&
                  text.$3[pixel + 1] > 200 &&
                  text.$3[pixel + 2] > 200) {
                white++;
              }
            }
          }
          expect(white, greaterThan(50));
          expect(await file.readAsBytes(), before);
        } finally {
          await directory.delete(recursive: true);
        }
      });
    },
  );

  testWidgets(
    'reference modes, ratios, layouts, filters and text are actual controls',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'huevia-collage237-controls-',
      );
      final file = await tester.runAsync(
        () => collageFixture(directory, 'photo', split: true),
      );
      final key = GlobalKey<CollageHarnessState>();
      await tester.pumpWidget(
        MaterialApp(
          home: CollageHarness(key: key, paths: List.filled(4, file!.path)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('拼图'), findsOneWidget);
      expect(find.text('New'), findsNothing);
      final canvas = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('collage-canvas')),
      );
      final point = canvas.localToGlobal(const Offset(50, 40));
      await tester.tapAt(point);
      await tester.pump();
      expect(key.currentState!.selected, 0);
      final view = tester.state<CollageViewportState>(
        find.byType(CollageViewport),
      );
      final beforePan = view.view.value.clone();
      await tester.dragFrom(point, const Offset(30, 12));
      await tester.pump();
      expect(view.view.value, isNot(beforePan));
      expect(key.currentState!.transforms.first.offset, Offset.zero);
      await tester.tap(find.byKey(const ValueKey('collage-edit-photo')));
      await tester.pump();
      final cropPoint = canvas.localToGlobal(const Offset(50, 40));
      await tester.dragFrom(cropPoint, const Offset(30, 12));
      await tester.pump();
      expect(key.currentState!.transforms.first.offset.dx, greaterThan(0));
      await tester.tap(find.byKey(const ValueKey('collage-edit-photo')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('collage-ratio-1')));
      await tester.pump();
      expect(key.currentState!.style.ratio, 1);
      await tester.tap(find.byKey(const ValueKey('collage-pattern-4')));
      await tester.pump();
      expect(key.currentState!.style.pattern, 4);
      await tester.tap(find.byKey(const ValueKey('collage-mode-template')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('collage-template-3')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('collage-template-3')));
      await tester.pump();
      expect(key.currentState!.style.template, 3);
      expect(key.currentState!.style.gap, 10);
      await tester.tap(find.byKey(const ValueKey('collage-mode-longImage')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('collage-viewer')), findsOneWidget);
      await tester.tap(find.text('横向长图'));
      await tester.pump();
      expect(key.currentState!.style.horizontal, isTrue);
      await tester.tap(find.byKey(const ValueKey('collage-tool-filter')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('collage-filter-5')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('collage-filter-5')));
      await tester.pump();
      expect(key.currentState!.style.filter, 5);
      await tester.tap(find.byKey(const ValueKey('collage-tool-text')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('collage-text-input')),
        '旅行日记',
      );
      await tester.pump();
      expect(key.currentState!.style.texts.single.value, '旅行日记');
      await tester.tap(find.byTooltip('管理拼图照片'));
      await tester.pumpAndSettle();
      final title = find.text('照片 4/9');
      final foreground =
          tester.widget<Text>(title).style?.color ??
          DefaultTextStyle.of(tester.element(title)).style.color!;
      expect(
        (collageUiSurface.computeLuminance() + .05) /
            (foreground.computeLuminance() + .05),
        greaterThanOrEqualTo(4.5),
      );
      await tester.tap(find.byTooltip('关闭照片管理'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        try {
          await directory.delete(recursive: true);
        } on FileSystemException catch (error) {
          if (!Platform.isWindows || error.osError?.errorCode != 32) rethrow;
        }
      });
    },
  );

  for (final variant in [
    (360.0, 800.0, 1.3),
    (320.0, 640.0, 1.0),
    (900.0, 1200.0, 1.0),
  ]) {
    testWidgets(
      'reference workspace fits ${variant.$1} with text scale ${variant.$3}',
      (tester) async {
        tester.view.physicalSize = Size(variant.$1, variant.$2);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(variant.$3)),
              child: child!,
            ),
            home: const CollageHarness(paths: []),
          ),
        );
        await tester.pumpAndSettle();
        for (final key in ['collage-ratio-0', 'collage-pattern-0']) {
          final size = tester.getSize(find.byKey(ValueKey(key)));
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        }
        await tester.drag(
          find.byKey(const ValueKey('collage-panel-handle')),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        for (final item in CollageTool.values) {
          await tester.tap(find.byKey(ValueKey('collage-tool-${item.name}')));
          await tester.pumpAndSettle();
          if (item == CollageTool.adjust || item == CollageTool.text) {
            final key = item == CollageTool.adjust
                ? 'collage-background-${Colors.white.toARGB32()}'
                : 'collage-text-color-${Colors.white.toARGB32()}';
            final scrollable = tester.state<ScrollableState>(
              find
                  .descendant(
                    of: find.byKey(
                      ValueKey(
                        item == CollageTool.adjust
                            ? 'collage-adjust-list'
                            : 'collage-text-list',
                      ),
                    ),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            );
            for (var step = 0; step <= 20; step++) {
              scrollable.position.jumpTo(
                (step * 40.0).clamp(0.0, scrollable.position.maxScrollExtent),
              );
              await tester.pumpAndSettle();
              if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) break;
            }
            expect(
              find.byKey(ValueKey(key)),
              findsOneWidget,
              reason:
                  '48dp color target for ${item.name}; scroll=${scrollable.position.pixels}/${scrollable.position.maxScrollExtent}',
            );
            final size = tester.getSize(find.byKey(ValueKey(key)));
            expect(size.width, greaterThanOrEqualTo(48));
            expect(size.height, greaterThanOrEqualTo(48));
          }
          expect(tester.takeException(), isNull);
        }
        expect(find.byKey(const Key('download-collage')), findsOneWidget);
      },
    );
  }
}
