import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Native document import keeps the provider filename and the owner from picker opening', () async {
    final root = Directory.systemTemp.createTempSync('huevia-native-import-');
    addTearDown(() => root.deleteSync(recursive: true));
    final core = HueviaCore()..root = root.path;
    final state = AppState(core)
      ..session = {
        'user': {'id': 'alice'},
      };
    final picked = Completer<String>();
    Json? imported;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HueviaCore.channel, (call) async {
          if (call.method == 'pickFile') {
            expect(call.arguments, {'preset': true});
            return picked.future;
          }
          final args = object(call.arguments),
              payload = object(jsonDecode(args['payload'] as String));
          if (args['operation'] == 'library.import') {
            imported = payload;
            throw PlatformException(code: 'OWNER_CHANGED', message: '账号已改变');
          }
          throw StateError('Unexpected channel operation');
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HueviaCore.channel, null),
    );
    final pending = state.pickPreset();
    final expectation = expectLater(pending, throwsA(isA<AppFailure>()));
    await Future<void>.delayed(Duration.zero);
    state.session = {
      'user': {'id': 'bob'},
    };
    picked.complete(
      jsonEncode({
        'path': p.join(root.path, 'incoming', '${'a' * 64}.ncp'),
        'name': '秋色.NCP',
        'sha256': 'a' * 64,
      }),
    );
    await expectation;
    expect(imported?['name'], '秋色.NCP');
    expect(imported?['owner'], 'alice');
    expect(imported?['path'], startsWith(root.path));
    state.dispose();
  });
  test('Cancelled or invalid native picks cannot register photos outside the private originals', () async {
    final root = Directory.systemTemp.createTempSync('huevia-native-cancel-');
    addTearDown(() => root.deleteSync(recursive: true));
    final core = HueviaCore()..root = root.path;
    var cancelled = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HueviaCore.channel, (call) async {
          expect(call.method, 'pickFile');
          return jsonEncode(
            cancelled
                ? {'cancelled': true}
                : {
                    'path': p.join(root.parent.path, 'outside.nef'),
                    'name': 'outside.nef',
                    'sha256': 'a' * 64,
                  },
          );
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HueviaCore.channel, null),
    );
    final state = AppState(core);
    expect(await state.pickPhoto(), isNull);
    cancelled = false;
    await expectLater(state.pickPhoto(), throwsA(isA<AppFailure>()));
    expect(state.photos, isEmpty);
    expect(File(p.join(root.path, 'photos-index.json')).existsSync(), isFalse);
    state.dispose();
  });
}
