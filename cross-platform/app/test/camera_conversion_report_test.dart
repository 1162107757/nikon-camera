import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_conversion_report.dart';
import 'package:huevia/theme.dart';

void main() {
  for (final size in [const Size(320, 720), const Size(812, 375)]) {
    testWidgets(
      'NP3 table wraps long unsupported fields without blocking confirmation at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var writes = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: AlertDialog(
                title: const Text('写入 C1？'),
                content: const SingleChildScrollView(
                  child: CameraConversionReport(
                    report: {
                      'omitted': ['灵活色彩全局饱和度：NCP 不支持，已忽略', '未识别的扩展参数：已忽略'],
                      'approximated': ['灵活色彩的对比度、高光、阴影、白色、黑色合成为近似明暗曲线'],
                      'retained': ['原始自定义明暗曲线', '锐化'],
                    },
                  ),
                ),
                actions: [
                  FilledButton(
                    onPressed: () => writes++,
                    child: const Text('确认写入此槽位'),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('np3-compatibility-table')),
          findsOneWidget,
        );
        expect(find.text('跳过'), findsNWidgets(2));
        expect(writes, 0);
        final action = find.widgetWithText(FilledButton, '确认写入此槽位');
        expect(action.hitTestable(), findsOneWidget);
        await tester.tap(action);
        expect(writes, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
