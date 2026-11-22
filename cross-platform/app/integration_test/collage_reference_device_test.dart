import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/main.dart' show HomeFrame;
import 'package:huevia/photos.dart';
import 'package:huevia/theme.dart';
import 'package:huevia/camera_slots.dart';

import '../test/photo_collage_test.dart' as preserved;
import '../test/collage_workspace_test.dart' as workspace;
import '../test/collage_export_test.dart' as export_checks;
import '../test/phone_album_categories_test.dart' as gallery;
import '../test/camera_slots_ui_test.dart' as slots;
import 'fixtures/gallery_fixture_bytes.dart';

class Collage237Binding extends IntegrationTestWidgetsFlutterBinding {
  @override
  bool get registerTestTextInput => true;
}

class Gallery237Core extends HueviaCore {
  Gallery237Core(this.paths);
  final List<String> paths;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'photo.stars') return {'keys': <String>[]};
    if (operation == 'gallery.access') return {'access': 'full'};
    if (operation == 'ui.preferences.set') return payload;
    if (operation == 'gallery.thumbnail') {
      return {'path': paths[int.parse(payload['id'] as String) % paths.length]};
    }
    if (operation == 'gallery.page') {
      final rows = [
        for (var i = 0; i < 8; i++)
          {
            'id': '$i',
            'name': '照片$i.${i % 4 == 3 ? 'NEF' : 'jpg'}',
            'raw': i % 4 == 3,
            'live': i % 4 == 2,
            'mediaType': 'image',
            'date': DateTime.now().millisecondsSinceEpoch,
          },
      ];
      final filtered = rows
          .where(
            (r) => payload['category'] == 'raw'
                ? r['raw'] == true
                : payload['category'] == 'live'
                ? r['live'] == true
                : payload['category'] == 'image'
                ? r['raw'] != true
                : true,
          )
          .toList();
      return {
        'items': filtered,
        'total': filtered.length,
        'hasMore': false,
        'nextOffset': filtered.length,
        'albums': [
          {'id': '', 'name': '全部相册', 'count': 8, 'cover': '0'},
        ],
      };
    }
    throw AppFailure(operation);
  }
}

void main() {
  Collage237Binding().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  preserved.main();
  workspace.main();
  export_checks.main();
  gallery.main();
  slots.main();
  testWidgets(
    'capture the reference collage workspace on Android phone, large text and tablet',
    (tester) async {
      final directory = Directory(
        '${Directory.systemTemp.path}/collage237-captures',
      );
      await directory.create(recursive: true);
      final paths = <String>[];
      for (final name in [
        'sunlit-forest.jpg',
        'coastal-water.jpg',
        'rainy-tokyo.jpg',
        'portrait-smile.jpg',
      ]) {
        final file = File('${directory.path}/$name');
        await file.writeAsBytes(base64Decode(galleryFixtureBytes[name]!));
        paths.add(file.path);
      }
      for (final variant in [
        ('phone', const Size(390, 844), 1.0),
        ('large', const Size(360, 800), 1.3),
        ('tablet', const Size(900, 1200), 1.0),
      ]) {
        tester.view.physicalSize = variant.$2;
        tester.view.devicePixelRatio = 1;
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(variant.$3)),
                child: child!,
              ),
              home: workspace.CollageHarness(paths: paths),
            ),
          ),
        );
        Future<void> capture(String name) async {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 350)),
          );
          await tester.pumpAndSettle();
          final failure = tester.takeException();
          if (failure is Error) debugPrintStack(stackTrace: failure.stackTrace);
          expect(failure, isNull);
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${directory.path}/$name.png')
              .writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        }

        await capture('${variant.$1}-layout');
        if (variant.$1 == 'phone') {
          await tester.tap(find.byKey(const ValueKey('collage-mode-template')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('collage-template-3')));
          await capture('phone-template');
          await tester.tap(
            find.byKey(const ValueKey('collage-mode-longImage')),
          );
          await capture('phone-long');
          await tester.tap(find.byKey(const ValueKey('collage-mode-collage')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('collage-ratio-7')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('collage-tool-filter')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('collage-filter-2')));
          await capture('phone-filter');
          await tester.tap(find.byKey(const ValueKey('collage-tool-adjust')));
          await capture('phone-adjust');
          await tester.tap(find.byKey(const ValueKey('collage-tool-text')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('collage-text-input')),
            '旅行日记',
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await capture('phone-text');
          await tester.tap(find.byTooltip('管理拼图照片'));
          await capture('phone-photos');
          await tester.tap(find.byTooltip('关闭照片管理'));
          await tester.pumpAndSettle();
          final state = AppState(Gallery237Core(paths))
            ..uiPreferences = {
              'album': {'source': 'phone'},
            };
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                key: const ValueKey('gallery-four237'),
                theme: hueviaTheme(Brightness.light, home: true),
                home: HomeFrame(
                  location: '/photos',
                  child: PhotosPage(state: state),
                ),
              ),
            ),
          );
          await capture('phone-gallery-four-categories');
          expect(find.text('视频'), findsNothing);
          await tester.pumpWidget(const SizedBox());
          state.dispose();
          final slotCore = slots.RepeatedDeleteCore();
          final slotState = AppState(slotCore)
            ..session = {
              'user': {'id': 'alice'},
            };
          await tester.pumpWidget(
            RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                key: const ValueKey('slots237'),
                theme: hueviaTheme(Brightness.light),
                home: CameraSlotsPage(state: slotState),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('camera-slot-delete')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('确认删除此槽位'));
          await tester.pumpAndSettle();
          await capture('phone-slots-after-delete');
          expect(slotCore.lease, 2);
          expect(find.text('相机预设槽位'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
          slotState.dispose();
        }
        await tester.pumpWidget(const SizedBox());
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
