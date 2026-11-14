import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/legacy_theme.dart';
import 'package:huevia/main.dart';

class OverlayCore extends HueviaCore {
  final calls = <(String, Json)>[];
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    switch (operation) {
      case 'photo.stars':
        return {'keys': []};
      case 'gallery.access':
        return {'access': 'none'};
      case 'online.page':
      case 'online.search':
        return {
          'items': [
            {
              'id': 'one',
              'name': '在线样片',
              'fileFormat': 'NCP',
              'sha256': 'a' * 64,
            },
          ],
          'page': 1,
          'hasMore': false,
          'categories': ['人像', '夜景'],
          'available': true,
        };
      default:
        throw AppFailure('Unexpected operation: $operation');
    }
  }
}

void main() {
  for (final scenario in [
    (const Size(375, 812), 1.0),
    (const Size(375, 812), 2.0),
    (const Size(812, 375), 2.0),
  ]) {
    testWidgets(
      'Root sheets cover navigation and retain fixed actions at $scenario',
      (tester) async {
        tester.view.physicalSize = scenario.$1;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scenario.$2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final core = OverlayCore();
        final state = AppState(core)..ready = true;
        await tester.pumpWidget(HueviaApp(state: state));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byTooltip('筛选预设'));
        await tester.tap(find.byTooltip('筛选预设'));
        await tester.pumpAndSettle();
        expect(find.text('相册').hitTestable(), findsNothing);
        expect(find.text('应用').hitTestable(), findsOneWidget);
        await tester.tap(find.text('应用'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('相册').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('排序，拍摄时间，新到旧'));
        await tester.pumpAndSettle();
        expect(find.text('预设').hitTestable(), findsNothing);
        expect(find.text('应用').hitTestable(), findsOneWidget);
        await tester.ensureVisible(find.text('添加时间'));
        await tester.tap(find.text('添加时间'));
        await tester.tap(find.text('应用'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('排序，添加时间，新到旧'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Online download filtering loads the complete catalog and source filters remain separate',
    (tester) async {
      final core = OverlayCore();
      final state = AppState(core)..ready = true;
      await tester.pumpWidget(HueviaApp(state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.text('在线预设'));
      await tester.pumpAndSettle();
      expect(find.text('在线样片'), findsOneWidget);
      await tester.tap(find.byTooltip('筛选预设'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已下载'));
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(core.calls.last.$1, 'online.search');
      expect(find.text('在线样片'), findsNothing);
      await tester.tap(
        find.descendant(
          of: find.byType(CapsuleSwitch),
          matching: find.text('我的预设'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('筛选预设'), findsOneWidget);
      await tester.tap(find.text('在线预设'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('筛选预设，已应用条件'), findsOneWidget);
      expect(find.text('在线样片'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
