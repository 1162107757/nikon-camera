import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/library.dart';
import 'package:huevia/theme.dart';

import 'preset_pins_test.dart' as fixtures;

class _ContextCore extends fixtures.PinCore {
  final removals = <Json>[];
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'library.remove') {
      removals.add(Map.of(payload));
      rows.removeWhere((row) => row['id'] == payload['id']);
      return {'removed': true};
    }
    return super.call(operation, payload, jobId);
  }
}

void main() {
  late _ContextCore core;
  late AppState state;
  setUp(() {
    core = _ContextCore();
    state = AppState(core)
      ..session = {
        'user': {'id': 'alice'},
      }
      ..presets = core.rows.map((row) => Preset(Map.of(row))).toList();
  });
  tearDown(() => state.dispose());
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.light),
        home: LibraryPage(state: state),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String name) async {
    await tester.longPress(find.text(name));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Preset compact menu pins and unpins immediately while retaining other pinned presets',
    (tester) async {
      await open(tester);
      await menu(tester, '第二款');
      await tester.tap(find.byKey(const ValueKey('preset-context-pin-action')));
      await tester.pumpAndSettle();
      expect(core.writes, [
        {'id': 'b' * 64, 'owner': 'alice', 'pinned': true},
      ]);
      expect(find.text('移除预设？'), findsNothing);
      await menu(tester, '第一款');
      // Both a pinned badge and this action can read "置顶"; only the last one
      // belongs to the newly opened route.
      await tester.tap(find.text('置顶').last);
      await tester.pumpAndSettle();
      expect(state.presets.where((p) => p.pinned), hasLength(2));
      await menu(tester, '第二款');
      await tester.tap(find.byKey(const ValueKey('preset-context-pin-action')));
      await tester.pumpAndSettle();
      expect(core.writes.last, {
        'id': 'b' * 64,
        'owner': 'alice',
        'pinned': false,
      });
      expect(state.presets.singleWhere((p) => p.id == 'a' * 64).pinned, isTrue);
      expect(
        state.presets.singleWhere((p) => p.id == 'b' * 64).pinned,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  testWidgets(
    'Preset compact deletion keeps the existing confirmation and cancel preserves the preset',
    (tester) async {
      await open(tester);
      await menu(tester, '第二款');
      await tester.tap(
        find.byKey(const ValueKey('preset-context-remove-action')),
      );
      await tester.pumpAndSettle();
      expect(find.text('移除预设？'), findsOneWidget);
      expect(find.textContaining('当前账号的云端预设'), findsOneWidget);
      expect(core.removals, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(state.presets, hasLength(2));
      expect(core.removals, isEmpty);
      await menu(tester, '第二款');
      await tester.tap(
        find.byKey(const ValueKey('preset-context-remove-action')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除'));
      await tester.pumpAndSettle();
      expect(core.removals, [
        {'id': 'b' * 64, 'owner': 'alice'},
      ]);
      expect(state.presets.map((p) => p.name), ['第一款']);
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
  testWidgets(
    'A preset menu opened for an old owner cannot mutate the new account',
    (tester) async {
      await open(tester);
      await menu(tester, '第二款');
      state.acceptAuthenticatedSession({
        'verified': true,
        'user': {'id': 'bob'},
      });
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('preset-context-pin-action')));
      await tester.pumpAndSettle();
      expect(core.writes, isEmpty);
      expect(core.removals, isEmpty);
      expect(find.text('移除预设？'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
