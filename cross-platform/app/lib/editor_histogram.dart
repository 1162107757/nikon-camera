import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

enum EditorHistogramChannel { luminance, red, green, blue }

/// Statistics of opaque, encoded sRGB working content, before an external frame.
/// Diagnostics are never recipe parameters or export pixels.
class EditorHistogramData {
  EditorHistogramData._(
    this.width,
    this.height,
    this._bins,
    this._clips,
    this.highlightCount,
    this.shadowCount,
  );

  factory EditorHistogramData.fromRgba(Uint8List rgba, int width, int height) {
    if (width < 1 || height < 1 || rgba.length != width * height * 4) {
      throw ArgumentError('预览像素范围无效。');
    }
    final bins = List.generate(4, (_) => List<int>.filled(256, 0));
    // Keep classifications, not a second complete preview pixel buffer.
    final clips = Uint8List(width * height);
    var highlights = 0, shadows = 0;
    for (var i = 0; i < clips.length; i++) {
      final p = i * 4;
      if (rgba[p + 3] != 255) {
        throw ArgumentError('预览需为不透明 sRGB 工作内容。');
      }
      final r = rgba[p], g = rgba[p + 1], b = rgba[p + 2];
      bins[0][(.2126 * r + .7152 * g + .0722 * b).round()]++;
      bins[1][r]++;
      bins[2][g]++;
      bins[3][b]++;
      if (r == 255 || g == 255 || b == 255) {
        clips[i] |= 1;
        highlights++;
      }
      if (r == 0 && g == 0 && b == 0) {
        clips[i] |= 2;
        shadows++;
      }
    }
    return EditorHistogramData._(
      width,
      height,
      [for (final channel in bins) List<int>.unmodifiable(channel)],
      clips,
      highlights,
      shadows,
    );
  }

  factory EditorHistogramData.empty() => EditorHistogramData._(
    0,
    0,
    List.generate(4, (_) => List<int>.unmodifiable(List<int>.filled(256, 0))),
    Uint8List(0),
    0,
    0,
  );

  final int width, height;
  final List<List<int>> _bins;
  final Uint8List _clips;
  final int highlightCount, shadowCount;
  int get pixelCount => width * height;
  bool get hasData => pixelCount > 0;
  List<int> bins(EditorHistogramChannel channel) => _bins[channel.index];
  int count(EditorHistogramChannel channel, int bin) {
    if (bin < 0 || bin > 255) throw ArgumentError('直方图区间须为 0–255。');
    return _bins[channel.index][bin];
  }

  int max(EditorHistogramChannel channel) =>
      _bins[channel.index].fold(0, math.max);
  int get sharedRgbMaximum => math.max(
    max(EditorHistogramChannel.red),
    math.max(
      max(EditorHistogramChannel.green),
      max(EditorHistogramChannel.blue),
    ),
  );
  String get highlightPercent => percent(highlightCount, pixelCount);
  String get shadowPercent => percent(shadowCount, pixelCount);

  static String percent(int hits, int total) {
    if (total < 0 || hits < 0 || hits > total) {
      throw ArgumentError('预览统计计数无效。');
    }
    if (total == 0) return '—';
    if (hits == 0) return '0%';
    final value = hits * 100 / total;
    return value < .1 ? '<0.1%' : '${value.toStringAsFixed(1)}%';
  }

  /// A distinct premultiplied RGBA overlay. Source pixels stay untouched.
  /// ui.PixelFormat.rgba8888 can consume these bytes directly.
  Uint8List makeWarningRgba({bool shadows = false, bool highlights = false}) {
    final result = Uint8List(pixelCount * 4);
    if (!shadows && !highlights) return result;
    final stripe = math.max(3, math.min(10, math.min(width, height) ~/ 70));
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        final high = highlights && (_clips[i] & 1) != 0;
        final low = shadows && (_clips[i] & 2) != 0;
        if (!high && !low) continue;
        final line = (high ? x - y : x + y) % (stripe * 2) < stripe;
        final alpha = line ? 144 : 46;
        final tint = high ? 0xf3a676 : 0x80b9f2;
        final p = i * 4;
        result[p] = (((tint >> 16) & 255) * alpha + 127) ~/ 255;
        result[p + 1] = (((tint >> 8) & 255) * alpha + 127) ~/ 255;
        result[p + 2] = ((tint & 255) * alpha + 127) ~/ 255;
        result[p + 3] = alpha;
      }
    }
    return result;
  }
}

String editorHistogramExplanation(EditorHistogramData? data, {String? error}) {
  final message = error?.trim() ?? '';
  final measured = data?.hasData == true
      ? '当前统计：暗部 ${data!.shadowPercent}，高光 ${data.highlightPercent}。\n\n'
      : '';
  return '${message.isEmpty ? '' : '$message\n\n'}$measured基于当前 sRGB 预览，统计整幅构图内容，不含外加边框。\n\n'
      '高光：任一 RGB 通道为 255。暗部：三通道均为 0。RGB 三通道共用纵轴。\n\n'
      '暖色右斜纹表示高光，蓝色左斜纹表示暗部，仅辅助判断，不代表原片细节一定不可恢复；并非 RAW 测量。警示不会写入导出照片。';
}

const _accent = Color(0xffffe335);
const _accentInk = Color(0xff2a1c12);

double _histogramLabelWidth(
  BuildContext context,
  String label,
  double size,
  FontWeight weight,
) {
  final text = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(fontSize: size, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = text.width;
  text.dispose();
  return width;
}

/// Controlled version of PhotoHistogramPanel's compact diagnostic overlay.
/// The host owns snapshot identity, asynchronous generations and image lifetime.
class EditorHistogramPanel extends StatelessWidget {
  const EditorHistogramPanel({
    super.key,
    this.data,
    this.updating = false,
    this.error,
    this.rgb = false,
    this.shadows = false,
    this.highlights = false,
    this.onRgb,
    this.onShadows,
    this.onHighlights,
    this.onExplain,
  });
  final EditorHistogramData? data;
  final bool updating, rgb, shadows, highlights;
  final String? error;
  final ValueChanged<bool>? onRgb, onShadows, onHighlights;
  final VoidCallback? onExplain;

  bool get valid => data?.hasData == true;
  bool get old => updating || (error?.trim().isNotEmpty ?? false);
  String get status => updating
      ? (valid ? '更新中 · 上次预览' : '统计中')
      : (error?.trim().isNotEmpty ?? false)
      ? (valid ? '失败 · 上次预览' : '统计不可用')
      : valid
      ? '8 位 sRGB'
      : '暂无预览';

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final footerStyle = const TextStyle(
      fontSize: 9.5,
      color: Color(0x6bffffff),
      height: 1,
    );
    final footerMeasure = TextPainter(
      text: TextSpan(text: status, style: footerStyle),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final footerHeight = math.max(12.0, footerMeasure.height.ceilToDouble());
    footerMeasure.dispose();
    final shadowPercent = valid ? data!.shadowPercent : '—';
    final highlightPercent = valid ? data!.highlightPercent : '—';
    final shadowLabel =
        '暗部警示，${shadows ? '已开启' : '已关闭'}，'
        '${old && valid ? '上次预览 ' : ''}$shadowPercent，蓝色左斜纹';
    final highlightLabel =
        '高光警示，${highlights ? '已开启' : '已关闭'}，'
        '${old && valid ? '上次预览 ' : ''}$highlightPercent，暖色右斜纹，任一通道触顶';
    final summary = valid
        ? '${rgb ? 'RGB 三通道，共享纵轴' : '显示亮度，0 至 255'}，有效预览像素 ${data!.pixelCount}，暗部 $shadowPercent，高光 $highlightPercent'
        : '暂无有效预览统计';
    final chartLabel =
        '$status，$summary${old && valid ? '，上一份有效预览' : ''}'
        '${error?.trim().isNotEmpty == true ? '，${error!.trim()}' : ''}，轻点查看直方图与警示说明';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xc71a1613),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x29ffffff), width: .5),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          height: 92 + footerHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 40,
                height: 52,
                child: Semantics(
                  label: chartLabel,
                  liveRegion: true,
                  button: true,
                  onTap: onExplain,
                  child: ExcludeSemantics(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onExplain,
                      child: CustomPaint(
                        key: const ValueKey('editor-histogram-chart'),
                        painter: EditorHistogramPainter(
                          data: data,
                          rgb: rgb,
                          updating: updating,
                          textScale: scaler.scale(12) / 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 92,
                height: footerHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onExplain,
                  child: DefaultTextStyle(
                    style: footerStyle,
                    maxLines: 1,
                    child: Row(
                      children: [
                        const SizedBox(width: 22, child: Text('0')),
                        Expanded(
                          child: Text(status, textAlign: TextAlign.center),
                        ),
                        const SizedBox(
                          width: 22,
                          child: Text('255', textAlign: TextAlign.end),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 48,
                child: LayoutBuilder(
                  builder: (context, bounds) {
                    final chipWidth = math.max(
                      48.0,
                      math
                              .max(
                                _histogramLabelWidth(
                                  context,
                                  '暗部',
                                  11,
                                  FontWeight.w400,
                                ),
                                _histogramLabelWidth(
                                  context,
                                  '暗部',
                                  11,
                                  FontWeight.w500,
                                ),
                              )
                              .ceilToDouble() +
                          28,
                    );
                    final contentWidth = math.max(
                      bounds.maxWidth,
                      96 + chipWidth * 2 + 6,
                    );
                    return Semantics(
                      label: '直方图工具，窄屏可左右滑动',
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: contentWidth,
                          child: Row(
                            children: [
                              _HistogramToggle(
                                label: '亮度',
                                selected: !rgb,
                                onTap: onRgb == null
                                    ? null
                                    : () => onRgb!(false),
                              ),
                              _HistogramToggle(
                                label: 'RGB',
                                selected: rgb,
                                onTap: onRgb == null
                                    ? null
                                    : () => onRgb!(true),
                              ),
                              const Spacer(),
                              _HistogramToggle(
                                label: '暗部',
                                semantics: shadowLabel,
                                selected: shadows,
                                high: false,
                                width: chipWidth,
                                enabled: valid,
                                onTap: !valid || onShadows == null
                                    ? null
                                    : () => onShadows!(!shadows),
                              ),
                              const SizedBox(width: 6),
                              _HistogramToggle(
                                label: '高光',
                                semantics: highlightLabel,
                                selected: highlights,
                                high: true,
                                width: chipWidth,
                                enabled: valid,
                                onTap: !valid || onHighlights == null
                                    ? null
                                    : () => onHighlights!(!highlights),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistogramToggle extends StatelessWidget {
  const _HistogramToggle({
    required this.label,
    required this.selected,
    this.semantics,
    this.high,
    this.width = 48,
    this.enabled = true,
    this.onTap,
  });
  final String label;
  final String? semantics;
  final bool selected, enabled;
  final bool? high;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = high != null;
    final textColor = chip
        ? (selected ? _accentInk : const Color(0xccffffff))
        : (selected ? Colors.white : const Color(0x99ffffff));
    final text = Text(
      label,
      maxLines: 1,
      style: TextStyle(
        fontSize: chip ? 11 : 12,
        color: textColor,
        fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
        height: 1,
      ),
    );
    return Semantics(
      label: semantics ?? label,
      button: true,
      checked: selected,
      enabled: enabled,
      onTap: onTap,
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          height: 48,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Opacity(
              opacity: enabled ? 1 : .55,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (chip)
                    Container(
                      height: 28,
                      width: width,
                      decoration: BoxDecoration(
                        color: selected ? _accent : const Color(0x12ffffff),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? _accent : const Color(0x38ffffff),
                        ),
                      ),
                    ),
                  if (chip)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CustomPaint(
                          size: const Size(8, 8),
                          painter: _WarningSwatchPainter(high!),
                        ),
                        const SizedBox(width: 4),
                        text,
                      ],
                    )
                  else
                    text,
                  if (!chip && selected)
                    Positioned(
                      bottom: 12,
                      child: Container(
                        height: 2,
                        width: math.max(
                          14,
                          _histogramLabelWidth(
                            context,
                            label,
                            12,
                            FontWeight.w500,
                          ).ceilToDouble(),
                        ),
                        decoration: BoxDecoration(
                          color: _accent,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WarningSwatchPainter extends CustomPainter {
  const _WarningSwatchPainter(this.high);
  final bool high;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)));
    canvas.drawRect(
      rect,
      Paint()..color = Color(high ? 0xff5a3a14 : 0xff17233a),
    );
    final paint = Paint()
      ..color = Color(high ? 0xffff9838 : 0xff6aa0ff)
      ..strokeWidth = 2;
    final extent = size.width + size.height;
    for (var x = -extent; x < extent * 2; x += 4) {
      canvas.drawLine(
        Offset(x, high ? size.height : 0),
        Offset(x + size.height, high ? 0 : size.height),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WarningSwatchPainter oldDelegate) =>
      high != oldDelegate.high;
}

class EditorHistogramPainter extends CustomPainter {
  const EditorHistogramPainter({
    this.data,
    this.rgb = false,
    this.updating = false,
    this.textScale = 1,
  });
  final EditorHistogramData? data;
  final bool rgb, updating;
  final double textScale;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 2) return;
    const top = 1.0;
    final bottom = size.height - 1;
    final grid = Paint()
      ..color = const Color(0x24ffffff)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, bottom), Offset(size.width, bottom), grid);
    final histogram = data;
    if (histogram == null || !histogram.hasData) {
      final text = TextPainter(
        text: TextSpan(
          text: updating ? '统计中' : '暂无统计',
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(textScale),
      )..layout(maxWidth: size.width);
      text.paint(
        canvas,
        Offset((size.width - text.width) / 2, (size.height - text.height) / 2),
      );
      text.dispose();
      return;
    }
    void channel(EditorHistogramChannel channel, int color, int maximum) {
      if (maximum <= 0) return;
      final path = Path();
      final bins = histogram.bins(channel);
      for (var bin = 0; bin < 256; bin++) {
        final x = size.width * bin / 255;
        final y = bottom - (bottom - top) * bins[bin] / maximum;
        if (bin == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final area = Path.from(path)
        ..lineTo(size.width, bottom)
        ..lineTo(0, bottom)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..color = Color((color & 0xffffff) | (rgb ? 0x47000000 : 0x4d000000)),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Color(color)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    if (rgb) {
      final maximum = histogram.sharedRgbMaximum;
      channel(EditorHistogramChannel.red, 0xffff6a5e, maximum);
      channel(EditorHistogramChannel.green, 0xff6fe38c, maximum);
      channel(EditorHistogramChannel.blue, 0xff6ea0ff, maximum);
    } else {
      channel(
        EditorHistogramChannel.luminance,
        0xd9ffffff,
        histogram.max(EditorHistogramChannel.luminance),
      );
      for (var i = 1; i < 4; i++) {
        final x = size.width * i / 4;
        canvas.drawLine(Offset(x, top), Offset(x, bottom), grid);
      }
    }
    void endpoint(double x, Color color) {
      final path = Path()
        ..moveTo(x, top + 6)
        ..lineTo(x - 3, top)
        ..lineTo(x + 3, top)
        ..close();
      canvas.drawPath(path, Paint()..color = color);
    }

    if (histogram.shadowCount > 0) endpoint(0, const Color(0xff93b6e4));
    if (histogram.highlightCount > 0) endpoint(size.width, _accent);
  }

  @override
  bool shouldRepaint(EditorHistogramPainter oldDelegate) =>
      data != oldDelegate.data ||
      rgb != oldDelegate.rgb ||
      updating != oldDelegate.updating ||
      textScale != oldDelegate.textScale;
}
