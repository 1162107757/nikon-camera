import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/raw_develop.dart';
import 'package:huevia/theme.dart';

class ReferenceUiCore extends HueviaCore {
  ReferenceUiCore(this.directory) {
    root = directory.path;
    Directory('$root/previews').createSync();
    Directory('$root/originals').createSync();
    image = File('$root/fixture.png')
      ..writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
        ),
      );
  }
  final Directory directory;
  late File image;
  int previews = 0;
  final calls = <(String, Json)>[];
  @override
  Stream<dynamic> get operationProgress => const Stream.empty();
  @override
  Future<void> cancel(String jobId) async {}
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    if (operation == 'media.rawPreview') {
      return {
        'path': image.copySync('$root/previews/${previews++}.png').path,
        'rawColorStatus': payload['reference'] == null
            ? 'NO_REFERENCE'
            : 'EXTERNAL_MATCHED',
      };
    }
    if (operation == 'media.rawReferenceInfo') {
      return {
        'path': payload['referencePath'],
        'sha256': 'a' * 64,
        'sourceSha': 'b' * 64,
      };
    }
    throw AppFailure(operation);
  }
}

class ReferenceUiState extends AppState {
  ReferenceUiState(super.core);
  int updates = 0;
  @override
  Future<Photo> updatePhoto(Photo photo, Json metadata) async {
    updates++;
    final next = Photo(photo.path, photo.name, {
      ...photos.firstWhere((item) => item.path == photo.path).info,
      ...metadata,
    });
    photos = [
      for (final item in photos)
        if (item.path == photo.path) next else item,
    ];
    notifyListeners();
    return next;
  }
}

void main() {
  testWidgets(
    'RAW reference requires explicit same-capture confirmation, persists and can restore embedded reference',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory.systemTemp.createTempSync(
        'huevia-raw-reference-ui-',
      );
      final core = ReferenceUiCore(directory);
      final raw = Photo('${core.root}/originals/source.nef', 'SOURCE.NEF', {
        'raw': true,
      });
      // Native bytes/codec checks are exercised by the real DNG pipeline;
      // this fixture checks selection, consent and cross-bridge state only.
      final jpeg = Photo('${core.root}/originals/reference.jpg', 'PAIR.JPG', {
        'raw': false,
      });
      final state = ReferenceUiState(core)..photos = [raw, jpeg];
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: RawDevelopPage(state: state, photo: raw),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> select() async {
        await tester.ensureVisible(find.text('选择 JPEG 参考'));
        await tester.tap(find.text('选择 JPEG 参考'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('PAIR.JPG'));
        await tester.pumpAndSettle();
      }

      await select();
      expect(find.text('确认同一次拍摄'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(state.updates, 0);
      expect(
        core.calls.any((call) => call.$1 == 'media.rawReferenceInfo'),
        false,
      );
      await select();
      await tester.tap(find.text('使用此 JPEG'));
      await tester.pumpAndSettle();
      expect(state.updates, 1);
      expect(
        state.photos.first.info['rawJpegReference']['relativePath'],
        'originals/reference.jpg',
      );
      final request = core.calls
          .lastWhere((call) => call.$1 == 'media.rawPreview')
          .$2;
      expect(request['reference']['sourceSha'], 'b' * 64);
      expect(request['reference']['path'], jpeg.path);
      await tester.ensureVisible(find.text('恢复内嵌参考'));
      await tester.tap(find.text('恢复内嵌参考'));
      await tester.pumpAndSettle();
      expect(state.photos.first.info['rawJpegReference'], isNull);
      expect(
        core.calls
            .lastWhere((call) => call.$1 == 'media.rawPreview')
            .$2
            .containsKey('reference'),
        false,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      tester.binding.imageCache.clear();
      tester.binding.imageCache.clearLiveImages();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        try {
          directory.deleteSync(recursive: true);
        } on FileSystemException {
          if (!Platform.isWindows) rethrow;
        }
      });
    },
  );
}
