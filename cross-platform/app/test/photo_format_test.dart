import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/photo_format.dart';
import 'package:huevia/photos.dart';
import 'package:huevia/theme.dart';

import 'editor_menu_test.dart' as fixtures;

class _FormatCore extends fixtures.MenuCore {
  _FormatCore(super.directory);

  @override
  Stream<dynamic> get operationProgress => const Stream.empty();
  @override
  Stream<dynamic> get galleryChanges => const Stream.empty();

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'photo.stars') return {'keys': <String>[]};
    if (operation == 'gallery.access') {
      return {'access': 'none', 'canAsk': false};
    }
    if (operation == 'media.rawThumbnail') {
      calls.add((operation, payload));
      return {'path': '$root/raw-thumbnails/fixture.png'};
    }
    return super.call(operation, payload, jobId);
  }
}

void main() {
  test(
    'the working path decides current format independently of the display name',
    () {
      expect(
        photoFormatLabel(
          filePath: '/private/originals/hash.jpg',
          name: 'shot.NEF',
        ),
        'JPG',
      );
      expect(
        photoFormatLabel(
          filePath: '/private/originals/hash.NEF',
          name: 'shot.jpg',
        ),
        'NEF',
      );
      expect(
        photoFormatLabel(filePath: r'C:\originals\hash.JpEg', name: '照片'),
        'JPEG',
      );
    },
  );

  test('a derived JPEG identifies its NEF as a separate source', () {
    expect(
      photoEditorFormatLabel(
        filePath: '/private/originals/hash.jpg',
        name: 'shot.jpg',
        rawSourcePath: '/private/originals/source.nef',
      ),
      'JPG · 编辑照片 · 来源 NEF',
    );
    expect(
      photoEditorFormatLabel(
        filePath: '/private/originals/plain.jpg',
        name: 'plain.jpg',
      ),
      'JPG · 编辑照片',
    );
    expect(
      photoEditorFormatLabel(
        filePath: '/private/originals/source.nef',
        name: 'source.nef',
      ),
      'NEF · 编辑照片',
    );
  });

  test('opaque platform identifiers fall back to names without inventing a MIME type', () {
    expect(
      photoFormatLabel(
        filePath: 'content://media/external/images/52',
        name: 'shot.nef',
      ),
      'NEF',
    );
    expect(photoFormatLabel(filePath: 'ABC/L0/001', name: 'shot.jpg'), 'JPG');
    expect(
      photoFormatLabel(
        filePath: 'file:///private/source.png?name=shot.nef',
        name: 'shot.nef',
      ),
      'PNG',
    );
    expect(photoFormatLabel(filePath: 'ABC/L0/001', name: '照片'), '照片');
  });

  testWidgets(
    'same-base JPEG and NEF retain distinct cards and opening the JPEG edits the JPEG',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('huevia-formats-');
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
      );
      Directory('${directory.path}/previews').createSync();
      Directory('${directory.path}/raw-thumbnails').createSync();
      File('${directory.path}/raw-thumbnails/fixture.png')
          .writeAsBytesSync(png);
      final jpeg = File('${directory.path}/shot.jpg')
        ..writeAsBytesSync(
          File('../../app/src/main/assets/preset-showcase/portrait-smile.jpg')
              .readAsBytesSync(),
        );
      final core = _FormatCore(directory.path);
      final raw = Photo('${directory.path}/shot.nef', 'shot.nef', const {
        'raw': true,
        'width': 640,
        'height': 960,
      });
      final working = Photo(jpeg.path, 'shot.jpg', {
        'width': 640,
        'height': 960,
        'rawSource': raw.path,
      });
      final state = AppState(core)
        ..session = {
          'user': {'id': 'alice'},
        }
        ..photos = [working, raw];
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => PhotosPage(state: state),
          ),
          GoRoute(
            path: '/photo/:id',
            builder: (_, route) {
              final photo = state.photos.singleWhere(
                (photo) => photo.id == route.pathParameters['id'],
              );
              return photo.info['raw'] == true
                  ? Scaffold(body: Text('RAW entry: ${photo.path}'))
                  : EditorPage(state: state, photo: photo);
            },
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          theme: hueviaTheme(Brightness.dark),
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
      final jpegCard = find.byKey(ValueKey('photo-${working.path}'));
      final rawCard = find.byKey(ValueKey('photo-${raw.path}'));
      expect(
        find.descendant(of: jpegCard, matching: find.text('JPG')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: rawCard, matching: find.text('NEF')),
        findsOneWidget,
      );
      await tester.tap(jpegCard);
      await tester.pumpAndSettle();
      expect(find.text('JPG · 编辑照片 · 来源 NEF'), findsOneWidget);
      expect(find.text('NEF · 编辑照片'), findsNothing);
      expect(
        tester.widget<EditorPage>(find.byType(EditorPage)).photo.path,
        working.path,
      );
      final previews = core.calls
          .where((call) => call.$1 == 'media.preview')
          .toList();
      expect(previews, isNotEmpty);
      expect(previews.every((call) => call.$2['path'] == working.path), isTrue);
      expect(core.calls.any((call) => call.$1 == 'media.rawDevelop'), isFalse);
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(rawCard);
      await tester.pumpAndSettle();
      expect(find.text('RAW entry: ${raw.path}'), findsOneWidget);
      expect(state.photos.map((photo) => photo.path), [working.path, raw.path]);
      expect(state.photos.first.info['rawSource'], raw.path);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
      state.dispose();
      // Windows image decoders may release file mappings only after process exit.
      try {
        directory.deleteSync(recursive: true);
      } on FileSystemException catch (error) {
        if (!Platform.isWindows || error.osError?.errorCode != 32) rethrow;
        debugPrint(
          'FIXTURE_CLEANUP_AFTER_PROCESS ${jsonEncode(directory.path)}',
        );
      }
    },
  );
}
