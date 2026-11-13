import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/photos.dart';
import 'package:huevia/raw_develop.dart';
import 'package:huevia/theme.dart';

import 'editor_menu_test.dart' as fixtures;

class _RawReturnCore extends fixtures.MenuCore {
  _RawReturnCore(super.directory, this.jpegBytes) {
    for (final name in [
      'originals',
      'previews',
      'raw-editor',
      'raw-thumbnails',
    ]) {
      Directory('$root/$name').createSync();
    }
    // RAW conversion is a native boundary here; the real widgets and routes run.
    File(rawPath).writeAsBytesSync([0x49, 0x49, 42, 0, 0, 0, 0, 0]);
    File(plainPath).writeAsBytesSync(jpegBytes);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
    );
    File('$root/previews/phone.png').writeAsBytesSync(png);
    File('$root/raw-thumbnails/raw.png').writeAsBytesSync(png);
  }
  final List<int> jpegBytes;
  String get rawPath => '$root/originals/roundtrip.dng';
  String get plainPath => '$root/originals/plain.jpg';
  int pickerCalls = 0, galleryImports = 0, developments = 0, copies = 0;
  Completer<Json?>? picker;
  Completer<Json>? galleryImport;
  Json get selectedRaw => {'path': rawPath, 'name': 'roundtrip.dng'};

  @override
  Stream<dynamic> get operationProgress => const Stream.empty();
  @override
  Stream<dynamic> get galleryChanges => const Stream.empty();
  @override
  Future<Json?> pickFile({required bool preset}) async {
    expect(preset, false);
    pickerCalls++;
    return picker == null ? selectedRaw : picker!.future;
  }

  @override
  Future<String> importFile(XFile selected, {required bool preset}) async {
    expect(preset, false);
    final target = File('$root/originals/working-${++copies}.jpg');
    target.writeAsBytesSync(await selected.readAsBytes());
    return target.path;
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    switch (operation) {
      case 'photo.stars':
        return {'keys': <String>[]};
      case 'gallery.access':
        return {'access': 'full', 'canAsk': false};
      case 'gallery.page':
        return {
          'items': [
            {
              'id': 'phone-raw',
              'name': 'roundtrip.dng',
              'raw': true,
              'width': 640,
              'height': 960,
            },
            {
              'id': 'phone-jpg',
              'name': 'plain.jpg',
              'width': 640,
              'height': 960,
            },
          ],
          'nextOffset': 2,
          'hasMore': false,
        };
      case 'gallery.thumbnail':
        return {'path': '$root/previews/phone.png'};
      case 'media.rawThumbnail':
        return {'path': '$root/raw-thumbnails/raw.png'};
      case 'gallery.import':
        galleryImports++;
        if (payload['id'] == 'phone-raw') {
          return galleryImport == null ? selectedRaw : galleryImport!.future;
        }
        return {'path': plainPath, 'name': 'plain.jpg'};
      case 'media.info':
        return {
          'width': 640,
          'height': 960,
          'raw': (payload['path'] as String).endsWith('.dng'),
        };
      case 'media.rawDevelop':
        calls.add((operation, payload));
        final output = File('$root/raw-editor/full-${++developments}.jpg');
        output.writeAsBytesSync(jpegBytes);
        return {
          'path': output.path,
          'sourceSha': 'a' * 64,
          'settings': payload['settings'],
          'rawColorStatus': 'native boundary fixture',
        };
    }
    return super.call(operation, payload, jobId);
  }
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  final clock = Stopwatch()..start();
  while (!ready() && clock.elapsed < const Duration(seconds: 8)) {
    // The actual photo-index journal and file decoders need real IO turns.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(ready(), isTrue, reason: reason);
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('cc.huevia/events'),
          (_) async => null,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('cc.huevia/events'),
          null,
        );
  });
  for (final phone in [false, true]) {
    testWidgets(
      '${phone ? 'Phone import' : 'Native picker'} RAW replacement returns to an album that can open photos repeatedly',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'huevia-raw-return-',
        );
        final core = _RawReturnCore(
          directory.path,
          File('../../app/src/main/assets/preset-showcase/portrait-smile.jpg')
              .readAsBytesSync(),
        );
        core.picker = Completer<Json?>();
        core.galleryImport = Completer<Json>();
        final plain = Photo(core.plainPath, 'plain.jpg', const {
          'width': 640,
          'height': 960,
        });
        final state = AppState(core)
          ..session = {
            'user': {'id': 'alice'},
          }
          ..photos = [plain]
          ..uiPreferences = {
            'album': {'source': phone ? 'phone' : 'app'},
          };
        var rawRoutes = 0;
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
                if (photo.info['raw'] == true) {
                  rawRoutes++;
                  return RawDevelopPage(
                    key: ValueKey('raw-${photo.id}'),
                    state: state,
                    photo: photo,
                    automaticallyEdit: true,
                  );
                }
                return EditorPage(
                  key: ValueKey('edit-${photo.id}'),
                  state: state,
                  photo: photo,
                );
              },
            ),
          ],
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
          router.dispose();
          state.dispose();
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
          try {
            directory.deleteSync(recursive: true);
          } on FileSystemException catch (error) {
            if (!Platform.isWindows || error.osError?.errorCode != 32) rethrow;
            debugPrint(
              'FIXTURE_CLEANUP_AFTER_PROCESS ${jsonEncode(directory.path)}',
            );
          }
        });
        await tester.pumpWidget(
          MaterialApp.router(
            theme: hueviaTheme(Brightness.dark),
            routerConfig: router,
          ),
        );
        await tester.pumpAndSettle();

        Future<void> pickRaw() async {
          await tester.tap(find.byTooltip('相册更多操作'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text('RAW 显影'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }

        if (phone) {
          await _until(
            tester,
            () => find
                .byKey(const ValueKey('photo-phone-raw'))
                .evaluate()
                .isNotEmpty,
            'Phone rows loaded',
          );
          await tester.tap(find.byKey(const ValueKey('photo-phone-raw')));
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('photo-phone-raw')));
          await tester.pump();
          expect(
            core.galleryImports,
            1,
            reason: 'The native import is protected against duplicate taps',
          );
          core.galleryImport!.complete(core.selectedRaw);
        } else {
          await pickRaw();
          // Reopen the real menu while the native picker is pending.
          await pickRaw();
          expect(
            core.pickerCalls,
            1,
            reason: 'The pending native picker is not started twice',
          );
          expect(find.byType(EditorPage), findsNothing);
          core.picker!.complete(core.selectedRaw);
        }
        await _until(
          tester,
          () => find.byType(EditorPage).evaluate().isNotEmpty,
          'Actual RawDevelopPage automatically replaces itself with the JPEG editor',
        );
        expect(rawRoutes, greaterThan(0));
        expect(find.byType(RawDevelopPage), findsNothing);
        expect(core.developments, 1);
        final working = tester
            .widget<EditorPage>(find.byType(EditorPage))
            .photo;
        expect(working.path.endsWith('.jpg'), isTrue);
        expect(working.info['rawSource'], core.rawPath);

        for (var repeat = 0; repeat < 2; repeat++) {
          await tester.tap(find.bySemanticsLabel('返回相册'));
          await _until(
            tester,
            () =>
                find.byType(PhotosPage).evaluate().isNotEmpty &&
                find.byType(EditorPage).evaluate().isEmpty,
            'The real editor header returns to the album',
          );
          final card = find.byKey(
            ValueKey('photo-${phone ? 'phone-jpg' : plain.path}'),
          );
          await tester.ensureVisible(card);
          await tester.pump();
          await tester.tap(card);
          await _until(
            tester,
            () => find.byType(EditorPage).evaluate().isNotEmpty,
            'Album photo tap must work after RAW context.replace and header back (repeat $repeat)',
          );
          expect(
            tester.widget<EditorPage>(find.byType(EditorPage)).photo.path,
            plain.path,
          );
          expect(core.developments, 1);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
