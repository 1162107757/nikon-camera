import 'dart:async';
import 'dart:convert';
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
  String? nativeResultRoot;
  const nativeRunId = String.fromEnvironment('HUEVIA_NATIVE_TEST_ID');
  if (Platform.isIOS && nativeRunId.isNotEmpty) {
    // Observe Flutter's final integration result, including framework checks.
    // The host accepts only this app's fresh nonce/source/fixture result.
    // XCUITest handles consent; the app verifies its effective PhotoKit access.
    unawaited(
      binding.allTestsPassed.future.then((passed) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (nativeResultRoot == null) return;
        final results = binding.results.map(
          (name, value) => MapEntry(name, '$value'),
        );
        final complete =
            passed &&
            binding.failureMethodsDetails.isEmpty &&
            results.length == 1 &&
            results.values.every((value) => value == 'success');
        await File('$nativeResultRoot/native-pipeline-result.json')
            .writeAsString(
              jsonEncode({
                'schema': 1,
                'runId': nativeRunId,
                'success': complete,
                'results': results,
                'sourceCommit': const String.fromEnvironment(
                  'HUEVIA_NATIVE_TEST_SOURCE',
                ),
                'fixtureSha256': const String.fromEnvironment(
                  'HUEVIA_PHOTOKIT_SHA',
                ),
              }),
              flush: true,
            );
      }),
    );
  }
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
        nativeResultRoot = core.root;
        if (Platform.isIOS && nativeRunId.isNotEmpty) {
          final initialAccess = await core.call('gallery.access');
          final permission = initialAccess['access'] == 'full'
              ? initialAccess
              : await core.galleryPermission();
          expect(permission['access'], 'full');
          await File('${core.root}/native-pipeline-ready.json').writeAsString(
            jsonEncode({
              'schema': 1,
              'phase': 'ready',
              'runId': nativeRunId,
              'sourceCommit': const String.fromEnvironment(
                'HUEVIA_NATIVE_TEST_SOURCE',
              ),
              'initialAccess': initialAccess,
              'access': permission,
            }),
            flush: true,
          );
          // The consent-only UI test must finish before the host directly
          // launches this same authorized app for the complete native scenario.
          final gate = File('${core.root}/native-pipeline-start');
          final deadline = DateTime.now().add(const Duration(seconds: 180));
          while (!await gate.exists() ||
              await gate.readAsString() != nativeRunId) {
            if (DateTime.now().isAfter(deadline)) {
              fail('Host did not start the authorized native scenario');
            }
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
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
        if (operation == 'media.export') {
          expect(result['id'], matches(r'^[0-9a-f]{64}$'));
          versions.add(result['id'] as String);
        }
        debugPrint('Native pipeline: $operation completed');
        return result;
      }

      try {
        if (Platform.isIOS) {
          var access = await core.call('gallery.access');
          for (
            var attempt = 0;
            attempt < 20 && access['access'] != 'full';
            attempt++
          ) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            access = await core.call('gallery.access');
          }
          debugPrint('PhotoKit test authorization: $access');
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
        final frozenDraft = await core.call('draft.load', {
          'path': source.path,
          'owner': '',
        });
        final review = await render('media.exportPreview', {
          'path': source.path,
          'owner': '',
          'recipe': {'schema': 1},
          'size': 'full',
          'snapshot': true,
          'expectedSourceSha': before,
        });
        await expectLater(
          core.call('media.exportPreviewCommit', {'id': review['id']}),
          throwsA(isA<AppFailure>()),
        );
        await core.call('media.exportPreviewClose', {'id': review['id']});
        expect(
          await core.call('draft.load', {'path': source.path, 'owner': ''}),
          frozenDraft,
        );
        await render('media.export', {
          'path': source.path,
          'owner': '',
          'recipe': {'schema': 1},
          'size': 'full',
          'snapshot': true,
          'expectedSourceSha': before,
        });
        expect(
          await core.call('draft.load', {'path': source.path, 'owner': ''}),
          frozenDraft,
        );
        await expectLater(
          core.call('media.export', {
            'path': source.path,
            'owner': '',
            'recipe': {'schema': 1},
            'size': 'full',
            'snapshot': true,
            'expectedSourceSha': '0' * 64,
          }),
          throwsA(isA<AppFailure>()),
        );
        expect(
          await core.call('draft.load', {'path': source.path, 'owner': ''}),
          frozenDraft,
        );
        final exported = await render('media.export', {
          'path': source.path,
          'owner': '',
          'size': 'full',
          'recipe': {'schema': 1},
        });
        final saveAccess = await core.gallerySavePermission();
        expect(saveAccess['granted'], isTrue);
        final publication = await render('gallery.publish', {
          'owner': '',
          'id': exported['id'],
          'filename': 'Huevia-QA-native-publish.jpg',
        });
        expect(publication['published'], isTrue);
        expect(publication['verified'], isTrue);
        final publishedAddress =
            publication[Platform.isAndroid ? 'uri' : 'identifier'] as String;
        expect(publishedAddress, isNotEmpty);
        if (Platform.isAndroid) {
          expect(Uri.parse(publishedAddress).scheme, 'content');
          expect(Uri.parse(publishedAddress).host, 'media');
          expect(
            Uri.parse(publishedAddress).path,
            matches(r'^/(external|external_primary)/images/media/[0-9]+$'),
          );
        }
        // ignore: avoid_print
        print('Native publication fixture address: $publishedAddress');
        final repeatedPublication = await render('gallery.publish', {
          'owner': '',
          'id': exported['id'],
          'filename': 'Huevia-QA-native-publish.jpg',
        });
        expect(
          repeatedPublication['uri'] ?? repeatedPublication['identifier'],
          publication['uri'] ?? publication['identifier'],
        );
        expect(repeatedPublication['verified'], isTrue);
        final originalBytes = jpegWithOrientation(
          await File(exported['path'] as String).readAsBytes(),
          6,
        );
        final originalSha = sha256.convert(originalBytes).toString();
        final originalJpeg = await File('${core.root}/originals/$originalSha.jpg')
            .writeAsBytes(originalBytes);
        outputs.add(originalJpeg.path);
        final originalOperation = sha256
            .convert(
              utf8.encode(
                'native-original-${DateTime.now().microsecondsSinceEpoch}',
              ),
            )
            .toString()
            .substring(0, 32);
        final originalRequest = <String, dynamic>{
          'owner': '',
          'path': originalJpeg.path,
          'expectedSourceSha': originalSha,
          'filename': 'Huevia-QA-original-208.jpg',
          'operationId': originalOperation,
        };
        final versionsBeforeOriginal = await core.call('version.list', {
          'owner': '',
        });
        final savedOriginal = await render(
          'gallery.publishOriginal',
          originalRequest,
        );
        expect(savedOriginal['published'], true);
        expect(savedOriginal['verified'], true);
        final retryOriginal = await render(
          'gallery.publishOriginal',
          originalRequest,
        );
        expect(
          retryOriginal['uri'] ?? retryOriginal['identifier'],
          savedOriginal['uri'] ?? savedOriginal['identifier'],
        );
        expect(
          retryOriginal['verified'],
          true,
          reason: 'Native resource bytes match the original JPEG including its EXIF orientation',
        );
        final anotherOriginal = await render('gallery.publishOriginal', {
          ...originalRequest,
          'operationId': sha256
              .convert(utf8.encode('another-$originalOperation'))
              .toString()
              .substring(0, 32),
        });
        expect(
          anotherOriginal['uri'] ?? anotherOriginal['identifier'],
          isNot(savedOriginal['uri'] ?? savedOriginal['identifier']),
        );
        await expectLater(
          core.call('gallery.publishOriginal', {
            ...originalRequest,
            'expectedSourceSha': '0' * 64,
          }),
          throwsA(isA<AppFailure>()),
        );
        await expectLater(
          core.call('gallery.publishOriginal', {
            ...originalRequest,
            'owner': 'another',
          }),
          throwsA(isA<AppFailure>()),
        );
        await expectLater(
          core.call('gallery.publishOriginal', {
            ...originalRequest,
            'extraCopy': true,
          }),
          throwsA(isA<AppFailure>()),
        );
        expect(
          await core.call('version.list', {'owner': ''}),
          versionsBeforeOriginal,
        );
        expect(await File(originalJpeg.path).readAsBytes(), originalBytes);
        expect(
          await core.call('draft.load', {'path': source.path, 'owner': ''}),
          isNotNull,
        );
        // ignore: avoid_print
        print(
          'Native original JPEG fixtures: ${savedOriginal['uri'] ?? savedOriginal['identifier']} | ${anotherOriginal['uri'] ?? anotherOriginal['identifier']} SHA=$originalSha',
        );
        final copyOperation = sha256
            .convert(
              utf8.encode(
                'native-copy-${DateTime.now().microsecondsSinceEpoch}',
              ),
            )
            .toString()
            .substring(0, 32);
        final freshCopy = await render('gallery.publish', {
          'owner': '',
          'id': exported['id'],
          'filename': 'Huevia-QA-native-copy.jpg',
          'extraCopy': true,
          'operationId': copyOperation,
        });
        final freshAddress =
            freshCopy[Platform.isAndroid ? 'uri' : 'identifier'] as String;
        expect(freshAddress, isNotEmpty);
        expect(freshAddress, isNot(publishedAddress));
        final copyRetry = await render('gallery.publish', {
          'owner': '',
          'id': exported['id'],
          'filename': 'Huevia-QA-native-copy.jpg',
          'extraCopy': true,
          'operationId': copyOperation,
        });
        expect(
          copyRetry[Platform.isAndroid ? 'uri' : 'identifier'],
          freshAddress,
        );
        final otherOperation = sha256
            .convert(utf8.encode('native-other-$copyOperation'))
            .toString()
            .substring(0, 32);
        final anotherCopy = await render('gallery.publish', {
          'owner': '',
          'id': exported['id'],
          'filename': 'Huevia-QA-native-copy.jpg',
          'extraCopy': true,
          'operationId': otherOperation,
        });
        final anotherAddress =
            anotherCopy[Platform.isAndroid ? 'uri' : 'identifier'] as String;
        expect(anotherAddress, isNotEmpty);
        expect(anotherAddress, isNot(freshAddress));
        // ignore: avoid_print
        print(
          'Native dated fixture addresses: $freshAddress | $anotherAddress',
        );
        final publishedVersion = await core.call('version.open', {
          'owner': '',
          'id': exported['id'],
        });
        expect(publishedVersion['sha256'], exported['sha256']);
        expect((await sha256.bind(source.openRead()).first).toString(), before);
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
        // A real JPEG and its lossless pre-encoder pixels, with no gallery
        // receipt until confirmation. Include JPEG95's retained EXIF 6 path.
        for (final candidate in [source, orientedTemplate]) {
          final rotated = candidate == orientedTemplate;
          final versionsBefore = await core.call('version.list', {'owner': ''});
          final inspected = await core.call('media.exportPreview', {
            'path': candidate.path,
            'owner': '',
            'recipe': {'schema': 1},
            'size': rotated ? 'full' : 'custom',
            'longEdge': 640,
            'quality': 70,
          });
          final width = rotated ? 192 : 256, height = rotated ? 256 : 192;
          expect(inspected['width'], width);
          expect(inspected['height'], height);
          final overviewFile = File(inspected['overview'] as String);
          final overviewCodec = await ui.instantiateImageCodec(
            await overviewFile.readAsBytes(),
          );
          final overviewImage = (await overviewCodec.getNextFrame()).image;
          expect(overviewImage.width, lessThanOrEqualTo(256));
          expect(overviewImage.height, lessThanOrEqualTo(256));
          expect(
            (overviewImage.width * height - overviewImage.height * width).abs(),
            lessThanOrEqualTo(width),
          );
          overviewImage.dispose();
          overviewCodec.dispose();
          expect(
            await core.call('version.list', {'owner': ''}),
            versionsBefore,
          );
          final frame = await core.call('media.exportPreviewFrame', {
            'id': inspected['id'],
            'width': width,
            'height': height,
            'scale': 1,
            'cx': .5,
            'cy': .5,
          });
          final images = <ui.Image>[];
          try {
            for (final key in ['before', 'jpeg']) {
              final decoder = await ui.instantiateImageCodec(
                await File(frame[key] as String).readAsBytes(),
              );
              final decoded = await decoder.getNextFrame();
              decoder.dispose();
              images.add(decoded.image);
              expect(decoded.image.width, width);
              expect(decoded.image.height, height);
            }
            if (!rotated) {
              final beforePixels = (await images[0].toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
              final jpegPixels = (await images[1].toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List();
              expect(
                List.generate(
                  beforePixels.length,
                  (i) => (beforePixels[i] - jpegPixels[i]).abs(),
                ).any((difference) => difference > 2),
                true,
                reason: 'Real JPEG at the minimum supported quality differs from pre-encoder pixels',
              );
            }
          } finally {
            for (final image in images) {
              image.dispose();
            }
          }
          await expectLater(
            core.call('media.exportPreviewFrame', {
              'id': inspected['id'],
              'width': 4097,
              'height': 8,
              'scale': 1,
            }),
            throwsA(isA<AppFailure>()),
          );
          final committed = await render('media.exportPreviewCommit', {
            'id': inspected['id'],
          });
          expect(committed['sha256'], inspected['sha256']);
          expect(
            (await sha256
                    .bind(File(committed['path'] as String).openRead())
                    .first)
                .toString(),
            inspected['sha256'],
          );
          expect(await File(frame['before'] as String).exists(), false);
          await expectLater(
            core.call('media.exportPreviewCommit', {'id': inspected['id']}),
            throwsA(isA<AppFailure>()),
          );
        }
        final abandoned = await core.call('media.exportPreview', {
          'path': source.path,
          'owner': '',
          'recipe': {'schema': 1},
          'size': 'full',
        });
        final cancellationVersions = await core.call('version.list', {
          'owner': '',
        });
        await core.call('media.exportPreviewClose', {'id': abandoned['id']});
        expect(
          await core.call('version.list', {'owner': ''}),
          cancellationVersions,
        );
        final geometryPreview = await core.call('media.preview', {
          'path': source.path,
          'owner': '',
          'recipe': {
            'geometry': {'turns': 1},
          },
        });
        outputs.add(geometryPreview['path'] as String);
        expect(geometryPreview['geometryWidth'], 192);
        expect(geometryPreview['geometryHeight'], 256);
        expect(geometryPreview['sourceWidth'], 256);
        expect(geometryPreview['sourceHeight'], 192);
        final localDraftBefore = await core.call('draft.load', {
          'path': source.path,
          'owner': '',
        });
        final localVersionsBefore = await core.call('version.list', {
          'owner': '',
        });
        final localSeed = await core.call('local.seedRegion', {
          'localData': '',
        });
        final regionSeed = object(localSeed['seed']);
        final localValues = List.filled(17, 0)..[1] = 10;
        final local = await core.call('local.change', {
          'localData': '',
          'expectedSha': localSeed['sha256'],
          'action': 'addRegion',
          'value': {
            ...regionSeed,
            'shapes': [
              {
                'kind': 'rectangle',
                'left': 0,
                'top': 0,
                'right': .45,
                'bottom': 1,
                'feather': 0,
                'subtract': false,
                'strokeIndex': 0,
              },
            ],
            'adjustments': {'values': localValues},
          },
        });
        final localRecipe = {
          'schema': 1,
          'localData': local['localData'],
          'geometry': {'turns': 1, 'right': 500000},
          'border': {'template': 3},
        };
        final localFrame = await render('media.localPreview', {
          'path': source.path,
          'owner': '',
          'recipe': localRecipe,
        });
        expect(localFrame['width'], 256);
        expect(localFrame['height'], 192);
        expect(localFrame['geometryWidth'], 256);
        expect(localFrame['geometryHeight'], 192);
        final localOverlay = await core.call('local.overlay', {
          'recipe': localRecipe,
          'regionId': regionSeed['id'],
          'sourceWidth': localFrame['sourceWidth'],
          'sourceHeight': localFrame['sourceHeight'],
          'outputWidth': 4000,
          'outputHeight': 6000,
        });
        expect(localOverlay['width'], 213);
        expect(localOverlay['height'], 320);
        final overlayBytes = base64Decode(localOverlay['rgba'] as String);
        expect(overlayBytes.length, 213 * 320 * 4);
        expect(
          List.generate(
            overlayBytes.length ~/ 4,
            (i) => overlayBytes[i * 4 + 3],
          ).any((alpha) => alpha > 0),
          isTrue,
        );
        final localNeutral = await render('media.localPreview', {
          'path': source.path,
          'owner': '',
          'recipe': {'schema': 1},
        });
        Future<List<int>> localPixel(Json frame, int x, int y) async {
          final codec = await ui.instantiateImageCodec(
            await File(frame['path'] as String).readAsBytes(),
          );
          final decoded = await codec.getNextFrame();
          try {
            final bytes = (await decoded.image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final at = (y * decoded.image.width + x) * 4;
            return List.generate(3, (c) => bytes.getUint8(at + c));
          } finally {
            decoded.image.dispose();
            codec.dispose();
          }
        }

        final inside = await localPixel(localFrame, 50, 90);
        final insideBefore = await localPixel(localNeutral, 50, 90);
        expect(inside[0], greaterThan(insideBefore[0] + 10));
        final outside = await localPixel(localFrame, 210, 90);
        final outsideBefore = await localPixel(localNeutral, 210, 90);
        for (var c = 0; c < 3; c++) {
          expect((outside[c] - outsideBefore[c]).abs(), lessThanOrEqualTo(3));
        }
        final gradientTools = await core.call('local.change', {
          'localData': local['localData'],
          'expectedSha': local['sha256'],
          'action': 'replaceTools',
          'value': {
            'masks': [
              {
                'kind': 'linear',
                'x0': .5,
                'y0': .5,
                'x1': .7,
                'y1': .5,
                'radius': .08,
                'feather': .7,
                'inverted': false,
                'enabled': true,
                'exposure': 10,
                'temperature': 0,
                'saturation': 0,
                'points': [],
              },
            ],
            'clones': [],
          },
        });
        expect(gradientTools['regions'], local['regions']);
        final gradientFrame = await render('media.localPreview', {
          'path': source.path,
          'owner': '',
          'recipe': {...localRecipe, 'localData': gradientTools['localData']},
        });
        final gradientPixel = await localPixel(gradientFrame, 210, 90);
        expect(gradientPixel[0], greaterThan(outside[0] + 10));
        final cloneTools = await core.call('local.change', {
          'localData': gradientTools['localData'],
          'expectedSha': gradientTools['sha256'],
          'action': 'replaceTools',
          'value': {
            'masks': gradientTools['masks'],
            'clones': [
              {
                'sourceX': .25,
                'sourceY': .4,
                'targetX': .75,
                'targetY': .4,
                'radius': .06,
                'feather': .6,
                'enabled': true,
              },
            ],
          },
        });
        expect(cloneTools['regions'], local['regions']);
        final cloneFrame = await render('media.localPreview', {
          'path': source.path,
          'owner': '',
          'recipe': {...localRecipe, 'localData': cloneTools['localData']},
        });
        expect(cloneFrame['width'], localFrame['width']);
        expect(cloneFrame['height'], localFrame['height']);
        final restoredTools = await core.call('local.change', {
          'localData': cloneTools['localData'],
          'expectedSha': cloneTools['sha256'],
          'action': 'replaceTools',
          'value': {'masks': [], 'clones': []},
        });
        expect(restoredTools['localData'], local['localData']);
        final regionalCleanup = await render('media.cleanupAnalyze', {
          'path': source.path,
          'owner': '',
          'recipe': localRecipe,
          'regionId': regionSeed['id'],
        });
        expect(regionalCleanup['sourceWidth'], 256);
        expect(regionalCleanup['sourceHeight'], 192);
        expect(regionalCleanup['patchCount'], greaterThan(0));
        await expectLater(
          core.call('media.cleanupAnalyze', {
            'path': source.path,
            'owner': '',
            'recipe': localRecipe,
            'regionId': 'missing-region',
          }),
          throwsA(isA<AppFailure>()),
        );
        expect(
          await core.call('draft.load', {'path': source.path, 'owner': ''}),
          localDraftBefore,
        );
        expect(
          await core.call('version.list', {'owner': ''}),
          localVersionsBefore,
        );
        expect((await sha256.bind(source.openRead()).first).toString(), before);
        final capture = await core.call('media.borderInfo', {
          'path': source.path,
          'owner': '',
        });
        expect(capture['brand'], '');
        expect(capture['model'], '');
        expect(capture['fields'], orderedEquals(List.filled(5, '')));
        // A completed native task ID may immediately be reused. The Android
        // result must release its own slot before Flutter can issue another.
        for (var i = 0; i < 16; i++) {
          final again = await core.call('media.borderInfo', {
            'path': source.path,
            'owner': '',
          }, 'pipeline-sequential-border-info');
          expect(again, capture);
        }
        final smallPreview = await core.call('media.preview', {
          'path': orientedTemplate.path,
          'owner': '',
          'maxEdge': 128,
          'recipe': {'schema': 1},
        });
        outputs.add(smallPreview['path'] as String);
        expect(
          (smallPreview['width'] as num) <= 128 &&
              (smallPreview['height'] as num) <= 128,
          true,
        );
        for (final edge in [127, 1281]) {
          await expectLater(
            core.call('media.preview', {
              'path': source.path,
              'owner': '',
              'maxEdge': edge,
              'recipe': {'schema': 1},
            }),
            throwsA(anything),
          );
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
