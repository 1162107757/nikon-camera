import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/legacy_glass_sheet.dart';
import 'package:huevia/legacy_sheets.dart';
import 'package:huevia/photos.dart';
import 'package:huevia/theme.dart';

class _SheetCore extends HueviaCore {
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'photo.stars') return {'keys': <String>[]};
    if (operation == 'gallery.access') return {'access': 'none'};
    throw AppFailure(operation);
  }
}

void main() {
  testWidgets(
    'Repeated apply and back-then-close cannot pop the page under a glass filter',
    (tester) async {
      var applications = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      body: Builder(
                        builder: (page) => TextButton(
                          onPressed: () => showLegacyGlassSheet<void>(
                            page,
                            wrap: false,
                            builder: (sheet) => HueFloatingSheet(
                              title: '筛选',
                              closeLabel: '关闭筛选',
                              onReset: () {},
                              onApply: () {
                                applications++;
                                Navigator.pop(sheet);
                              },
                              children: const [Text('选项')],
                            ),
                          ),
                          child: const Text('打开筛选'),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('进入相册'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('进入相册'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开筛选'));
      await tester.pumpAndSettle();
      final apply = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '应用'))
          .onPressed!;
      apply();
      apply();
      await tester.pumpAndSettle();
      expect(applications, 1);
      expect(find.text('打开筛选'), findsOneWidget);
      await tester.tap(find.text('打开筛选'));
      await tester.pumpAndSettle();
      final close = tester
          .widget<HueIconButton>(
            find.byWidgetPredicate(
              (w) => w is HueIconButton && w.label == '关闭筛选',
            ),
          )
          .onPressed!;
      await tester.binding.handlePopRoute();
      close();
      await tester.pumpAndSettle();
      expect(find.text('打开筛选'), findsOneWidget);
      expect(applications, 1);
    },
  );
  for (final viewport in [
    (const Size(375, 812), Brightness.light, 1.0),
    (const Size(812, 375), Brightness.dark, 2.0),
  ]) {
    testWidgets(
      'Glass sorting keeps actions reachable and discards unapplied changes at $viewport',
      (tester) async {
        tester.view.physicalSize = viewport.$1;
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final state = AppState(_SheetCore())
          ..photos = [const Photo('/unavailable/a.jpg', 'a.jpg', {})];
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(viewport.$2),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(viewport.$3),
                disableAnimations: true,
                padding: const EdgeInsets.only(top: 24, bottom: 20),
              ),
              child: child!,
            ),
            home: PhotosPage(state: state),
          ),
        );
        await tester.pumpAndSettle();
        Future<void> open() async {
          await tester.tap(find.byTooltip('排序，拍摄时间，新到旧'));
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: find.byType(LegacyGlassSheet),
              matching: find.byType(BackdropFilter),
            ),
            findsOneWidget,
          );
          expect(
            tester.getBottomRight(find.widgetWithText(FilledButton, '应用')).dy,
            lessThan(viewport.$1.height - 10),
          );
        }

        await open();
        await tester.ensureVisible(find.text('旧到新'));
        await tester.tap(find.text('旧到新'));
        await tester.tap(find.byTooltip('关闭排序，放弃未应用修改'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('排序，拍摄时间，新到旧'), findsOneWidget);
        await open();
        await tester.ensureVisible(find.text('旧到新'));
        await tester.tap(find.text('旧到新'));
        await tester.tap(find.text('应用'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('排序，拍摄时间，旧到新'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      },
    );
  }

  testWidgets(
    'Shared tool host respects a non-dismissible operation and system back closes only its sheet',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showLegacyGlassSheet<void>(
                  context,
                  isDismissible: false,
                  enableDrag: false,
                  builder: (_) => const SizedBox(
                    height: 200,
                    child: Center(child: Text('进行中的操作')),
                  ),
                ),
                child: const Text('打开工具'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开工具'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('进行中的操作'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('进行中的操作'), findsNothing);
      expect(find.text('打开工具'), findsOneWidget);
    },
  );
}
