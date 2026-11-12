import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/main.dart';

class NavigationCameraCore extends HueviaCore {
  final page = Completer<Json>();
  final cancelled = <String>[];
  int pages = 0, statuses = 0;
  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    switch (operation) {
      case 'camera.status':
        statuses++;
        return {'connected': true, 'session': 'retained', 'model': 'Z 6_2'};
      case 'camera.page':
        pages++;
        return page.future;
      case 'gallery.access':
        return {'access': 'none'};
      case 'photo.stars':
        return {'keys': []};
      default:
        return {};
    }
  }
}

void main() {
  testWidgets(
    'Four home tabs preserve an active camera page and do not cancel its connection',
    (tester) async {
      final core = NavigationCameraCore();
      final state = AppState(core)..ready = true;
      await tester.pumpWidget(HueviaApp(state: state));
      await tester.pumpAndSettle();
      await tester.tap(find.text('同步').last);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(core.pages, 1);
      for (final label in ['预设', '相册', '设置', '同步']) {
        await tester.tap(find.text(label).last);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump();
        expect(
          core.cancelled,
          isEmpty,
          reason: 'Switching to $label must keep the PTP session',
        );
      }
      expect(core.pages, 1);
      core.page.complete({'items': [], 'nextOffset': 0, 'hasMore': false});
      await tester.pumpAndSettle();
      expect(find.textContaining('Z 6_2'), findsOneWidget);
      expect(core.cancelled, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
