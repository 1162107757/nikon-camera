import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'domain.dart';
import 'photo_grid.dart';
import 'theme.dart';

class PhoneAlbumToolbar extends StatelessWidget {
  const PhoneAlbumToolbar({
    super.key,
    required this.anchor,
    required this.name,
    required this.count,
    required this.onAlbums,
    required this.onBatch,
  });
  final GlobalKey anchor;
  final String name, count;
  final VoidCallback? onAlbums, onBatch;

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return Padding(
      key: anchor,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: TextButton(
                    key: const ValueKey('phone-album-picker'),
                    onPressed: onAlbums,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.only(left: 3, right: 4),
                      minimumSize: const Size(48, 48),
                      foregroundColor: p.ink,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      ],
                    ),
                  ),
                ),
                Container(
                  height: 13,
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: p.outline,
                ),
                Text(
                  count,
                  maxLines: 1,
                  style: TextStyle(fontSize: 13, color: p.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onBatch,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(72, 48),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: ShapeDecoration(
                color: p.container,
                shape: const StadiumBorder(),
              ),
              child: Text(
                '批量修图',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: onBatch == null ? p.secondary : p.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<String?> showPhoneAlbumPicker(
  BuildContext context, {
  required GlobalKey anchor,
  required HueviaCore core,
  required List<Json> albums,
  required String selected,
}) {
  final box = anchor.currentContext?.findRenderObject() as RenderBox?;
  if (box == null) return Future.value();
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay!.context.findRenderObject() as RenderBox;
  final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
  final screen = MediaQuery.sizeOf(context);
  final width = (screen.width * .52).clamp(210.0, 260.0);
  final left = origin.dx.clamp(12.0, math.max(12.0, screen.width - width - 12));
  final top = origin.dy + box.size.height;
  final maxHeight = math.max(
    80.0,
    screen.height - top - MediaQuery.paddingOf(context).bottom - 16,
  );
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭相册列表',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (context, _, _) {
      final p = HuePalette.of(context);
      return Stack(
        children: [
          Positioned(
            left: left.toDouble(),
            top: top + 1,
            width: width,
            child: Material(
              key: const ValueKey('phone-album-menu'),
              color: p.surface,
              elevation: 12,
              shadowColor: Colors.black.withValues(alpha: .2),
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 9),
                      child: Text(
                        '手机相册',
                        style: TextStyle(fontSize: 12, color: p.secondary),
                      ),
                    ),
                    for (final album in albums)
                      Semantics(
                        selected: album['id'] == selected,
                        child: InkWell(
                          key: ValueKey('phone-folder-${album['id']}'),
                          borderRadius: BorderRadius.circular(9),
                          onTap: () =>
                              Navigator.pop(context, album['id'] as String),
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: album['id'] == selected
                                  ? p.ink.withValues(alpha: .07)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(7),
                                  child: SizedBox.square(
                                    dimension: 34,
                                    child: album['cover'] is String
                                        ? GalleryThumbnail(
                                            core: core,
                                            id: album['cover'] as String,
                                          )
                                        : ColoredBox(
                                            color: p.container,
                                            child: Icon(
                                              Icons.photo_outlined,
                                              size: 20,
                                              color: p.secondary,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    album['name'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: p.ink,
                                      fontWeight: album['id'] == selected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${album['count']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.secondary,
                                  ),
                                ),
                                SizedBox(
                                  width: 20,
                                  child: album['id'] == selected
                                      ? Icon(
                                          Icons.check_rounded,
                                          size: 17,
                                          color: p.ink,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}
