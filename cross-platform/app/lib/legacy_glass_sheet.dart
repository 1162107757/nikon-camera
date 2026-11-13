import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The original floating sheet material: 28dp blur/radius and 83% surface.
class LegacyGlassSheet extends StatelessWidget {
  const LegacyGlassSheet({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    final contrast = MediaQuery.highContrastOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: p.surface.withValues(alpha: contrast ? .995 : .83),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: p.dark
                  ? Colors.white.withValues(alpha: .16)
                  : p.card.withValues(alpha: .90),
            ),
          ),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      ),
    );
  }
}

/// Hosts a bounded, draggable sheet without dimming the original page.
/// Set [wrap] false for HueFloatingSheet, which already supplies this material.
Future<T?> showLegacyGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool enableDrag = true,
  bool isDismissible = true,
  bool useRootNavigator = true,
  bool wrap = true,
}) async {
  ModalRoute<T>? presented;
  final result = await showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    useSafeArea: true,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    isDismissible: isDismissible,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    builder: (sheet) {
      presented = ModalRoute.of<T>(sheet);
      if (!wrap) return builder(sheet);
      final media = MediaQuery.of(sheet);
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: (media.size.height - media.padding.vertical - 24)
                  .clamp(0, double.infinity),
            ),
            child: LegacyGlassSheet(child: builder(sheet)),
          ),
        ),
      );
    },
  );
  // Pop resolves before the exit animation disposes the panel and its lease.
  // Resume the original page only after those children have actually left.
  if (presented != null) await presented!.completed;
  return result;
}
