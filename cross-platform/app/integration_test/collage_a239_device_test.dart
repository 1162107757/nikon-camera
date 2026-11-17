import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/photo_collage.dart';
import 'package:huevia/collage_viewport.dart';
import 'package:huevia/theme.dart';
import 'package:huevia/collage_thumbnail.dart';
import 'package:huevia/collage_chrome.dart';

import '../test/collage_workspace_test.dart' as workspace;
import '../test/collage_export_test.dart' as export_checks;
import '../test/photo_collage_test.dart' as preserved;
import 'fixtures/gallery_fixture_bytes.dart';

class Collage239Binding extends IntegrationTestWidgetsFlutterBinding {
  @override
  bool get registerTestTextInput => true;
}

Future<void> until(WidgetTester tester, bool Function() ready) async {
  await tester.pump();
  for (var i = 0; i < 1000 && !ready(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(ready(), isTrue);
}

void main() {
  Collage239Binding().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  preserved.main();
  workspace.main();
  export_checks.main();
  testWidgets(
    'native collage download validates actual source and publishes a JPEG to Android MediaStore',
    (tester) async {
      final core = HueviaCore();
      await tester.runAsync(core.initialize);
      final state = AppState(core);
      final dir = Directory('${Directory.systemTemp.path}/collage239-native');
      dir.createSync(recursive: true);
      final file = await tester.runAsync(
        () => workspace.collageFixture(dir, 'native-source', split: true),
      );
      final photo = await tester.runAsync(
        () => state.importPhoto(XFile(file!.path)),
      );
      final before = file!.readAsBytesSync();
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('native239'),
          theme: hueviaTheme(Brightness.light),
          home: PhotoCollagePage(
            state: state,
            rows: [
              {'id': photo!.path},
              {'id': photo.path},
            ],
          ),
        ),
      );
      await until(
        tester,
        () =>
            tester
                .widget<IconButton>(find.byKey(const Key('download-collage')))
                .onPressed !=
            null,
      );
      await tester.tap(find.byKey(const Key('download-collage')));
      await until(
        tester,
        () =>
            tester
                .widget<IconButton>(find.byKey(const Key('download-collage')))
                .onPressed !=
            null,
      );
      expect(find.text('拼图已保存到手机相册'), findsOneWidget);
      expect(find.text('原图与打开导出设置时不同，请重新打开照片。'), findsNothing);
      expect(state.photos.length, greaterThanOrEqualTo(2));
      final page = await tester.runAsync(
        () => core.call('gallery.page', {
          'refresh': true,
          'limit': 100,
          'offset': 0,
          'category': 'all',
        }),
      );
      expect(
        (page!['items'] as List).any(
          (r) => (r['name'] as String? ?? '').contains('拼接_'),
        ),
        isTrue,
      );
      expect(file.readAsBytesSync(), before);
      final summary = {
        'result': 'passed',
        'actualNativeCore': true,
        'photoCount': state.photos.length,
        'originalUnchanged': true,
        'operations': core.recentOperations,
      };
      File('${dir.path}/native-export.json')
          .writeAsStringSync(jsonEncode(summary));
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'pan pinch fit and draggable panel preserve composition; capture Android phone large text tablet',
    (tester) async {
      final dir = Directory('${Directory.systemTemp.path}/collage239-captures')
        ..createSync(recursive: true);
      final paths = <String>[];
      for (final name in [
        'sunlit-forest.jpg',
        'coastal-water.jpg',
        'rainy-tokyo.jpg',
        'portrait-smile.jpg',
      ]) {
        final f = File('${dir.path}/$name')
          ..writeAsBytesSync(base64Decode(galleryFixtureBytes[name]!));
        paths.add(f.path);
      }
      for (final variant in [
        ('phone', const Size(390, 844), 1.0),
        ('large', const Size(360, 800), 1.3),
        ('tablet', const Size(900, 1200), 1.0),
      ]) {
        tester.view.physicalSize = variant.$2;
        tester.view.devicePixelRatio = 1;
        final boundary = GlobalKey(),
            key = GlobalKey<workspace.CollageHarnessState>();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              key: ValueKey(variant.$1),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(variant.$3)),
                child: child!,
              ),
              home: workspace.CollageHarness(key: key, paths: paths),
            ),
          ),
        );
        Future<void> capture(String name) async {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 250)),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('${dir.path}/$name.png')
              .writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        }

        await capture('${variant.$1}-default');
        final thumbnail = tester.widget<CollageThumbnail>(
          find.byType(CollageThumbnail).first,
        );
        expect(thumbnail.cache.images.keys.toSet(), paths.toSet());
        expect(
          thumbnail.cache.images.values.every(
            (image) => image.width <= 192 && image.height <= 192,
          ),
          isTrue,
        );
        expect(
          Theme.of(
            tester.element(find.byKey(const ValueKey('collage-ratio-0'))),
          ).colorScheme.primary,
          collageUiAccent,
        );
        expect(find.text('New'), findsNothing);
        final ratioFinder = find.byKey(const ValueKey('collage-ratio-0'));
        final ratioText = tester.widget<Text>(
          find.descendant(of: ratioFinder, matching: find.byType(Text)),
        );
        final ratioBox = tester.widget<AnimatedContainer>(
          find.descendant(
            of: ratioFinder,
            matching: find.byType(AnimatedContainer),
          ),
        );
        final fg = ratioText.style!.color!.computeLuminance();
        final bg = (ratioBox.decoration! as BoxDecoration).color!
            .computeLuminance();
        expect((bg + .05) / (fg + .05), greaterThanOrEqualTo(4.5));

        if (variant.$1 != 'phone') continue;
        final panel = find.byKey(const ValueKey('collage-tool-panel'));
        final initial = tester.getSize(panel).height;
        Future<void> dragPanel(double distance) async {
          final box = tester.getRect(
            find.byKey(const ValueKey('collage-panel-handle')),
          );
          final origin = Offset(box.center.dx, box.top + 8);
          final finger = await tester.startGesture(origin);
          for (var i = 1; i <= 8; i++) {
            await finger.moveTo(origin + Offset(0, distance * i / 8));
            await tester.pump(const Duration(milliseconds: 40));
          }
          await finger.up();
          await tester.pumpAndSettle();
        }

        await dragPanel(220);
        await tester.pumpAndSettle();
        expect(tester.getSize(panel).height, lessThan(initial / 2));
        await capture('phone-collapsed');
        final view = tester.state<CollageViewportState>(
          find.byType(CollageViewport),
        );
        final start = view.view.value.clone();
        final area = tester.getRect(
          find.byKey(const ValueKey('collage-viewer')),
        );
        final center = area.center;
        await tester.dragFrom(center, const Offset(40, 25));
        await tester.pumpAndSettle();
        expect(view.view.value, isNot(start));
        final before = view.view.value.getMaxScaleOnAxis();
        final a = await tester.startGesture(
          center - const Offset(35, 0),
          pointer: 11,
        );
        final b = await tester.startGesture(
          center + const Offset(35, 0),
          pointer: 12,
        );
        await tester.pump();
        await a.moveTo(center - const Offset(85, 0));
        await b.moveTo(center + const Offset(85, 0));
        await tester.pump();
        await a.up();
        await b.up();
        await tester.pumpAndSettle();
        expect(view.view.value.getMaxScaleOnAxis(), greaterThan(before));
        expect(
          key.currentState!.transforms.every(
            (t) => t.scale == 1 && t.offset == Offset.zero,
          ),
          isTrue,
        );
        await capture('phone-zoom');
        final zoomed = view.view.value.getMaxScaleOnAxis();
        final c = await tester.startGesture(
          center - const Offset(85, 0),
          pointer: 21,
        );
        final d = await tester.startGesture(
          center + const Offset(85, 0),
          pointer: 22,
        );
        await tester.pump();
        await c.moveTo(center - const Offset(25, 0));
        await d.moveTo(center + const Offset(25, 0));
        await tester.pump();
        await c.up();
        await d.up();
        await tester.pumpAndSettle();
        expect(view.view.value.getMaxScaleOnAxis(), lessThan(zoomed));
        await capture('phone-zoom-out');

        await tester.tap(find.byKey(const ValueKey('collage-fit')));
        await tester.pumpAndSettle();
        expect(
          view.view.value.getMaxScaleOnAxis(),
          closeTo(start.getMaxScaleOnAxis(), .001),
        );
        await capture('phone-fit');
        await dragPanel(-340);
        await tester.pumpAndSettle();
        expect(tester.getSize(panel).height, greaterThan(initial));
        await capture('phone-expanded');
        await tester.tap(find.byKey(const ValueKey('collage-panel-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('collage-tool-text')));
        await tester.pumpAndSettle();
        expect(tester.getSize(panel).height, closeTo(initial, 1));
        await tester.enterText(
          find.byKey(const ValueKey('collage-text-input')),
          '旅行日记',
        );
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const ValueKey('collage-move-text')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('collage-move-text')));
        await tester.pumpAndSettle();
        expect(find.text('完成移动'), findsOneWidget);
        final textPosition = key.currentState!.style.texts.single.position;
        final origin = tester
            .getRect(find.byKey(const ValueKey('collage-viewer')))
            .center;
        final finger = await tester.startGesture(origin);
        for (var i = 1; i <= 8; i++) {
          await finger.moveTo(origin + Offset(48 * i / 8, -48 * i / 8));
          await tester.pump(const Duration(milliseconds: 40));
        }
        await finger.up();
        await tester.pumpAndSettle();
        expect(
          key.currentState!.style.texts.single.position,
          isNot(textPosition),
        );
        await capture('phone-text-move');
        final textScroll = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey('collage-text-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        textScroll.position.jumpTo(0);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('collage-text-input')),
          '',
        );
        await tester.pump();
        textScroll.position.jumpTo(
          100.0.clamp(0.0, textScroll.position.maxScrollExtent),
        );
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<TextButton>(
                find.byKey(const ValueKey('collage-move-text')),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byKey(const ValueKey('collage-move-text')));
        await tester.pumpAndSettle();
        final viewer = tester.widget<InteractiveViewer>(
          find.byKey(const ValueKey('collage-viewer')),
        );
        expect(viewer.panEnabled, isTrue);
        expect(viewer.scaleEnabled, isTrue);
        final beforeResume = view.view.value.clone();
        final resumeOrigin = tester
            .getRect(find.byKey(const ValueKey('collage-viewer')))
            .center;
        final resumeFinger = await tester.startGesture(resumeOrigin);
        for (var step = 1; step <= 8; step++) {
          await resumeFinger.moveTo(
            resumeOrigin + Offset(80 * step / 8, 40 * step / 8),
          );
          await tester.pump(const Duration(milliseconds: 40));
        }
        await resumeFinger.up();
        await tester.pumpAndSettle();
        expect(view.view.value, isNot(beforeResume));
        await tester.tap(find.byKey(const ValueKey('collage-fit')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('collage-tool-layout')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('collage-mode-template')));
        await capture('phone-template');
        await tester.tap(find.byKey(const ValueKey('collage-mode-longImage')));
        await capture('phone-long');
        await tester.tap(find.byKey(const ValueKey('collage-tool-filter')));
        await capture('phone-filter');
        await tester.tap(find.byKey(const ValueKey('collage-tool-adjust')));
        await capture('phone-adjust');
        await tester.tap(find.byTooltip('管理拼图照片'));
        await capture('phone-photos');
        await tester.tap(find.byTooltip('关闭照片管理'));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: const MaterialApp(
              key: ValueKey('empty239'),
              home: workspace.CollageHarness(paths: []),
            ),
          ),
        );
        await capture('phone-empty');
        final add = tester.widget<TextButton>(
          find.widgetWithText(TextButton, '添加照片'),
        );
        expect(add.onPressed, isNotNull);
        expect(add.style!.foregroundColor!.resolve({}), Colors.white);
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
