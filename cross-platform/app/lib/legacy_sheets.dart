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
  });
  final String title, closeLabel;
  final List<Widget> children;
  final VoidCallback onReset, onApply;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(10),
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
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
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
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: children,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: onReset,
                            child: const Text('重置'),
                          ),
                          const Spacer(),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
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
  });
  final String title, selected;
  final List<(String, String)> values;
  final ValueChanged<String> onSelected;
  final int columns;
  final double fontSize, verticalInset;
  final bool boldSelection;

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(
            title,
            style: TextStyle(fontSize: 12, color: p.secondary),
          ),
        ),
        LayoutBuilder(
          builder: (context, bounds) {
            final count = (bounds.maxWidth / 76).floor().clamp(1, columns);
            final width = (bounds.maxWidth - (count - 1) * 6) / count;
            return Wrap(
              spacing: 6,
              runSpacing: 6,
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
