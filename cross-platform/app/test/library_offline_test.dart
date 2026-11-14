import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/legacy_presets.dart';
import 'package:huevia/library.dart';
import 'package:huevia/theme.dart';

const _rawFailure =
    'HTTP request failed: https://nikon-example.invalid/preset-library/community/feed?page=1&pageSize=24 SocketException: no network';
const _emptyFailure = '暂时无法连接在线预设，请重试或使用我的预设。';
const _cachedFailure = '暂时无法连接在线预设，已保留缓存。';

Json _row(String id, String name) => {
  'id': id,
  'sha256': id,
  'name': name,
  'category': '人像',
  'fileFormat': 'NCP',
};
Json _page(List<Json> rows) => {
  'items': rows,
  'page': 1,
  'hasMore': false,
  'total': rows.length,
  'categories': ['人像'],
};

class _OfflineCore extends HueviaCore {
  final calls = <(String, Json)>[];
  final gates = <Completer<Json>>[];
  Json reply = _page([]);
  Completer<Json>? held;
  bool fail = false;
  int active = 0, maximumActive = 0;
  int get onlineCalls => calls
      .where((call) => call.$1 == 'online.page' || call.$1 == 'online.search')
      .length;
  Completer<Json> hold() {
    final gate = held = Completer<Json>();
    gates.add(gate);
    return gate;
  }

  @override
  Future<Json> call(String op, [Json payload = const {}, String? jobId]) async {
    calls.add((op, Map.of(payload)));
    if (op == 'ui.preferences.set') return Map.of(payload);
    if (op != 'online.page' && op != 'online.search') {
      throw const AppFailure('No thumbnail in offline fixture');
    }
    active++;
    if (active > maximumActive) maximumActive = active;
    try {
      final pending = held;
      held = null;
      if (pending != null) return await pending.future;
      if (fail) throw const AppFailure(_rawFailure);
      return Map.of(reply);
    } finally {
      active--;
    }
  }
}

class _OfflineState extends AppState {
  _OfflineState(super.core);
  void switchOwner(String owner) {
    session = {
      'user': {'id': owner},
    };
    presets = [
      Preset({'id': 'b' * 64, 'displayName': '我的离线预设', 'fileFormat': 'NCP'}),
    ];
    notifyListeners();
  }

  void pendingLogout() {
    session = {'logoutPending': true};
    notifyListeners();
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var index = 0; index < 5; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<_OfflineState> _open(
  WidgetTester tester,
  _OfflineCore core, {
  bool search = false,
}) async {
  final state = _OfflineState(core)
    ..uiPreferences = {
      'presetSource': 'online',
      if (search) 'presetOnline': {'format': 'NCP'},
    }
    ..presets = [
      Preset({'id': 'b' * 64, 'displayName': '我的离线预设', 'fileFormat': 'NCP'}),
    ];
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    for (final gate in core.gates) {
      if (!gate.isCompleted) gate.complete(_page([]));
    }
    await tester.pump();
    expect(
      core.calls.any(
        (call) =>
            call.$1.contains('remove') ||
            call.$1.contains('delete') ||
            call.$1.contains('clear'),
      ),
      false,
    );
    state.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.light),
      home: LibraryPage(state: state),
    ),
  );
  await _frames(tester);
  return state;
}

void _noRawError() {
  expect(find.textContaining('https://'), findsNothing);
  expect(find.textContaining('SocketException'), findsNothing);
  expect(find.textContaining('community/feed'), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Offline first load has one clear recovery message, no raw URL, and a working local-preset entry',
    (tester) async {
      final core = _OfflineCore()..fail = true;
      await _open(tester, core);
      expect(find.text(_emptyFailure), findsOneWidget);
      expect(find.text('暂时没有在线预设'), findsNothing);
      expect(find.text('重试加载'), findsOneWidget);
      _noRawError();
      await tester.tap(find.widgetWithText(TextButton, '我的预设'));
      await _frames(tester);
      expect(find.text('我的离线预设'), findsOneWidget);
      expect(core.onlineCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'A successful empty response stays a genuine empty state and an explicit retry can recover from failure',
    (tester) async {
      final core = _OfflineCore();
      await _open(tester, core);
      expect(find.text('暂时没有在线预设'), findsOneWidget);
      expect(find.text(_emptyFailure), findsNothing);
      core.fail = true;
      await tester.tap(find.widgetWithText(OutlinedButton, '重新加载'));
      await _frames(tester);
      expect(find.text(_emptyFailure), findsOneWidget);
      core
        ..fail = false
        ..reply = _page([_row('a' * 64, '恢复后的预设')]);
      await tester.tap(find.text('重试加载'));
      await _frames(tester);
      expect(find.text('恢复后的预设'), findsOneWidget);
      expect(find.text(_emptyFailure), findsNothing);
      expect(core.onlineCalls, 3);
      _noRawError();
    },
  );

  testWidgets(
    'A failed refresh preserves loaded cards and shows one cache recovery notice',
    (tester) async {
      final core = _OfflineCore()..reply = _page([_row('a' * 64, '已加载的缓存')]);
      await _open(tester, core);
      core.fail = true;
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await _frames(tester);
      expect(find.text('已加载的缓存'), findsOneWidget);
      expect(find.text(_cachedFailure), findsOneWidget);
      expect(find.text('暂时没有在线预设'), findsNothing);
      expect(
        tester
            .widget<LegacyPresetGrid>(find.byType(LegacyPresetGrid))
            .rows
            .single
            .name,
        '已加载的缓存',
      );
      expect(
        tester.widget<LegacyPresetGrid>(find.byType(LegacyPresetGrid)).onMore,
        isNull,
      );
      await tester.drag(find.byType(LegacyPresetGrid), const Offset(0, -500));
      await _frames(tester);
      expect(
        core.onlineCalls,
        2,
      ); // Scrolling a failed refresh never loops requests.
      _noRawError();
    },
  );

  testWidgets(
    'Unavailable native responses do not overwrite existing cache with an empty catalog',
    (tester) async {
      final core = _OfflineCore()..reply = _page([_row('a' * 64, '离线保留卡片')]);
      await _open(tester, core);
      core.reply = {
        'items': <Json>[],
        'categories': <String>[],
        'available': false,
        'message': _rawFailure,
      };
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await _frames(tester);
      expect(find.text('离线保留卡片'), findsOneWidget);
      expect(find.text(_cachedFailure), findsOneWidget);
      _noRawError();
    },
  );

  testWidgets(
    'Native cached search results remain visible while their raw diagnostic never reaches the page',
    (tester) async {
      final core = _OfflineCore()
        ..reply = {
          'items': [_row('a' * 64, '原生缓存预设')],
          'categories': ['人像'],
          'available': true,
          'fromCache': true,
          'message': _rawFailure,
        };
      await _open(tester, core, search: true);
      expect(core.calls.any((call) => call.$1 == 'online.search'), true);
      expect(find.text('原生缓存预设'), findsOneWidget);
      expect(find.text(_cachedFailure), findsOneWidget);
      _noRawError();
    },
  );

  testWidgets(
    'An owner switch rejects late old rows, serially loads the new view, and logout retires it',
    (tester) async {
      final core = _OfflineCore();
      final old = core.hold();
      final state = await _open(tester, core);
      core.reply = _page([_row('b' * 64, '新账号在线预设')]);
      state.switchOwner('new-owner');
      await tester.pump();
      old.complete(_page([_row('a' * 64, '旧账号迟到预设')]));
      await _frames(tester);
      expect(find.text('旧账号迟到预设'), findsNothing);
      expect(find.text('新账号在线预设'), findsOneWidget);
      expect(core.onlineCalls, 2);
      expect(core.maximumActive, 1);
      state.pendingLogout();
      await _frames(tester);
      expect(find.text('新账号在线预设'), findsNothing);
      expect(core.onlineCalls, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
