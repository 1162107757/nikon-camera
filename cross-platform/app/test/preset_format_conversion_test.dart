import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/original_files.dart';
import 'package:huevia/preset_format_conversion.dart';
import 'package:huevia/preset_showcase_compare.dart';

class _Core extends HueviaCore {
  _Core(Directory directory) {
    root = directory.path;
  }

  String original = '', effect = '', scene = 'same-scene';
  final requests = <Json>[];
  final staged = <List<int>>[];

  @override
  Future<Json> call(
    String operation, [
    Json value = const {},
    String? job,
  ]) async {
    switch (operation) {
      case 'library.convertPlan':
      case 'online.convertPlan':
        requests.add(value);
        final target = value['targetFormat'] as String;
        return {
          'sourceFormat': 'NP3',
          'targetFormat': target,
          'cameraName': 'NIGHT TEST',
          'rows': [
            {'label': '色调曲线', 'status': 'retained'},
            if (target == 'NP2') {'label': '色彩混合器', 'status': 'omitted'},
          ],
          'bytes': base64Encode(utf8.encode(target)),
        };
      case 'media.showcase':
        return value['original'] == true
            ? {'path': original, 'scene': scene}
            : {'path': effect, 'scene': 'same-scene'};
      case 'library.import':
        staged.add(File(value['path'] as String).readAsBytesSync());
        return {'added': true};
      case 'library.list':
        return {'items': []};
      default:
        throw StateError(operation);
    }
  }
}

void main() {
  const local = Preset({
    'id': 'night',
    'displayName': '夜雨街巷',
    'originalFileName': 'NIGHT_SOURCE.NP3',
    'fileFormat': 'NP3',
  });

  testWidgets(
    'Omissions allow conversion and both actions use the confirmed copy',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync(
        'huevia-conversion-test',
      );
      final core = _Core(temp);
      final state = AppState(core);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() {
        messenger.setMockMethodCallHandler(OriginalFiles.channel, null);
        state.dispose();
        temp.deleteSync(recursive: true);
      });
      messenger.setMockMethodCallHandler(OriginalFiles.channel, (call) async {
        expect(call.method, 'savePreset');
        final file = File(call.arguments['path'] as String);
        expect(file.path, endsWith('夜雨街巷.NP2'));
        core.staged.add(file.readAsBytesSync());
        return true;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: PresetFormatConversionPage(state: state, preset: local),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('转换为 NCP'), findsOneWidget);
      expect(find.text('色彩混合器'), findsNothing);
      await tester.tap(find.widgetWithText(OutlinedButton, 'NP2'));
      await tester.pumpAndSettle();
      expect(core.requests.last['targetFormat'], 'NP2');
      expect(find.text('色彩混合器'), findsOneWidget);
      expect(find.text('省略'), findsOneWidget);
      await tester.tap(find.text('转换为 NP2'));
      await tester.pumpAndSettle();
      expect(find.text('转换完成'), findsOneWidget);
      expect(find.text('源文件  NIGHT_SOURCE.NP3'), findsOneWidget);
      expect(core.staged, isEmpty);
      await tester.runAsync(() async {
        await tester.tap(find.text('保存文件'));
        await _waitFor(
          () =>
              core.staged.length == 1 &&
              Directory('${temp.path}/preset-conversions').listSync().isEmpty,
        );
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('加入我的预设'));
        await _waitFor(
          () =>
              core.staged.length == 2 &&
              Directory('${temp.path}/preset-conversions').listSync().isEmpty,
        );
      });
      await tester.pumpAndSettle();
      expect(core.staged.map(utf8.decode), ['NP2', 'NP2']);
      expect(find.text('已加入我的预设'), findsOneWidget);
    },
  );

  testWidgets(
    'The detail compare handle can return from an edge and rejects unmatched samples',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('huevia-compare-test');
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aP9sAAAAASUVORK5CYII=';
      final core = _Core(temp)
        ..original = (File(
          '${temp.path}/original.png',
        )..writeAsBytesSync(base64Decode(png))).path
        ..effect = (File(
          '${temp.path}/effect.png',
        )..writeAsBytesSync(base64Decode(png))).path;
      addTearDown(() => temp.deleteSync(recursive: true));
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 340,
              height: 272,
              child: PresetShowcaseCompare(
                core: core,
                preset: local,
                owner: '',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final divider = find.byKey(const ValueKey('compare-divider'));
      final line = find.byKey(const ValueKey('compare-line'));
      final center = tester.getTopLeft(line).dx;
      await tester.drag(divider, const Offset(380, 0));
      await tester.pumpAndSettle();
      final right = tester.getTopLeft(line).dx;
      expect(right, greaterThan(center));
      await tester.drag(divider, const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(line).dx, lessThan(right));
      core.scene = 'other-scene';
      core.previewRevision.value++;
      await tester.pumpAndSettle();
      expect(divider, findsNothing);
    },
  );
}

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('File action did not finish');
}
