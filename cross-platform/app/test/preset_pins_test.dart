import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/library.dart';
import 'package:huevia/theme.dart';

class PinCore extends HueviaCore {
  final rows = [
    for (final entry in [('a', '第一款'), ('b', '第二款')])
      <String, dynamic>{
        'id': entry.$1 * 64,
        'displayName': entry.$2,
        'fileFormat': 'NCP',
        'category': '',
        'pinned': false,
      },
  ];
  final List<Json> writes = [];
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'library.pin') {
      writes.add(Map.of(payload));
      final row = rows.firstWhere((row) => row['id'] == payload['id']);
      row['pinned'] = payload['pinned'];
      rows.remove(row);
      rows.insert(0, row);
      return row;
    }
    if (operation == 'library.list') return {'items': rows};
    throw const AppFailure('No preview in pin test');
  }
}

void main() {
  testWidgets(
    'Long-press can pin multiple presets and shows their persisted state',
    (tester) async {
      final core = PinCore();
      final actual = AppState(core)
        ..presets = core.rows.map((row) => Preset(Map.of(row))).toList();
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: LibraryPage(state: actual),
        ),
      );
      await tester.longPress(find.text('第二款'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('preset-context-menu')), findsOneWidget);
      expect(find.text('置顶'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('preset-context-pin-action')));
      await tester.pumpAndSettle();
      expect(core.writes.single, {'id': 'b' * 64, 'owner': '', 'pinned': true});
      expect(actual.presets.first.name, '第二款');
      expect(find.text('置顶'), findsOneWidget);
      await tester.longPress(find.text('第一款'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('preset-context-pin-action')));
      await tester.pumpAndSettle();
      expect(actual.presets.where((preset) => preset.pinned), hasLength(2));
      expect(find.text('置顶'), findsNWidgets(2));
      await tester.longPress(find.text('第二款'));
      await tester.pumpAndSettle();
      expect(find.text('取消置顶'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      actual.dispose();
    },
  );
}
