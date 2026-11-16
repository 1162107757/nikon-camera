import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huevia/camera_slots.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/theme.dart';

import '../test/editor_menu_actions_test.dart' as fixture;
import '../test/camera_slots_ui_test.dart' as slots;

class VisualCore extends fixture.ActionsCore {
  VisualCore(super.directory) {
    lightingFixture = true;
    draft['presetName'] = '布局测试配方';
  }
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'media.preview' || operation == 'media.localPreview') {
      calls.add((operation, payload));
      final output = '$root/previews/owned-${calls.length}.png';
      File('$root/chart.png').copySync(output);
      return {'path': output, 'width': 360, 'height': 480};
    }
    if (operation == 'camera.status')
      return {
        'connected': true,
        'session': 'photo',
        'transport': 'usb',
        'mode': 'photos',
      };
    if (operation == 'camera.slots.open' || operation == 'camera.slots.refresh')
      return {
        'session': 'slots',
        'connected': true,
        'model': 'Z 6_2',
        'canWrite': true,
        'canDelete': true,
        'items': [
          for (var i = 201; i <= 209; i++)
            {
              'target': i,
              'label': 'C${i - 200}',
              'name': '现有预设',
              'empty': false,
              'sha256': 'a' * 64,
            },
        ],
      };
    if (operation == 'library.export') return {'path': '$root/fixture.np3'};
    if (operation == 'camera.slots.prepare')
      return {
        'confirmationId': 'visual-only',
        'targetLabel': 'C1',
        'beforeName': '现有预设',
        'overwrite': true,
        'name': 'NP3 TEST',
        'explanation': 'NP3 已转换为兼容 NCP，原文件保留。\n保留：登记名称、原始自定义明暗曲线与锐化\n近似转换：灵活色彩基底改为自然\n不导入：全局饱和度、色彩混合器与分区调色\n可继续导入以上兼容部分；机身效果请试拍确认。',
        'parameterSummary': '不调整',
      };
    if (operation == 'camera.slots.close') return {};
    return super.call(operation, payload, jobId);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  slots.main();
  testWidgets(
    'Bottom light and informative NP3 confirmation on phone and tablet',
    (tester) async {
      final output = Directory(
        '/data/user/0/cc.huevia.next/files/light-np3-231-ui',
      )..createSync(recursive: true);
      final dir = Directory('${output.path}/fixture')
        ..createSync(recursive: true);
      Directory('${dir.path}/previews').createSync();
      final recorder = ui.PictureRecorder();
      // Synthetic chart: layout evidence only, never presented as a camera photograph.
      final chartCanvas = Canvas(recorder);
      final colours = [
        const Color(0xff9bb6c7),
        const Color(0xffdad6c5),
        const Color(0xff57745d),
        const Color(0xff493c36),
      ];
      for (var i = 0; i < colours.length; i++)
        chartCanvas.drawRect(
          Rect.fromLTWH(0, i * 120, 360, 120),
          Paint()..color = colours[i],
        );
      final chart = await recorder.endRecording().toImage(360, 480),
          bytes = await chart.toByteData(format: ui.ImageByteFormat.png);
      File('${dir.path}/chart.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      chart.dispose();
      final core = VisualCore(dir.path);
      // Each fixture owns its state and files; existing app accounts/photos are untouched.
      final model = AppState(core)
        ..session = {
          'user': {'id': 'visual-owner'},
        };
      final photo = Photo('${dir.path}/source.jpg', '布局测试', const {});
      Future<void> settle() async {
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> save(GlobalKey key, String name) async {
        await settle();
        expect(tester.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1),
            data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/$name.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      }

      for (final size in [const Size(320, 720), const Size(1024, 768)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: hueviaTheme(Brightness.dark),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: EditorPage(state: model, photo: photo),
            ),
          ),
        );
        await save(key, 'bottom-light-${size.width.toInt()}');
        expect(find.text('光影').hitTestable(), findsOneWidget);
        await tester.tap(find.text('光影').hitTestable());
        await save(key, 'light-workspace-${size.width.toInt()}');
        for (final name in ['柔光', '侧光', '聚光', '阴影'])
          expect(find.text(name), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await settle();
      }
      tester.view.physicalSize = const Size(390, 844);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: hueviaTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: CameraSlotsPage(
              state: model,
              initialPreset: Preset({
                'id': 'b' * 64,
                'displayName': 'NP3 测试',
                'fileFormat': 'NP3',
              }),
            ),
          ),
        ),
      );
      await settle();
      await tester.tap(find.byKey(const ValueKey('camera-slot-import')));
      await settle();
      expect(find.textContaining('不导入：'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认写入此槽位'))
            .onPressed,
        isNotNull,
      );
      await save(key, 'np3-compatible-confirmation');
      await tester.pumpWidget(const SizedBox());
      await settle();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      model.dispose();
    },
  );
}
