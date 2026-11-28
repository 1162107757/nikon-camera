import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/album_batch_presets.dart';
import 'package:huevia/album_selection_actions.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';
import 'package:path/path.dart' as p;

import 'album_preset_preview_test.dart' show AlbumPresetPreviewTestCore;

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAEklEQVR4nGMQWm3yHx9mGBkKAKq5fAFPbl0bAAAAAElFTkSuQmCC',
);

class _Core extends AlbumPresetPreviewTestCore {
  final exports = <Json>[];
  final publications = <Json>[];
  Completer<void>? holdExport;
  bool saveAllowed = true;
  @override
  Future<Json> gallerySavePermission() async => {'granted': saveAllowed};
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'gallery.thumbnail') return {'path': importedPath};
    if (operation == 'media.export') {
      exports.add(object(jsonDecode(jsonEncode(payload))));
      if (holdExport != null) {
        final held = holdExport!;
        holdExport = null;
        await held.future;
      }
      final file = File(
        p.join(root, 'photo-versions', '${exports.length}.png'),
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(_png);
      return {'path': file.path, 'id': 'version-${exports.length}'};
    }
    if (operation == 'gallery.publish') {
      publications.add(object(payload));
      return {
        'published': true,
        'identifier': 'saved-${publications.length}',
        'filename': payload['filename'],
      };
    }
    return super.call(operation, payload, jobId);
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var n = 0; n < 120 && !ready(); n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    ready(),
    isTrue,
    reason: 'Bounded asynchronous UI operation completed',
  );
}

void main() {
  testWidgets(
    'B toolbar keeps two independent visible actions and touch targets at large text',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var presets = 0, exports = 0;
      for (final theme in [Brightness.light, Brightness.dark]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(theme),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.8)),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: AlbumSelectionActions(
                  count: 3,
                  onPreset: () => presets++,
                  onExport: () => exports++,
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('套用预设'));
        await tester.tap(find.byKey(const ValueKey('album-export-circle')));
        expect(
          tester.getSize(find.byKey(const Key('album-apply-presets'))).height,
          greaterThanOrEqualTo(48),
        );
        expect(tester.takeException(), isNull);
      }
      expect(presets, 2);
      expect(exports, 2);
    },
  );

  for (final phone in [false, true]) {
    testWidgets(
      '${phone ? 'Phone' : 'App'} batch sheet previews without committing, then exports shared preset copies',
      (tester) async {
        final dir = Directory.systemTemp.createTempSync('huevia-album-b-ui-');
        final core = _Core()
          ..root = dir.resolveSymbolicLinksSync()
          ..platform = phone ? 'ios' : 'android';
        final files = <File>[];
        for (var i = 0; i < 2; i++) {
          final file = File(p.join(core.root, 'originals', '$i.jpg'));
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(_png);
          files.add(file);
        }
        core.importedPath = files.first.path;
        final state = AppState(core)
          ..session = {
            'user': {'id': 'account-a'},
          }
          ..photos = files
              .map(
                (f) => Photo(f.path, p.basename(f.path), {
                  'width': 8,
                  'height': 8,
                }),
              )
              .toList()
          ..presets = [
            Preset({
              'id': 'b' * 64,
              'displayName': '暖调胶片',
              'fileFormat': 'NCP',
            }),
          ];
        final rows = [
          for (var i = 0; i < 2; i++)
            <String, dynamic>{
              'id': phone ? 'phone-$i' : files[i].path,
              'name': '$i.jpg',
            },
        ];
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          state.dispose();
          await tester.runAsync(() => dir.delete(recursive: true));
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.light).copyWith(
              platform: phone ? TargetPlatform.iOS : TargetPlatform.android,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      showAlbumBatchPresets(context, state, rows, phone: phone),
                  child: const Text('原相册'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('原相册'));
        await tester.pumpAndSettle();
        expect(find.text('批量套用预设'), findsOneWidget);
        await _until(
          tester,
          () => core.calls.any((c) => c.operation == 'media.reviewPreview'),
        );
        await tester.tap(find.text('暖调胶片'));
        await _until(tester, () {
          final button = tester.widget<FilledButton>(
            find.byKey(const Key('album-batch-preset-run')),
          );
          return button.onPressed != null;
        });
        expect(core.exports, isEmpty);
        expect(
          core.calls.where(
            (c) =>
                c.operation == 'draft.save' || c.operation == 'media.preview',
          ),
          isEmpty,
        );
        // Closing only the sheet preserves the caller and starts no task.
        await tester.tap(find.byTooltip('关闭批量预设'));
        await tester.pumpAndSettle();
        expect(find.text('原相册'), findsOneWidget);
        expect(core.exports, isEmpty);
        await tester.tap(find.text('原相册'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('暖调胶片'));
        await _until(
          tester,
          () =>
              tester
                  .widget<FilledButton>(
                    find.byKey(const Key('album-batch-preset-run')),
                  )
                  .onPressed !=
              null,
        );
        core.saveAllowed = false;
        await tester.tap(find.byKey(const Key('album-batch-preset-run')));
        await _until(tester, () => find.text('新建批量任务').evaluate().isNotEmpty);
        expect(core.exports, isEmpty);
        final reset = tester
            .widget<TextButton>(
              find.ancestor(
                of: find.text('新建批量任务'),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed!;
        reset();
        reset();
        await _until(tester, () => find.text('我的预设').evaluate().isNotEmpty);
        core.saveAllowed = true;
        await tester.tap(find.text('暖调胶片'));
        await _until(
          tester,
          () =>
              tester
                  .widget<FilledButton>(
                    find.byKey(const Key('album-batch-preset-run')),
                  )
                  .onPressed !=
              null,
        );
        final held = Completer<void>();
        core.holdExport = held;
        await tester.tap(find.byKey(const Key('album-batch-preset-run')));
        await _until(tester, () => core.exports.isNotEmpty);
        expect(find.text('停止处理'), findsOneWidget);
        expect(find.text('我的预设'), findsNothing);
        held.complete();
        await _until(
          tester,
          () => find.text('已保存 2 张照片').evaluate().isNotEmpty,
        );
        expect(core.exports, hasLength(2));
        expect(core.publications, hasLength(2));
        expect(
          core.exports.every(
            (v) => object(v['recipe'])['presetId'] == 'b' * 64,
          ),
          isTrue,
        );
        expect(core.publications.every((v) => v['extraCopy'] == true), isTrue);
        expect(
          files.every((f) => f.readAsBytesSync().length == _png.length),
          isTrue,
        );
        if (phone) {
          await tester.ensureVisible(find.text('查看结果'));
          await tester.tap(find.text('查看结果'));
          await tester.pumpAndSettle();
          expect(find.byType(InteractiveViewer), findsOneWidget);
          state.session = {
            'user': {'id': 'different-owner'},
          };
          state.notifyListeners();
          await tester.pumpAndSettle();
          expect(find.byType(InteractiveViewer), findsNothing);
          expect(find.text('账号已改变，照片预览已关闭。'), findsOneWidget);
          await tester.tap(find.text('关闭').last);
          await tester.pumpAndSettle();
          expect(find.text('账号已改变，请关闭后重新选择照片。'), findsOneWidget);
          await tester.tap(find.text('关闭'));
          await tester.pumpAndSettle();
        } else {
          await _until(tester, () => find.text('完成').evaluate().isNotEmpty);
          await tester.tap(find.text('完成'));
          await tester.pumpAndSettle();
        }
        expect(find.text('原相册'), findsOneWidget);
        // The sheet must bind to the selecting account before its first frame.
        await tester.tap(find.text('原相册'));
        state.session = {
          'user': {'id': 'changed-before-sheet-frame'},
        };
        state.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.text('账号已改变，请关闭后重新选择照片。'), findsOneWidget);
        expect(find.byType(AlbumBatchPresets), findsNothing);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
