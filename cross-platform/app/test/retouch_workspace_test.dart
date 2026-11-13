import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/retouch_workspace.dart';
import 'package:huevia/theme.dart';

class PortraitMenuCore extends HueviaCore {
  PortraitMenuCore(String directory) {
    root = directory;
    snapshots['start'] = {
      'localData': 'start',
      'sha256': 'start',
      'patchCount': 1,
      'tones': [
        {'id': 0, 'name': '原肤', 'color': 0},
        {'id': 1, 'name': '自然米色', 'color': 0xe1bfa5},
      ],
      'portrait': {
        'tonePerFace': false,
        'hasSkinMask': true,
        'skinPixels': 100,
        'faces': [
          {
            'cx': .5,
            'cy': .5,
            'rx': .25,
            'ry': .3,
            'enabled': true,
            'toneId': 0,
            'toneRgb': 0,
            'toneAmount': 0,
            'brightness': 0,
            'smoothing': 0,
            'warmth': 0,
            'texture': 0,
            'redness': 0,
            'light': 0,
            'shadows': 0,
          },
        ],
        'skin': {'toneId': 0, 'toneRgb': 0, 'toneAmount': 0, 'smoothing': 0},
        'body': [
          {'left': .25, 'top': .25, 'right': .75, 'bottom': .90, 'amount': 0},
          {'left': .30, 'top': .50, 'right': .70, 'bottom': .94, 'amount': 0},
          {'left': .23, 'top': .48, 'right': .77, 'bottom': .90, 'amount': 0},
        ],
        'hasBodyMask': false,
        'protection': 0,
        'singleLeg': false,
        'heals': [
          {'tx': .2, 'ty': .3},
          {'tx': .6, 'ty': .7},
        ],
      },
    };
  }
  final Map<String, Json> snapshots = {};
  final List<(String, Json)> calls = [];
  final List<Json> cards = [];
  final gates = <String, Completer<void>>{};
  final cancelledJobs = <String>[];
  final blockedJobs = <String>[];
  int serial = 0;
  String? failAnalyze;
  String regionId = '';
  @override
  Future<void> cancel(String jobId) async {
    cancelledJobs.add(jobId);
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
    final gate = gates.remove('$operation/${payload['mode'] ?? ''}');
    if (gate != null) {
      if (jobId != null) blockedJobs.add(jobId);
      await gate.future;
    }
    if (operation == 'toneCards.list') return {'cards': cards};
    if (operation == 'toneCards.save') {
      cards.add({
        'id': 'card-${cards.length}',
        'name': payload['name'],
        'rgb': payload['rgb'],
      });
      return {'cards': cards};
    }
    if (operation == 'toneCards.remove') {
      cards.removeWhere((row) => row['id'] == payload['id']);
      return {'cards': cards};
    }
    if (operation == 'media.reviewPreview' ||
        operation == 'media.localPreview') {
      return {'path': '$root/previews/portrait.png', 'width': 8, 'height': 8};
    }
    if (operation == 'media.retouchDescribe') {
      return {...snapshots['start']!, 'regionId': regionId};
    }
    if (operation == 'media.retouchAnalyze') {
      final mode = payload['mode'];
      if (mode == failAnalyze) throw const AppFailure('分析未完成测试');
      if (mode == 'overlay') {
        return {'regionId': regionId, 'selectionOverlay': null};
      }
      if (mode == 'hitFace') return {'regionId': regionId, 'hitFace': 1};
      final next = object(
        jsonDecode(jsonEncode(snapshots[payload['localData']]!)),
      );
      final portrait = next['portrait'] as Json;
      if (mode == 'skin') portrait['hasSkinMask'] = true;
      if (mode == 'face' && (portrait['faces'] as List).isEmpty) {
        portrait['faces'] = [
          {'cx': .8, 'cy': .5, 'rx': .1, 'ry': .15, 'enabled': true},
        ];
      }
      if (mode == 'body') {
        portrait['hasBodyMask'] = true;
        portrait['protection'] = payload['protection'];
        next['people'] = [
          {'left': .1, 'right': .4},
          {'left': .6, 'right': .9},
        ];
        if (payload['locate'] == true) {
          (portrait['body'] as List)[0] = {
            'left': .1,
            'top': .2,
            'right': .6,
            'bottom': .9,
            'amount': 0,
          };
        }
      }
      next['regionId'] = regionId;
      next['localData'] = next['sha256'] = 'edit-${serial++}';
      snapshots[next['localData'] as String] = next;
      return next;
    }
    if (operation == 'media.retouchChange') {
      if (payload['action'] == 'beforeBody') {
        return {...snapshots[payload['localData']]!, 'regionId': regionId};
      }
      final next = object(
        jsonDecode(jsonEncode(snapshots[payload['localData']]!)),
      );
      final portrait = next['portrait'] as Json;
      final faces = portrait['faces'] as List;
      final value = object(payload['value'] ?? {});
      switch (payload['action']) {
        case 'removeHeal':
          (portrait['heals'] as List).removeAt(payload['index'] as int);
        case 'face':
          (faces[payload['index'] as int] as Json).addAll(value);
        case 'body':
          final tool = value['tool'] as int? ?? 0;
          final body = (portrait['body'] as List)[tool] as Json;
          for (final key in ['left', 'top', 'right', 'bottom', 'amount']) {
            if (value.containsKey(key)) body[key] = value[key];
          }
          for (final key in ['protection', 'singleLeg']) {
            if (value.containsKey(key)) portrait[key] = value[key];
          }
        case 'faceStroke':
          final face = faces[payload['index'] as int] as Json;
          face['strokeCount'] = (face['strokeCount'] as int? ?? 0) + 1;
        case 'removeFace':
          faces.removeAt(payload['index'] as int);
        case 'toneScope':
          portrait['tonePerFace'] = value['perFace'];
        case 'skin':
          final skin = portrait['skin'] as Json;
          skin.addAll(value);
          if (value.containsKey('toneRgb')) skin['toneId'] = 10;
        case 'clearPortrait':
          portrait['faces'] = [];
          portrait['heals'] = [];
          portrait['skin'] = {'toneId': 0, 'toneRgb': 0, 'toneAmount': 0};
      }
      next['regionId'] = regionId;
      next['localData'] = next['sha256'] = 'edit-${serial++}';
      snapshots[next['localData'] as String] = next;
      return next;
    }
    throw AppFailure(operation);
  }
}

class PortraitRouteReceipt {
  int completed = 0;
  Json? result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PortraitMenuCore core;
  late AppState state;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('huevia-portrait-menu-');
    Directory('${directory.path}/previews').createSync();
    File('${directory.path}/previews/portrait.png').writeAsBytesSync(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAEklEQVR4nGMQWm3yHx9mGBkKAKq5fAFPbl0bAAAAAElFTkSuQmCC',
      ),
    );
    core = PortraitMenuCore(directory.path);
    state = AppState(core)
      ..session = {
        'user': {'id': 'alice'},
      };
  });
  tearDown(() {
    state.dispose();
    directory.deleteSync(recursive: true);
  });
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pumpAndSettle();
    }
  }

  Future<void> open(
    WidgetTester tester, {
    bool Function()? current,
    bool enterFace = true,
    String? regionId,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.dark),
        home: RetouchWorkspace(
          state: state,
          photo: Photo('${directory.path}/original.jpg', '人像样片', const {}),
          owner: 'alice',
          regionId: regionId,
          regionName: regionId == null ? null : '人物局部',
          recipe: Recipe().data,
          isCurrent: current ?? () => true,
        ),
      ),
    );
    await settle(tester);
    if (enterFace) {
      await tester.tap(find.text('面部'));
      await settle(tester);
    }
  }

  Future<void> skinPage(WidgetTester tester) async {
    await tester.tap(find.byTooltip('返回人像工具'));
    await settle(tester);
    await tester.tap(find.text('皮肤'));
    await settle(tester);
  }

  Future<void> more(WidgetTester tester, String label) async {
    await tester.tap(
      find.bySemanticsLabel('更多人像操作').evaluate().isNotEmpty
          ? find.bySemanticsLabel('更多人像操作')
          : find.bySemanticsLabel('更多肤色选项'),
    );
    await settle(tester);
    await tester.tap(find.text(label));
    await settle(tester);
  }

  List<Json> changes(String action) => core.calls
      .where((c) => c.$1 == 'media.retouchChange' && c.$2['action'] == action)
      .map((c) => c.$2)
      .toList();

  testWidgets(
    'Original portrait menu changes face enabled state and deletes only the selected face',
    (tester) async {
      await open(tester);
      await more(tester, '停用此人脸');
      expect(changes('face').single['value'], {'enabled': false});
      await more(tester, '启用此人脸');
      expect(changes('face').last['value'], {'enabled': true});
      await more(tester, '删除此人脸');
      expect(changes('removeFace').single['index'], 0);
      expect(core.calls.where((c) => c.$1 == 'draft.save'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Healing history and last-heal undo target heals and preserve independent patches',
    (tester) async {
      await open(tester);
      await more(tester, '逐处撤销祛痘');
      await tester.tap(find.textContaining('撤销第 1 处'));
      await settle(tester);
      expect(changes('removeHeal').single['index'], 0);
      await more(tester, '撤回上一处祛痘');
      expect(changes('removeHeal').last['index'], 0);
      expect(changes('removePatch'), isEmpty);
      await tester.tap(find.bySemanticsLabel('撤销'));
      await settle(tester);
      await more(tester, '逐处撤销祛痘');
      expect(find.textContaining('撤销第 1 处'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Tone scope is explicit, propagated on subsequent commands and restored by undo',
    (tester) async {
      await open(tester);
      await skinPage(tester);
      await more(tester, '逐人肤色调节（高级）');
      expect(changes('toneScope').single['value'], {'perFace': true});
      expect(changes('toneScope').single['tonePerFace'], false);
      await more(tester, '全图肤色调节');
      expect(changes('toneScope').last['tonePerFace'], true);
      await tester.tap(find.bySemanticsLabel('撤销'));
      await settle(tester);
      await tester.tap(
        find.bySemanticsLabel('更多人像操作').evaluate().isNotEmpty
            ? find.bySemanticsLabel('更多人像操作')
            : find.bySemanticsLabel('更多肤色选项'),
      );
      await settle(tester);
      expect(find.text('全图肤色调节'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Reset requires confirmation and stays tentative with undo available',
    (tester) async {
      await open(tester);
      await more(tester, '重置人像精修');
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('取消')),
      );
      await settle(tester);
      expect(changes('clearPortrait'), isEmpty);
      await more(tester, '重置人像精修');
      await tester.tap(find.text('重置'));
      await settle(tester);
      expect(changes('clearPortrait'), hasLength(1));
      await tester.tap(find.bySemanticsLabel('撤销'));
      await settle(tester);
      await more(tester, '停用此人脸');
      expect(changes('face').single['index'], 0);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Photo color picking uses actual neutral portrait bitmap pixels and previews until confirmed',
    (tester) async {
      await open(tester);
      await skinPage(tester);
      await tester.ensureVisible(find.text('自定义'));
      await settle(tester);
      await tester.tap(find.text('自定义'));
      await settle(tester);
      await tester.ensureVisible(find.text('照片取色'));
      await settle(tester);
      await tester.tap(find.text('照片取色'));
      await settle(tester);
      expect(find.text('点按照片取色'), findsOneWidget);
      expect(find.text('自定义肤色'), findsNothing);
      await tester.runAsync(() async {
        await tester.tap(find.bySemanticsLabel('待编辑照片：人像样片'));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await settle(tester);
      expect(changes('clearPortrait'), hasLength(1));
      expect(find.text('自定义肤色'), findsOneWidget);
      await tester.ensureVisible(find.text('预览效果'));
      await settle(tester);
      await tester.tap(find.text('预览效果'));
      await settle(tester);
      expect(object(changes('skin').last['value'])['toneRgb'], 0x12ab34);
      expect(find.text('使用此色'), findsOneWidget);
      final apply = tester.widget<TextButton>(
        find.widgetWithText(TextButton, '应用'),
      );
      expect(apply.onPressed, isNull);
      await tester.tap(find.text('使用此色'));
      await settle(tester);
      expect(find.text('使用此色'), findsNothing);
      expect(core.calls.where((c) => c.$1 == 'draft.save'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Account change closes private editing scope and prevents an old menu from mutating',
    (tester) async {
      await open(tester);
      await tester.tap(
        find.bySemanticsLabel('更多人像操作').evaluate().isNotEmpty
            ? find.bySemanticsLabel('更多人像操作')
            : find.bySemanticsLabel('更多肤色选项'),
      );
      await settle(tester);
      state.session = {
        'user': {'id': 'bob'},
      };
      state.notifyListeners();
      await tester.tap(find.text('停用此人脸'));
      await settle(tester);
      expect(changes('face'), isEmpty);
      expect(find.bySemanticsLabel('待编辑照片：人像样片'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  String lastPreviewLocal() =>
      object(
            core.calls
                .lastWhere((c) => c.$1 == 'media.reviewPreview')
                .$2['recipe'],
          )['localData']
          as String;
  Future<void> brightness(WidgetTester tester) async {
    await tester.tap(find.text('提亮'));
    await settle(tester);
  }

  Future<void> moveSlider(WidgetTester tester, {bool cancel = false}) async {
    final slider = find.byType(Slider).first;
    final r = tester.getRect(slider);
    final gesture = await tester.startGesture(Offset(r.center.dx, r.center.dy));
    await gesture.moveBy(const Offset(35, 0));
    await settle(tester);
    await gesture.moveBy(const Offset(20, 0));
    await settle(tester);
    if (cancel) {
      await gesture.cancel();
    } else {
      await gesture.up();
    }
    await settle(tester);
  }

  testWidgets(
    'Continuous face parameter drag commits one undo; cancel restores the complete candidate',
    (tester) async {
      await open(tester);
      await brightness(tester);
      await moveSlider(tester, cancel: true);
      expect(changes('face').length, greaterThanOrEqualTo(1));
      final brightnessValue = object(
        changes('face').last['value'],
      )['brightness'];
      expect(brightnessValue, isA<int>());
      expect(brightnessValue, greaterThan(1));
      expect(lastPreviewLocal(), 'start');
      await moveSlider(tester);
      expect(lastPreviewLocal(), isNot('start'));
      await tester.tap(find.bySemanticsLabel('撤销'));
      await settle(tester);
      expect(lastPreviewLocal(), 'start');
      expect(core.calls.where((c) => c.$1 == 'draft.save'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Natural retouch analysis is atomic when the second analysis fails',
    (tester) async {
      final portrait = core.snapshots['start']!['portrait'] as Json;
      portrait['hasSkinMask'] = false;
      portrait['faces'] = [];
      core.failAnalyze = 'face';
      await open(tester, enterFace: false);
      await tester.tap(find.text('自然精修'));
      await settle(tester);
      expect(find.textContaining('分析未完成测试'), findsOneWidget);
      expect(changes('skin'), isEmpty);
      expect(lastPreviewLocal(), 'start');
      await tester.tap(find.byTooltip('返回人像工具'));
      await settle(tester);
      await tester.tap(find.text('皮肤'));
      await settle(tester);
      expect(
        core.calls
            .where(
              (c) => c.$1 == 'media.retouchAnalyze' && c.$2['mode'] == 'skin',
            )
            .length,
        2,
      );
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Body child cancellation restores parent effects and its independent undo history',
    (tester) async {
      await open(tester);
      await more(tester, '停用此人脸');
      final parent = lastPreviewLocal();
      await tester.tap(find.byTooltip('返回人像工具'));
      await settle(tester);
      await tester.tap(find.text('塑形'));
      await settle(tester);
      await moveSlider(tester);
      expect(lastPreviewLocal(), isNot(parent));
      await tester.tap(find.byTooltip('取消塑形并返回人像'));
      await settle(tester);
      expect(lastPreviewLocal(), parent);
      await tester.tap(find.bySemanticsLabel('撤销'));
      await settle(tester);
      expect(lastPreviewLocal(), 'start');
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Body multi-person localization cancel installs no masks or guessed area',
    (tester) async {
      await open(tester, enterFace: false);
      await tester.tap(find.text('塑形'));
      await settle(tester);
      await tester.tap(find.text('自动定位'));
      await settle(tester);
      expect(find.text('选择要塑形的人物'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await settle(tester);
      expect(lastPreviewLocal(), 'start');
      final bodyCalls = core.calls
          .where(
            (c) => c.$1 == 'media.retouchAnalyze' && c.$2['mode'] == 'body',
          )
          .toList();
      expect(bodyCalls.single.$2['locate'], false);
      expect(bodyCalls.single.$2['protection'], 100);
      await tester.tap(find.text('背景保护'));
      await settle(tester);
      expect(lastPreviewLocal(), isNot('start'));
      expect(changes('body'), isEmpty);
      await tester.tap(find.text('背景保护 · 开'));
      await settle(tester);
      expect(object(changes('body').last['value'])['protection'], 0);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Regional portrait hides global body entry and keeps every request scoped',
    (tester) async {
      core.regionId = 'region-a';
      await open(tester, enterFace: false, regionId: 'region-a');
      expect(find.text('塑形'), findsNothing);
      expect(find.textContaining('人物局部'), findsOneWidget);
      await tester.tap(find.text('面部'));
      await settle(tester);
      await more(tester, '停用此人脸');
      expect(changes('face').single['regionId'], 'region-a');
      expect(
        core.calls
            .where((c) => c.$1.startsWith('media.retouch'))
            .every((c) => c.$2['regionId'] == 'region-a'),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Overview retains original global or face mask mode and restores it after body',
    (tester) async {
      List<Json> overlays() => core.calls
          .where(
            (c) => c.$1 == 'media.retouchAnalyze' && c.$2['mode'] == 'overlay',
          )
          .map((c) => c.$2)
          .toList();
      await open(tester, enterFace: false);
      expect(overlays().last['global'], true);
      await tester.tap(find.text('面部'));
      await settle(tester);
      expect(overlays().last['global'], false);
      await tester.tap(find.byTooltip('返回人像工具'));
      await settle(tester);
      expect(overlays().last['global'], false);
      var count = overlays().length;
      await tester.tap(find.text('塑形'));
      await settle(tester);
      expect(overlays().length, count);
      await tester.tap(find.byTooltip('取消塑形并返回人像'));
      await settle(tester);
      expect(overlays().length, greaterThan(count));
      expect(overlays().last['global'], false);
      count = overlays().length;
      await tester.tap(find.text('塑形'));
      await settle(tester);
      await tester.tap(find.text('应用'));
      await settle(tester);
      expect(overlays().length, greaterThan(count));
      expect(overlays().last['global'], false);
      count = overlays().length;
      await tester.tap(find.bySemanticsLabel('显示或隐藏选区'));
      await settle(tester);
      expect(overlays().length, count);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  Future<PortraitRouteReceipt> pushWorkspace(
    WidgetTester tester, {
    String? regionId,
    bool parentStage = false,
  }) async {
    final receipt = PortraitRouteReceipt();
    Widget workspace() => RetouchWorkspace(
      state: state,
      photo: Photo('${directory.path}/original.jpg', '人像样片', const {}),
      owner: 'alice',
      recipe: Recipe().data,
      isCurrent: () => true,
      regionId: regionId,
      regionName: regionId == null ? null : '人物局部',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.dark),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                if (parentStage) {
                  await Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (parent) => Scaffold(
                        body: Column(
                          children: [
                            const Text('父人像暂存效果'),
                            TextButton(
                              onPressed: () async {
                                receipt.result = await Navigator.of(parent)
                                    .push<Json>(
                                      MaterialPageRoute(
                                        builder: (_) => workspace(),
                                      ),
                                    );
                                receipt.completed++;
                              },
                              child: const Text('打开局部人像'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                } else {
                  receipt.result = await Navigator.of(
                    context,
                  ).push<Json>(MaterialPageRoute(builder: (_) => workspace()));
                  receipt.completed++;
                }
              },
              child: const Text('父编辑器'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('父编辑器'));
    await settle(tester);
    if (parentStage) {
      await tester.tap(find.text('打开局部人像'));
      await settle(tester);
    }
    return receipt;
  }

  int previewCount() =>
      core.calls.where((c) => c.$1 == 'media.reviewPreview').length;
  Future<void> startHeldFace(WidgetTester tester, Completer<void> gate) async {
    core.gates['media.retouchAnalyze/face'] = gate;
    await tester.tap(find.text('自动选脸'));
    await settle(tester);
    await tester.tap(find.text('重新识别'));
    await settle(tester);
  }

  testWidgets(
    'Busy face header cancellation closes only the workspace and rejects native late success during pop animation',
    (tester) async {
      final receipt = await pushWorkspace(tester);
      await tester.tap(find.text('面部'));
      await settle(tester);
      final gate = Completer<void>();
      await startHeldFace(tester, gate);
      final previews = previewCount(), blocked = core.blockedJobs.single;
      final close = find.byTooltip('取消人像精修');
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(of: close, matching: find.byType(IconButton)).first,
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(close);
      await tester.pump();
      expect(core.cancelledJobs, contains(blocked));
      gate.complete();
      await tester.pump();
      expect(previewCount(), previews);
      await settle(tester);
      expect(receipt.completed, 1);
      expect(receipt.result, isNull);
      expect(find.text('父编辑器'), findsOneWidget);
      expect(core.calls.where((c) => c.$1 == 'draft.save'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Busy Android system back cancels a held preview before late image installation',
    (tester) async {
      final gate = Completer<void>();
      core.gates['media.reviewPreview/'] = gate;
      final receipt = await pushWorkspace(tester);
      expect(find.bySemanticsLabel('待编辑照片：人像样片'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(core.cancelledJobs, contains(core.blockedJobs.single));
      gate.complete();
      await tester.pump();
      expect(find.bySemanticsLabel('待编辑照片：人像样片'), findsNothing);
      await settle(tester);
      expect(receipt.completed, 1);
      expect(receipt.result, isNull);
      expect(core.calls.where((c) => c.$1 == 'draft.save'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Busy body cancellation restores parent staged effects and old analysis finally cannot unlock a new face task',
    (tester) async {
      final receipt = await pushWorkspace(tester);
      await tester.tap(find.text('面部'));
      await settle(tester);
      await more(tester, '停用此人脸');
      final parent = lastPreviewLocal();
      await tester.tap(find.byTooltip('返回人像工具'));
      await settle(tester);
      await tester.tap(find.text('塑形'));
      await settle(tester);
      final oldBody = Completer<void>();
      core.gates['media.retouchAnalyze/body'] = oldBody;
      await tester.tap(find.text('自动定位'));
      await settle(tester);
      final blocked = core.blockedJobs.single;
      await tester.tap(find.byTooltip('取消塑形并返回人像'));
      await settle(tester);
      expect(receipt.completed, 0);
      expect(lastPreviewLocal(), parent);
      expect(core.cancelledJobs, contains(blocked));
      expect(find.text('人像'), findsOneWidget);
      await tester.tap(find.text('面部'));
      await settle(tester);
      expect(find.textContaining('已停用'), findsOneWidget);
      final newFace = Completer<void>();
      await startHeldFace(tester, newFace);
      final previews = previewCount();
      oldBody.complete();
      await settle(tester);
      expect(previewCount(), previews);
      expect(lastPreviewLocal(), parent);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '应用'))
            .onPressed,
        isNull,
      );
      expect(
        core.calls.where(
          (c) =>
              c.$1 == 'media.retouchAnalyze' &&
              c.$2['mode'] == 'body' &&
              c.$2['locate'] == true,
        ),
        isEmpty,
      );
      await tester.tap(find.byTooltip('取消人像精修'));
      await tester.pump();
      newFace.complete();
      await settle(tester);
      expect(receipt.completed, 1);
      expect(receipt.result, isNull);
      expect(core.calls.where((c) => c.$1 == 'draft.save'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Busy body system back returns to its staged portrait without popping that route',
    (tester) async {
      final receipt = await pushWorkspace(tester);
      await tester.tap(find.text('塑形'));
      await settle(tester);
      final gate = Completer<void>();
      core.gates['media.retouchAnalyze/body'] = gate;
      await tester.tap(find.text('背景保护'));
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(receipt.completed, 0);
      expect(find.text('人像'), findsOneWidget);
      expect(find.text('父编辑器'), findsNothing);
      final previews = previewCount();
      gate.complete();
      await settle(tester);
      expect(previewCount(), previews);
      await tester.tap(find.byTooltip('取消人像精修'));
      await settle(tester);
      expect(receipt.completed, 1);
      expect(receipt.result, isNull);
      expect(core.calls.where((c) => c.$1 == 'draft.save'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'Busy regional child cancellation pops only that route and leaves the parent staged portrait',
    (tester) async {
      core.regionId = 'region-a';
      final receipt = await pushWorkspace(
        tester,
        regionId: 'region-a',
        parentStage: true,
      );
      await tester.tap(find.text('面部'));
      await settle(tester);
      final gate = Completer<void>();
      await startHeldFace(tester, gate);
      final previews = previewCount();
      await tester.tap(find.byTooltip('取消人像精修'));
      await tester.pump();
      gate.complete();
      await settle(tester);
      expect(previewCount(), previews);
      expect(receipt.completed, 1);
      expect(receipt.result, isNull);
      expect(find.text('父人像暂存效果'), findsOneWidget);
      expect(find.text('父编辑器'), findsNothing);
      expect(core.calls.where((c) => c.$1 == 'draft.save'), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
}
