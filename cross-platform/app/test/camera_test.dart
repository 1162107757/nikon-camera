import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';

class CameraCore extends HueviaCore {
  CameraCore(this.preview) {
    root = preview.parent.parent.path;
  }
  final File preview;
  final calls = <(String, Json)>[];
  bool failPage = false, failThumbnail = false;
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    switch (operation) {
      case 'camera.status':
        return {'connected': true, 'session': 'z6-fixture', 'model': 'Z 6_2'};
      case 'camera.page':
        if (failPage) throw const AppFailure('相机读取超时');
        return {
          'items': payload['raw'] == true
              ? [
                  {
                    'handle': 1,
                    'name': 'DSC_6522.NEF',
                    'bytes': 27000000,
                    'width': 6048,
                    'height': 4024,
                  },
                ]
              : [],
          'nextOffset': 1,
          'hasMore': false,
        };
      case 'camera.thumbnail':
        if (failThumbnail) throw const AppFailure('缩略图读取失败');
        return {
          'session': payload['session'],
          'handle': payload['handle'],
          'path': preview.path,
        };
      default:
        throw AppFailure(operation);
    }
  }
}

Future<CameraCore> fixture() async {
  final directory = Directory.systemTemp.createTempSync('huevia-camera-ui-');
  final cache = Directory('${directory.path}/camera-previews')..createSync();
  final image = File('${cache.path}/fixture.png');
  image.writeAsBytesSync(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
    ),
  );
  addTearDown(() async {
    if (await image.exists()) await image.delete();
    await cache.delete();
    await directory.delete();
  });
  return CameraCore(image);
}

Future<void> settleImages(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // File decoding finishes outside the fake clock on desktop test hosts.
  // Advance both clocks until a real image frame arrives, rather than relying
  // on one fixed delay that races a busy CI runner.
  for (var attempt = 0; attempt < 50; attempt++) {
    final decoded = tester
        .widgetList<RawImage>(find.byType(RawImage))
        .any((image) => image.image != null);
    if (decoded || find.byType(Image).evaluate().isEmpty) break;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pumpAndSettle();
}

Future<void> open(
  WidgetTester tester,
  AppState state, {
  bool configuration = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.light),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: CameraPage(state: state, configuration: configuration),
        ),
      ),
    ),
  );
  await settleImages(tester);
}

void main() {
  testWidgets(
    'RAW-only camera has an explicit JPEG hint and can show RAW thumbnails in the overview',
    (tester) async {
      final core = await fixture();
      final actual = AppState(core);
      await open(tester, actual);
      expect(find.text('未找到 JPEG 照片，可切换到 RAW / NEF 查看。'), findsOneWidget);
      await tester.tap(find.text('RAW / NEF'));
      await settleImages(tester);
      expect(find.text('DSC_6522.NEF'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image && widget.semanticLabel == 'DSC_6522.NEF 缩略图',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((image) => image.image != null),
        isTrue,
      );
      expect(actual.cameraRaw, isTrue);
      expect(core.calls.any((call) => call.$1 == 'camera.download'), isFalse);
      await tester.pumpWidget(const SizedBox());
      actual.dispose();
    },
  );
  testWidgets(
    'Connection page remembers RAW selection and shows the same thumbnail',
    (tester) async {
      final core = await fixture();
      final state = AppState(core)..cameraRaw = true;
      await open(tester, state, configuration: true);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'RAW / NEF'))
            .selected,
        isTrue,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image && widget.semanticLabel == 'DSC_6522.NEF 缩略图',
        ),
        findsOneWidget,
      );
      expect(
        core.calls.firstWhere((call) => call.$1 == 'camera.page').$2['raw'],
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets('Overview exposes read errors and retries the camera inventory', (
    tester,
  ) async {
    final core = await fixture();
    core.failPage = true;
    final state = AppState(core)..cameraRaw = true;
    await open(tester, state);
    expect(find.text('相机读取超时'), findsOneWidget);
    expect(find.textContaining('未找到'), findsNothing);
    core.failPage = false;
    await tester.tap(find.text('重试读取照片'));
    await settleImages(tester);
    expect(find.text('DSC_6522.NEF'), findsOneWidget);
    expect(find.text('相机读取超时'), findsNothing);
    expect(
      core.calls
          .where((call) => call.$1 == 'camera.page')
          .every((call) => call.$2['refresh'] == true),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets(
    'Thumbnail errors retry only the preview and keep the source untouched',
    (tester) async {
      final core = await fixture();
      core.failThumbnail = true;
      final state = AppState(core)..cameraRaw = true;
      await open(tester, state);
      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      core.failThumbnail = false;
      await tester.tap(find.byIcon(Icons.image_not_supported_outlined));
      await settleImages(tester);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Image && widget.semanticLabel == 'DSC_6522.NEF 缩略图',
        ),
        findsOneWidget,
      );
      expect(
        core.calls
            .where((call) => call.$1 == 'camera.thumbnail')
            .last
            .$2['refresh'],
        isTrue,
      );
      expect(core.calls.any((call) => call.$1 == 'camera.download'), isFalse);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'Camera controls and thumbnail rows fit a small screen with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final core = await fixture();
      final state = AppState(core)..cameraRaw = true;
      await open(tester, state, scale: 1.6);
      expect(find.text('DSC_6522.NEF'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
