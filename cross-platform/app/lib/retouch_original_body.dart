import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'retouch_more.dart';
import 'retouch_original_controls.dart';

/// Original PhotoBodyDialog.resize height, including the panel's 12 dp padding.
double retouchOriginalBodyDockHeight(
  Size body,
  double fontScale, {
  required bool expanded,
}) {
  if (body.width > body.height && body.width >= 480) return body.height;
  final height = (expanded ? 372 : 180) + 72 * (math.max(1.0, fontScale) - 1);
  return math.max(1.0, math.min(body.height / 2, height));
}

/// Pure controlled PhotoBodyDialog panel. RetouchOriginalDock supplies the
/// original padding (12,4,12,8); this widget adds none of its own.
class RetouchOriginalBodyControls extends StatelessWidget {
  const RetouchOriginalBodyControls({
    super.key,
    required this.tool,
    required this.area,
    required this.protection,
    required this.singleLeg,
    required this.expanded,
    required this.busy,
    this.onTool,
    this.onExpanded,
    this.onLocate,
    this.onProtection,
    this.onSingleLeg,
    this.onReset,
    this.onExact,
    this.onAxis,
    this.onStart,
    this.onChanged,
    this.onEnd,
    this.onCancel,
    this.onAxisStart,
    this.onAxisEnd,
    this.onAxisCancel,
  });
  final int tool, protection;
  final Map<String, dynamic> area;
  final bool singleLeg, expanded, busy;
  final ValueChanged<int>? onTool,
      onExact,
      onAxisStart,
      onAxisEnd,
      onAxisCancel;
  final ValueChanged<bool>? onExpanded;
  final VoidCallback? onLocate,
      onProtection,
      onSingleLeg,
      onReset,
      onStart,
      onEnd,
      onCancel;
  final ValueChanged<double>? onChanged;
  final void Function(int axis, double normalized)? onAxis;
  static const names = ['瘦身', '瘦腿', '腿部拉长'];
  double n(String key) => (area[key] as num).toDouble();
  Future<void> exact(BuildContext context) async {
    final value = await showRetouchOriginalInteger(
      context,
      title: '${names[tool]} · 0—100',
      value: n('amount').round(),
    );
    if (context.mounted && value != null) onExact?.call(value);
  }

  Widget action(
    String label,
    VoidCallback? callback, {
    String? description,
    Color color = retouchOriginalMuted,
  }) => Semantics(
    label: description,
    button: true,
    enabled: !busy && callback != null,
    child: TextButton(
      onPressed: busy ? null : callback,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        foregroundColor: color,
        textStyle: const TextStyle(fontSize: 11, height: 1),
      ),
      child: Text(label, maxLines: 2, textAlign: TextAlign.center),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final axes = [
      n('left'),
      n('top'),
      n('right') - n('left'),
      n('bottom') - n('top'),
    ];
    final height =
        72.0 * math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  names[tool],
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1,
                    color: retouchOriginalText,
                  ),
                ),
              ),
              if (tool == 1)
                SizedBox(
                  width: 56,
                  child: action(
                    singleLeg ? '单腿' : '双腿',
                    onSingleLeg,
                    description: singleLeg ? '当前单腿，点按切换为双腿' : '当前双腿，点按切换为单腿',
                  ),
                ),
              Expanded(
                child: RetouchOriginalSlider(
                  label: '',
                  labelWidth: 0,
                  valueWidth: 48,
                  value: n('amount'),
                  min: 0,
                  max: 100,
                  semanticLabel: '${names[tool]}强度，范围0至100',
                  trailing: Semantics(
                    label:
                        '${names[tool]}强度 ${n('amount').round()}，范围0至100，点按输入数值',
                    button: true,
                    child: TextButton(
                      onPressed: busy || onExact == null
                          ? null
                          : () => exact(context),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        padding: EdgeInsets.zero,
                        foregroundColor: retouchOriginalAccent,
                        textStyle: const TextStyle(fontSize: 12, height: 1),
                      ),
                      child: Text('${n('amount').round()}'),
                    ),
                  ),
                  onChangeStart: busy || onChanged == null
                      ? null
                      : (_) => onStart?.call(),
                  onChanged: busy ? null : onChanged,
                  onChangeEnd: busy || onChanged == null
                      ? null
                      : (_) => onEnd?.call(),
                  onChangeCancel: onCancel,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in [
                (0, '瘦身', 'body'),
                (1, '瘦腿', 'legs'),
                (2, '拉长', 'length'),
              ])
                Expanded(
                  child: RetouchOriginalToolButton(
                    label: item.$2,
                    icon: item.$3,
                    semanticLabel: names[item.$1],
                    selected: tool == item.$1,
                    onPressed: busy || onTool == null
                        ? null
                        : () => onTool!(item.$1),
                  ),
                ),
              Expanded(
                child: RetouchOriginalToolButton(
                  label: '范围',
                  icon: 'range-options',
                  selected: expanded,
                  semanticLabel: expanded ? '收起塑形范围参数' : '展开塑形范围参数',
                  onPressed: busy || onExpanded == null
                      ? null
                      : () => onExpanded!(!expanded),
                ),
              ),
              Expanded(
                child: RetouchOriginalToolButton(
                  label: '重置',
                  icon: 'reset',
                  semanticLabel: '重置当前${names[tool]}，保留其他塑形项',
                  onPressed: busy ? null : onReset,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Expanded(child: action('自动定位', onLocate)),
              Expanded(
                child: action(
                  protection > 0 ? '背景保护 · 开' : '背景保护',
                  onProtection,
                  color: protection > 0
                      ? retouchOriginalAccent
                      : retouchOriginalMuted,
                ),
              ),
            ],
          ),
        ),
        if (expanded)
          for (var axis = 0; axis < 4; axis++)
            RetouchOriginalSlider(
              key: ValueKey('body-box-$axis'),
              label: ['左边', '上边', '宽度', '高度'][axis],
              labelWidth: 48,
              valueWidth: 40,
              value: (axes[axis] * 1000).roundToDouble().clamp(0, 1000),
              min: 0,
              max: 1000,
              semanticLabel: '塑形范围${['左边', '上边', '宽度', '高度'][axis]}',
              formatValue: (value) => '${(value / 10).round()}%',
              trailing: Text(
                '${(axes[axis] * 100).round()}%',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1,
                  color: retouchOriginalMuted,
                ),
              ),
              onChangeStart: busy || onAxis == null
                  ? null
                  : (_) => onAxisStart?.call(axis),
              onChanged: busy || onAxis == null
                  ? null
                  : (value) => onAxis!(axis, value.round() / 1000),
              onChangeEnd: busy || onAxis == null
                  ? null
                  : (_) => onAxisEnd?.call(axis),
              onChangeCancel: () => onAxisCancel?.call(axis),
            ),
      ],
    );
  }
}
