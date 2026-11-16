import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor_more.dart';
import 'package:huevia/editor_quick.dart';
import 'package:huevia/hue_icons.dart';

void main() {
  test('Original photo actions retain source ordering, scope hints and conditional groups', () {
    List<EditorMoreEntry> rows(EditorMoreState state) =>
        editorMoreEntries(state, iconFor: (_) => HueIconKind.more);
    final all = rows(const EditorMoreState(canDelete: true, parkedDraft: true));
    expect(all.map((e) => e.title), [
      '收藏照片',
      '直方图',
      '照片版本',
      '查看细节',
      '全部滤镜',
      '快速优化',
      '照片配方',
      '精细构图',
      '复制调色',
      '撤销复制',
      '继续编辑',
      '重置调色',
      '还原原图',
      '删除照片',
    ]);
    expect(all.map((e) => e.group), [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 3]);
    final scope = rows(
      const EditorMoreState(
        showFavourite: false,
        readable: false,
        regionName: '天空',
      ),
    );
    expect(scope.where((e) => e.action == EditorMoreAction.favourite), isEmpty);
    expect(
      scope.where((e) => e.action == EditorMoreAction.continueDraft),
      isEmpty,
    );
    expect(scope.where((e) => e.action == EditorMoreAction.delete), isEmpty);
    expect(
      scope.singleWhere((e) => e.action == EditorMoreAction.resetColour).hint,
      '仅清除天空的调色',
    );
    expect(
      scope
          .where(
            (e) => [
              EditorMoreAction.copy,
              EditorMoreAction.resetColour,
              EditorMoreAction.restoreOriginal,
            ].contains(e.action),
          )
          .every((e) => !e.enabled),
      isTrue,
    );
  });
  test('Quick presets use original absolute coefficients and preserve unrelated editing', () {
    final base = Recipe().data
      ..addAll({
        'presetId': 'look',
        'localData': 'portrait-regions-patches',
        'geometry': {'turns': 1},
        'border': {'template': 3},
        'curves': {
          'r': [1, 2],
        },
      });
    base['values'] = [70, 80, 90, 33, ...List.filled(13, 0)];
    final parameters = [
      for (final (i, name) in ['BRIGHTNESS', 'CONTRAST', 'VIBRANCE'].indexed)
        {'index': i, 'name': name, 'min': -100, 'max': 100},
    ];
    final natural = editorQuickRecipe(
      base: base,
      parameters: parameters,
      style: 1,
      amount: 55,
      cleanupData: 'actual-analysis',
      localData: 'portrait-regions-patches',
    );
    expect((natural['values'] as List).take(4), [3, 1, 1, 33]);
    expect(natural['presetId'], 'look');
    expect(natural['localData'], base['localData']);
    expect(natural['geometry'], base['geometry']);
    expect(natural['border'], base['border']);
    expect(natural['curves'], base['curves']);
    expect(natural['cleanup'], {'amount': 55, 'haze': 45, 'noise': 85});
    final clear = editorQuickRecipe(
      base: base,
      parameters: parameters,
      style: 2,
      amount: 48,
      cleanupData: 'a',
      localData: 'p',
    );
    expect((clear['values'] as List).take(3), [1, 4, 3]);
    final portrait = editorQuickRecipe(
      base: base,
      parameters: parameters,
      style: 3,
      amount: 45,
      cleanupData: 'a',
      localData: 'p',
    );
    expect(portrait['cleanup'], {'amount': 20, 'haze': 25, 'noise': 65});
    final zero = editorQuickRecipe(
      base: natural,
      parameters: parameters,
      style: 1,
      amount: 0,
      cleanupData: 'a',
      localData: 'p',
    );
    expect(zero.containsKey('cleanupData'), isFalse);
    expect(zero.containsKey('cleanup'), isFalse);
    expect(base['values'], [70, 80, 90, 33, ...List.filled(13, 0)]);
  });
  testWidgets(
    'Header uses full 48 target and original menu is anchored and scrollable at large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      EditorMoreAction? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 600),
              textScaler: TextScaler.linear(1.8),
            ),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 62, top: 20),
                  child: Builder(
                    builder: (anchor) => EditorHeaderButton(
                      icon: HueIconKind.more,
                      label: '更多照片操作和重置',
                      onPressed: () async {
                        chosen = await showEditorMoreMenu(
                          anchor,
                          entries: editorMoreEntries(
                            const EditorMoreState(canDelete: true),
                            iconFor: (_) => HueIconKind.more,
                          ),
                          isCurrent: () => true,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final button = find.byType(EditorHeaderButton);
      expect(tester.getSize(button), const Size(48, 48));
      await tester.tapAt(tester.getTopLeft(button) + const Offset(2, 24));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      final popup = find.byKey(const ValueKey('photo-actions-menu'));
      expect(tester.getTopLeft(popup).dx, 28);
      expect(tester.getTopLeft(popup).dy, 74);
      expect(tester.getSize(popup).width, 280);
      final deletion = find.byKey(const ValueKey('photo-action-delete'));
      await tester.ensureVisible(deletion);
      await tester.tap(deletion);
      await tester.pumpAndSettle();
      expect(chosen, EditorMoreAction.delete);
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
  testWidgets('An open menu closes when its photo owner becomes invalid', (
    tester,
  ) async {
    final lifecycle = ValueNotifier<bool>(true);
    addTearDown(lifecycle.dispose);
    EditorMoreAction? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (anchor) => EditorHeaderButton(
              icon: HueIconKind.more,
              label: '更多',
              onPressed: () async {
                chosen = await showEditorMoreMenu(
                  anchor,
                  entries: editorMoreEntries(
                    const EditorMoreState(),
                    iconFor: (_) => HueIconKind.more,
                  ),
                  isCurrent: () => lifecycle.value,
                  lifecycle: lifecycle,
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(EditorHeaderButton));
    await tester.pumpAndSettle();
    lifecycle.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('photo-actions-menu')), findsNothing);
    expect(chosen, isNull);
  }, timeout: const Timeout(Duration(seconds: 45)));
}
