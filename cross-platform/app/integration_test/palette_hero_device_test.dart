import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/theme.dart';

import 'palette_b_device_test.dart' show PaletteBinding, PaletteScreenshotCore;
import '../test/editor_color_workspace_test.dart' as editor;
import '../test/editor_realtime_preview_test.dart' show RealtimeState;

void main() {
  PaletteBinding().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets('Native approved-comp reproduction at 830 by 1894', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(830, 1894);
    tester.view.devicePixelRatio = 2;
    final core = PaletteScreenshotCore();
    final model = RealtimeState(core), key = GlobalKey();
    final path = '${core.root}/sample.jpg';
    core.sample.copySync(path);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: hueviaTheme(Brightness.dark),
          home: EditorPage(
            state: model,
            photo: Photo(path, '调色盘 B', const {'width': 720, 'height': 960}),
          ),
        ),
      ),
    );
    await editor.frames(tester, count: 12);
    await tester.tap(find.text('调节').hitTestable());
    await tester.pump();
    await editor.tool(tester, '调色盘');
    await editor.frames(tester, count: 10);
    expect(find.byKey(const Key('palette-tools-toolbar')), findsNothing);
    expect(
      find.byKey(const Key('palette-scope')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    expect(image.width, 830);
    expect(image.height, 1894);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/data/user/0/cc.huevia.next/files/palette233-ui/hero-repro.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    model.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
