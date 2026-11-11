import 'package:flutter/material.dart';

import 'theme.dart';

/// Original floating sheet: fixed actions and a separately scrollable body.
class HueFloatingSheet extends StatelessWidget {
  const HueFloatingSheet({
    super.key,
    required this.title,
    required this.closeLabel,
    required this.children,
    required this.onReset,
    required this.onApply,
    this.titleSize = 18,
    this.sorting = false,
  });
  final String title, closeLabel;
  final List<Widget> children;
  final VoidCallback onReset, onApply;
  final double titleSize;
  final bool sorting;

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    final density = MediaQuery.devicePixelRatioOf(context);
    double snap(double value) => (value * density).round() / density;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(snap(10)),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight:
                  (MediaQuery.sizeOf(context).height -
                          MediaQuery.viewPaddingOf(context).vertical -
                          24)
                      .clamp(160, double.infinity),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: p.dark ? Colors.white.withValues(alpha: .16) : p.card,
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  snap(18),
                  snap(10),
                  snap(18),
                  snap(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 30,
                        height: 3,
                        decoration: BoxDecoration(
                          color: p.outline,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: titleSize,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        HueIconButton(
                          kind: HueIconKind.close,
                          label: closeLabel,
                          disc: false,
                          iconSize: 20,
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.only(bottom: sorting ? 0 : snap(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: children,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(top: sorting ? 0 : snap(8)),
                      child: Row(
                        children: [
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: Size(sorting ? 64 : 0, 48),
                              padding: EdgeInsets.symmetric(
                                horizontal: sorting ? 6 : 12,
                              ),
                              textStyle: const TextStyle(fontSize: 14),
                            ),
                            onPressed: onReset,
                            child: const Text('重置'),
                          ),
                          const Spacer(),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: Size(sorting ? 108 : 0, 48),
                              padding: EdgeInsets.symmetric(
                                horizontal: sorting ? 20 : 28,
                                vertical: 8,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: onApply,
                            child: const Text('应用'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HueSheetChoices extends StatelessWidget {
  const HueSheetChoices({
    super.key,
    required this.title,
    required this.values,
    required this.selected,
    required this.onSelected,
    this.columns = 3,
    this.fontSize = 12,
    this.verticalInset = 0,
    this.boldSelection = true,
    this.topPadding = 12,
    this.bottomPadding = 8,
  });
  final String title, selected;
  final List<(String, String)> values;
  final ValueChanged<String> onSelected;
  final int columns;
  final double fontSize, verticalInset, topPadding, bottomPadding;
  final bool boldSelection;

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
          child: Text(
            title,
            style: TextStyle(fontSize: 12, color: p.secondary),
          ),
        ),
        LayoutBuilder(
          builder: (context, bounds) {
            final scale = MediaQuery.textScalerOf(context)
                .scale(1)
                .clamp(1, double.infinity);
            final density = MediaQuery.devicePixelRatioOf(context);
            final gap = (8 * density).round() / density;
            final count = ((bounds.maxWidth + gap) / (64 * scale + gap))
                .floor()
                .clamp(1, columns);
            final width =
                ((bounds.maxWidth - (count - 1) * gap) * density / count)
                    .floor() /
                density;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final value in values)
                  SizedBox(
                    width: width,
                    child: Semantics(
                      label: '$title：${value.$2}',
                      selected: selected == value.$1,
                      button: true,
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: verticalInset),
                        child: Material(
                          color: selected == value.$1
                              ? p.primaryContainer
                              : p.card.withValues(alpha: .70),
                          borderRadius: BorderRadius.circular(24),
                          child: InkWell(
                            onTap: () => onSelected(value.$1),
                            borderRadius: BorderRadius.circular(24),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: 48 - verticalInset * 2,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        value.$2,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: fontSize,
                                          fontWeight:
                                              selected == value.$1 &&
                                                  boldSelection
                                              ? FontWeight.w700
                                              : FontWeight.w400,
                                          color: selected == value.$1
                                              ? p.onPrimaryContainer
                                              : p.ink,
                                        ),
                                      ),
                                    ),
                                    if (selected == value.$1) ...[
                                      const SizedBox(width: 3),
                                      HueIcon(
                                        HueIconKind.check,
                                        size: 12,
                                        color: p.onPrimaryContainer,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
