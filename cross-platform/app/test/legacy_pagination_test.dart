import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/legacy_presets.dart';
import 'package:huevia/library.dart';
import 'package:huevia/theme.dart';

class _PagingCore extends HueviaCore {
  final pages = <int>[];
  Completer<Json>? second;
  bool failThird = true;
  Json row(int i) => {
    'id': '$i'.padLeft(64, '0'),
    'displayName': '预设$i',
    'fileFormat': 'NCP',
    'category': '',
  };
  Json result(int page) => {
    'items': [
      for (
        var i = page == 1
            ? 0
            : page == 2
            ? 23
            : 47;
        i <
            (page == 1
                ? 24
                : page == 2
                ? 48
                : 49);
        i++
      )
        row(i),
    ],
    'page': page,
    'hasMore': page < 3,
    'total': 49,
    'categories': <String>[],
  };
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation != 'online.page') {
      throw const AppFailure('No image in pagination fixture');
    }
    final page = payload['page'] as int;
    pages.add(page);
    if (page == 2) return (second = Completer<Json>()).future;
    if (page == 3 && failThird) throw const AppFailure('临时网络错误');
    return result(page);
  }
}

void main() {
  testWidgets(
    'Online presets load one page per gesture, deduplicate, and retry the failed page without parallel requests',
    (tester) async {
      final core = _PagingCore();
      final state = AppState(core)..uiPreferences = {'presetSource': 'online'};
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: LibraryPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      expect(core.pages, [1]);
      expect(find.text('加载更多'), findsNothing);
      await tester.drag(find.byType(LegacyPresetGrid), const Offset(0, -10000));
      await tester.pump(const Duration(milliseconds: 100));
      expect(core.pages, [1, 2]);
      await tester.drag(find.byType(LegacyPresetGrid), const Offset(0, -1000));
      await tester.pump(const Duration(milliseconds: 100));
      expect(core.pages, [1, 2]);
      core.second!.complete(core.result(2));
      await tester.pumpAndSettle();
      final rows = tester
          .widget<LegacyPresetGrid>(find.byType(LegacyPresetGrid))
          .rows;
      expect(rows, hasLength(48));
      expect(rows.map((p) => p.id).toSet(), hasLength(48));
      expect(core.pages, [1, 2]); // Content growth is not another user gesture.
      await tester.drag(find.byType(LegacyPresetGrid), const Offset(0, -10000));
      await tester.pumpAndSettle();
      expect(core.pages, [1, 2, 3]);
      await tester.drag(find.byType(LegacyPresetGrid), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(core.pages, [1, 2, 3]); // Error cannot trigger an automatic loop.
      core.failThird = false;
      await tester.ensureVisible(find.text('重试加载'));
      await tester.tap(find.text('重试加载'));
      await tester.pumpAndSettle();
      expect(core.pages, [1, 2, 3, 3]);
      expect(
        tester.widget<LegacyPresetGrid>(find.byType(LegacyPresetGrid)).rows,
        hasLength(49),
      );
      await tester.drag(find.byType(LegacyPresetGrid), const Offset(0, -1000));
      await tester.pumpAndSettle();
      expect(core.pages, [1, 2, 3, 3]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
