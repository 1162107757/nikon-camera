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
    this.loadingMore = false,
    this.pageError,
  });
  final List<Preset> rows;
  final HueviaCore core;
  final String owner;
  final ValueChanged<Preset> onOpen, onRemove;
  final VoidCallback? onMore;
  final bool loadingMore;
  final String? pageError;

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
            '${preset.name}，${preset.pinned ? '已置顶，' : ''}${preset.category.isEmpty ? '未分类' : preset.category}，查看预设',
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
                      if (preset.pinned)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: palette.card,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '置顶',
                              style: TextStyle(
                                color: palette.ink,
                                fontSize: 11,
                              ),
                            ),
                          ),
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
      return LegacyScrollPagination(
        onMore: onMore,
        loading: loadingMore,
        error: pageError,
        child: ListView.builder(
          addSemanticIndexes: false,
          padding: EdgeInsets.fromLTRB(
            18,
            0,
            18,
            108 + hueNavigationInset(context),
          ),
          itemCount: chunks + (onMore == null && !loadingMore ? 0 : 1),
          itemBuilder: (context, block) {
            if (block == chunks) {
              return LegacyPageStatus(
                loading: loadingMore,
                error: pageError,
                onRetry: onMore,
              );
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
        ),
      );
    },
  );
}

/// One page at most for each user scroll. Layout/content growth never drains
/// subsequent pages, and a failed page requires an explicit retry.
class LegacyScrollPagination extends StatefulWidget {
  const LegacyScrollPagination({
    super.key,
    required this.child,
    this.onMore,
    this.loading = false,
    this.error,
  });
  final Widget child;
  final VoidCallback? onMore;
  final bool loading;
  final String? error;

  @override
  State<LegacyScrollPagination> createState() => _LegacyScrollPaginationState();
}

class _LegacyScrollPaginationState extends State<LegacyScrollPagination> {
  bool armed = false;

  bool scroll(ScrollNotification event) {
    if (event.depth != 0) return false;
    if (event is ScrollStartNotification && event.dragDetails != null) {
      armed = true;
    }
    final advancing = event is ScrollUpdateNotification
        ? (event.scrollDelta ?? 0) > 0
        : event is OverscrollNotification && event.overscroll > 0;
    if (armed &&
        advancing &&
        event.metrics.extentAfter <= 240 &&
        widget.onMore != null &&
        !widget.loading &&
        widget.error == null) {
      armed = false;
      widget.onMore!();
    }
    if (event is ScrollEndNotification) armed = false;
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: scroll,
        child: widget.child,
      );
}

class LegacyPageStatus extends StatelessWidget {
  const LegacyPageStatus({
    super.key,
    required this.loading,
    this.error,
    this.onRetry,
  });
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: loading
        ? const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : error != null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error!, textAlign: TextAlign.center),
              TextButton(onPressed: onRetry, child: const Text('重试加载')),
            ],
          )
        : Text(
            '继续向上滑动加载',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: HuePalette.of(context).secondary,
            ),
          ),
  );
}
