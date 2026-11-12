import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/raw_develop.dart';
import 'package:huevia/theme.dart';

class ReferenceUiCore extends HueviaCore {
  ReferenceUiCore() {
    root = '/raw-reference-test';
  }
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
      // Image decoding and disposal are exercised by the native DNG scenario.
      // This control-flow test stays wholly inside the widget test clock.
      throw const AppFailure('此测试不生成预览像素。');
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
      final core = ReferenceUiCore();
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
      Future<void> finishRouteAnimations() async {
        // Choosing a reference intentionally keeps an indeterminate spinner
        // alive behind the modal. It cannot reach pumpAndSettle's idle state.
        for (var frame = 0; frame < 3; frame++) {
          await tester.pump(const Duration(milliseconds: 300));
        }
      }

      Future<void> select() async {
        await tester.ensureVisible(find.text('选择 JPEG 参考'));
        await tester.tap(find.text('选择 JPEG 参考'));
        await finishRouteAnimations();
        await tester.tap(find.text('PAIR.JPG'));
        await finishRouteAnimations();
      }

      await select();
      expect(find.text('确认同一次拍摄'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await finishRouteAnimations();
      expect(state.updates, 0);
      expect(
        core.calls.any((call) => call.$1 == 'media.rawReferenceInfo'),
        false,
      );
      await select();
      await tester.tap(find.text('使用此 JPEG'));
      await finishRouteAnimations();
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
      await finishRouteAnimations();
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
    },
  );
}
