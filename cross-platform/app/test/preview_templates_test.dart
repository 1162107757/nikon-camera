import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/preview_templates.dart';
import 'package:huevia/theme.dart';

class TemplateCore extends HueviaCore {
  int picks = 0, updates = 0;
  bool storedCustom = false;
  final operations = <String>[];
  @override
  Future<Json?> pickFile({required bool preset}) async {
    expect(preset, false);
    picks++;
    return picks == 1 ? null : {'path': '/private/originals/template.jpg'};
  }

  Future<String> nativeRequest(MethodCall call) async {
    expect(call.method, 'request');
    final arguments = object(call.arguments);
    final operation = arguments['operation'] as String;
    final payload = object(jsonDecode(arguments['payload'] as String));
    operations.add(operation);
    expect(
      operation,
      isIn(['media.templateInfo', 'media.templateSet', 'media.templateReset']),
      reason: 'Template settings must not request standalone sample rendering',
    );
    if (operation == 'media.templateSet') {
      expect(payload['path'], '/private/originals/template.jpg');
      storedCustom = true;
      updates++;
    }
    if (operation == 'media.templateReset') storedCustom = false;
    return jsonEncode({
      'custom': storedCustom,
      'count': storedCustom ? 1 : 10,
      'version': '$updates',
    });
  }
}

void main() {
  void bind(TemplateCore core) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HueviaCore.channel, core.nativeRequest);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HueviaCore.channel, null),
    );
  }

  testWidgets(
    'the full restore button stays above system navigation with large text in a short viewport',
    (tester) async {
      tester.view.devicePixelRatio = 2.7;
      tester.view.physicalSize = const Size(1080, 900);
      tester.view.viewPadding = const FakeViewPadding(top: 63, bottom: 126);
      tester.view.padding = const FakeViewPadding(top: 63, bottom: 126);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetPadding);
      final core = TemplateCore()..storedCustom = true;
      bind(core);
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: PreviewTemplatesPage(core: core),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      final list = find.byType(ListView);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      );
      expect(
        scrollable.position.maxScrollExtent,
        greaterThan(0),
        reason: 'Large text must require real scrolling in a short viewport',
      );
      await tester.drag(list, const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(
        scrollable.position.pixels,
        closeTo(scrollable.position.maxScrollExtent, .1),
      );
      final restore = find.byType(OutlinedButton);
      final bounds = tester.getRect(restore);
      final systemTop =
          (tester.view.physicalSize.height - tester.view.viewPadding.bottom) /
          tester.view.devicePixelRatio;
      expect(
        MediaQuery.viewPaddingOf(tester.element(find.byType(Scaffold))).bottom,
        greaterThan(0),
      );
      expect(
        bounds.bottom,
        lessThanOrEqualTo(systemTop),
        reason: 'The entire restore action must remain above the system navigation bar',
      );
      expect(tester.widget<OutlinedButton>(restore).onPressed, isNotNull);
      await tester.tap(restore);
      await tester.pumpAndSettle();
      expect(core.customTemplate, isFalse);
      expect(find.text('查看下一张样片'), findsNothing);
      expect(core.operations, isNot(contains('media.templateSource')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Template selection uses streamed native picking, handles cancellation and restores built-ins',
    (tester) async {
      final core = TemplateCore();
      bind(core);
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: PreviewTemplatesPage(core: core),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('查看下一张样片'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.text('模板照片'), findsNothing);
      expect(core.operations, ['media.templateInfo']);
      final initialRevision = core.previewRevision.value;
      expect(find.text('从手机选择模板图'), findsOneWidget);
      expect(find.text('恢复内置摄影样片'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('从手机选择模板图'));
      await tester.pumpAndSettle();
      expect(core.picks, 1);
      expect(core.updates, 0);
      expect(core.previewRevision.value, initialRevision);
      expect(find.text('内置摄影样片 · 10 张'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      await tester.tap(find.text('从手机选择模板图'));
      await tester.pumpAndSettle();
      expect(core.picks, 2);
      expect(core.updates, 1);
      expect(core.previewRevision.value, greaterThan(initialRevision));
      final customRevision = core.previewRevision.value;
      expect(find.text('自选模板'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
      await tester.tap(find.text('恢复内置摄影样片'));
      await tester.pumpAndSettle();
      expect(find.text('内置摄影样片 · 10 张'), findsOneWidget);
      expect(core.previewRevision.value, greaterThan(customRevision));
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      expect(find.text('查看下一张样片'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(core.operations, [
        'media.templateInfo',
        'media.templateSet',
        'media.templateInfo',
        'media.templateReset',
        'media.templateInfo',
      ]);
      expect(tester.takeException(), isNull);
    },
  );
}
