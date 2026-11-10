import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huevia/domain.dart';

import 'synthetic_dng.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Native codecs and LibRaw retain originals, dimensions and white highlights',
    (tester) async {
      final core = HueviaCore();
      debugPrint('Native pipeline: initializing');
      try {
        await core.initialize();
      } on AppFailure catch (failure) {
        fail(
          'Native initialization failed: ${failure.message}; ${failure.details}',
        );
      }
      final directory = await Directory(
        '${core.root}/originals/integration-${DateTime.now().microsecondsSinceEpoch}',
      ).create(recursive: true);
      final outputs = <String>[];
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
        debugPrint('Native pipeline: $operation completed');
        return result;
      }

      try {
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
        final exported = await render('media.export', {
          'path': source.path,
          'owner': '',
          'size': 'full',
          'recipe': {'schema': 1},
        });
        expect(exported['width'], 256);
        expect(exported['height'], 192);
        expect(exported['model'], endsWith(':full-jpeg95-srgb-v1'));
        expect(
          exported['exportSpec'],
          'jpeg-srgb-v1:256x192:q95:capture-no-gps-v1',
        );
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
        final raw = await File('${directory.path}/synthetic.dng')
            .writeAsBytes(syntheticDng());
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
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
