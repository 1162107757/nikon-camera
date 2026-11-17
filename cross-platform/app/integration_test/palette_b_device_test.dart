import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/theme.dart';

import '../test/palette_workspace_test.dart' as palette;
import '../test/editor_color_workspace_test.dart' as editor;
import '../test/editor_realtime_preview_test.dart' show RealtimeState;
import '../test/legacy_color_controls_test.dart' as gestures;

class PaletteBinding extends IntegrationTestWidgetsFlutterBinding {
  @override
  bool get registerTestTextInput => true;
}

class PaletteScreenshotCore extends editor.ColorWorkspaceCore {
  final File sample = File(
    '/data/user/0/cc.huevia.next/files/palette233-sample.jpg',
  );
  @override
  Json image() {
    final path = '$root/previews/palette-${serial++}.jpg';
    sample.copySync(path);
    return {
      'path': path,
      'width': 720,
      'height': 960,
      'sourceWidth': 720,
      'sourceHeight': 960,
    };
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'draft.load') {
      return {
        'sourceSha': 'fixture-sha',
        'recipe': Recipe().data
          ..['palette'] = {'color': 24, 'tone': 12, 'amount': 80},
      };
    }
    return super.call(operation, payload, jobId);
  }
}

void main() {
  PaletteBinding().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  palette.main();
  gestures.main();
  editor.main();
  testWidgets(
    'Palette B actual editor screenshots expanded collapsed and dragging',
    (tester) async {
      final output = Directory(
        '/data/user/0/cc.huevia.next/files/palette233-ui',
      )..createSync(recursive: true);
      for (final spec in [
        ('phone-small', const Size(320, 720), 1.3),
        ('phone', const Size(390, 844), 1.0),
        ('tablet', const Size(1024, 768), 1.3),
        ('landscape-large-text', const Size(812, 375), 2.0),
      ]) {
        final core = PaletteScreenshotCore();
        final state = RealtimeState(core);
        final path = '${core.root}/sample.jpg';
        core.sample.copySync(path);
        final key = GlobalKey();
        tester.view.physicalSize = spec.$2;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: hueviaTheme(Brightness.dark),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(spec.$3),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: EditorPage(
                state: state,
                photo: Photo(path, '调色盘 B', const {
                  'width': 720,
                  'height': 960,
                }),
              ),
            ),
          ),
        );
        await editor.frames(tester, count: 12);
        await tester.tap(find.text('调节').hitTestable());
        await tester.pump();
        await editor.tool(tester, '调色盘');
        Future<void> save(String name) async {
          await editor.frames(tester, count: 10);
          expect(tester.takeException(), isNull);
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1),
              data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${output.path}/${spec.$1}-$name.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        }

        expect(find.byKey(const Key('palette-tools-toolbar')), findsNothing);
        expect(
          find.byKey(const Key('palette-scope')).hitTestable(),
          findsOneWidget,
        );
        final paint = tester.widget<CustomPaint>(
          find.descendant(
            of: find.byKey(const Key('legacy-palette-pad')),
            matching: find.byType(CustomPaint),
          ),
        );
        final field = (paint.painter as dynamic).rect as Rect;
        expect(field.width / field.height, greaterThan(1.4));
        expect(field.height, greaterThanOrEqualTo(72));
        await save('expanded');
        await tester.tap(find.byKey(const Key('palette-panel-toggle')));
        await editor.frames(tester);
        expect(find.byKey(const Key('palette-tools-toolbar')), findsOneWidget);
        expect(find.byKey(const Key('legacy-palette-pad')), findsNothing);
        await save('collapsed');
        await tester.tap(find.byKey(const Key('palette-tool-2')));
        await editor.frames(tester);
        await tester.dragFrom(
          tester.getCenter(find.byKey(const Key('legacy-palette-pad'))),
          const Offset(24, 12),
        );
        expect(find.byKey(const Key('palette-tools-toolbar')), findsNothing);
        await save('dragged');
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        state.dispose();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
