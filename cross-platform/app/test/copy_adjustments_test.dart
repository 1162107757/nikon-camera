import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/copy_adjustments.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';

class CopyCore extends HueviaCore {
  final List<(String, Json)> calls = [];
  @override
  Future<void> cancel(String jobId) async {}
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    if (operation == 'photo.copy') {
      return {'changed': 1, 'skipped': 0, 'receipt': 'copy-receipt'};
    }
    if (operation == 'photo.copyUndo') {
      return {'restored': 0, 'changed': 1, 'keptNewer': 1};
    }
    throw AppFailure(operation);
  }
}

void main() {
  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets(
      'Copy scope and owner stay pinned; newer edits survive undo at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('cc.huevia/events'),
              (_) async => null,
            );
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('cc.huevia/events'),
                null,
              ),
        );
        final core = CopyCore(),
            source = const Photo('/originals/source.jpg', '来源.jpg', {
              'width': 256,
              'height': 192,
            });
        final state = AppState(core)
          ..photos = [
            source,
            const Photo('/originals/target.jpg', '目标.jpg', {
              'width': 512,
              'height': 384,
            }),
            const Photo('/originals/raw.nef', '待显影.nef', {'raw': true}),
          ]
          ..session = {
            'user': {'id': 'alice'},
          };
        final recipe = Recipe().data;
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    final result = await Navigator.push<Json>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CopyAdjustmentsPage(
                          state: state,
                          source: source,
                          recipe: recipe,
                          owner: 'alice',
                        ),
                      ),
                    );
                    if (context.mounted && result != null) {
                      showCopyReceipt(context, core, 'alice', result);
                    }
                  },
                  child: const Text('打开复制'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开复制'));
        await tester.pumpAndSettle();
        expect(find.text('待显影.nef'), findsNothing);
        Future<void> tap(String label) async {
          final item = find.text(label);
          if (item.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              item,
              180,
              scrollable: find.byType(Scrollable).last,
            );
          } else {
            await tester.ensureVisible(item);
          }
          await tester.pumpAndSettle();
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }

        await tap('基础调节与去灰');
        await tap('HSL 与调色盘');
        await tap('目标.jpg');
        await tester.tap(find.text('应用到 1 张照片'));
        await tester.pumpAndSettle();
        final payload = core.calls
            .singleWhere((call) => call.$1 == 'photo.copy')
            .$2;
        expect(payload['owner'], 'alice');
        expect(payload['recipe'], recipe);
        expect(payload['paths'], ['/originals/target.jpg']);
        expect(payload['basic'], false);
        expect(payload['curves'], true);
        expect(payload['colour'], false);
        await tester.tap(find.text('撤销'));
        await tester.pumpAndSettle();
        expect(core.calls.last.$1, 'photo.copyUndo');
        expect(core.calls.last.$2['owner'], 'alice');
        expect(find.textContaining('保留了后续修改'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      },
    );
  }
}
