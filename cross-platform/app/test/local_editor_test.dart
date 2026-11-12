import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/split_compare.dart';
import 'package:huevia/theme.dart';

import 'editor_test.dart' show DraftCore;
import 'editor_workspace_test.dart' show WorkspaceState;

class ScopedEditorCore extends DraftCore {
  ScopedEditorCore(super.root);
  int sequence = 0;
  Json region = {
    'id': 'region-one',
    'name': '区域 1',
    'enabled': true,
    'amount': 1,
    'inverted': false,
    'strokes': [],
    'shapes': [
      {
        'kind': 'rectangle',
        'left': .1,
        'top': .1,
        'right': .9,
        'bottom': .9,
        'feather': .2,
        'subtract': false,
        'strokeIndex': 0,
      },
    ],
    'adjustments': {'values': List.filled(17, 0)},
  };
  Json descriptor([Json? value]) => {
    'localData': jsonEncode(value ?? region),
    'sha256': 'fingerprint-$sequence',
    'regions': [value ?? region],
  };
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'media.preview') {
      return {
        ...await super.call(operation, payload, jobId),
        'width': 1,
        'height': 1,
        'sourceWidth': 1,
        'sourceHeight': 1,
      };
    }
    if (operation == 'local.overlay') {
      calls.add((operation, payload));
      return {
        'width': 1,
        'height': 1,
        'rgba': base64Encode([38, 36, 34, 38]),
      };
    }
    if (operation == 'draft.load') {
      final saved = await super.call(operation, payload, jobId);
      saved['recipe'] = {
        ...object(saved['recipe']),
        'localData': jsonEncode(region),
      };
      return saved;
    }
    if (operation == 'local.describe') {
      calls.add((operation, payload));
      final encoded = payload['localData'] as String? ?? '';
      return encoded.isEmpty
          ? {'localData': '', 'sha256': 'fingerprint-$sequence', 'regions': []}
          : descriptor(object(jsonDecode(encoded)));
    }
    if (operation == 'local.change') {
      calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
      if (payload['regionId'] != 'region-one') {
        throw StateError('Unexpected region');
      }
      final previous = object(jsonDecode(payload['localData'] as String));
      final patch = object(payload['value']);
      if (patch['adjustments'] != null) {
        previous['adjustments'] = {
          ...object(previous['adjustments']),
          ...object(patch['adjustments']),
        };
      }
      sequence++;
      region = previous;
      return descriptor();
    }
    return super.call(operation, payload, jobId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'scope adjustments preserve global settings and undo the original binary snapshot',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'huevia-local-editor-',
      );
      Directory('${directory.path}/previews').createSync();
      File('${directory.path}/previews/preview.png').writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
        ),
      );
      final core = ScopedEditorCore(directory.path);
      final state = WorkspaceState(core);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('cc.huevia/events'),
            (_) async => null,
          );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('cc.huevia/events'),
              null,
            );
        state.dispose();
        final absolute = directory.resolveSymbolicLinksSync().replaceAll(
          '\\',
          '/',
        );
        final parent = Directory.systemTemp
            .resolveSymbolicLinksSync()
            .replaceAll('\\', '/');
        expect(absolute.startsWith('$parent/'), isTrue);
        expect(absolute.split('/').last, startsWith('huevia-local-editor-'));
        try {
          directory.deleteSync(recursive: true);
        } on FileSystemException catch (failure) {
          if (!Platform.isWindows || failure.osError?.errorCode != 32) rethrow;
          debugPrint('Deferred owned fixture cleanup: ${directory.path}');
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.dark),
          home: EditorPage(
            state: state,
            photo: Photo('${directory.path}/source.png', '私有照片', const {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('调节'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('调节范围：全图'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('区域 1'));
      await tester.pumpAndSettle();
      expect(find.text('曝光 · 区域 1'), findsOneWidget);
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
        if (tester.widget<SplitCompare>(find.byType(SplitCompare)).selection !=
            null) {
          break;
        }
      }
      expect(core.calls.where((row) => row.$1 == 'local.overlay'), isNotEmpty);
      expect(
        tester.widget<SplitCompare>(find.byType(SplitCompare)).selection,
        isNotNull,
      );
      await tester.tap(find.byTooltip('隐藏选区，保留调整'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<SplitCompare>(find.byType(SplitCompare)).selection,
        isNull,
      );
      await tester.tap(find.byTooltip('显示选区'));
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(find.byType(Slider).first);
      slider.onChangeStart!(0);
      slider.onChanged!(10);
      slider.onChanged!(20);
      slider.onChangeEnd!(20);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      final rendered = object(
        core.calls.lastWhere((row) => row.$1 == 'media.preview').$2['recipe'],
      );
      expect((rendered['values'] as List)[1], 0);
      final local = object(jsonDecode(rendered['localData'] as String));
      expect(
        (object(local['adjustments'])['values'] as List)[1],
        20,
        reason: jsonEncode({
          'commands': core.calls
              .where((row) => row.$1 == 'local.change')
              .map((row) => row.$2)
              .toList(),
          'messages': tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .toList(),
        }),
      );
      await tester.tap(find.byTooltip('撤销'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      final undone = object(
        core.calls.lastWhere((row) => row.$1 == 'media.preview').$2['recipe'],
      );
      expect(
        (object(
              object(jsonDecode(undone['localData'] as String))['adjustments'],
            )['values']
            as List)[1],
        0,
      );
      expect(find.text('曝光 · 区域 1'), findsOneWidget);
      await tester.tap(find.byTooltip('点击输入数值，长按查看参数说明'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1.23');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('请输入范围内的数值，步长 0.1 EV'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1.3');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      final exactRecipe = object(
        core.calls.lastWhere((row) => row.$1 == 'media.preview').$2['recipe'],
      );
      expect((exactRecipe['values'] as List)[1], 0);
      expect(
        (object(
              object(
                jsonDecode(exactRecipe['localData'] as String),
              )['adjustments'],
            )['values']
            as List)[1],
        13,
      );
      await tester.ensureVisible(find.text('HSL'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HSL'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('洋红'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(
              find.ancestor(
                of: find.text('洋红'),
                matching: find.byType(ChoiceChip),
              ),
            )
            .selected,
        isTrue,
      );
      final hue = tester.widget<Slider>(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Slider),
            )
            .first,
      );
      hue.onChangeStart!(0);
      hue.onChanged!(25);
      hue.onChangeEnd!(25);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      final hueRecipe = object(
        core.calls.lastWhere((row) => row.$1 == 'media.preview').$2['recipe'],
      );
      expect(hueRecipe['hsl'], isNull);
      expect(
        (object(
              object(
                jsonDecode(hueRecipe['localData'] as String),
              )['adjustments'],
            )['hsl']
            as List)[21],
        25,
      );
      await tester.tap(find.byTooltip('完成'));
      await tester.pumpAndSettle();
      state.switchOwner();
      await tester.pumpAndSettle();
      expect(find.text('私有照片'), findsNothing);
      expect(find.bySemanticsLabel('照片效果预览'), findsNothing);
      expect(find.textContaining('账号已改变'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
