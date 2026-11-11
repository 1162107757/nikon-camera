import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/batch_export.dart';

import 'synthetic_dng.dart';
import 'synthetic_exif.dart';

class PipelineCore extends HueviaCore {
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    debugPrint('Native operation: $operation begin');
    try {
      final result = await super.call(operation, payload, jobId);
      debugPrint('Native operation: $operation complete');
      return result;
    } catch (failure) {
      debugPrint('Native operation: $operation failed: $failure');
      rethrow;
    }
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // iOS can enable platform accessibility after the first test has recorded its
  // semantics-handle baseline. Establish that platform handle before the case,
  // keep the normal test-owned handle checks, and restore the real setting.
  setUpAll(() {
    binding.platformDispatcher.semanticsEnabledTestValue = true;
  });
  tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  testWidgets(
    'Native codecs and LibRaw retain originals, dimensions and white highlights',
    (tester) async {
      final core = PipelineCore();
      debugPrint(
        'Native pipeline: semantics baseline ${tester.binding.debugOutstandingSemanticsHandles}',
      );
      debugPrint('Native pipeline: initializing');
      try {
        await core.initialize();
      } on AppFailure catch (failure) {
        fail(
          'Native initialization failed: ${failure.message}; ${failure.details}',
        );
      }
      // Read-only smoke against the same managed feed used by the real screen.
      // This catches a configured URL whose managed paging mode was not enabled.
      final feed = await core.call('online.page', {'page': 1, 'pageSize': 2});
      expect(feed['page'], 1);
      expect(feed['items'], isA<List>());
      expect((feed['items'] as List).length, lessThanOrEqualTo(2));
      expect(feed['categories'], isA<List>());
      expect(feed['total'], greaterThanOrEqualTo(0));
      final directory = await Directory(
        '${core.root}/originals/integration-${DateTime.now().microsecondsSinceEpoch}',
      ).create(recursive: true);
      final outputs = <String>[];
      final versions = <String>{};
      Future<Json> render(String operation, Json payload) async {
        debugPrint(
          'Native pipeline: $operation begin (border ${payload['recipe']?['border']?['template'] ?? 0})',
        );
        late final Json result;
        try {
          result = await core.call(
            operation,
            payload,
            'integration-${DateTime.now().microsecondsSinceEpoch}',
          );
        } on AppFailure catch (failure) {
          fail('$operation failed: ${failure.message}; ${failure.details}');
        }
        if (result['path'] is String) outputs.add(result['path'] as String);
        if (result['id'] is String) versions.add(result['id'] as String);
        debugPrint('Native pipeline: $operation completed');
        return result;
      }

      try {
        if (Platform.isIOS) {
          final access = await core.call('gallery.access');
          expect(access['access'], 'full');
          expect(access['alternateBasis'], 'modified');
          Json? fixture;
          for (var attempt = 0; attempt < 20 && fixture == null; attempt++) {
            final page = await core.call('gallery.page', {
              'offset': 0,
              'refresh': true,
            });
            final matches = (page['items'] as List)
                .map(object)
                .where((row) => row['name'] == 'Huevia-QA-PhotoKit.png');
            if (matches.isNotEmpty) fixture = matches.first;
            if (fixture == null) {
              await Future<void>.delayed(const Duration(milliseconds: 500));
            }
          }
          expect(
            fixture,
            isNotNull,
            reason: 'simctl seeded PhotoKit fixture must be visible',
          );
          final thumb = await core.call('gallery.thumbnail', {
            'id': fixture!['id'],
          });
          final thumbnailCodec = await ui.instantiateImageCodec(
            await File(thumb['path'] as String).readAsBytes(),
          );
          final thumbnail = await thumbnailCodec.getNextFrame();
          expect(thumbnail.image.width, lessThanOrEqualTo(384));
          expect(thumbnail.image.height, lessThanOrEqualTo(384));
          thumbnail.image.dispose();
          thumbnailCodec.dispose();
          final imported = await core.call('gallery.import', {
            'id': fixture['id'],
          });
          if (imported['created'] == true) {
            outputs.add(imported['path'] as String);
          }
          const expected = String.fromEnvironment('HUEVIA_PHOTOKIT_SHA');
          expect(expected, matches(RegExp('^[0-9a-f]{64}\$')));
          expect(imported['sha256'], expected);
          expect(
            (await sha256
                    .bind(File(imported['path'] as String).openRead())
                    .first)
                .toString(),
            expected,
          );
          final importedInfo = await core.call('media.info', {
            'path': imported['path'],
          });
          expect(importedInfo['width'], 256);
          expect(importedInfo['height'], 192);
          try {
            await core.call('gallery.import', {
              'id': 'not-observed-in-library',
            });
            fail('A gallery identifier not returned by paging was accepted');
          } on AppFailure catch (failure) {
            expect(failure.message, isNotEmpty);
          }
        }
        final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
        final paint = ui.Paint();
        for (var y = 0; y < 192; y++) {
          for (var x = 0; x < 256; x++) {
            paint.color = ui.Color(
              0xff000000 |
                  (20 + x ~/ 2) << 16 |
                  (20 + y ~/ 2) << 8 |
                  (40 + (x + y) ~/ 4),
            );
            canvas.drawRect(
              ui.Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
              paint,
            );
          }
        }
        final picture = recorder.endRecording(),
            image = await picture.toImage(256, 192);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        final source = await File('${directory.path}/source.png')
            .writeAsBytes(png!.buffer.asUint8List());
        final before = (await sha256.bind(source.openRead()).first).toString();
        final templateBefore = await core.call('media.templateInfo');
        expect(
          templateBefore['custom'],
          false,
          reason:
              'Run in the isolated test application with built-in templates',
        );
        try {
          final revision = core.previewRevision.value;
          final selected = await core.call('media.templateSet', {
            'path': source.path,
          });
          expect(selected['custom'], true);
          expect(selected['count'], 1);
          expect(core.previewRevision.value, greaterThan(revision));
          final preview = await core.call('media.templateSource');
          final codec = await ui.instantiateImageCodec(
            await File(preview['path'] as String).readAsBytes(),
          );
          final frame = await codec.getNextFrame();
          expect(frame.image.width, lessThanOrEqualTo(960));
          expect(frame.image.height, lessThanOrEqualTo(960));
          frame.image.dispose();
          codec.dispose();
          final transparentRecorder = ui.PictureRecorder();
          ui.Canvas(transparentRecorder).drawRect(
            const ui.Rect.fromLTWH(128, 0, 128, 192),
            ui.Paint()..color = const ui.Color(0x80ff0000),
          );
          final transparentPicture = transparentRecorder.endRecording();
          final transparentImage = await transparentPicture.toImage(256, 192);
          final transparentBytes = await transparentImage.toByteData(
            format: ui.ImageByteFormat.png,
          );
          transparentImage.dispose();
          transparentPicture.dispose();
          final transparentFile = await File(
            '${directory.path}/transparent-template.png',
          ).writeAsBytes(transparentBytes!.buffer.asUint8List());
          await core.call('media.templateSet', {'path': transparentFile.path});
          final whitePreview = await core.call('media.templateSource');
          final whiteCodec = await ui.instantiateImageCodec(
            await File(whitePreview['path'] as String).readAsBytes(),
          );
          final whiteFrame = await whiteCodec.getNextFrame();
          final whitePixels = await whiteFrame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          final whiteAt = (10 * whiteFrame.image.width + 10) * 4;
          for (var c = 0; c < 3; c++) {
            expect(
              whitePixels!.getUint8(whiteAt + c),
              greaterThan(245),
              reason: 'Transparent template pixels use the original white background',
            );
          }
          whiteFrame.image.dispose();
          whiteCodec.dispose();
          await expectLater(
            core.call('media.templateSet', {'path': '/outside/private.jpg'}),
            throwsA(isA<AppFailure>()),
          );
          expect((await core.call('media.templateInfo'))['custom'], true);
          await expectLater(
            core.call('media.templateSource', {'index': 1}),
            throwsA(isA<AppFailure>()),
          );
        } finally {
          await core.call('media.templateReset');
        }
        final restored = await core.call('media.templateInfo');
        expect(restored['custom'], false);
        expect(restored['count'], 10);
        expect(
          await File(
            (await core.call('media.templateSource', {'index': 9}))['path']
                as String,
          ).exists(),
          true,
        );
        expect((await sha256.bind(source.openRead()).first).toString(), before);
        final exported = await render('media.export', {
          'path': source.path,
          'owner': '',
          'size': 'full',
          'recipe': {'schema': 1},
        });
        expect(exported['width'], 256);
        expect(exported['height'], 192);
        final orientedTemplate =
            await File('${directory.path}/orientation6-template.jpg')
                .writeAsBytes(
                  jpegWithOrientation(
                    await File(exported['path'] as String).readAsBytes(),
                    6,
                  ),
                );
        try {
          expect(
            (await core.call('media.info', {
              'path': orientedTemplate.path,
            }))['orientation'],
            6,
          );
          await core.call('media.templateSet', {'path': orientedTemplate.path});
          final source = await core.call('media.templateSource');
          final info = await core.call('media.info', {'path': source['path']});
          expect(info['width'], 192);
          expect(info['height'], 256);
          expect(info['orientation'], 1);
        } finally {
          await core.call('media.templateReset');
        }
        expect(exported['model'], endsWith(':full-jpeg95-srgb-v1'));
        expect(
          exported['exportSpec'],
          'jpeg-srgb-v1:256x192:q95:capture-no-gps-v1',
        );
        final repeated = await render('media.export', {
          'path': source.path,
          'owner': '',
          'size': 'full',
          'recipe': {'schema': 1},
        });
        expect(repeated['id'], exported['id']);
        expect(repeated['path'], exported['path']);
        expect(repeated['sha256'], exported['sha256']);
        expect(repeated['reused'], true);
        final opened = await core.call('version.open', {
          'owner': '',
          'id': exported['id'],
        });
        expect(opened['sha256'], exported['sha256']);
        final second = await File(exported['path'] as String)
            .copy('${directory.path}/second.jpg');
        final batchState = AppState(core)
          ..photos = [
            Photo(source.path, '批量源图.png', {'width': 256, 'height': 192}),
            Photo(second.path, '批量照片.jpg', {'width': 256, 'height': 192}),
          ];
        final batch = BatchExport(
          batchState,
          batchState.photos
              .map(
                (photo) => <String, dynamic>{
                  'id': photo.path,
                  'name': photo.name,
                },
              )
              .toList(),
          phone: false,
        );
        try {
          await batch.run();
          expect(batch.completed, 2);
          expect(batch.failed, 0);
          for (final item in batch.items) {
            expect(await File(item.output!).exists(), true);
          }
          final saved = await core.call('version.list', {'owner': ''});
          for (final record in (saved['items'] as List).map(object)) {
            if (batch.items.any((item) => item.output == record['path'])) {
              versions.add(record['id'] as String);
            }
          }
          final firstOutput = batch.items.first.output;
          await batch.run();
          expect(batch.items.first.output, firstOutput);
        } finally {
          batch.dispose();
          batchState.dispose();
        }
        expect((await sha256.bind(source.openRead()).first).toString(), before);
        final shared = await render('media.export', {
          'path': source.path,
          'owner': '',
          'size': 'share',
          'recipe': {'schema': 1},
        });
        expect(shared['model'], startsWith('export-jpeg-v1:'));
        expect(shared['model'], isNot(exported['model']));
        final cleanup = await render('media.cleanupAnalyze', {
          'path': source.path,
          'owner': '',
        });
        expect(cleanup['sourceWidth'], 256);
        expect(cleanup['sourceHeight'], 192);
        expect(cleanup['patchCount'], greaterThan(0));
        expect(cleanup['cleanupData'], isNotEmpty);
        final cleaned = await render('media.export', {
          'path': source.path,
          'owner': '',
          'size': 'full',
          'recipe': {
            'cleanupData': cleanup['cleanupData'],
            'cleanup': {'amount': 50, 'haze': 80, 'noise': 60},
          },
        });
        expect(cleaned['width'], 256);
        expect(cleaned['height'], 192);
        final crop = await render('media.export', {
          'path': source.path,
          'owner': '',
          'size': 'full',
          'recipe': {
            'geometry': {'turns': 1, 'right': 500000},
          },
        });
        expect(crop['width'], 96);
        expect(crop['height'], 256);
        final savedBeforeCompare = await core.call('draft.load', {
          'path': source.path,
          'owner': '',
        });
        final originalView = await render('media.originalPreview', {
          'path': source.path,
          'owner': '',
        });
        expect(originalView['width'], 256);
        expect(originalView['height'], 192);
        expect(
          await core.call('draft.load', {'path': source.path, 'owner': ''}),
          savedBeforeCompare,
        );
        final cropCodec = await ui.instantiateImageCodec(
          await File(crop['path'] as String).readAsBytes(),
        );
        final cropFrame = await cropCodec.getNextFrame();
        final cropPixels = await cropFrame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final center = (128 * 96 + 48) * 4;
        for (var channel = 0; channel < 3; channel++) {
          expect(
            (cropPixels!.getUint8(center + channel) - [84, 92, 108][channel])
                .abs(),
            lessThanOrEqualTo(8),
            reason: 'Rotation/crop maps the same source coordinates on both platforms',
          );
        }
        cropFrame.image.dispose();
        cropCodec.dispose();
        for (final entry in [(1, 312, 229), (2, 371, 228), (3, 256, 221)]) {
          final framed = await render('media.export', {
            'path': source.path,
            'owner': '',
            'size': 'full',
            'recipe': {
              'border': {
                'template': entry.$1,
                'automatic': false,
                'brand': 'NIKON',
                'model': 'TEST CAMERA',
                'fields': ['50mm', 'F2.8', '1/125s', 'ISO400', '2026-11-10'],
              },
            },
          });
          expect(framed['width'], entry.$2);
          expect(framed['height'], entry.$3);
        }
        final target = await File('${directory.path}/copy-target.jpg')
            .writeAsBytes(await File(exported['path'] as String).readAsBytes());
        await core.call('draft.save', {
          'path': target.path,
          'owner': '',
          'recipe': {
            'geometry': {'turns': 3},
            'border': {'template': 3},
          },
        });
        final beforeCopy = await core.call('draft.load', {
          'path': target.path,
          'owner': '',
        });
        final copied = await core.call('photo.copy', {
          'path': source.path,
          'owner': '',
          'recipe': {
            'values': [0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
          },
          'paths': [target.path],
          'basic': true,
          'curves': false,
          'colour': false,
        });
        expect(copied['changed'], 1);
        final targetDraft = object(
          (await core.call('draft.load', {
            'path': target.path,
            'owner': '',
          }))['recipe'],
        );
        expect((targetDraft['values'] as List)[1], 10);
        expect(targetDraft['geometry']['turns'], 3);
        expect(targetDraft['border']['template'], 3);
        final undone = await core.call('photo.copyUndo', {
          'owner': '',
          'receipt': copied['receipt'],
        });
        expect(undone['restored'], 1);
        expect(
          await core.call('draft.load', {'path': target.path, 'owner': ''}),
          beforeCopy,
        );
        expect((await sha256.bind(source.openRead()).first).toString(), before);
        // Vary metadata so a previous native development cache cannot mask a
        // decoder regression; sensor pixels and white-highlight checks stay equal.
        final raw = await File('${directory.path}/synthetic.dng').writeAsBytes(
          syntheticDng(
            identity:
                'Huevia pipeline ${DateTime.now().microsecondsSinceEpoch}',
          ),
        );
        final rawHash = (await sha256.bind(raw.openRead()).first).toString();
        final info = await core.call('media.info', {'path': raw.path});
        expect(info['raw'], true);
        final developed = await render('media.rawDevelop', {
          'path': raw.path,
          'owner': '',
          'settings': <String, dynamic>{},
        });
        expect(developed['width'], info['width']);
        expect(developed['height'], info['height']);
        final codec = await ui.instantiateImageCodec(
          await File(developed['path'] as String).readAsBytes(),
        );
        final frame = await codec.getNextFrame(),
            rgba = await frame.image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
        final x = frame.image.width * 9 ~/ 10,
            y = frame.image.height ~/ 2,
            at = (y * frame.image.width + x) * 4;
        final channels = rgba!.buffer.asUint8List().sublist(at, at + 3);
        expect(
          channels.reduce((a, b) => a < b ? a : b),
          greaterThan(220),
          reason: 'Synthetic saturated highlights remain white',
        );
        expect(
          channels.reduce((a, b) => a > b ? a : b) -
              channels.reduce((a, b) => a < b ? a : b),
          lessThan(15),
          reason: 'No magenta cast in neutral saturated highlights',
        );
        frame.image.dispose();
        codec.dispose();
        final custom = await render('media.rawDevelop', {
          'path': raw.path,
          'owner': '',
          'settings': {
            'whiteBalance': 'CUSTOM',
            'temperature': 4800,
            'tint': 10,
            'exposure': 5,
            'highlights': 2,
            'quality': 3,
            'colorMode': 'NEUTRAL',
          },
        });
        expect(custom['settings']['temperature'], 4800);
        expect(custom['settings']['colorMode'], 'NEUTRAL');
        expect((await sha256.bind(raw.openRead()).first).toString(), rawHash);
      } finally {
        for (final id in versions) {
          await core.call('version.delete', {'owner': '', 'id': id});
        }
        for (final path in outputs) {
          if (path.startsWith('${core.root}/') ||
              path.startsWith('${core.root}\\')) {
            try {
              await File(path).delete();
            } on FileSystemException {
              /* Already removed. */
            }
          }
        }
        await directory.delete(recursive: true);
        debugPrint(
          'Native pipeline: semantics remaining ${tester.binding.debugOutstandingSemanticsHandles}',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
