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
  Future<(ExportUiCore, ExportSettings)> open(
    WidgetTester tester, {
    Size size = const Size(412, 892),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final core = ExportUiCore();
    final actual = ExportFormState(core);
    final form = ExportSettings(
      state: actual,
      photo: Photo(core.imageFile.path, 'own.png', {}),
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
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
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
