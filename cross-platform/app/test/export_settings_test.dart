import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/export_settings.dart';
import 'package:huevia/export_settings_model.dart';
import 'package:huevia/theme.dart';

import 'export_settings_model_test.dart' show ExportFormCore, ExportFormState;

class ExportUiCore extends ExportFormCore {
  ExportUiCore() {
    root = directory.path;
    imageFile.writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
      ),
    );
  }
  final directory = Directory.systemTemp.createTempSync(
    'huevia-export-settings-',
  );
  late final imageFile = File('${directory.path}/source.png');
  int copies = 0;
  String originalFormat = 'PNG';
  bool failOriginal = false;
  Completer<Json>? pendingInspection;
  @override
  Future<Json> gallerySavePermission() async => {'granted': true};
  String copy() =>
      imageFile.copySync('${directory.path}/preview-${copies++}.png').path;
  void cleanup() {
    for (final file in directory.listSync()) {
      if (file is File) file.deleteSync();
    }
    directory.deleteSync();
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'source.inspect') {
      calls.add((operation, exportCopy(payload), jobId));
      if (pendingInspection != null) return pendingInspection!.future;
      return {
        'path': imageFile.path,
        'sourceSha': source,
        'format': originalFormat,
      };
    }
    if (operation == 'gallery.publishOriginal') {
      calls.add((operation, exportCopy(payload), jobId));
      if (failOriginal) throw const AppFailure('test storage full');
      return {'published': true, 'uri': 'content://own/1'};
    }
    if (operation.startsWith('media.exportPreview')) {
      calls.add((operation, exportCopy(payload), jobId));
      if (operation == 'media.exportPreview') {
        return {
          'id': 'test-session',
          'width': 1200,
          'height': 934,
          'bytes': 1024,
          'quality': 95,
          'overview': copy(),
        };
      }
      if (operation == 'media.exportPreviewFrame') {
        return {'before': copy(), 'jpeg': copy()};
      }
      if (operation == 'media.exportPreviewClose') return {};
      throw StateError('A review must never commit');
    }
    return super.call(operation, payload, jobId);
  }
}

void main() {
  Future<void> reach(WidgetTester tester, Finder destination) async {
    // Route completion and the next page's async work can finish after the
    // transition's last scheduled frame on a real device under build load.
    for (
      var attempt = 0;
      attempt < 50 && destination.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(destination, findsWidgets);
    await tester.pumpAndSettle();
  }

  Future<(ExportUiCore, ExportSettings)> open(
    WidgetTester tester, {
    Size size = const Size(412, 892),
    double textScale = 1,
    String name = 'own.png',
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final core = ExportUiCore();
    core.originalFormat = name.endsWith('.jpg') ? 'JPG' : 'PNG';
    final actual = ExportFormState(core);
    final form = ExportSettings(
      state: actual,
      photo: Photo(core.imageFile.path, name, {}),
      owner: '',
      recipe: {
        'schema': 1,
        'border': {'template': 3},
      },
      isCurrent: () => true,
    );
    addTearDown(() {
      form.dispose();
      actual.dispose();
      core.cleanup();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showLegacyExport(context, form),
              child: const Text('打开导出'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开导出'));
    await tester.pumpAndSettle();
    return (core, form);
  }

  testWidgets(
    'original JPEG confirmation can be cancelled without saving or changing settings',
    (tester) async {
      final (core, form) = await open(tester, name: 'own.jpg');
      await tester.tap(find.text('更多设置'));
      await reach(tester, find.text('JPEG'));
      await tester.ensureVisible(find.text('原始文件'));
      await tester.ensureVisible(find.text('JPEG').last);
      await tester.tap(find.text('JPEG').last);
      await reach(tester, find.text('保存 JPEG 原始文件？'));
      expect(find.text('保存 JPEG 原始文件？'), findsOneWidget);
      expect(find.textContaining('可能包含定位'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(
        core.calls.where((c) => c.$1 == 'gallery.publishOriginal'),
        isEmpty,
      );
      expect(form.chosen.single.id, 'current');
      expect(find.text('打开导出'), findsOneWidget);
      expect(find.text('完整尺寸'), findsNothing);
    },
  );

  testWidgets(
    'confirmed original JPEG saves directly and retries the same task without rendering',
    (tester) async {
      final (core, form) = await open(
        tester,
        name: 'own.jpg',
        size: const Size(320, 568),
        textScale: 1.6,
      );
      core.failOriginal = true;
      await tester.ensureVisible(find.text('更多设置'));
      await tester.tap(find.text('更多设置'));
      await reach(tester, find.text('JPEG'));
      await tester.ensureVisible(find.text('JPEG').last);
      await tester.tap(find.text('JPEG').last);
      await reach(tester, find.text('保存原始文件'));
      await tester.ensureVisible(find.text('保存原始文件'));
      await tester.tap(find.text('保存原始文件'));
      await reach(tester, find.text('重试保存'));
      expect(find.text('test storage full'), findsOneWidget);
      final first = core.calls
          .singleWhere((c) => c.$1 == 'gallery.publishOriginal')
          .$2;
      core.failOriginal = false;
      await tester.tap(find.text('重试保存'));
      await tester.pumpAndSettle();
      expect(find.text('已保存到手机相册'), findsOneWidget);
      expect(
        core.calls.where((c) => c.$1 == 'gallery.publishOriginal').last.$2,
        first,
      );
      expect(core.calls.where((c) => c.$1.startsWith('media.export')), isEmpty);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(form.chosen.single.id, 'current');
      expect(find.text('打开导出'), findsOneWidget);
      expect(find.text('完整尺寸'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late original inspection cannot open a confirmation after leaving its editor route',
    (tester) async {
      final (core, _) = await open(tester, name: 'own.jpg');
      await tester.tap(find.text('更多设置'));
      await reach(tester, find.text('JPEG'));
      await tester.ensureVisible(find.text('JPEG').last);
      core.pendingInspection = Completer<Json>();
      await tester.tap(find.text('JPEG').last);
      await reach(tester, find.text('打开导出'));
      Navigator.of(tester.element(find.text('打开导出'))).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('另一个页面')),
        ),
      );
      core.pendingInspection!.complete({
        'path': core.imageFile.path,
        'sourceSha': core.source,
        'format': 'JPG',
      });
      await tester.pumpAndSettle();
      expect(find.text('保存 JPEG 原始文件？'), findsNothing);
      expect(find.text('另一个页面'), findsOneWidget);
      expect(
        core.calls.where((c) => c.$1 == 'gallery.publishOriginal'),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'quick export restores original qualities and versions and reopens the same selections',
    (tester) async {
      final (core, form) = await open(tester);
      for (final label in ['当前编辑', '原图', '保存的胶片', '轻量', '均衡', '高清', '原画']) {
        expect(find.text(label), findsWidgets);
      }
      await tester.tap(find.text('原图'));
      await tester.pumpAndSettle();
      expect(form.selected, {'current', 'original'});
      await tester.tap(find.text('更多设置'));
      await reach(tester, find.text('完整尺寸'));
      expect(find.text('1200 × 934 px'), findsOneWidget);
      expect(find.text('1200 × 800 px'), findsOneWidget);
      await tester.tap(find.text('更改导出版本'));
      await tester.pumpAndSettle();
      expect(form.selected, {'current', 'original'});
      expect(find.text('导出版本 · 可多选'), findsOneWidget);
      expect(core.calls.map((c) => c.$1), isNot(contains('draft.save')));
      await tester.ensureVisible(find.byTooltip('取消导出，返回照片'));
      await tester.tap(find.byTooltip('取消导出，返回照片'));
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'preview Done returns to custom settings without committing or resetting inputs',
    (tester) async {
      final (core, _) = await open(tester);
      await tester.tap(find.text('更多设置'));
      await reach(tester, find.text('自定义'));
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '1000');
      await tester.enterText(find.byType(TextField).last, '88');
      await tester.ensureVisible(find.text('查看成品预览'));
      await tester.tap(find.text('查看成品预览'));
      await tester.pumpAndSettle();
      expect(
        core.calls.lastWhere((c) => c.$1 == 'media.exportPreview').$2,
        containsPair('snapshot', true),
      );
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.text('自定义'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1000'), findsOneWidget);
      expect(find.widgetWithText(TextField, '88'), findsOneWidget);
      expect(
        core.calls.any(
          (c) => [
            'media.exportPreviewCommit',
            'media.export',
            'gallery.publish',
            'draft.save',
          ].contains(c.$1),
        ),
        false,
      );
      expect(core.calls.any((c) => c.$1 == 'media.exportPreviewClose'), true);
      await tester.tap(find.byTooltip('取消导出'));
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'slow version inspection keeps the quick modal open and a close cannot later open advanced settings',
    (tester) async {
      final (core, form) = await open(tester);
      await tester.tap(find.text('保存的胶片'));
      core.pendingRecipe = Completer<Json>();
      await tester.tap(find.text('更多设置'));
      await tester.pump();
      expect(form.freezing, true);
      expect(find.text('导出版本 · 可多选'), findsOneWidget);
      expect(find.text('完整尺寸'), findsNothing);
      await tester.ensureVisible(find.byTooltip('取消导出，返回照片'));
      await tester.tap(find.byTooltip('取消导出，返回照片'));
      core.pendingRecipe!.complete({
        'sourceSha': core.source,
        'recipe': core.savedRecipe,
      });
      await tester.pumpAndSettle();
      expect(find.text('打开导出'), findsOneWidget);
      expect(find.text('完整尺寸'), findsNothing);
      expect(core.calls.any((c) => c.$1 == 'media.export'), false);
    },
  );
  testWidgets(
    'narrow enlarged-text quick export scrolls every version and confirmation into view',
    (tester) async {
      await open(tester, size: const Size(320, 568), textScale: 1.6);
      await tester.ensureVisible(find.text('导出到手机相册'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byTooltip('取消导出，返回照片'));
      await tester.tap(find.byTooltip('取消导出，返回照片'));
      await tester.pumpAndSettle();
    },
  );
}
