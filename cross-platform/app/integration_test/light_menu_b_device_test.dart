import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/theme.dart';

import '../test/light_menu_b_test.dart' as menu;
import '../test/editor_menu_actions_test.dart' as actions;
import '../test/light_workspace_test.dart' as masks;

class ScreenshotCore extends menu.LightMenuCore {
  ScreenshotCore(super.directory);
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'media.preview' || operation == 'media.localPreview') {
      calls.add((operation, payload));
      final output = '$root/previews/chart-${calls.length}.png';
      File('$root/chart.png').copySync(output);
      return {'path': output, 'width': 360, 'height': 480};
    }
    return super.call(operation, payload, jobId);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Light B navigation and parameter controls', menu.main);
  group('Existing editor actions', actions.main);
  group('Existing source-coordinate lighting masks', masks.main);
  testWidgets('Capture light B phone, large text and tablet layouts', (
    tester,
  ) async {
    final dir = Directory('/data/user/0/cc.huevia.next/files/light-menu-b')
      ..createSync(recursive: true);
    Directory('${dir.path}/previews').createSync();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // A synthetic chart provides unambiguous layout evidence, not a camera test.
    for (final entry in const [
      Color(0xff9bb6c7),
      Color(0xffdad6c5),
      Color(0xff57745d),
      Color(0xff493c36),
    ].indexed) {
      canvas.drawRect(
        Rect.fromLTWH(0, entry.$1 * 120, 360, 120),
        Paint()..color = entry.$2,
      );
    }
    final chart = await recorder.endRecording().toImage(360, 480);
    final data = await chart.toByteData(format: ui.ImageByteFormat.png);
    File('${dir.path}/chart.png').writeAsBytesSync(data!.buffer.asUint8List());
    chart.dispose();
    for (final target in [
      (const Size(390, 844), 1.0, 'phone'),
      (const Size(320, 720), 1.3, 'large-text'),
      (const Size(1024, 768), 1.0, 'tablet'),
    ]) {
      tester.view.physicalSize = target.$1;
      tester.view.devicePixelRatio = 1;
      final core = ScreenshotCore(dir.path);
      final state = AppState(core)
        ..session = {
          'user': {'id': 'alice'},
        };
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: hueviaTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(target.$2),
                padding: const EdgeInsets.symmetric(vertical: 24),
                viewPadding: const EdgeInsets.symmetric(vertical: 24),
              ),
              child: child!,
            ),
            home: EditorPage(
              state: state,
              photo: Photo('${dir.path}/source.jpg', 'DSC_4821.JPG', const {}),
            ),
          ),
        ),
      );
      await menu.lightMenuSettle(tester);
      await tester.tap(find.text('光影').hitTestable());
      await menu.lightMenuSettle(tester);
      await tester.tap(find.byKey(const ValueKey('light-style-1')));
      await menu.lightMenuSettle(tester);
      expect(find.text('方向').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('light-parameter-冷暖')).hitTestable(),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('light-parameter-冷暖'))).bottom,
        lessThanOrEqualTo(target.$1.height - 24),
      );
      expect(find.text('滤镜').hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${dir.path}/${target.$3}.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
      await tester.pumpWidget(const SizedBox());
      await menu.lightMenuSettle(tester);
      state.dispose();
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
