import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_slots.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';

class _SlotsCore extends HueviaCore {
  final calls = <(String, Json)>[];
  String phase = 'verified';
  bool parametersUncertain = false;
  Completer<Json>? execution;
  Json get state => {
    'session': 'slots-owned',
    'connected': true,
    'model': 'Z 6_2',
    'canWrite': true,
    'canDelete': true,
    'consumed': false,
    'action': <String, dynamic>{},
    'items': [
      for (var i = 201; i <= 209; i++)
        {
          'target': i,
          'label': 'C${i - 200}',
          'name': i == 202 ? '' : '预设${i - 200}',
          'empty': i == 202,
          'sha256': 'a' * 64,
        },
    ],
  };
  Json outcome([String? requestedPhase]) {
    final actual = requestedPhase ?? phase;
    return {
      ...state,
      'consumed': true,
      'canWrite': false,
      'canDelete': false,
      'action': {
        'phase': actual,
        'actionId': 'once',
        'pending': actual == 'resultUnknown' || parametersUncertain,
        'presetVerified':
            actual == 'verified' || actual == 'verifiedByReadback',
        'message': actual == 'rejected' ? '相机拒绝操作，未写入。' : '相机响应丢失，请核对。',
        if (parametersUncertain) ...{
          'parametersPending': true,
          'parameterResult': {
            'uncertain': true,
            'detail': '白平衡结果未确认，请在相机核对；预设不会重复写入。',
          },
        },
      },
    };
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, Map.of(payload)));
    switch (operation) {
      case 'camera.status':
        return {
          'connected': true,
          'mode': 'photos',
          'session': 'photo-owned',
          'transport': 'wifi',
        };
      case 'camera.slots.open':
      case 'camera.slots.refresh':
        return state;
      case 'library.export':
        return {'path': '/private/test.ncp'};
      case 'camera.slots.prepare':
        return {
          'confirmationId': 'nonce',
          'targetLabel': 'C${(payload['target'] as int) - 200}',
          'beforeName': '预设${(payload['target'] as int) - 200}',
          'overwrite': payload['target'] != 202,
          'name': '标准曲线',
          'explanation': '完整转换参数已核对',
          'parameterSummary': '按所选参数处理',
        };
      case 'camera.slots.execute':
        return execution == null ? outcome() : execution!.future;
      case 'camera.slots.reconcile':
        return outcome('verifiedByReadback');
      case 'camera.slots.acknowledge':
        final before = outcome();
        parametersUncertain = false;
        return {
          ...before,
          'action': {
            ...object(before['action']),
            'pending': false,
            'parametersPending': false,
            'parametersManuallyChecked': true,
          },
        };
      case 'camera.slots.close':
        return {'closed': true};
      default:
        throw AppFailure('Fixture has no preview: $operation');
    }
  }
}

void main() {
  late _SlotsCore core;
  late AppState model;
  setUp(() {
    core = _SlotsCore();
    model = AppState(core)
      ..session = {
        'user': {'id': 'alice'},
      };
  });
  tearDown(() => model.dispose());
  Future<void> open(
    WidgetTester tester, {
    bool importing = true,
    bool embedded = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.light),
        home: CameraSlotsPage(
          state: model,
          embedded: embedded,
          initialPreset: importing
              ? Preset({
                  'id': 'b' * 64,
                  'displayName': '标准曲线',
                  'fileFormat': 'NCP',
                })
              : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirm(
    WidgetTester tester, {
    bool doubleConfirm = false,
  }) async {
    await tester.tap(find.byKey(const ValueKey('camera-slot-import')));
    await tester.pumpAndSettle();
    expect(core.calls.where((c) => c.$1 == 'camera.slots.execute'), isEmpty);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '确认写入此槽位'),
    );
    button.onPressed!();
    if (doubleConfirm) button.onPressed!();
    await tester.pump(const Duration(milliseconds: 350));
  }

  testWidgets(
    'Embedded import stays reachable in landscape with doubled system text',
    (tester) async {
      tester.view.physicalSize = const Size(812, 375);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              padding: const EdgeInsets.only(bottom: 20),
            ),
            child: child!,
          ),
          home: CameraSlotsPage(
            state: model,
            file: '/private/test.ncp',
            name: '标准曲线.ncp',
            embedded: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('camera-slot-209')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('camera-slot-209')));
      await tester.pump();
      expect(
        tester
            .getBottomRight(find.byKey(const ValueKey('camera-slot-import')))
            .dy,
        lessThan(355),
      );
      expect(find.text('覆盖 C9…'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'C1-C9 are three columns; selection and canceled deletion never mutate the camera',
    (tester) async {
      await open(tester, importing: false);
      final one = tester.getCenter(
        find.byKey(const ValueKey('camera-slot-201')),
      );
      final two = tester.getCenter(
        find.byKey(const ValueKey('camera-slot-202')),
      );
      final three = tester.getCenter(
        find.byKey(const ValueKey('camera-slot-203')),
      );
      expect(one.dy, closeTo(two.dy, 1));
      expect(two.dy, closeTo(three.dy, 1));
      expect(one.dx, lessThan(two.dx));
      expect(two.dx, lessThan(three.dx));
      expect(find.byKey(const ValueKey('camera-slot-209')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('camera-slot-202')));
      await tester.pump();
      expect(find.byKey(const ValueKey('camera-slot-delete')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('camera-slot-201')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('camera-slot-delete')));
      await tester.pumpAndSettle();
      expect(find.text('删除 C1？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(core.calls.where((c) => c.$1 == 'camera.slots.execute'), isEmpty);
      expect(core.calls.where((c) => c.$1 == 'camera.slots.close'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Import confirms target 209 exactly once and only actual verified readback produces the success page',
    (tester) async {
      await open(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('camera-slot-209')));
      await tester.tap(find.byKey(const ValueKey('camera-slot-209')));
      await tester.pump();
      expect(find.text('将替换「预设9」。原槽位内容会被覆盖。'), findsOneWidget);
      await confirm(tester, doubleConfirm: true);
      await tester.pumpAndSettle();
      final plan = core.calls
          .singleWhere((c) => c.$1 == 'camera.slots.prepare')
          .$2;
      expect(plan, {
        'session': 'slots-owned',
        'target': 209,
        'kind': 'write',
        'path': '/private/test.ncp',
        'middleQuarter': 4,
        'clarityQuarter': 0,
        'parameters': <String, dynamic>{},
      });
      expect(
        core.calls.where((c) => c.$1 == 'camera.slots.execute'),
        hasLength(1),
      );
      expect(find.text('已保存到 C9'), findsOneWidget);
      expect(find.text('已读回核对'), findsOneWidget);
      expect(find.text('不会自动切换相机当前预设'), findsOneWidget);
      expect(
        core.calls.where(
          (c) => c.$1 == 'camera.page' || c.$1 == 'camera.disconnect',
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final phase in ['resultUnknown', 'rejected']) {
    testWidgets(
      '$phase never displays readback success or retries the mutation',
      (tester) async {
        core.phase = phase;
        await open(tester);
        await confirm(tester);
        await tester.pumpAndSettle();
        expect(find.text('已读回核对'), findsNothing);
        expect(find.text('已保存到 C1'), findsNothing);
        expect(
          find.text(phase == 'resultUnknown' ? '结果待核对' : '导入失败'),
          findsOneWidget,
        );
        if (phase == 'resultUnknown') {
          await tester.tap(find.text('只读核对相机'));
          await tester.pumpAndSettle();
          expect(find.text('已读回核对'), findsOneWidget);
        }
        expect(
          core.calls.where((c) => c.$1 == 'camera.slots.execute'),
          hasLength(1),
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Preset readback and uncertain camera parameters have separate outcomes and manual confirmation',
    (tester) async {
      core.parametersUncertain = true;
      await open(tester);
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(find.text('已保存到 C1'), findsOneWidget);
      expect(find.text('已读回核对'), findsOneWidget);
      expect(find.textContaining('白平衡结果未确认'), findsOneWidget);
      await tester.tap(find.text('我已在相机手动核对'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已在相机核对'));
      await tester.pumpAndSettle();
      expect(
        core.calls.singleWhere((c) => c.$1 == 'camera.slots.acknowledge').$2,
        {
          'session': 'slots-owned',
          'confirmedOnCamera': true,
          'actionId': 'once',
        },
      );
      expect(
        core.calls.where((c) => c.$1 == 'camera.slots.execute'),
        hasLength(1),
      );
      expect(find.text('已保存到 C1'), findsOneWidget);
      expect(find.textContaining('已在相机手动核对'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'A late execute result cannot replace a new account or close a different session',
    (tester) async {
      core.execution = Completer<Json>();
      await open(tester);
      await confirm(tester);
      model.acceptAuthenticatedSession({
        'verified': true,
        'user': {'id': 'bob'},
      });
      await tester.pump();
      core.execution!.complete(core.outcome());
      await tester.pumpAndSettle();
      expect(find.text('已读回核对'), findsNothing);
      expect(find.text('账号已改变，请关闭后重新打开相机预设槽位。'), findsOneWidget);
      expect(
        core.calls.where((c) => c.$1 == 'camera.slots.close').map((c) => c.$2),
        [
          {'session': 'slots-owned'},
        ],
      );
      expect(core.calls.where((c) => c.$1 == 'camera.disconnect'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Optional Kelvin and exposure choices are forwarded to the same guarded slot plan',
    (tester) async {
      await open(tester);
      await tester.scrollUntilVisible(
        find.text('选择 ›'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择 ›'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slot-white-balance')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('指定色温'),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('指定色温').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('slot-exposure')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('slot-exposure')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('1.0 EV'),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.0 EV').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存选择'));
      await tester.pumpAndSettle();
      await confirm(tester);
      await tester.pumpAndSettle();
      expect(
        core.calls
            .singleWhere((c) => c.$1 == 'camera.slots.prepare')
            .$2['parameters'],
        {'whiteBalance': 0x8012, 'kelvin': 5000, 'exposureMilliEv': 1000},
      );
      expect(
        core.calls.where((c) => c.$1.startsWith('camera.remote.')),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
