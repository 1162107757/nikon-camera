import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'domain.dart';
import 'theme.dart';

/// Keep a closed dropdown from resolving the names of every unseen choice.
List<Widget> selectedPresetDropdownItems(
  List<DropdownMenuItem<String>> items,
  String selected,
) => [
  for (final item in items)
    item.value == selected ? item.child : const SizedBox.shrink(),
];

/// A preset's display title and, when enabled, its on-camera registration name.
class PresetDisplayName extends StatelessWidget {
  const PresetDisplayName({
    super.key,
    required this.state,
    this.preset,
    this.title,
    this.presetId = '',
    this.sourcePath = '',
    this.projectId = '',
    this.cameraName = '',
    this.style,
    this.cameraStyle,
    this.maxLines = 1,
    this.textAlign,
    this.copyCameraName = false,
  });

  final AppState state;
  final Preset? preset;
  final String? title;
  final String presetId, sourcePath, projectId, cameraName;
  final TextStyle? style, cameraStyle;
  final int? maxLines;
  final TextAlign? textAlign;
  final bool copyCameraName;

  @override
  Widget build(BuildContext context) {
    final name = title ?? preset?.name ?? '';
    final primary = Text(
      name,
      style: style,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textAlign: textAlign,
    );
    Widget names(String original) {
      if (original.isEmpty || !copyCameraName && original == name) {
        return primary;
      }
      final theme = Theme.of(context);
      final secondary = Text(
        copyCameraName ? '机内名称 $original' : original,
        style:
            cameraStyle ??
            TextStyle(
              fontSize: 11,
              color:
                  theme.extension<HuePalette>()?.secondary ??
                  theme.colorScheme.onSurfaceVariant,
            ),
        maxLines: copyCameraName ? null : 1,
        overflow: copyCameraName ? null : TextOverflow.ellipsis,
        textAlign: textAlign,
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: textAlign == TextAlign.center
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          primary,
          const SizedBox(height: 2),
          if (!copyCameraName)
            Semantics(
              label: '机内名称 $original',
              excludeSemantics: true,
              child: secondary,
            )
          else
            Row(
              children: [
                Expanded(child: secondary),
                IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  tooltip: '复制机内名称',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: original));
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('已复制机内名称')));
                    }
                  },
                ),
              ],
            ),
        ],
      );
    }

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        if (!state.showPresetCameraNames) return primary;
        if (cameraName.isNotEmpty) return names(cameraName);
        if (preset == null && presetId.isEmpty && sourcePath.isEmpty) {
          return primary;
        }
        final result = state.loadPresetCameraName(
          preset: preset,
          presetId: presetId,
          sourcePath: sourcePath,
          projectId: projectId,
        );
        return FutureBuilder<String>(
          key: ValueKey(result),
          future: result,
          builder: (context, snapshot) => names(snapshot.data ?? ''),
        );
      },
    );
  }
}
