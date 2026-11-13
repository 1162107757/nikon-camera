import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'domain.dart';
import 'photo_format.dart';
import 'theme.dart';

class PhotoMasonry extends StatelessWidget {
  const PhotoMasonry({
    super.key,
    required this.rows,
    required this.phone,
    required this.core,
    required this.onOpen,
    required this.onLongPress,
    this.onMore,
    this.selected,
    this.onGroup,
    this.bottomPadding,
  });
  final List<Json> rows;
  final bool phone;
  final HueviaCore core;
  final Future<void> Function(Json) onOpen, onLongPress;
  final VoidCallback? onMore;
  final Set<String>? selected;
  final void Function(List<Json>)? onGroup;
  final double? bottomPadding;

  Widget tile(BuildContext context, Json row, double ratio) {
    final p = HuePalette.of(context);
    final image = phone
        ? _GalleryThumbnail(core: core, id: row['id'] as String)
        : row['raw'] == true
        ? _RawThumbnail(core: core, source: row['id'] as String)
        : Image.file(
            File(row['id'] as String),
            fit: BoxFit.cover,
            cacheWidth: 384,
            errorBuilder: (_, _, _) => ColoredBox(color: p.container),
          );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AspectRatio(
        aspectRatio: 1 / ratio,
        child: Semantics(
          container: true,
          excludeSemantics: true,
          onTap: () => onOpen(row),
          onLongPress: () => onLongPress(row),
          label: row['name'] as String,
          button: true,
          selected: selected?.contains(row['id']),
          child: GestureDetector(
            key: ValueKey('photo-${row['id']}'),
            onTap: () => onOpen(row),
            onLongPress: () => onLongPress(row),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  image,
                  if (selected != null)
                    Positioned(
                      right: 9,
                      top: 9,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected!.contains(row['id'])
                              ? p.ink
                              : const Color(0x66333333),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: selected!.contains(row['id'])
                            ? HueIcon(
                                HueIconKind.check,
                                size: 16,
                                color: p.card,
                              )
                            : null,
                      ),
                    ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xb3232521),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        photoFormatLabel(
                          filePath: row['id'] as String,
                          name: row['name'] as String,
                        ),
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1.3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    final columns = MediaQuery.sizeOf(context).width >= 600 ? 4 : 2;
    String day(Json row) {
      final milliseconds = (row['date'] as num?)?.toInt() ?? 0;
      if (milliseconds <= 0) return '日期未知';
      final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
      final now = DateTime.now(),
          today = DateTime(
            DateTime.now().year,
            DateTime.now().month,
            DateTime.now().day,
          );
      final value = DateTime(date.year, date.month, date.day);
      if (value == today) return '今天';
      if (value == today.subtract(const Duration(days: 1))) return '昨天';
      return '${date.year == now.year ? '' : '${date.year}年'}${date.month}月${date.day}日';
    }

    final sections = <(String?, List<Json>, int)>[];
    for (var first = 0; first < rows.length;) {
      final label = day(rows[first]);
      var last = first + 1;
      while (last < rows.length && day(rows[last]) == label) {
        last++;
      }
      sections.add((label, rows.sublist(first, last), last - first));
      for (var offset = first; offset < last; offset += columns * 3) {
        sections.add((
          null,
          rows.sublist(offset, (offset + columns * 3).clamp(0, last)),
          0,
        ));
      }
      first = last;
    }
    return ListView.builder(
      addSemanticIndexes: false,
      padding: EdgeInsets.fromLTRB(
        15,
        0,
        15,
        bottomPadding ?? 112 + hueNavigationInset(context),
      ),
      itemCount: sections.length + (onMore == null ? 0 : 1),
      itemBuilder: (context, block) {
        if (block == sections.length) {
          return TextButton(onPressed: onMore, child: const Text('加载更多'));
        }
        final section = sections[block];
        if (section.$1 != null) {
          return Padding(
            padding: const EdgeInsets.only(left: 8, top: 6),
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      section.$1!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.bold,
                        color: p.ink,
                      ),
                    ),
                  ),
                  if (selected != null)
                    IconButton(
                      tooltip: '${section.$1}，共 ${section.$3} 张，选择整组',
                      onPressed: () => onGroup?.call(section.$2),
                      icon: Icon(
                        section.$2.every((row) => selected!.contains(row['id']))
                            ? Icons.check_circle
                            : Icons.circle_outlined,
                        size: 21,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '${section.$3} 张照片',
                        style: TextStyle(fontSize: 11, color: p.secondary),
                      ),
                    ),
                ],
              ),
            ),
          );
        }
        final chunk = section.$2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var col = 0; col < columns; col++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Column(
                        children: [
                          for (
                            var index = col;
                            index < chunk.length;
                            index += columns
                          )
                            tile(
                              context,
                              chunk[index],
                              (col.isEven
                                  ? [1.45, .93, 1.14]
                                  : [1.14, 1.45, .93])[(index ~/ columns) % 3],
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

Future<void> _thumbnailQueue = Future.value();

class _RawThumbnail extends StatefulWidget {
  const _RawThumbnail({required this.core, required this.source});
  final HueviaCore core;
  final String source;
  @override
  State<_RawThumbnail> createState() => _RawThumbnailState();
}

class _RawThumbnailState extends State<_RawThumbnail> {
  late Future<String?> image = load();
  Future<String?> load() {
    final result = _thumbnailQueue.then((_) async {
      if (!mounted) return null;
      final value = await widget.core.call('media.rawThumbnail', {
        'path': widget.source,
      });
      final target = value['path'];
      if (target is! String ||
          !path.isWithin(
            path.join(widget.core.root, 'raw-thumbnails'),
            target,
          )) {
        throw const AppFailure('RAW 预览路径无效。');
      }
      return target;
    });
    _thumbnailQueue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @override
  void didUpdateWidget(_RawThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source || oldWidget.core != widget.core) {
      image = load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: image,
    builder: (context, snapshot) => snapshot.data != null
        ? Image.file(
            File(snapshot.data!),
            fit: BoxFit.cover,
            cacheWidth: 384,
            errorBuilder: (_, _, _) => fallback(context),
          )
        : snapshot.connectionState != ConnectionState.done
        ? const Center(
            child: SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : fallback(context),
  );
  Widget fallback(BuildContext context) => Tooltip(
    message: 'RAW 预览暂不可用，点按仍可打开原文件',
    child: ColoredBox(
      color: HuePalette.of(context).container,
      child: Center(
        child: HueIcon(
          HueIconKind.file,
          size: 36,
          color: HuePalette.of(context).secondary,
        ),
      ),
    ),
  );
}

class _GalleryThumbnail extends StatefulWidget {
  const _GalleryThumbnail({required this.core, required this.id});
  final HueviaCore core;
  final String id;
  @override
  State<_GalleryThumbnail> createState() => _GalleryThumbnailState();
}

class _GalleryThumbnailState extends State<_GalleryThumbnail> {
  late Future<String?> image = load();
  Future<String?> load() {
    final identity = widget.id;
    final core = widget.core;
    final future = _thumbnailQueue.then((_) async {
      if (!mounted || widget.id != identity) return null;
      try {
        return (await core.call('gallery.thumbnail', {'id': identity}))['path']
            as String;
      } catch (_) {
        return null;
      }
    });
    _thumbnailQueue = future.then<void>((_) {});
    return future;
  }

  @override
  void didUpdateWidget(covariant _GalleryThumbnail old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) image = load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    key: ValueKey(widget.id),
    future: image,
    builder: (context, snapshot) => snapshot.data == null
        ? ColoredBox(
            color: HuePalette.of(context).container,
            child: Center(
              child: HueIcon(
                HueIconKind.album,
                color: HuePalette.of(context).secondary,
              ),
            ),
          )
        : Image.file(
            File(snapshot.data!),
            fit: BoxFit.cover,
            cacheWidth: 384,
            errorBuilder: (_, _, _) =>
                ColoredBox(color: HuePalette.of(context).container),
          ),
  );
}
