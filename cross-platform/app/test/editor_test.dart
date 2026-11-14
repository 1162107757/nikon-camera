import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/theme.dart';

class DraftCore extends HueviaCore {
  DraftCore(String directory) {
    root = directory;
    schema = {
      'parameters': List.generate(
        17,
        (i) => {
          'index': i,
          'name': i == 1 ? 'EXPOSURE' : 'BRIGHTNESS',
          'label': i == 1 ? '曝光' : '参数$i',
          'min': -100,
          'max': 100,
          'help': '参数说明',
        },
      ),
    };
  }
  final List<(String, Json)> calls = [];
  int previewSerial = 0;
  @override
  Future<void> cancel(String jobId) async {}
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    if (operation == 'local.describe') {
      return {'localData': '', 'sha256': 'empty', 'regions': []};
    }
    if (operation == 'draft.load') {
      return {
        'sourceSha': 'photo-sha',
        'recipe': {
          'schema': 1,
          'presetId': 'removed-preset',
          'presetName': '已保存的秋色',
          'strength': 70,
          'values': List.filled(17, 0),
          'geometry': {
            'left': 200000,
            'top': 100000,
            'right': 800000,
            'bottom': 900000,
          },
        },
      };
    }
    if (operation == 'media.preview' ||
        operation == 'media.reviewPreview' ||
        operation == 'media.originalPreview') {
      final path = '$root/previews/frame-${previewSerial++}.png';
      File(
        path,
      ).writeAsBytesSync(File('$root/previews/preview.png').readAsBytesSync());
      return {'path': path};
    }
    if (operation == 'media.cleanupAnalyze') {
      return {'cleanupData': 'AWRkZAA='};
    }
    if (operation == 'draft.save') {
      return {'recipe': payload['recipe']};
    }
    throw AppFailure(operation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets(
      'Restored orphaned preset and advanced editor work at $size with large text',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'huevia-editor-test-',
        );
        Directory('${directory.path}/previews').createSync();
        File('${directory.path}/previews/preview.png').writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
          ),
        );
        final core = DraftCore(directory.path);
        final state = AppState(core)
          ..presets = [
            const Preset({
              'id': 'available',
              'displayName': '新滤镜',
              'fileFormat': 'NCP',
            }),
          ];
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          tester.binding.imageCache.clear();
          tester.binding.imageCache.clearLiveImages();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          final resolved = directory.absolute.path;
          expect(
            resolved.startsWith(Directory.systemTemp.absolute.path),
            isTrue,
          );
          expect(
            directory.uri.pathSegments.where(
              (v) => v.startsWith('huevia-editor-test-'),
            ),
            isNotEmpty,
          );
          await tester.runAsync(() => directory.delete(recursive: true));
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('cc.huevia/events'),
              (_) async => null,
            );
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: EditorPage(
              state: state,
              photo: Photo('${directory.path}/source.png', '测试照片', const {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('已保存的秋色'), findsOneWidget);
        // A tiny source must occupy the photo viewport, as in the original
        // editor; it must not retain its intrinsic one-pixel widget size.
        final effectImage = find.bySemanticsLabel('照片效果预览');
        expect(tester.getSize(effectImage).width, greaterThan(size.width * .5));
        Future<void> tapLabel(String label) async {
          await tester.ensureVisible(find.text(label));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label));
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 80));
          }
          await tester.pumpAndSettle();
        }

        await tapLabel('调节');
        await tapLabel('曲线');
        expect(tester.takeException(), isNull);
        await tapLabel('重置通道');
        expect(
          core.calls
              .lastWhere((c) => c.$1 == 'media.reviewPreview')
              .$2['recipe']['curves'],
          hasLength(4),
        );
        await tapLabel('应用');
        await tapLabel('裁切');
        await tapLabel('水平翻转');
        final geometry = core.calls
            .lastWhere((c) => c.$1 == 'media.preview')
            .$2['recipe']['geometry'];
        expect(geometry['left'], 200000);
        expect(geometry['right'], 800000);
        expect(geometry['mirrored'], true);
        await tapLabel('调节');
        await tapLabel('HSL');
        expect(find.text('洋红'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tapLabel('应用');
        await tapLabel('滤镜');
        await tester.tap(find.byTooltip('查看全部滤镜'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('picker-filter-')));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('查看全部滤镜'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('filter-source-mine')).last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('picker-filter-available')));
        await tester.pumpAndSettle();
        final newRecipe = core.calls
            .lastWhere((call) => call.$1 == 'media.preview')
            .$2['recipe'];
        expect(newRecipe['presetId'], 'available');
        expect(newRecipe['strength'], 100);
        await tester.tap(find.byTooltip('对比原图'));
        await tester.pumpAndSettle();
        final originalRequest = core.calls
            .lastWhere((call) => call.$1 == 'media.originalPreview')
            .$2;
        expect(originalRequest.containsKey('recipe'), isFalse);
        await tester.tap(find.byTooltip('显示效果'));
        await tester.pumpAndSettle();
        expect(
          core.calls
              .lastWhere((call) => call.$1 == 'media.preview')
              .$2['recipe']['presetId'],
          'available',
        );
        await tapLabel('调节');
        await tapLabel('去灰');
        // The original cleanup workspace analyzes once on entry. Adjust the
        // controlled legacy strength row; it now previews before Apply.
        final amount = find.byKey(const ValueKey('cleanup-axis-0'));
        await tester.ensureVisible(amount);
        final amountSlider = find.descendant(
          of: amount,
          matching: find.byType(Slider),
        );
        final control = tester.widget<Slider>(amountSlider);
        control.onChangeStart?.call(100);
        control.onChanged!(99);
        control.onChangeEnd?.call(99);
        await tester.pumpAndSettle();
        final cleaned = core.calls
            .lastWhere((call) => call.$1 == 'media.reviewPreview')
            .$2['recipe'];
        expect(cleaned['cleanupData'], 'AWRkZAA=');
        expect(cleaned['cleanup']['amount'], 99);
        await tapLabel('应用');
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(core.calls.last.$1, 'draft.save');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('cc.huevia/events'),
              null,
            );
      },
    );
  }
}
