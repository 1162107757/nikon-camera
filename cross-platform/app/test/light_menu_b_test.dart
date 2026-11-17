import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/theme.dart';

import 'editor_menu_actions_test.dart' as fixture;

class LightMenuCore extends fixture.ActionsCore {
  LightMenuCore(super.directory) {
    lightingFixture = true;
  }
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'local.change') {
      calls.add((operation, payload));
      final value = object(payload['value']);
      return {
        ...value,
        'localData': (value['masks'] as List).isEmpty
            ? 'existing-portrait-regions-patches'
            : jsonEncode(value),
      };
    }
    return super.call(operation, payload, jobId);
  }
}

Future<void> lightMenuSettle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final size in [
    const Size(320, 720),
    const Size(390, 844),
    const Size(1024, 768),
  ]) {
    testWidgets(
      'Light B replaces main tools, exposes all controls and returns at $size',
      (tester) async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('cc.huevia/events'),
              (_) async => null,
            );
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final dir = Directory.systemTemp.createTempSync('huevia-light-b-');
        Directory('${dir.path}/previews').createSync();
        File('${dir.path}/previews/preview.png').writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
          ),
        );
        final core = LightMenuCore(dir.path);
        final state = AppState(core)
          ..session = {
            'user': {'id': 'alice'},
          };
        final photo = Photo('${dir.path}/source.jpg', '光影布局', const {});
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.3),
                padding: const EdgeInsets.symmetric(vertical: 24),
                viewPadding: const EdgeInsets.symmetric(vertical: 24),
              ),
              child: child!,
            ),
            home: EditorPage(state: state, photo: photo),
          ),
        );
        await lightMenuSettle(tester);
        final beforeHeight = tester
            .getSize(find.byKey(const Key('editor-photo-viewport')))
            .height;
        await tester.tap(find.text('光影').hitTestable());
        await lightMenuSettle(tester);
        expect(find.text('滤镜').hitTestable(), findsNothing);
        expect(find.text('裁切').hitTestable(), findsNothing);
        if (size.width < 600) {
          expect(
            tester
                .getSize(find.byKey(const Key('editor-photo-viewport')))
                .height,
            greaterThan(beforeHeight),
          );
        }
        for (var i = 0; i < 4; i++) {
          final target = find.byKey(ValueKey('light-style-$i'));
          expect(target.hitTestable(), findsOneWidget);
          final bounds = tester.getSize(target);
          expect(bounds.width, greaterThanOrEqualTo(48));
          expect(bounds.height, greaterThanOrEqualTo(48));
          await tester.tap(target);
          await lightMenuSettle(tester);
          expect(
            tester.getSemantics(target).flagsCollection.isSelected,
            Tristate.isTrue,
          );
          expect(find.text(i == 1 ? '方向' : '范围').hitTestable(), findsOneWidget);
        }
        final warmth = tester.widget<Slider>(
          find.byKey(const ValueKey('light-parameter-冷暖')),
        );
        expect(
          find.byKey(const ValueKey('light-parameter-冷暖')).hitTestable(),
          findsOneWidget,
        );
        expect(warmth.value, (warmth.min + warmth.max) / 2);
        final renderCalls = core.calls
            .where((c) => c.$1 == 'media.localPreview')
            .length;
        await tester.tap(find.byTooltip('对比进入前'));
        await tester.pump();
        expect(find.byTooltip('查看光影效果'), findsOneWidget);
        expect(
          core.calls.where((c) => c.$1 == 'media.localPreview').length,
          renderCalls,
        );
        await tester.tap(find.text('重置'));
        await lightMenuSettle(tester);
        expect(
          tester
              .widget<Slider>(find.byKey(const ValueKey('light-parameter-强度')))
              .value,
          0,
        );
        await tester.tap(find.byKey(const ValueKey('light-back')));
        await lightMenuSettle(tester);
        expect(find.text('滤镜').hitTestable(), findsOneWidget);
        expect(core.draft['localData'], 'existing-portrait-regions-patches');
        if (size.width == 390) {
          await tester.tap(find.text('光影').hitTestable());
          await lightMenuSettle(tester);
          await tester.tap(find.byKey(const ValueKey('light-style-1')));
          await lightMenuSettle(tester);
          expect(
            tester
                .widget<TextButton>(find.byKey(const Key('apply-light')))
                .onPressed,
            isNotNull,
          );
          await tester.tap(find.byKey(const Key('apply-light')));
          await lightMenuSettle(tester);
          expect(find.text('滤镜').hitTestable(), findsOneWidget);
          expect(core.draft['localData'], contains('"masks"'));
          expect(core.draft['border'], containsPair('template', 3));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await lightMenuSettle(tester);
        state.dispose();
        imageCache.clear();
        imageCache.clearLiveImages();
        // FileImage can hold Windows handles until the test process exits.
        if (!Platform.isWindows) await dir.delete(recursive: true);
      },
    );
  }
}
