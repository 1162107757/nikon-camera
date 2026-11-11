import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/preview_templates.dart';
import 'package:huevia/theme.dart';

class TemplateCore extends HueviaCore {
  int picks = 0, updates = 0;
  @override
  Future<Json?> pickFile({required bool preset}) async {
    expect(preset, false);
    picks++;
    return picks == 1 ? null : {'path': '/private/originals/template.jpg'};
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'media.templateSet') {
      expect(payload['path'], '/private/originals/template.jpg');
      customTemplate = true;
      updates++;
    }
    if (operation == 'media.templateReset') customTemplate = false;
    if (operation == 'media.templateSource') {
      return {'path': '/missing/preview.jpg', 'label': '模板照片'};
    }
    return {
      'custom': customTemplate,
      'count': customTemplate ? 1 : 10,
      'version': '$updates',
    };
  }
}

void main() {
  testWidgets(
    'Template selection uses streamed native picking, handles cancellation and restores built-ins',
    (tester) async {
      final core = TemplateCore();
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: PreviewTemplatesPage(core: core),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('从手机选择模板图'));
      await tester.pumpAndSettle();
      expect(core.picks, 1);
      expect(core.updates, 0);
      expect(find.text('内置摄影样片 · 10 张'), findsOneWidget);
      await tester.tap(find.text('从手机选择模板图'));
      await tester.pumpAndSettle();
      expect(core.picks, 2);
      expect(core.updates, 1);
      expect(find.text('自选模板'), findsOneWidget);
      await tester.tap(find.text('恢复内置摄影样片'));
      await tester.pumpAndSettle();
      expect(find.text('内置摄影样片 · 10 张'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
