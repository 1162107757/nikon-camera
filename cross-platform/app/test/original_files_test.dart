import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_raw_pairing.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/original_files.dart';
import 'package:huevia/original_save.dart';
import 'package:huevia/original_targets.dart';
import 'package:huevia/theme.dart';
import 'package:path/path.dart' as p;

class FilesCore extends HueviaCore {
  FilesCore() {
    root = p.join(Directory.systemTemp.path, 'huevia-raw-pairing');
  }
  final calls = <(String, Json)>[];
  bool fail = false, badReceipt = false;
  int permissions = 0;
  @override
  Stream<dynamic> get operationProgress => const Stream<dynamic>.empty();
  @override
  Future<Json> gallerySavePermission() async {
    permissions++;
    throw StateError('Files must not require Photos permission');
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, Map<String, dynamic>.from(payload)));
    if (operation == 'source.inspect') {
      return {
        'path': '/own/originals/${'a' * 64}.nef',
        'sourceSha': 'a' * 64,
        'bytes': 100,
        'format': 'NEF',
      };
    }
    if (operation == 'files.publishOriginal') {
      if (fail) throw const AppFailure('provider unavailable');
      return {
        'published': true,
        'uri': 'content://documents/raw',
        'targetId': payload['targetId'],
        'sha256': badReceipt ? 'b' * 64 : payload['expectedSourceSha'],
        'bytes': 100,
        'verified': true,
      };
    }
    if (operation == 'camera.raw.pair') {
      return {
        'session': 'camera',
        'pairId': 'pair',
        'cameraId': 'c' * 64,
        'jpegDescriptor': 'd' * 64,
        'matchedHandle': 0,
        'objects': 3,
        'rawCount': 2,
        'reason': '多个同名 RAW，请明确选择',
        'hasMore': false,
        'items': [
          {
            'handle': 2,
            'descriptor': 'e' * 64,
            'name': 'DSC_0042.NEF',
            'raw': true,
            'storage': 1,
            'capturedAt': '20261113T123000',
            'sequence': 42,
            'bytes': 100,
          },
          {
            'handle': 3,
            'descriptor': 'f' * 64,
            'name': 'DSC_0042.NEF',
            'raw': true,
            'storage': 2,
            'capturedAt': '20261113T123000',
            'sequence': 42,
            'bytes': 100,
          },
        ],
      };
    }
    if (operation == 'camera.raw.select') return {'session': 'camera'};
    if (operation == 'camera.download') {
      return {
        'path': p.join(root, 'originals', '${'a' * 64}.nef'),
        'name': 'DSC_0042.NEF',
        'sha256': 'a' * 64,
        'bytes': 100,
        'raw': true,
        'downloadCameraId': 'c' * 64,
        'downloadTrusted': true,
        'descriptor': 'e' * 64,
        'storage': 1,
      };
    }
    if (operation == 'media.info') {
      return {'raw': true, 'width': 2, 'height': 2};
    }
    throw StateError('Unexpected request $operation');
  }
}

class PairState extends AppState {
  PairState(super.core, {required bool proven}) {
    photos = [
      Photo(p.join(core.root, 'originals', '${'b' * 64}.jpg'), 'DSC_0042.JPG', {
        if (proven)
          'cameraSource': {'cameraId': 'c' * 64, 'descriptor': 'd' * 64},
      }),
    ];
  }
  int associations = 0;
  @override
  Future<Photo> registerPhoto(String path, String name, Json info) async {
    final photo = Photo(path, name, info);
    photos = [photo, ...photos];
    notifyListeners();
    return photo;
  }

  @override
  Future<Photo> updatePhoto(Photo photo, Json metadata) async {
    associations++;
    final updated = Photo(photo.path, photo.name, metadata);
    photos = photos
        .map((entry) => entry.path == photo.path ? updated : entry)
        .toList();
    notifyListeners();
    return updated;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(OriginalFiles.channel, null);
  });

  test('Files retry keeps the chosen target and operation and requires SHA readback', () async {
    final core = FilesCore();
    final actual = AppState(core);
    final save = OriginalSave(
      actual,
      '',
      '/own/source.nef',
      'a' * 64,
      'DSC.NEF',
      targetId: 'f' * 32,
    );
    core.fail = true;
    await save.run();
    expect(save.done, false);
    final first = core.calls.single;
    core.fail = false;
    core.badReceipt = true;
    await save.run();
    expect(save.done, false);
    expect(save.error, contains('读回'));
    core.badReceipt = false;
    await save.run();
    expect(save.done, true);
    expect(core.permissions, 0);
    expect(
      core.calls.every(
        (call) =>
            call.$1 == 'files.publishOriginal' &&
            call.$2['targetId'] == 'f' * 32 &&
            call.$2['operationId'] == first.$2['operationId'],
      ),
      true,
    );
    save.dispose();
    actual.dispose();
  });

  test('folder picker returns only an opaque persisted target ID', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(OriginalFiles.channel, (call) async {
          expect(call.method, 'chooseTarget');
          expect(call.arguments, {'owner': 'owner'});
          return jsonEncode({'id': 'f' * 32, 'name': 'Camera originals'});
        });
    final target = await OriginalFiles.chooseTarget('owner');
    expect(target, {'id': 'f' * 32, 'name': 'Camera originals'});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          OriginalFiles.channel,
          (_) async => jsonEncode({'id': '/external/arbitrary', 'name': 'bad'}),
        );
    await expectLater(
      OriginalFiles.chooseTarget('owner'),
      throwsA(isA<AppFailure>()),
    );
  });

  testWidgets(
    'NEF destination page offers app, exact Photos and persisted Files',
    (tester) async {
      final core = FilesCore();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            OriginalFiles.channel,
            (_) async => jsonEncode({'id': 'f' * 32, 'name': 'RAW folder'}),
          );
      await tester.pumpWidget(
        MaterialApp(
          home: OriginalTargetsPage(
            state: AppState(core),
            source: '/own/source.nef',
            sourceSha: 'a' * 64,
            filename: 'DSC.NEF',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('应用相册'), findsOneWidget);
      expect(find.text('手机系统相册'), findsOneWidget);
      expect(find.text('Files / 文件夹'), findsOneWidget);
      await tester.tap(find.text('Files / 文件夹'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('选择文件夹'));
      await tester.tap(find.text('选择文件夹'));
      await tester.pumpAndSettle();
      expect(find.text('RAW folder'), findsOneWidget);
      final publish = find.text('确认保存 NEF 原文件');
      await tester.ensureVisible(publish);
      await tester.tap(publish);
      await tester.pumpAndSettle();
      expect(
        core.calls.where((call) => call.$1 == 'files.publishOriginal'),
        hasLength(1),
      );
      expect(core.permissions, 0);
      expect(find.text('原始文件已保存并保留完整格式。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'ambiguous RAW inventory never downloads until explicit selection and confirmation',
    (tester) async {
      final core = FilesCore();
      await tester.pumpWidget(
        MaterialApp(
          home: CameraRawPairingPage(
            state: AppState(core),
            session: 'camera',
            jpegHandle: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final receive = find.widgetWithText(FilledButton, '接收所选 NEF 原文件');
      await tester.scrollUntilVisible(find.text('接收所选 NEF 原文件'), 150);
      expect(tester.widget<FilledButton>(receive).onPressed, isNull);
      expect(core.calls.map((call) => call.$1), ['camera.raw.pair']);
      await tester.ensureVisible(find.text('DSC_0042.NEF').first);
      await tester.tap(find.text('DSC_0042.NEF').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(receive);
      await tester.tap(receive);
      await tester.pumpAndSettle();
      expect(find.text('接收 DSC_0042.NEF？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(core.calls.map((call) => call.$1), ['camera.raw.pair']);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  for (final proven in [true, false]) {
    testWidgets(
      'RAW association uses complete camera evidence: proven=$proven',
      (tester) async {
        final core = FilesCore();
        final actual = PairState(core, proven: proven);
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.light),
            home: CameraRawPairingPage(
              state: actual,
              session: 'camera',
              jpegHandle: 1,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('DSC_0042.NEF').first);
        await tester.pumpAndSettle();
        final receive = find.text('接收所选 NEF 原文件');
        await tester.ensureVisible(receive);
        await tester.tap(receive);
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认接收此 RAW'));
        await tester.pumpAndSettle();
        // Subscription cancellation may complete on the real engine event loop.
        await tester.runAsync(() async {
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(
          core.calls.where((call) => call.$1 == 'camera.download'),
          hasLength(1),
        );
        final jpeg = actual.photos.singleWhere(
          (photo) => photo.name.endsWith('.JPG'),
        );
        if (proven) {
          expect(actual.associations, 1);
          expect(jpeg.info['rawSourceSha'], 'a' * 64);
          expect(object(jpeg.info['rawPairing'])['rawDescriptor'], 'e' * 64);
          expect(object(jpeg.info['rawPairing'])['explicitSelection'], true);
        } else {
          expect(actual.associations, 0);
          expect(jpeg.info.containsKey('rawSource'), false);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        actual.dispose();
      },
    );
  }
}
