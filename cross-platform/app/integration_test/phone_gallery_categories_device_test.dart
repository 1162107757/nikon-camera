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
import 'package:huevia/phone_album_categories.dart';
import 'package:huevia/theme.dart';

// Prepare with python cross-platform/tool/phone_gallery_fixture.py.
import 'fixtures/gallery_fixture_bytes.dart';
import '../test/phone_album_categories_test.dart' as categories;
import '../test/app_launch_services_test.dart' as launch;
import '../test/album_inline_selection_test.dart' as selection;
import '../test/photos_test.dart' as photos;
import '../test/camera_navigation_test.dart' as navigation;

class Gallery236Binding extends IntegrationTestWidgetsFlutterBinding {
  @override
  bool get registerTestTextInput => true;
}

class CaptureCore extends HueviaCore {
  CaptureCore(this.paths);
  final List<String> paths;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'photo.stars') return {'keys': <String>[]};
    if (operation == 'gallery.access') {
      return {'access': 'full', 'videoAccess': 'full'};
    }
    if (operation == 'ui.preferences.set') return payload;
    if (operation == 'gallery.thumbnail') {
      return {'path': paths[int.parse(payload['id'] as String) % paths.length]};
    }
    if (operation == 'gallery.page') {
      final rows = [
        for (var i = 0; i < 18; i++)
          <String, dynamic>{
            'id': '$i',
            'name':
                '旅行照片$i.${i % 6 == 4
                    ? 'NEF'
                    : i % 6 == 5
                    ? 'mp4'
                    : 'jpg'}',
            'raw': i % 6 == 4,
            'live': i % 6 == 3,
            'mediaType': i % 6 == 5 ? 'video' : 'image',
            'date': DateTime.now().millisecondsSinceEpoch,
          },
      ];
      final selected = rows
          .where(
            (r) => switch (payload['category']) {
              'raw' => r['raw'] == true,
              'live' => r['live'] == true,
              'video' => r['mediaType'] == 'video',
              'image' => r['mediaType'] == 'image' && r['raw'] != true,
              _ => true,
            },
          )
          .toList();
      final album = payload['album'] as String? ?? '';
      if (album.isNotEmpty) {
        selected.removeWhere(
          (row) => int.parse(row['id'] as String) % 4 != int.parse(album),
        );
      }
      return {
        'albums': [
          {'id': '', 'name': '全部相册', 'count': 18, 'cover': '0'},
          for (var i = 0; i < 4; i++)
            {
              'id': '$i',
              'name': ['相机', '截图', '微信', '下载'][i],
              'count': i < 2 ? 5 : 4,
              'cover': '$i',
            },
        ],
        'items': selected,
        'total': selected.length,
        'nextOffset': selected.length,
        'hasMore': false,
      };
    }
    throw AppFailure(operation);
  }
}

void main() {
  Gallery236Binding().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets(
    'real Android MediaStore album buckets combine with media filters',
    (tester) async {
      await tester.runAsync(() async {
        final core = HueviaCore();
        await core.initialize();
        final all = await core.call('gallery.page', {
          'refresh': true,
          'category': 'all',
          'offset': 0,
        });
        final albums = (all['albums'] as List).map(object).toList();
        final camera = albums.singleWhere(
          (a) => a['name'] == 'HueviaGallery236Camera',
        );
        final downloads = albums.singleWhere(
          (a) => a['name'] == 'HueviaGallery236Downloads',
        );
        expect(camera['count'], 1);
        expect(downloads['count'], 1);
        final page = await core.call('gallery.page', {
          'album': camera['id'],
          'category': 'image',
          'offset': 0,
          'refresh': true,
        });
        final rows = (page['items'] as List).map(object).toList();
        expect(rows, hasLength(1));
        expect(rows.single['name'], 'gallery236-camera.jpg');
        final thumb = await core.call('gallery.thumbnail', {
          'id': camera['cover'],
        });
        expect(await File(thumb['path'] as String).exists(), isTrue);
        final raw = await core.call('gallery.page', {
          'album': camera['id'],
          'category': 'raw',
          'offset': 0,
          'refresh': true,
        });
        expect(raw['items'], isEmpty);
      });
    },
  );
  categories.main();
  launch.main();
  selection.main();
  photos.main();
  navigation.main();
  testWidgets(
    'A category bar on native Android phone, dark large text and tablet',
    (tester) async {
      final output = Directory(
        '${Directory.systemTemp.path}/phone-gallery236-captures',
      );
      await output.create(recursive: true);
      final paths = <String>[];
      for (final item in galleryFixtureBytes.entries) {
        final file = File('${output.path}/${item.key}');
        await file.writeAsBytes(base64Decode(item.value));
        paths.add(file.path);
      }
      for (final variant in [
        ('phone', const Size(390, 844), false, 1.0),
        ('phone-dark-large', const Size(360, 800), true, 1.3),
        ('tablet', const Size(900, 1200), false, 1.0),
      ]) {
        tester.view.physicalSize = variant.$2;
        tester.view.devicePixelRatio = 1;
        final state = AppState(CaptureCore(paths))
          ..uiPreferences = {
            'album': {'source': 'phone'},
          };
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: hueviaTheme(
                variant.$3 ? Brightness.dark : Brightness.light,
                home: true,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(variant.$4),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: HomeFrame(
                location: '/photos',
                child: PhotosPage(state: state),
              ),
            ),
          ),
        );
        Future<void> capture(String name) async {
          await tester.pumpAndSettle();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 600)),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${output.path}/$name.png')
              .writeAsBytes(png!.buffer.asUint8List());
          image.dispose();
        }

        await capture(variant.$1);
        if (variant.$1 == 'phone') {
          await tester.tap(find.byKey(const ValueKey('phone-album-picker')));
          await capture('phone-album-menu');
          await tester.tap(find.byKey(const ValueKey('phone-folder-0')));
          await capture('phone-camera');
          await tester.tap(find.byKey(const ValueKey('phone-album-picker')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('phone-folder-')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('RAW'));
          await capture('phone-raw');
          await tester.tap(find.text('应用相册'));
          await capture('app-album-unchanged');
          expect(find.byType(PhoneAlbumCategories), findsNothing);
        }
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
