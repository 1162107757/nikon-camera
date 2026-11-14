import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/retouch_more.dart';

const heals = [
  RetouchHealEntry(index: 0, x: .2, y: .31),
  RetouchHealEntry(index: 1, x: .55, y: .42),
];
const card = RetouchToneCard(id: 'card-one', name: '日常暖肤', rgb: 0xc9977c);
RetouchMoreState state({
  int? face = 0,
  bool enabled = true,
  bool skin = true,
  bool perFace = false,
  bool hasHeals = true,
  int cards = 1,
  bool available = true,
}) => RetouchMoreState(
  selectedFace: face,
  faceEnabled: enabled,
  heals: hasHeals ? heals : [],
  hasPortrait: true,
  skinMode: skin,
  tonePerFace: perFace,
  toneCardCount: cards,
  enabled: available,
);

Widget launch(Future<void> Function(BuildContext) action) => MaterialApp(
  home: Scaffold(
    appBar: AppBar(
      actions: [
        Builder(
          builder: (context) => IconButton(
            key: const ValueKey('open'),
            onPressed: () => action(context),
            icon: const Icon(Icons.more_horiz),
          ),
        ),
      ],
    ),
  ),
);
Future<void> open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'automatic blemishes begin selected and apply only confirmed candidates',
    (tester) async {
      List<int>? result;
      await tester.pumpWidget(
        launch((context) async {
          result = await showRetouchBlemishCandidates(
            context,
            candidates: heals,
          );
        }),
      );
      await open(tester);
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .every((checkbox) => checkbox.value == true),
        isTrue,
      );
      await tester.tap(find.text('第 1 处 · 20%, 31%'));
      await tester.pump();
      await tester.tap(find.text('修复所选'));
      await tester.pumpAndSettle();
      expect(result, [1]);
      await open(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );

  testWidgets(
    'original seven menu actions and scope labels return real selections',
    (tester) async {
      RetouchMoreAction? result;
      await tester.pumpWidget(
        launch((context) async {
          result = await showRetouchMoreMenu(context, state: state());
        }),
      );
      await open(tester);
      expect(
        tester
            .widgetList<PopupMenuItem<RetouchMoreAction>>(
              find.byType(PopupMenuItem<RetouchMoreAction>),
            )
            .map((item) => item.value),
        RetouchMoreAction.values,
      );
      await tester.tap(find.text('逐人肤色调节（高级）'));
      await tester.pumpAndSettle();
      expect(result, RetouchMoreAction.toggleToneScope);
      await tester.pumpWidget(
        launch((context) async {
          result = await showRetouchMoreMenu(
            context,
            state: state(perFace: true, enabled: false),
          );
        }),
      );
      await open(tester);
      expect(find.text('全图肤色调节'), findsOneWidget);
      await tester.tap(find.text('启用此人脸'));
      await tester.pumpAndSettle();
      expect(result, RetouchMoreAction.toggleFace);
    },
  );

  testWidgets('empty history, no face and empty saved cards stay disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      launch((context) async {
        await showRetouchMoreMenu(
          context,
          state: state(face: null, hasHeals: false, cards: 0),
        );
      }),
    );
    await open(tester);
    for (final label in ['逐处撤销祛痘', '管理个人色卡', '停用此人脸', '删除此人脸', '撤回上一处祛痘']) {
      expect(
        tester
            .widget<PopupMenuItem<RetouchMoreAction>>(
              find.ancestor(
                of: find.text(label),
                matching: find.byType(PopupMenuItem<RetouchMoreAction>),
              ),
            )
            .enabled,
        isFalse,
      );
    }
    await tester.tapAt(const Offset(1, 500));
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      launch((context) async {
        await showRetouchMoreMenu(
          context,
          state: state(skin: false, available: false),
        );
      }),
    );
    await open(tester);
    expect(find.text('管理个人色卡'), findsNothing);
    expect(find.text('逐人肤色调节（高级）'), findsNothing);
    expect(
      tester
          .widgetList<PopupMenuItem<RetouchMoreAction>>(
            find.byType(PopupMenuItem<RetouchMoreAction>),
          )
          .every((item) => !item.enabled),
      isTrue,
    );
  });

  testWidgets(
    'history returns the selected heal index rather than last patch',
    (tester) async {
      int? result;
      await tester.pumpWidget(
        launch((context) async {
          result = await showRetouchHealingHistory(context, heals: heals);
        }),
      );
      await open(tester);
      await tester.tap(find.text('撤销第 1 处 · 20%, 31%'));
      await tester.pumpAndSettle();
      expect(result, 0);
      await open(tester);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );

  testWidgets(
    'portrait reset requires explicit confirmation and explains undo',
    (tester) async {
      bool? result;
      await tester.pumpWidget(
        launch((context) async {
          result = await confirmRetouchReset(context);
        }),
      );
      await open(tester);
      expect(find.text('清除本次照片的肤色、磨皮、面部调整、塑形、选区修正和祛痘。仍可撤销。'), findsOneWidget);
      final dialog = tester.widget<Dialog>(find.byType(Dialog));
      expect(dialog.backgroundColor, const Color(0xff292724));
      expect(
        (dialog.shape! as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(24),
      );
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      await open(tester);
      await tester.tap(find.text('重置'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    },
  );

  testWidgets(
    'card manager confirms deletion, preserves photograph colour, reloads authoritative list',
    (tester) async {
      var deleted = <String>[];
      List<RetouchToneCard>? result;
      await tester.pumpWidget(
        launch((context) async {
          result = await showRetouchToneCards(
            context,
            cards: [card],
            onDelete: (id) async {
              deleted.add(id);
              return [];
            },
          );
        }),
      );
      await open(tester);
      await tester.tap(find.text('删除 · 日常暖肤'));
      await tester.pumpAndSettle();
      expect(find.text('照片中已经使用的颜色会保留。'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty);
      await tester.tap(find.text('删除 · 日常暖肤'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(deleted, ['card-one']);
      expect(find.text('在自定义肤色中保存个人色卡。'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(result, isEmpty);
    },
  );

  testWidgets('delete failure keeps existing cards and allows retry', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      launch((context) async {
        await showRetouchToneCards(
          context,
          cards: [card],
          onDelete: (_) async {
            if (attempts++ == 0) throw StateError('private backend detail');
            return [];
          },
        );
      }),
    );
    await open(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('删除 · 日常暖肤'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      if (i == 0) {
        expect(find.text('色卡未能删除，请重试。'), findsOneWidget);
        expect(find.textContaining('private backend'), findsNothing);
      }
    }
    expect(attempts, 2);
    expect(find.text('删除 · 日常暖肤'), findsNothing);
  });

  testWidgets(
    'saving validates names and duplicate colours before persistent callback',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        launch((context) async {
          await showRetouchSaveToneCard(
            context,
            cards: [card],
            rgb: card.rgb,
            onSave: (_, _) async {
              calls++;
              return [];
            },
          );
        }),
      );
      await open(tester);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请为色卡填写 1–12 个字的名称。'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('skin-tone-name')),
        '新色卡',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('这个颜色已经保存在个人色卡中。'), findsOneWidget);
      expect(calls, 0);
    },
  );

  testWidgets(
    'failed save retains input; pending save blocks dismissal and duplicate requests',
    (tester) async {
      var calls = 0;
      final pending = Completer<List<RetouchToneCard>>();
      List<RetouchToneCard>? result;
      await tester.pumpWidget(
        launch((context) async {
          result = await showRetouchSaveToneCard(
            context,
            cards: [],
            rgb: card.rgb,
            onSave: (name, rgb) async {
              calls++;
              expect(name, '日常暖肤');
              expect(rgb, card.rgb);
              if (calls == 1) throw StateError('private detail');
              return pending.future;
            },
          );
        }),
      );
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('skin-tone-name')),
        ' 日常暖肤 ',
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('色卡未能保存，请重试。'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('skin-tone-name')))
            .controller!
            .text,
        ' 日常暖肤 ',
      );
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '保存'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
            .onPressed,
        isNull,
      );
      pending.complete([card]);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(result!.single.id, card.id);
    },
  );

  testWidgets(
    'custom HSV changes notify immediately and closing retains the selected RGB',
    (tester) async {
      RetouchTonePickerResult? result;
      final live = <int>[];
      await tester.pumpWidget(
        launch((context) async {
          result = await showRetouchCustomTone(
            context,
            rgb: 0xff0000,
            cards: [],
            onSave: (_, _) async => [],
            onChanged: live.add,
          );
        }),
      );
      await open(tester);
      expect(find.text('预览  #FF0000'), findsOneWidget);
      final hue = tester.widget<Slider>(
        find.byKey(const ValueKey('skin-tone-hue')),
      );
      hue.onChanged!(120);
      await tester.pump();
      expect(result, isNull);
      expect(find.text('预览  #00FF00'), findsOneWidget);
      expect(live, [0x00ff00]);
      expect(find.text('预览效果'), findsNothing);
      await tester.tap(find.byTooltip('关闭肤色选择器'));
      await tester.pumpAndSettle();
      expect(result!.action, RetouchTonePickerAction.preview);
      expect(result!.rgb, 0x00ff00);
      await open(tester);
      await tester.ensureVisible(find.text('照片取色'));
      await tester.tap(find.text('照片取色'));
      await tester.pumpAndSettle();
      expect(result!.action, RetouchTonePickerAction.sample);
      expect(result!.rgb, 0xff0000);
      await open(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );

  testWidgets(
    'saving in custom picker persists a card and leaves preview uncommitted',
    (tester) async {
      var saved = 0;
      RetouchTonePickerResult? result;
      await tester.pumpWidget(
        launch((context) async {
          result = await showRetouchCustomTone(
            context,
            rgb: card.rgb,
            cards: [],
            onSave: (name, rgb) async {
              saved++;
              expect(rgb, card.rgb);
              return [card];
            },
          );
        }),
      );
      await open(tester);
      await tester.ensureVisible(find.text('保存色卡'));
      await tester.tap(find.text('保存色卡'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('skin-tone-name')),
        card.name,
      );
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(saved, 1);
      expect(result, isNull);
      expect(find.text('自定义肤色'), findsOneWidget);
      await tester.ensureVisible(find.text('已保存，可在肤色栏中重复使用。'));
      expect(find.text('已保存，可在肤色栏中重复使用。'), findsOneWidget);
    },
  );
}
