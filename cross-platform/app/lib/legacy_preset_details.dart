import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'domain.dart';
import 'theme.dart';
import 'widgets.dart';
import 'camera.dart';

class LegacyPresetDetails extends StatefulWidget {
  const LegacyPresetDetails({
    super.key,
    required this.state,
    required this.preset,
    required this.onShare,
    required this.onCategory,
    required this.onRemove,
    required this.onDownload,
  });
  final AppState state;
  final Preset preset;
  final VoidCallback onShare, onCategory, onRemove, onDownload;
  @override
  State<LegacyPresetDetails> createState() => _LegacyPresetDetailsState();
}

class _LegacyPresetDetailsState extends State<LegacyPresetDetails> {
  bool original = false;
  late final Future<Json> inspection = widget.preset.online
      ? Future.value({})
      : widget.state.core.call('library.inspect', {'id': widget.preset.id});
  @override
  Widget build(BuildContext context) {
    final theme = hueviaTheme(Theme.of(context).brightness, home: false);
    final palette = theme.extension<HuePalette>()!;
    final preset = widget.preset;
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: const HueHeader(title: '预设详情', back: true),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  children: [
                    AspectRatio(
                      aspectRatio: 1.25,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(26),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PresetImage(
                              preset: preset,
                              original: original,
                              detail: true,
                              core: widget.state.core,
                              owner:
                                  widget.state.session['user']?['id']
                                      as String? ??
                                  '',
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xaa000000),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  original ? '原图' : '预设效果',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                            if (!preset.online)
                              Positioned(
                                right: 14,
                                bottom: 12,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xe62c3037),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(66, 55),
                                  ),
                                  onPressed: () =>
                                      setState(() => original = !original),
                                  child: Text(
                                    original ? '效果' : '原图',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 20, bottom: 4),
                      child: Text(
                        preset.name,
                        style: TextStyle(
                          fontSize: 24,
                          height: 1.17,
                          fontWeight: FontWeight.bold,
                          color: palette.ink,
                        ),
                      ),
                    ),
                    if (preset.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          preset.description,
                          style: const TextStyle(fontSize: 15, height: 1.4),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        height: 48,
                        child: TextButton(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          onPressed: preset.online ? null : widget.onCategory,
                          child: Text(
                            '分类 · ${preset.category.isEmpty ? '未分类' : preset.category}',
                            style: TextStyle(
                              fontSize: 13,
                              color: palette.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!preset.online)
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 16),
                        child: FutureBuilder<Json>(
                          future: inspection,
                          builder: (context, value) {
                            final samples =
                                (value.data?['toneSamples'] as List?)
                                    ?.cast<num>();
                            return Semantics(
                              label:
                                  '色调曲线，${samples == null ? '暂不可用' : '257 个采样点'}',
                              child: SizedBox(
                                height:
                                    188 +
                                    math.max(
                                          0,
                                          MediaQuery.textScalerOf(context)
                                                  .scale(1) -
                                              1,
                                        ) *
                                        86,
                                child: CustomPaint(
                                  painter: _PresetTonePainter(
                                    palette,
                                    preset.format,
                                    samples,
                                    MediaQuery.textScalerOf(context),
                                    value.connectionState ==
                                        ConnectionState.done,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ListTile(
                      leading: const HueIcon(HueIconKind.check),
                      title: Text(preset.online ? '在线预设 · 尚未下载' : '已保存在手机'),
                      subtitle: Text(preset.online ? '下载后保留在我的预设' : '原始预设已保留'),
                      tileColor: palette.container,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    const Divider(height: 24),
                    const ListTile(
                      leading: HueIcon(HueIconKind.camera),
                      title: Text('相机兼容导入'),
                      subtitle: Text('按相机能力与预设格式检查兼容性。'),
                    ),
                    if (!preset.online) ...[
                      TextButton(
                        onPressed: widget.onShare,
                        child: const Text('分享预设文件'),
                      ),
                      TextButton(
                        onPressed: widget.onRemove,
                        child: const Text('删除本地预设'),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '展示样片用于手机近似模拟；相机导入会单独检查可保留的参数，实际效果请试拍确认。',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: palette.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(26),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: palette.dark
                              ? const [Color(0xfff0e8df), Color(0xffdad0c5)]
                              : const [Color(0xff46413b), Color(0xff27241f)],
                        ),
                      ),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          foregroundColor: palette.dark
                              ? const Color(0xff26211c)
                              : Colors.white,
                        ),
                        onPressed: preset.online
                            ? widget.onDownload
                            : () => Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CameraPage(
                                    state: widget.state,
                                    configuration: true,
                                  ),
                                ),
                              ),
                        child: Text(
                          preset.online ? '保存到我的预设' : '导入相机',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    if (!preset.online)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          '导入前检查相机能力与槽位',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: palette.secondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetTonePainter extends CustomPainter {
  const _PresetTonePainter(
    this.palette,
    this.format,
    this.samples,
    this.scaler,
    this.finished,
  );
  final HuePalette palette;
  final String format;
  final List<num>? samples;
  final TextScaler scaler;
  final bool finished;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = palette.card;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      paint,
    );
    void text(
      String label,
      double x,
      double y,
      double size,
      Color color, {
      TextAlign align = TextAlign.left,
      bool bold = false,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: size,
            color: color,
            fontFamily: 'Roboto',
            fontWeight: bold ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
        textScaler: scaler,
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          x -
              (align == TextAlign.center
                  ? painter.width / 2
                  : align == TextAlign.right
                  ? painter.width
                  : 0),
          y,
        ),
      );
    }

    text(
      format == 'NP3' ? '手机色调映射' : '色调曲线',
      16,
      14,
      13,
      palette.ink,
      bold: true,
    );
    text(
      format,
      size.width - 16,
      16,
      11,
      palette.secondary,
      align: TextAlign.right,
    );
    if (samples == null) {
      text(
        finished ? '曲线暂不可用' : '正在读取曲线…',
        size.width / 2,
        size.height / 2 - 2,
        12,
        palette.secondary,
        align: TextAlign.center,
      );
      return;
    }
    final growth = math.max(0.0, scaler.scale(1) - 1);
    final plot = Rect.fromLTRB(
      45 + growth * 12,
      47 + growth * 20,
      size.width - 17,
      size.height - 49 - growth * 22,
    );
    paint
      ..color = palette.outline.withAlpha(palette.dark ? 150 : 160)
      ..strokeWidth = .7;
    for (var i = 0; i <= 4; i++) {
      canvas.drawLine(
        Offset(plot.left + plot.width * i / 4, plot.top),
        Offset(plot.left + plot.width * i / 4, plot.bottom),
        paint,
      );
      canvas.drawLine(
        Offset(plot.left, plot.top + plot.height * i / 4),
        Offset(plot.right, plot.top + plot.height * i / 4),
        paint,
      );
    }
    paint
      ..color = palette.secondary.withAlpha(200)
      ..strokeWidth = 1;
    final diagonal = plot.topRight - plot.bottomLeft;
    for (var step = 0.0; step < diagonal.distance; step += 8) {
      canvas.drawLine(
        plot.bottomLeft + diagonal * (step / diagonal.distance),
        plot.bottomLeft +
            diagonal *
                (math.min(step + 4, diagonal.distance) / diagonal.distance),
        paint,
      );
    }
    final curve = Path();
    for (var i = 0; i < samples!.length; i++) {
      final x = plot.left + plot.width * i / (samples!.length - 1),
          y = plot.bottom - plot.height * samples![i];
      if (i == 0) {
        curve.moveTo(x, y.toDouble());
      } else {
        curve.lineTo(x, y.toDouble());
      }
    }
    paint
      ..style = PaintingStyle.stroke
      ..color = palette.primary
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(curve, paint);
    text(
      '255',
      plot.left - 8,
      plot.top - scaler.scale(5),
      9,
      palette.secondary,
      align: TextAlign.right,
    );
    text(
      '0',
      plot.left - 8,
      plot.bottom - scaler.scale(5),
      9,
      palette.secondary,
      align: TextAlign.right,
    );
    text('输出', 16, plot.center.dy - scaler.scale(5), 9, palette.secondary);
    text(
      '0',
      plot.left,
      plot.bottom + 7,
      9,
      palette.secondary,
      align: TextAlign.center,
    );
    text(
      '255',
      plot.right,
      plot.bottom + 7,
      9,
      palette.secondary,
      align: TextAlign.center,
    );
    text(
      '输入',
      plot.center.dx,
      plot.bottom + 7,
      9,
      palette.secondary,
      align: TextAlign.center,
    );
    final legend = size.height - 24,
        left = size.width / 2 - 91,
        right = size.width / 2 + 13;
    canvas.drawLine(
      Offset(left, legend + scaler.scale(5.5)),
      Offset(left + 14, legend + scaler.scale(5.5)),
      paint,
    );
    text('预设曲线', left + 20, legend, 10, palette.secondary);
    paint
      ..color = palette.secondary.withAlpha(200)
      ..strokeWidth = 1;
    for (var x = right; x < right + 14; x += 8) {
      canvas.drawLine(
        Offset(x, legend + scaler.scale(5.5)),
        Offset(math.min(x + 4, right + 14), legend + scaler.scale(5.5)),
        paint,
      );
    }
    text('线性参考', right + 20, legend, 10, palette.secondary);
  }

  @override
  bool shouldRepaint(covariant _PresetTonePainter old) =>
      old.samples != samples ||
      old.palette != palette ||
      old.scaler != scaler ||
      old.finished != finished;
}
