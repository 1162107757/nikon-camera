import 'package:flutter/material.dart';

import 'theme.dart';

/// Keeps selection controls legible when accessibility text needs two rows.
class AlbumSelectionHeader extends StatelessWidget
    implements PreferredSizeWidget {
  const AlbumSelectionHeader({
    super.key,
    required this.title,
    required this.navigation,
    required this.actions,
    required this.expanded,
    required this.compact,
  });
  final String title;
  final Widget navigation;
  final List<Widget> actions;
  final bool expanded, compact;

  @override
  Size get preferredSize => Size.fromHeight(
    expanded
        ? 112
        : compact
        ? 48
        : 64,
  );

  @override
  Widget build(BuildContext context) {
    if (!expanded) {
      return HueHeader(
        title: title,
        navigation: navigation,
        actions: actions,
        compact: compact,
        endPadding: 12,
      );
    }
    final p = HuePalette.of(context);
    return ColoredBox(
      color: p.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            children: [
              SizedBox(
                height: 48,
                child: Row(children: [navigation, const Spacer(), ...actions]),
              ),
              SizedBox(
                height: 48,
                child: Center(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                      color: p.ink,
                    ),
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

/// Approved A: Sync's round action stays above the persistent navigation dock.
class AlbumExportAction extends StatelessWidget {
  const AlbumExportAction({
    super.key,
    required this.count,
    required this.onPressed,
    this.showEffectHint = true,
  });

  final int count;
  final VoidCallback? onPressed;
  final bool showEffectHint;

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showEffectHint)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 18),
              child: Text(
                '按当前效果导出',
                maxLines: 2,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 12, height: 1.4, color: p.secondary),
              ),
            ),
          ),
        Semantics(
          button: true,
          enabled: onPressed != null,
          label: '导出所选 $count 张照片，按当前调整效果',
          onTap: onPressed,
          excludeSemantics: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                key: const ValueKey('album-export-circle'),
                width: 56,
                height: 56,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Material(
                        color: const Color(0xff242420),
                        elevation: 3,
                        shadowColor: const Color(0x30000000),
                        shape: CircleBorder(
                          side: BorderSide(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xff777771)
                                : Colors.transparent,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onPressed,
                          customBorder: const CircleBorder(),
                          child: Icon(
                            Icons.download_rounded,
                            size: 28,
                            color: onPressed == null
                                ? const Color(0xffb5b5af)
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: -3,
                      top: -4,
                      child: IgnorePointer(
                        child: Container(
                          width: count > 99 ? 29 : 24,
                          height: count > 99 ? 29 : 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: p.surface, width: 2),
                          ),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xff242420),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '导出',
                style: TextStyle(fontSize: 12, height: 1.2, color: p.ink),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
