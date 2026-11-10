import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/main.dart';

class OfflineCore extends HueviaCore {
  @override
  Future<void> initialize() async {}
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'library.list') return {'items': [], 'diagnostics': []};
    if (operation == 'account.current') return {};
    throw AppFailure('Unexpected offline operation: $operation');
  }
}

void main() {
  test('Frozen export recipe retains independent advanced edits', () {
    final source = Recipe(
      data: {
        'schema': 1,
        'presetId': 'a' * 64,
        'strength': 57,
        'values': List.filled(17, 0),
        'hsl': List.filled(24, 3),
        'geometry': {'turns': 2, 'mirrored': true},
        'localData': 'opaque-original-recipe',
      },
    );
    final frozen = source.clone();
    source.setValue(3, -20);
    (source.data['geometry'] as Json)['turns'] = 1;
    expect(frozen.values[3], 0);
    expect(frozen.data['geometry'], {'turns': 2, 'mirrored': true});
    expect(frozen.data['localData'], 'opaque-original-recipe');
    expect(frozen.data['hsl'], List.filled(24, 3));
  });
  test(
    'File import retains exact original bytes and rejects a corrupt collision',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'huevia-import-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final original = File('${directory.path}/source.NEF');
      final bytes = List.generate(1024 * 257, (i) => (i * 31) & 255);
      await original.writeAsBytes(bytes);
      final core = HueviaCore()..root = '${directory.path}/private';
      final path = await core.importFile(XFile(original.path), preset: false);
      expect(await File(path).readAsBytes(), bytes);
      expect(await original.readAsBytes(), bytes);
      expect(path, contains(sha256.convert(bytes).toString()));
      expect(await core.importFile(XFile(original.path), preset: false), path);
      await File(path).writeAsBytes([1, 2, 3]);
      await expectLater(
        core.importFile(XFile(original.path), preset: false),
        throwsA(isA<AppFailure>()),
      );
      final parts = Directory('${core.root}/originals')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.part'));
      expect(parts, isEmpty);
    },
  );
  for (final scenario in [
    (const Size(375, 812), Brightness.light, 1.0),
    (const Size(812, 375), Brightness.dark, 2.0),
    (const Size(375, 812), Brightness.dark, 2.0),
  ]) {
    testWidgets(
      'Offline navigation remains usable at ${scenario.$1}, ${scenario.$2}, text ${scenario.$3}',
      (tester) async {
        tester.view.physicalSize = scenario.$1;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.platformBrightnessTestValue = scenario.$2;
        tester.platformDispatcher.textScaleFactorTestValue = scenario.$3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final state = AppState(OfflineCore())..ready = true;
        await tester.pumpWidget(HueviaApp(state: state));
        await tester.pumpAndSettle();
        expect(find.text('预设库'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('照片').last);
        await tester.pumpAndSettle();
        expect(find.text('选择照片'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('我的').last);
        await tester.pumpAndSettle();
        expect(find.text('用户名'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
