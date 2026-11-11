import 'package:flutter/material.dart';

import 'domain.dart';
import 'theme.dart';
import 'widgets.dart';

class LegacyPresetGrid extends StatelessWidget {
  const LegacyPresetGrid({
    super.key,
    required this.rows,
    required this.core,
    required this.owner,
    required this.onOpen,
    required this.onRemove,
    this.onMore,
  });
  final List<Preset> rows;
  final HueviaCore core;
  final String owner;
  final ValueChanged<Preset> onOpen, onRemove;
  final VoidCallback? onMore;

  Widget card(BuildContext context, Preset preset, double ratio) {
    final palette = HuePalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        container: true,
        excludeSemantics: true,
        onTap: () => onOpen(preset),
        onLongPress: preset.online ? null : () => onRemove(preset),
        label:
            '${preset.name}，${preset.category.isEmpty ? '未分类' : preset.category}，查看预设',
        button: true,
        child: InkWell(
          onTap: () => onOpen(preset),
          onLongPress: preset.online ? null : () => onRemove(preset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 1 / ratio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(17),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PresetImage(
                        preset: preset,
                        core: core,
                        owner: owner,
                        showBadge: true,
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(1, 7, 1, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      preset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.17,
                        fontWeight: FontWeight.bold,
                        color: palette.ink,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3, bottom: 2),
                      child: Text(
                        preset.category.isEmpty ? '未分类' : preset.category,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.17,
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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final columns = bounds.maxWidth >= 600 ? 4 : 2;
      final chunks = (rows.length / (columns * 3)).ceil();
      return ListView.builder(
        addSemanticIndexes: false,
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          108 + hueNavigationInset(context),
        ),
        itemCount: chunks + (onMore == null ? 0 : 1),
        itemBuilder: (context, block) {
          if (block == chunks) {
            return TextButton(onPressed: onMore, child: const Text('加载更多'));
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: column == 0 ? 0 : 6,
                      right: column == columns - 1 ? 0 : 6,
                    ),
                    child: Column(
                      children: [
                        for (var rank = 0; rank < 3; rank++)
                          if (block * columns * 3 + rank * columns + column <
                              rows.length)
                            card(
                              context,
                              rows[block * columns * 3 +
                                  rank * columns +
                                  column],
                              (column.isEven
                                  ? [1.12, .94, 1.0]
                                  : [.94, 1.12, 1.0])[rank],
                            ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}
