import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/editor_histogram.dart';

Uint8List _rgba(List<int> colors) => Uint8List.fromList([
  for (final color in colors) ...[
    (color >> 16) & 255,
    (color >> 8) & 255,
    color & 255,
    255,
  ],
]);

void main() {
  test('Encoded sRGB bins match original coefficients and exact clipping boundaries', () {
    final data = EditorHistogramData.fromRgba(
      _rgba([0, 0xffffff, 0xff0000, 0x00ff00, 0x0000ff, 0xfefefe, 0x010000]),
      7,
      1,
    );
    expect(data.pixelCount, 7);
    expect(data.highlightCount, 4);
    expect(data.shadowCount, 1);
    expect(data.highlightPercent, '57.1%');
    expect(data.shadowPercent, '14.3%');
    expect(data.count(EditorHistogramChannel.luminance, 0), 2);
    for (final bin in [18, 54, 182, 254, 255]) {
      expect(data.count(EditorHistogramChannel.luminance, bin), 1);
    }
    for (final channel in EditorHistogramChannel.values) {
      expect(data.bins(channel).fold(0, (int a, int b) => a + b), 7);
    }
    expect(data.max(EditorHistogramChannel.red), 3);
    expect(data.max(EditorHistogramChannel.green), 4);
    expect(data.sharedRgbMaximum, 4);
  });

  test(
    'No data, measured zero, tiny clipping and full clipping remain distinct',
    () {
      final empty = EditorHistogramData.empty();
      expect(empty.hasData, false);
      expect(empty.highlightPercent, '—');
      expect(empty.makeWarningRgba(shadows: true), isEmpty);
      expect(EditorHistogramData.percent(0, 9), '0%');
      expect(EditorHistogramData.percent(1, 1001), '<0.1%');
      expect(EditorHistogramData.percent(1, 1000), '0.1%');
      expect(EditorHistogramData.percent(1, 3), '33.3%');
      expect(EditorHistogramData.percent(9, 9), '100.0%');
      for (final pair in [(-1, 2), (3, 2), (0, -1)]) {
        expect(
          () => EditorHistogramData.percent(pair.$1, pair.$2),
          throwsArgumentError,
        );
      }
    },
  );

  test('Histogram rejects malformed dimensions, nonopaque working pixels and out-of-range bins', () {
    for (final size in [(0, 1), (1, 0), (-1, 1), (2, 2)]) {
      expect(
        () => EditorHistogramData.fromRgba(_rgba([0]), size.$1, size.$2),
        throwsArgumentError,
      );
    }
    expect(
      () =>
          EditorHistogramData.fromRgba(Uint8List.fromList([0, 0, 0, 0]), 1, 1),
      throwsArgumentError,
    );
    final data = EditorHistogramData.fromRgba(_rgba([0]), 1, 1);
    expect(
      () => data.count(EditorHistogramChannel.red, -1),
      throwsArgumentError,
    );
    expect(
      () => data.count(EditorHistogramChannel.blue, 256),
      throwsArgumentError,
    );
    expect(
      () => data.bins(EditorHistogramChannel.red)[0] = 0,
      throwsUnsupportedError,
    );
  });

  test('Warnings retain frozen classifications without changing the input or histogram', () {
    final source = _rgba([0, 0xffffff, 0xfefefe, 0x010101]);
    final before = Uint8List.fromList(source);
    final data = EditorHistogramData.fromRgba(source, 4, 1);
    final disabled = data.makeWarningRgba();
    final mask = data.makeWarningRgba(shadows: true, highlights: true);
    expect(disabled, everyElement(0));
    expect(mask.sublist(8), everyElement(0));
    expect(source, before);
    source.fillRange(0, source.length, 255);
    expect(data.makeWarningRgba(shadows: true, highlights: true), mask);
    expect(data.shadowCount, 1);
    expect(data.highlightCount, 1);
    expect(
      identical(mask, data.makeWarningRgba(shadows: true, highlights: true)),
      false,
    );
  });

  test('Warm right stripes and blue left stripes preserve original phase and alpha', () {
    final white = EditorHistogramData.fromRgba(
      _rgba(List.filled(36, 0xffffff)),
      6,
      6,
    );
    final black = EditorHistogramData.fromRgba(_rgba(List.filled(36, 0)), 6, 6);
    final high = white.makeWarningRgba(highlights: true);
    final low = black.makeWarningRgba(shadows: true);
    List<int> at(Uint8List bytes, int x, int y) =>
        bytes.sublist((y * 6 + x) * 4, (y * 6 + x) * 4 + 4);
    expect(at(high, 0, 0), [137, 94, 67, 144]);
    expect(at(low, 0, 0), [72, 104, 137, 144]);
    expect(at(high, 0, 1), [44, 30, 21, 46]);
    expect(at(low, 0, 1), [72, 104, 137, 144]);
    expect(at(high, 3, 0).last, 46);
    expect(at(high, 3, 3).last, 144);
    expect(at(low, 3, 3).last, 144);
    expect(black.makeWarningRgba(highlights: true), everyElement(0));
    expect(white.makeWarningRgba(shadows: true), everyElement(0));
  });

  test(
    'Warning stripe scale clamps at original upper bound on larger previews',
    () {
      final data = EditorHistogramData.fromRgba(
        _rgba(List.filled(700 * 700, 0xffffff)),
        700,
        700,
      );
      final mask = data.makeWarningRgba(highlights: true);
      expect(mask[9 * 4 + 3], 144);
      expect(mask[10 * 4 + 3], 46);
      expect(mask[19 * 4 + 3], 46);
      expect(mask[20 * 4 + 3], 144);
    },
  );

  test('Explanation identifies preview-only encoded measurements and excludes export warnings', () {
    final data = EditorHistogramData.fromRgba(_rgba([0, 0xffffff]), 2, 1);
    final text = editorHistogramExplanation(data, error: '预览读取失败');
    expect(text, startsWith('预览读取失败\n\n当前统计：暗部 50.0%，高光 50.0%。'));
    expect(text, contains('不含外加边框'));
    expect(text, contains('RGB 三通道共用纵轴'));
    expect(text, contains('并非 RAW 测量'));
    expect(text, contains('警示不会写入导出照片'));
  });

  Future<void> show(
    WidgetTester tester,
    Widget panel, {
    Size size = const Size(400, 300),
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(width: size.width, child: panel),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'No preview keeps mode controls available while both warning controls are disabled',
    (tester) async {
      var modes = 0, warnings = 0;
      final semantics = tester.ensureSemantics();
      try {
        await show(
          tester,
          EditorHistogramPanel(
            onRgb: (_) => modes++,
            onShadows: (_) => warnings++,
            onHighlights: (_) => warnings++,
          ),
        );
        await tester.tap(find.text('RGB'));
        await tester.tap(find.text('暗部'));
        await tester.tap(find.text('高光'));
        expect(modes, 1);
        expect(warnings, 0);
        expect(find.text('暂无预览'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('暂无有效预览统计')), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'Controlled diagnostics update warning selection without altering measurement or recipe',
    (tester) async {
      final data = EditorHistogramData.fromRgba(_rgba([0, 0xffffff]), 2, 1);
      var rgb = false, shadows = false, highlights = false, explained = 0;
      await show(
        tester,
        StatefulBuilder(
          builder: (context, update) => EditorHistogramPanel(
            data: data,
            rgb: rgb,
            shadows: shadows,
            highlights: highlights,
            onRgb: (v) => update(() => rgb = v),
            onShadows: (v) => update(() => shadows = v),
            onHighlights: (v) => update(() => highlights = v),
            onExplain: () => explained++,
          ),
        ),
      );
      await tester.tap(find.text('RGB'));
      await tester.tap(find.text('暗部'));
      await tester.tap(find.text('高光'));
      await tester.pump();
      expect((rgb, shadows, highlights), (true, true, true));
      expect(data.highlightCount, 1);
      expect(data.shadowCount, 1);
      await tester.tap(find.byKey(const ValueKey('editor-histogram-chart')));
      await tester.tap(find.text('8 位 sRGB'));
      expect(explained, 2);
    },
  );

  testWidgets(
    'Updating and failed diagnostics retain the last valid plot with explicit stale-preview labels',
    (tester) async {
      final data = EditorHistogramData.fromRgba(_rgba([0, 0xffffff]), 2, 1);
      final semantics = tester.ensureSemantics();
      try {
        await show(tester, EditorHistogramPanel(data: data, updating: true));
        expect(find.text('更新中 · 上次预览'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('上一份有效预览')), findsOneWidget);
        final paint =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('editor-histogram-chart')),
                    )
                    .painter
                as EditorHistogramPainter;
        expect(identical(paint.data, data), true);
        await show(tester, EditorHistogramPanel(data: data, error: '读取失败'));
        expect(find.text('失败 · 上次预览'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('读取失败')), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'Narrow large-text panel can scroll warning controls without layout overflow',
    (tester) async {
      final data = EditorHistogramData.fromRgba(_rgba([0, 0xffffff]), 2, 1);
      var high = false;
      await show(
        tester,
        EditorHistogramPanel(data: data, onHighlights: (v) => high = v),
        size: const Size(150, 300),
        scale: 2,
      );
      await tester.ensureVisible(find.text('高光'));
      await tester.tap(find.text('高光'));
      expect(high, true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'RGB painter uses the shared vertical maximum in actual raster output',
    (tester) async {
      final data = EditorHistogramData.fromRgba(
        _rgba([0x506414, 0x506515, 0x506616, 0x506717]),
        4,
        1,
      );
      expect(data.max(EditorHistogramChannel.red), 4);
      expect(data.max(EditorHistogramChannel.green), 1);
      final recorder = ui.PictureRecorder();
      EditorHistogramPainter(
        data: data,
        rgb: true,
      ).paint(Canvas(recorder), const Size(255, 52));
      final picture = recorder.endRecording();
      ui.Image? image;
      try {
        image = await tester.runAsync(() => picture.toImage(256, 52));
        final bytes = await tester.runAsync(
          () => image!.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        final rgba = bytes!.buffer.asUint8List();
        int alpha(int x, int y) => rgba[(y * 256 + x) * 4 + 3];
        expect(
          [for (var y = 0; y < 30; y++) alpha(101, y)],
          everyElement(0),
          reason: 'A channel with one quarter of the shared maximum cannot reach the top.',
        );
        expect(
          [for (var y = 37; y < 42; y++) alpha(101, y)].any((a) => a > 0),
          true,
        );
        expect(
          [for (var y = 0; y < 4; y++) alpha(80, y)].any((a) => a > 0),
          true,
        );
      } finally {
        image?.dispose();
        picture.dispose();
      }
    },
  );
}
