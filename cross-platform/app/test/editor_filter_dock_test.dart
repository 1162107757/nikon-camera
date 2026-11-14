import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor.dart';
import 'package:huevia/split_compare.dart';
import 'package:huevia/theme.dart';

class _FilterDockCore extends HueviaCore {
  _FilterDockCore(this.directory) {
    root = directory.path;
    schema = {
      'parameters': List.generate(
        17,
        (index) => {
          'index': index,
          'name': 'BRIGHTNESS',
          'label': '参数$index',
          'min': -100,
          'max': 100,
        },
      ),
    };
  }
  final Directory directory;
  final calls = <(String, Json)>[];
  final pending = <String, Completer<Json>>{};
  final rejected = <String>{};
  bool catalogFails = false;
  String get image => '${directory.path}/previews/filter.png';
  static String identity(int index) => index.toRadixString(16).padLeft(64, 'a');
  final catalog = List.generate(
    30,
    (index) => {
      'id': 'catalog-$index',
      'sha256': identity(index),
      'name': '在线滤镜${index.toString().padLeft(2, '0')}',
      'category': index.isEven ? '风景' : '人像',
      'fileFormat': 'NCP',
    },
  );

  @override
  Future<void> cancel(String jobId) async {}

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    // Freeze request data: the product may advance its mutable editor recipe.
    calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
    switch (operation) {
      case 'editor.catalog':
        return catalogFails
            ? {'status': 'network_error', 'message': '离线'}
            : {'status': 'ok', 'items': catalog};
      case 'editor.prepare':
        final id = object(payload['preset'])['sha256'] as String;
        if (rejected.contains(id)) throw const AppFailure('准备失败');
        return pending[id]?.future ?? {'id': id};
      case 'draft.load':
        return {
          'sourceSha': 'source-unchanged',
          'recipe': {
            'schema': 1,
            'presetId': 'saved-filter',
            'presetName': '已保存滤镜',
            'strength': 37,
            'values': List.filled(17, 0),
          },
        };
      case 'local.describe':
        return {'localData': '', 'sha256': 'empty', 'regions': []};
      case 'media.reviewPreview':
      case 'media.preview':
      case 'media.originalPreview':
        return {
          'path': image,
          'width': 1,
          'height': 1,
          'sourceWidth': 1,
          'sourceHeight': 1,
        };
      case 'draft.save':
        return {'sourceSha': 'source-unchanged', 'recipe': payload['recipe']};
      default:
        return {};
    }
  }

  List<(String, Json)> get edits => calls
      .where((call) => call.$1 == 'media.preview' || call.$1 == 'draft.save')
      .toList();
  String get editFingerprint => jsonEncode([
    for (final call in edits) [call.$1, call.$2],
  ]);
}

class _FilterDockState extends AppState {
  _FilterDockState(super.core);
  void changeOwner() {
    session = {
      'user': {'id': 'another-owner'},
    };
    notifyListeners();
  }
}

Future<void> _frames(WidgetTester tester, [int count = 8]) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 70));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 4)),
    );
  }
}

Future<(_FilterDockCore, _FilterDockState)> _open(
  WidgetTester tester, {
  Size size = const Size(375, 844),
  double textScale = 1,
  void Function(_FilterDockCore)? configure,
}) async {
  final directory = Directory.systemTemp.createTempSync('huevia-filter-dock-');
  Directory('${directory.path}/previews').createSync();
  File('${directory.path}/previews/filter.png').writeAsBytesSync(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
    ),
  );
  final core = _FilterDockCore(directory);
  configure?.call(core);
  final state = _FilterDockState(core)
    ..presets = [
      const Preset({
        'id': 'mine-film',
        'displayName': '我的胶片',
        'category': '胶片',
        'fileFormat': 'NCP',
      }),
      const Preset({
        'id': 'mine-night',
        'displayName': '我的夜景',
        'category': '夜景',
        'fileFormat': 'NCP',
      }),
      const Preset({
        'id': 'mine-plain',
        'displayName': '无分类滤镜',
        'fileFormat': 'NCP',
      }),
    ];
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('cc.huevia/events'),
        (_) async => null,
      );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await _frames(tester, 2);
    state.dispose();
    tester.binding.imageCache.clear();
    tester.binding.imageCache.clearLiveImages();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('cc.huevia/events'),
          null,
        );
    await tester.runAsync(() async {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: EditorPage(
        state: state,
        photo: Photo('${directory.path}/source.png', '照片', const {}),
      ),
    ),
  );
  await _frames(tester);
  expect(find.byKey(const ValueKey('legacy-filter-dock')), findsOneWidget);
  return (core, state);
}

Finder _picker() => find.byKey(const ValueKey('legacy-filter-picker'));
Finder _card(int index) =>
    find.byKey(ValueKey('picker-filter-${_FilterDockCore.identity(index)}'));

Future<void> _viewAll(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('filter-view-all')));
  await _frames(tester);
  expect(_picker(), findsOneWidget);
}

// Measure the laid-out glyph boxes, rather than the surrounding 48dp targets.
double _glyphCenter(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final length = paragraph.text.toPlainText().length;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: length),
  );
  expect(boxes, isNotEmpty);
  var bounds = boxes.first.toRect();
  for (final box in boxes.skip(1)) {
    bounds = bounds.expandToInclude(box.toRect());
  }
  return paragraph.localToGlobal(bounds.center).dy;
}

void _expectHeadingCenters(WidgetTester tester, [String category = '']) {
  final icon = find.descendant(
    of: find.byKey(const ValueKey('filter-view-all')),
    matching: find.byType(HueIcon),
  );
  final iconCenter = tester.getRect(icon).center.dy;
  for (final key in [
    'filter-source-mine',
    'filter-source-online',
    'filter-category-$category',
  ]) {
    final label = find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(Text),
    );
    expect(
      (_glyphCenter(tester, label) - iconCenter).abs(),
      lessThanOrEqualTo(1.5),
      reason:
          '$key must share the visible grid icon center, including selected underline',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Visible source/category glyphs and all-filters icon keep one center when a category is selected',
    (tester) async {
      await _open(tester);
      _expectHeadingCenters(tester);
      await tester.tap(find.byKey(const ValueKey('filter-category-人像')));
      await _frames(tester);
      _expectHeadingCenters(tester, '人像');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Fixed source and categories browse without changing the saved effect or strength',
    (tester) async {
      final (core, _) = await _open(tester);
      final before = core.editFingerprint;
      await tester.tap(find.byKey(const ValueKey('filter-source-mine')));
      await _frames(tester);
      await tester.tap(find.byKey(const ValueKey('filter-category-胶片')));
      await _frames(tester);
      expect(find.text('我的胶片'), findsOneWidget);
      expect(find.text('我的夜景'), findsNothing);
      expect(core.editFingerprint, before);
      expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('filter-strength')))
            .value,
        37,
      );
      await tester.tap(find.byKey(const ValueKey('filter-source-online')));
      await _frames(tester);
      expect(find.byKey(const ValueKey('filter-category-风景')), findsOneWidget);
      expect(core.editFingerprint, before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'View all is a three-column search grid and source changes clear its query',
    (tester) async {
      final (core, _) = await _open(tester);
      final before = core.editFingerprint;
      await _viewAll(tester);
      final grid = tester.widget<GridView>(
        find.byKey(const ValueKey('filter-picker-grid')),
      );
      expect(
        (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount,
        3,
      );
      await tester.enterText(
        find.byKey(const ValueKey('filter-picker-search')),
        '人像',
      );
      await _frames(tester);
      expect(
        find.descendant(of: _picker(), matching: find.text('原图')),
        findsNothing,
      );
      expect(
        find.descendant(of: _picker(), matching: find.text('在线滤镜01')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _picker(), matching: find.text('在线滤镜00')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('filter-source-mine')).last);
      await _frames(tester);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('filter-picker-search')),
            )
            .controller!
            .text,
        '',
      );
      expect(
        find.descendant(of: _picker(), matching: find.text('我的胶片')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('filter-picker-search')),
        '未分类',
      );
      await _frames(tester);
      expect(
        find.descendant(of: _picker(), matching: find.text('无分类滤镜')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _picker(), matching: find.text('我的胶片')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('filter-picker-close')));
      await _frames(tester);
      expect(_picker(), findsNothing);
      expect(core.editFingerprint, before);
    },
  );

  testWidgets(
    'Picker installs the prepared SHA once and original disables intensity',
    (tester) async {
      final (core, _) = await _open(tester);
      await _viewAll(tester);
      await tester.tap(
        find.descendant(of: _card(0), matching: find.text('在线滤镜00')),
      );
      await _frames(tester);
      expect(_picker(), findsNothing);
      final applied = core.edits
          .lastWhere((call) => call.$1 == 'media.preview')
          .$2['recipe'];
      expect(applied['presetId'], _FilterDockCore.identity(0));
      expect(applied['strength'], 100);
      expect(
        core.calls.where(
          (call) =>
              call.$1 == 'editor.prepare' &&
              object(call.$2['preset'])['sha256'] ==
                  _FilterDockCore.identity(0),
        ),
        hasLength(1),
      );
      await tester.tap(find.byKey(const ValueKey('strip-filter-')));
      await _frames(tester);
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('filter-strength')),
      );
      expect(slider.value, 0);
      expect(slider.onChanged, isNull);
    },
  );

  testWidgets(
    'Failed preparation stays in the picker and can retry without losing the current effect',
    (tester) async {
      final (core, _) = await _open(
        tester,
        configure: (core) => core.rejected.add(_FilterDockCore.identity(0)),
      );
      final before = core.editFingerprint;
      await _viewAll(tester);
      await tester.tap(
        find.descendant(of: _card(0), matching: find.text('在线滤镜00')),
      );
      await _frames(tester);
      expect(_picker(), findsOneWidget);
      expect(find.textContaining('滤镜准备失败'), findsOneWidget);
      expect(core.editFingerprint, before);
      core.rejected.clear();
      await tester.tap(
        find.descendant(of: _card(0), matching: find.text('在线滤镜00')),
      );
      await _frames(tester);
      expect(_picker(), findsNothing);
      expect(
        core.edits.last.$2['recipe']['presetId'],
        _FilterDockCore.identity(0),
      );
    },
  );

  testWidgets(
    'Cancel during preparation ignores the late result and repeated close never pops the editor',
    (tester) async {
      final reply = Completer<Json>();
      final (core, _) = await _open(
        tester,
        configure: (core) => core.pending[_FilterDockCore.identity(0)] = reply,
      );
      final before = core.editFingerprint;
      await _viewAll(tester);
      await tester.tap(
        find.descendant(of: _card(0), matching: find.text('在线滤镜00')),
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'Starting a pending picker preparation keeps a valid semantics tree',
      );
      await tester.tap(find.byKey(const ValueKey('filter-picker-close')));
      await tester.tap(find.byKey(const ValueKey('filter-picker-close')));
      await _frames(tester);
      reply.complete({'id': _FilterDockCore.identity(0)});
      await _frames(tester);
      expect(_picker(), findsNothing);
      expect(find.byType(EditorPage), findsOneWidget);
      expect(core.editFingerprint, before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Owner change while preparing hides the picker and cannot install in the new account',
    (tester) async {
      final reply = Completer<Json>();
      final (core, state) = await _open(
        tester,
        configure: (core) => core.pending[_FilterDockCore.identity(0)] = reply,
      );
      await _viewAll(tester);
      await tester.tap(
        find.descendant(of: _card(0), matching: find.text('在线滤镜00')),
      );
      await tester.pump();
      state.changeOwner();
      await tester.pump();
      expect(
        find.descendant(of: _picker(), matching: find.byType(Image)),
        findsNothing,
      );
      reply.complete({'id': _FilterDockCore.identity(0)});
      await _frames(tester);
      expect(_picker(), findsNothing);
      expect(
        core.edits.any((call) => call.$2['owner'] == 'another-owner'),
        false,
      );
      expect(
        core.edits
            .where((call) => call.$1 == 'media.preview')
            .every((call) => call.$2['recipe']['presetId'] == 'saved-filter'),
        true,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final layout in [
    (const Size(320, 640), 1.0),
    (const Size(375, 844), 1.3),
    (const Size(844, 390), 1.3),
  ]) {
    testWidgets(
      'Filter source and picker remain usable at ${layout.$1} / ${layout.$2}',
      (tester) async {
        await _open(tester, size: layout.$1, textScale: layout.$2);
        expect(
          tester
              .getRect(find.byKey(const ValueKey('filter-source-tabs')))
              .height,
          48,
        );
        expect(
          tester.getRect(find.byType(SplitCompare)).height,
          greaterThan(40),
        );
        _expectHeadingCenters(tester);
        await _viewAll(tester);
        expect(
          find.byKey(const ValueKey('filter-picker-search')),
          findsOneWidget,
        );
        expect(
          tester.getRect(_picker()).bottom,
          lessThanOrEqualTo(layout.$1.height + 1),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('filter-picker-close')));
        await _frames(tester);
      },
    );
  }
}
