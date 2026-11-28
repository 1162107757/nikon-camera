import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'album_export_action.dart';
import 'theme.dart';

/// Approved B: two explicit actions, above the persistent home navigation.
class AlbumSelectionActions extends StatelessWidget {
  static double reservedHeight(BuildContext context) =>
      128 +
      (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 100) * 1.4;
  const AlbumSelectionActions({
    super.key,
    required this.count,
    this.onPreset,
    this.onExport,
  });
  final int count;
  final VoidCallback? onPreset, onExport;

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    final contrast = MediaQuery.highContrastOf(context);
    const shape = StadiumBorder();
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width < 600 ? 360 : 420,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: p.dark ? .22 : .08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipPath(
          clipper: const ShapeBorderClipper(shape: shape),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: Material(
              key: const Key('album-selection-action-bar'),
              color: (p.dark ? p.card : Colors.white).withValues(
                alpha: contrast ? 1 : .92,
              ),
              shape: StadiumBorder(
                side: BorderSide(
                  color: Colors.white.withValues(alpha: p.dark ? .16 : .95),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: TextButton(
                        key: const Key('album-apply-presets'),
                        onPressed: count == 0 ? null : onPreset,
                        style: TextButton.styleFrom(
                          foregroundColor: p.ink,
                          minimumSize: const Size(48, 76),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 56,
                              height: 56,
                              child: Icon(
                                Icons.auto_awesome_outlined,
                                size: 34,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              '套用预设',
                              style: TextStyle(fontSize: 12, height: 1.2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: AlbumExportAction(
                          count: count,
                          onPressed: count == 0 ? null : onExport,
                          showEffectHint: false,
                        ),
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
