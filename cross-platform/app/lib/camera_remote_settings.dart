import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

part 'camera_remote_ruler.dart';

const _surface = Color(0xf5202b25);
const _border = Color(0x55e2f2dd);
const _accent = Color(0xffd6ecbb);
const _muted = Color(0xffc7cec2);

const remoteWhiteBalance = 0x5005;
const remoteTemperature = 0xd01e;
const remoteTemperatureMode = 0x8012;

const remoteSettingTitles = <int, String>{
  0x500d: '快门',
  0x5007: '光圈',
  0x500f: 'ISO',
  0x5010: '曝光补偿',
  remoteWhiteBalance: '白平衡',
};

const remoteWhiteBalanceLabels = <int, String>{
  2: '自动',
  4: '晴天',
  0x8010: '阴天',
  6: '白炽灯',
  5: '荧光灯',
  0x8011: '阴影',
  7: '闪光灯',
  0x8015: '闪光灯',
  0x8016: '自然光自动',
  0x8013: '手动预设',
  1: '手动',
  3: '单次自动',
  0x8014: '关闭',
  remoteTemperatureMode: '色温',
};

class CameraRemoteSettingCard extends StatelessWidget {
  const CameraRemoteSettingCard({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
    this.tabs,
    this.action,
    this.readout,
  });

  final String title;
  final VoidCallback? onClose;
  final Widget child;
  final Widget? tabs;
  final Widget? action;
  final Widget? readout;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: _surface,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 8, 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: _muted,
                          ),
                        ),
                      ),
                      if (readout case final value?) ...[
                        const SizedBox(width: 7),
                        Flexible(
                          fit: FlexFit.tight,
                          child: FittedBox(
                            alignment: Alignment.centerLeft,
                            fit: BoxFit.scaleDown,
                            child: value,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?tabs,
                ?action,
                IconButton(
                  tooltip: '收起参数调节',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                ),
              ],
            ),
            child,
          ],
        ),
      ),
    ),
  );
}

class CameraRemoteWhiteBalancePresets extends StatefulWidget {
  const CameraRemoteWhiteBalancePresets({
    super.key,
    required this.presets,
    required this.selected,
    required this.onChanged,
  });

  final List<int> presets;
  final int? selected;
  final ValueChanged<int>? onChanged;

  @override
  State<CameraRemoteWhiteBalancePresets> createState() =>
      _CameraRemoteWhiteBalancePresetsState();
}

class _CameraRemoteWhiteBalancePresetsState
    extends State<CameraRemoteWhiteBalancePresets> {
  final scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void more() {
    if (!scroll.hasClients) return;
    final position = scroll.position;
    final offset = position.pixels >= position.maxScrollExtent - 1
        ? 0.0
        : math.min(
            position.pixels + position.viewportDimension,
            position.maxScrollExtent,
          );
    scroll.animateTo(
      offset,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: scroll,
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 6,
                children: [
                  for (final preset in widget.presets)
                    ChoiceChip(
                      showCheckmark: false,
                      selectedColor: const Color(0xff42533b),
                      label: Text(remoteWhiteBalanceLabels[preset]!),
                      selected: preset == widget.selected,
                      onSelected: widget.onChanged == null
                          ? null
                          : (selected) {
                              if (selected) widget.onChanged?.call(preset);
                            },
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '浏览更多白平衡预设',
            icon: const Icon(Icons.chevron_right),
            onPressed: more,
          ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 5),
        child: Text(
          '点按切换 · 左右滑动查看更多',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: _muted),
        ),
      ),
    ],
  );
}
