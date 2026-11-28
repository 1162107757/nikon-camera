import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_slots.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/split_compare.dart';
import 'package:huevia/theme.dart';

import 'palette_b_device_test.dart' as palette;
import '../test/editor_color_workspace_test.dart' as editor;
import '../test/editor_interaction_fixes_test.dart' as interactions;
import '../test/camera_conversion_report_test.dart' as report;
import '../test/camera_slots_ui_test.dart' as slots;
import '../test/editor_realtime_preview_test.dart' show RealtimeState;

void main() {
  palette.main();
  interactions.main();
  report.main();
  slots.main();
  testWidgets(
    'Capture original comparison endpoints and NP3 confirmation table',
    (tester) async {
      final output = Directory('/data/user/0/cc.huevia.next/files/fixes234-ui')
        ..createSync(recursive: true);
      final boundaryKey = GlobalKey();
      Future<void> save(String name) async {
        await editor.frames(tester);
        expect(tester.takeException(), isNull);
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      }

      for (final size in [const Size(320, 720), const Size(812, 375)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final landscape = size.width > size.height;
        final core = palette.PaletteScreenshotCore();
        final editorState = RealtimeState(core);
        final path = '${core.root}/sample.jpg';
        core.sample.copySync(path);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: hueviaTheme(Brightness.dark),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(landscape ? 2 : 1.3),
                  systemGestureInsets: const EdgeInsets.symmetric(
                    horizontal: 24,
                  ),
                ),
                child: child!,
              ),
              home: EditorPage(
                state: editorState,
                photo: Photo(path, '照片编辑', const {'width': 720, 'height': 960}),
              ),
            ),
          ),
        );
        await editor.frames(tester, count: 12);
        await tester.tap(find.text('调节').hitTestable());
        await tester.pump();
        await editor.tool(tester, '调色盘');
        await tester.tap(find.byKey(const Key('editor-compare-toggle')));
        await editor.frames(tester);
        for (final direction in [-1.0, 1.0]) {
          await interactions.dragCompare(tester, direction * size.width * 2);
          await tester.pump();
          expect(
            (tester.state(find.byType(SplitCompare)) as dynamic).divider,
            direction < 0 ? 0.0 : 1.0,
          );
          await save(
            '${landscape ? 'landscape' : 'phone'}-compare-${direction < 0 ? 'left' : 'right'}',
          );
        }
        await tester.pumpWidget(const SizedBox());
        await editor.frames(tester, count: 2);
        editorState.dispose();
        final slotsCore = slots.SlotsTestCore()
          ..presetFormat = 'NP3'
          ..compatibility = {
            'format': 'NP3',
            'omitted': [
              '灵活色彩全局饱和度：NCP 不支持，已忽略',
              '色彩混合器：NCP 不支持，已忽略',
              '分区调色：NCP 不支持，已忽略',
              '自动参数：已忽略，使用已转换的独立参数',
            ],
            'approximated': ['灵活色彩基底改为自然；相机色彩响应会不同'],
            'retained': ['原始自定义明暗曲线', '锐化'],
          };
        final model = AppState(slotsCore)
          ..session = {
            'user': {'id': 'alice'},
          };
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              theme: hueviaTheme(Brightness.light),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(landscape ? 2 : 1.3)),
                child: child!,
              ),
              home: CameraSlotsPage(
                state: model,
                initialPreset: Preset({
                  'id': 'b' * 64,
                  'displayName': 'NP3 预设',
                  'fileFormat': 'NP3',
                }),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('camera-slot-import')));
        await tester.pumpAndSettle();
        if (landscape) {
          await tester.ensureVisible(
            find.byKey(const Key('np3-compatibility-table')),
          );
          await tester.pumpAndSettle();
        }
        await save('${landscape ? 'landscape' : 'phone'}-np3-table');
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        model.dispose();
      }
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
}
