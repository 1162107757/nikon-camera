import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
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
      await core.initialize();
      final directory = await Directory(
        '${core.root}/integration-${DateTime.now().microsecondsSinceEpoch}',
      ).create();
      final outputs = <String>[];
      Future<Json> render(String operation, Json payload) async {
        final result = await core.call(
          operation,
          payload,
          'integration-${DateTime.now().microsecondsSinceEpoch}',
        );
        if (result['path'] is String) outputs.add(result['path'] as String);
        return result;
      }

      try {
        final recorder = ui.PictureRecorder(), canvas = ui.Canvas(recorder);
        canvas.drawColor(const ui.Color(0xff707070), ui.BlendMode.src);
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
        expect(exported['model'], isNotEmpty);
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
