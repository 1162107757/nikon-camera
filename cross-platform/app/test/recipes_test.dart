import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/recipes.dart';
import 'package:huevia/theme.dart';

class RecipeCore extends HueviaCore {
  final List<(String, Json)> calls = [];
  final List<Json> items = [];
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    if (operation == 'recipe.list') return {'items': items};
    if (operation == 'recipe.create') {
      final item = {
        'id': 'saved-id',
        'name': payload['name'],
        'summary': '秋色 · 65% · 调节 2 项',
      };
      items.add(item);
      return item;
    }
    if (operation == 'recipe.apply') {
      return {
        'recipe': {'presetId': 'frozen-preset', 'strength': 65},
      };
    }
    throw AppFailure(operation);
  }
}

void main() {
  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets(
      'Save and apply a recipe at $size with large text and a pinned owner',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final core = RecipeCore();
        Json? applied;
        final current = {
          'strength': 65,
          'geometry': {'turns': 1},
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () async {
                    applied = await Navigator.push<Json>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RecipesPage(
                          core: core,
                          owner: 'alice',
                          path: '/private/source.jpg',
                          current: current,
                        ),
                      ),
                    );
                  },
                  child: const Text('打开配方'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开配方'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('保存当前配方'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), '秋色');
        await tester.ensureVisible(find.text('保存').last);
        await tester.tap(find.text('保存').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final create = core.calls
            .singleWhere((call) => call.$1 == 'recipe.create')
            .$2;
        expect(create['owner'], 'alice');
        expect(create['recipe'], current);
        expect(create['name'], '秋色');
        await tester.ensureVisible(find.text('秋色'));
        await tester.tap(find.text('秋色'));
        await tester.pumpAndSettle();
        expect(applied?['presetId'], 'frozen-preset');
        expect(applied?['strength'], 65);
        expect(core.calls.every((call) => call.$2['owner'] == 'alice'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
