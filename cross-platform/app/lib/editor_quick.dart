import 'dart:io';

import 'package:flutter/material.dart';

import 'domain.dart';

/// PhotoQuickPreset.java's reversible parameter bundles; native analysis is supplied separately.
Json editorQuickRecipe({
  required Json base,
  required List<Json> parameters,
  required int style,
  required int amount,
  required String cleanupData,
  required String localData,
}) {
  if (style < 1 || style > 3 || amount < 0 || amount > 100) {
    throw const AppFailure('快速优化参数无效。');
  }
  final result = Recipe(data: base).data,
      values = List<int>.from(base['values'] as List);
  void owned(String name, double delta) {
    final parameter = parameters.where((p) => p['name'] == name).firstOrNull;
    if (parameter == null) throw AppFailure('当前编辑模型缺少$name参数。');
    final index = parameter['index'] as int;
    values[index] = delta.round().clamp(
      parameter['min'] as int,
      parameter['max'] as int,
    );
  }

  owned(
    'BRIGHTNESS',
    amount *
        (style == 1
            ? .06
            : style == 3
            ? .03
            : .015),
  );
  owned(
    'CONTRAST',
    amount *
        (style == 2
            ? .09
            : style == 1
            ? .025
            : 0),
  );
  owned('VIBRANCE', amount * (style == 2 ? .06 : .025));
  result['values'] = values;
  result['localData'] = localData;
  if (amount == 0) {
    result.remove('cleanupData');
    result.remove('cleanup');
  } else {
    result['cleanupData'] = cleanupData;
    result['cleanup'] = {
      'amount': style == 3 ? (amount * .45).round() : amount,
      'haze': style == 2
          ? 100
          : style == 1
          ? 45
          : 25,
      'noise': style == 2
          ? 75
          : style == 1
          ? 85
          : 65,
    };
  }
  return result;
}

class EditorQuickPanel extends StatelessWidget {
  const EditorQuickPanel({
    super.key,
    required this.style,
    required this.amount,
    required this.busy,
    this.thumbnail,
    this.onStyle,
    this.onStart,
    this.onChanged,
    this.onEnd,
    this.onCancel,
  });
  final int style, amount;
  final bool busy;
  final String? thumbnail;
  final ValueChanged<int>? onStyle;
  final VoidCallback? onStart, onEnd, onCancel;
  final ValueChanged<int>? onChanged;
  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (index, name) in [
                  '原图',
                  '自然',
                  '通透',
                  '人像',
                ].indexed) ...[
                  if (index > 0) const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: style == index,
                      label: '快速优化，$name',
                      excludeSemantics: true,
                      onTap: busy || onStyle == null
                          ? null
                          : () => onStyle!(index),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(9),
                        splashColor: const Color(0x22ffe335),
                        onTap: busy || onStyle == null
                            ? null
                            : () => onStyle!(index),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: 52,
                              clipBehavior: Clip.antiAlias,
                              foregroundDecoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(9),
                                border: style == index
                                    ? Border.all(color: const Color(0xffbbb9a1))
                                    : null,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xff33302c),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: thumbnail == null
                                  ? null
                                  : Image.file(
                                      File(thumbnail!),
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      gaplessPlayback: true,
                                    ),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 22 * scale,
                              child: Center(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: style == index
                                        ? const Color(0xfff4f5f7)
                                        : const Color(0xffc8cdca),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                SizedBox(
                  width: 52 * scale,
                  child: busy
                      ? TextButton(
                          onPressed: onCancel,
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          child: const Text(
                            '取消分析',
                            style: TextStyle(fontSize: 11),
                          ),
                        )
                      : Text(
                          style < 0 ? '已调整' : '强度',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xffc8cdca),
                          ),
                        ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbColor: Colors.white,
                      activeTrackColor: const Color(0xffffe335),
                      inactiveTrackColor: const Color(0x66ffffff),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                    ),
                    child: Slider(
                      value: amount.toDouble(),
                      min: 0,
                      max: 100,
                      divisions: 100,
                      onChangeStart: busy || style < 1
                          ? null
                          : (_) => onStart?.call(),
                      onChanged: busy || style < 1 || onChanged == null
                          ? null
                          : (v) => onChanged!(v.round()),
                      onChangeEnd: busy || style < 1
                          ? null
                          : (_) => onEnd?.call(),
                    ),
                  ),
                ),
                SizedBox(
                  width: 32 * scale,
                  child: Text(
                    style > 0 ? '$amount' : '—',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xffffe335),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
