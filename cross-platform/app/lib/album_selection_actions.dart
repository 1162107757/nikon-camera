import 'package:flutter/material.dart';

import 'album_export_action.dart';
import 'legacy_glass_sheet.dart';
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: LegacyGlassSheet(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.auto_awesome_outlined, size: 32),
                      const SizedBox(height: 8),
                      const Text('套用预设', style: TextStyle(fontSize: 12)),
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
    );
  }
}
