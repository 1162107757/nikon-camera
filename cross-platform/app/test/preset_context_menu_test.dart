import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/preset_context_menu.dart';
import 'package:huevia/theme.dart';

Widget _host(
  List<PresetContextAction?> results, {
  bool pinned = false,
  Brightness brightness = Brightness.light,
  String name = '林间漫步',
  double textScale = 1,
  bool reduceMotion = false,
}) => MaterialApp(
  theme: hueviaTheme(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: reduceMotion,
      padding: const EdgeInsets.only(bottom: 24),
      viewPadding: const EdgeInsets.only(bottom: 24),
    ),
    child: child!,
  ),
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: GestureDetector(
          key: const ValueKey('preset-card'),
          onLongPress: () async {
            results.add(
              await showPresetContextMenu(
                context: context,
                presetName: name,
                pinned: pinned,
              ),
            );
          },
          child: const SizedBox(
            width: 160,
            height: 160,
            child: Center(child: Text('预设卡片')),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester) async {
  await tester.longPress(find.byKey(const ValueKey('preset-card')));
  await tester.pumpAndSettle();
}

Future<NavigatorState> _pushParentAndOpen(
  WidgetTester tester,
  List<PresetContextAction?> results,
) async {
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      theme: hueviaTheme(Brightness.light),
      home: const Scaffold(body: Text('根页面')),
      routes: {
        '/presets': (context) => Scaffold(
          body: Column(
            children: [
              const Text('预设父页面'),
              TextButton(
                onPressed: () async {
                  results.add(
                    await showPresetContextMenu(
                      context: context,
                      presetName: '林间漫步',
                      pinned: false,
                    ),
                  );
                },
                child: const Text('打开菜单'),
              ),
            ],
          ),
        ),
      },
    ),
  );
  navigator.currentState!.pushNamed('/presets');
  await tester.pumpAndSettle();
  await tester.tap(find.text('打开菜单'));
  await tester.pumpAndSettle();
  return navigator.currentState!;
}

void _size(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'two queued close callbacks in one frame preserve the parent route',
    (tester) async {
      final results = <PresetContextAction?>[];
      await _pushParentAndOpen(tester, results);
      final close = tester
          .widget<HueIconButton>(find.byType(HueIconButton))
          .onPressed!;
      close();
      close();
      await tester.pumpAndSettle();
      expect(results, [null]);
      expect(find.text('预设父页面'), findsOneWidget);
      expect(find.text('根页面'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final lateAction in ['pin', 'close']) {
    testWidgets('queued $lateAction after system back cannot pop the parent', (
      tester,
    ) async {
      final results = <PresetContextAction?>[];
      await _pushParentAndOpen(tester, results);
      final close = tester
          .widget<HueIconButton>(find.byType(HueIconButton))
          .onPressed!;
      final pin = tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(const ValueKey('preset-context-pin-action')),
              matching: find.byType(InkWell),
            ),
          )
          .onTap!;
      await tester.binding.handlePopRoute();
      // No frame is pumped between system back and the retained callback.
      (lateAction == 'pin' ? pin : close)();
      await tester.pumpAndSettle();
      expect(results, [null]);
      expect(find.text('预设父页面'), findsOneWidget);
      expect(find.text('根页面'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'long press offers two actions and pin returns immediately once',
    (tester) async {
      final results = <PresetContextAction?>[];
      await tester.pumpWidget(_host(results));
      await _open(tester);
      expect(find.text('林间漫步'), findsOneWidget);
      expect(find.text('置顶'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      await tester.tap(find.text('置顶'));
      await tester.pumpAndSettle();
      expect(results, [PresetContextAction.pin]);
      expect(find.byKey(const ValueKey('preset-context-menu')), findsNothing);
      expect(find.text('确认'), findsNothing);
    },
  );

  testWidgets(
    'a pinned preset offers unpin and returns the same toggle action',
    (tester) async {
      final results = <PresetContextAction?>[];
      await tester.pumpWidget(_host(results, pinned: true));
      await _open(tester);
      expect(find.text('取消置顶'), findsOneWidget);
      expect(find.text('置顶'), findsNothing);
      await tester.tap(find.text('取消置顶'));
      await tester.pumpAndSettle();
      expect(results, [PresetContextAction.pin]);
    },
  );

  testWidgets('delete returns an intent for the existing caller confirmation', (
    tester,
  ) async {
    final results = <PresetContextAction?>[];
    await tester.pumpWidget(_host(results));
    await _open(tester);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(results, [PresetContextAction.remove]);
  });

  for (final dismissal in ['outside', 'close', 'back']) {
    testWidgets('$dismissal cancels without dispatching an action', (
      tester,
    ) async {
      final results = <PresetContextAction?>[];
      await tester.pumpWidget(_host(results));
      await _open(tester);
      if (dismissal == 'outside') {
        await tester.tapAt(const Offset(8, 8));
      } else if (dismissal == 'close') {
        await tester.tap(find.byTooltip('关闭预设操作'));
      } else {
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(results, [null]);
      expect(find.byKey(const ValueKey('preset-context-menu')), findsNothing);
    });
  }

  testWidgets('phone menu is compact with comfortably sized action targets', (
    tester,
  ) async {
    _size(tester, const Size(360, 780));
    await tester.pumpWidget(_host([]));
    await _open(tester);
    final menu = tester.getRect(
      find.byKey(const ValueKey('preset-context-menu')),
    );
    expect(menu.width, lessThanOrEqualTo(336));
    expect(menu.height, lessThan(200));
    expect(menu.bottom, lessThanOrEqualTo(780 - 24 - 12));
    for (final key in ['pin', 'remove']) {
      final target = tester.getSize(
        find.byKey(ValueKey('preset-context-$key-action')),
      );
      expect(target.height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('long names and large type fit a narrow $brightness phone', (
      tester,
    ) async {
      _size(tester, const Size(280, 640));
      final results = <PresetContextAction?>[];
      await tester.pumpWidget(
        _host(
          results,
          pinned: true,
          brightness: brightness,
          name: 'Huevia_超长的预设名称_秋日海岸与山间的光线_20261113.NP3',
          textScale: 2,
          reduceMotion: true,
        ),
      );
      await _open(tester);
      expect(tester.takeException(), isNull);
      final palette = HuePalette(
        dark: brightness == Brightness.dark,
        home: true,
      );
      expect(
        tester
            .widget<Material>(find.byKey(const ValueKey('preset-context-menu')))
            .color,
        palette.card,
      );
      await tester.tap(find.text('取消置顶'));
      await tester.pumpAndSettle();
      expect(results, [PresetContextAction.pin]);
    });
  }

  testWidgets('short landscape can scroll to deletion and still dismiss', (
    tester,
  ) async {
    _size(tester, const Size(720, 180));
    final results = <PresetContextAction?>[];
    await tester.pumpWidget(_host(results, textScale: 2));
    await _open(tester);
    await tester.ensureVisible(find.text('删除'));
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(results, [PresetContextAction.remove]);
  });
}
