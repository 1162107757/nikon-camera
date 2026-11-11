import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as path;

import 'domain.dart';
import 'theme.dart';
import 'widgets.dart';

class PhotosPage extends StatefulWidget {
  const PhotosPage({super.key, required this.state});
  final AppState state;
  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> with WidgetsBindingObserver {
  AppState get state => widget.state;
  bool phone = false, importing = false, loading = false, more = false;
  bool oldest = false, added = false;
  int nextOffset = 0, generation = 0;
  String access = 'none', query = '', filter = '', error = '';
  List<Json> phonePhotos = [];
  final Set<String> pendingStars = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(state.refreshStars().catchError((Object _) {}));
    unawaited(readAccess());
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState phase) {
    if (phase == AppLifecycleState.resumed) unawaited(readAccess());
  }

  Future<void> readAccess() async {
    try {
      final result = await state.core.call('gallery.access');
      if (!mounted) return;
      final previous = access;
      setState(() => access = result['access'] as String);
      if (phone && access != 'none' && previous != access) await loadPhone();
    } catch (_) {
      /* The system file picker remains available without library permission. */
    }
  }

  Future<void> loadPhone({bool next = false}) async {
    if (loading || access == 'none') return;
    final current = ++generation;
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final result = await state.core.call('gallery.page', {
        'offset': next ? nextOffset : 0,
        'added': added,
        'oldest': oldest,
        'refresh': !next,
      });
      if (!mounted || current != generation) return;
      setState(() {
        final rows = (result['items'] as List).map(object).toList();
        phonePhotos = next ? [...phonePhotos, ...rows] : rows;
        nextOffset = result['nextOffset'] as int;
        more = result['hasMore'] == true;
      });
    } catch (failure) {
      if (mounted && current == generation) setState(() => error = '$failure');
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  Future<void> permission() async {
    try {
      final result = await state.core.galleryPermission();
      if (!mounted) return;
      setState(() => access = result['access'] as String);
      await loadPhone();
    } catch (failure) {
      if (mounted) report(context, failure);
    }
  }

  void source(int index) {
    setState(() => phone = index == 1);
    if (phone && access != 'none') unawaited(loadPhone());
  }

  Future<void> pick() async {
    if (importing) return;
    setState(() => importing = true);
    try {
      final photo = await state.pickPhoto();
      if (mounted && photo != null) await context.push(photo.editorLocation);
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> open(Json row) async {
    if (importing) return;
    if (!phone) {
      final photo = state.photos.firstWhere((photo) => photo.path == row['id']);
      await context.push(photo.editorLocation);
      return;
    }
    setState(() => importing = true);
    try {
      final imported = await state.core.call('gallery.import', {
        'id': row['id'],
      });
      final info = await state.core.call('media.info', {
        'path': imported['path'],
      });
      final photo = await state.registerPhoto(
        imported['path'] as String,
        imported['name'] as String,
        info,
      );
      if (mounted) await context.push(photo.editorLocation);
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Future<void> search() async {
    final input = TextEditingController(text: query);
    final result = await hueDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('搜索照片'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入照片名称'),
          onSubmitted: (value) => Navigator.pop(dialog, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, input.text),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    input.dispose();
    if (result != null && mounted) setState(() => query = result);
  }

  Future<void> sort() async {
    var nextAdded = added, nextOldest = oldest;
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (sheet) => StatefulBuilder(
        builder: (context, refresh) {
          final p = HuePalette.of(context);
          Widget pair(
            List<String> labels,
            bool selected,
            void Function(bool) update,
          ) => Row(
            children: [
              for (var i = 0; i < 2; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 6,
                    ),
                    child: SizedBox(
                      height: 36,
                      child: Material(
                        color: selected == (i == 1) ? p.action : p.card,
                        borderRadius: BorderRadius.circular(24),
                        child: InkWell(
                          onTap: () => refresh(() => update(i == 1)),
                          borderRadius: BorderRadius.circular(24),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  labels[i],
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: selected == (i == 1)
                                        ? p.onAction
                                        : p.ink,
                                  ),
                                ),
                                if (selected == (i == 1)) ...[
                                  const SizedBox(width: 8),
                                  HueIcon(
                                    HueIconKind.check,
                                    size: 16,
                                    color: p.onAction,
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
            ],
          );
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Container(
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: p.card),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 30,
                            height: 3,
                            color: p.outline,
                          ),
                        ),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '时间排序',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            HueIconButton(
                              kind: HueIconKind.close,
                              label: '关闭排序，放弃未应用修改',
                              disc: false,
                              iconSize: 20,
                              onPressed: () => Navigator.pop(sheet),
                            ),
                          ],
                        ),
                        Text(
                          '排序依据',
                          style: TextStyle(fontSize: 12, color: p.secondary),
                        ),
                        pair(
                          ['拍摄时间', '添加时间'],
                          nextAdded,
                          (value) => nextAdded = value,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '排列顺序',
                          style: TextStyle(fontSize: 12, color: p.secondary),
                        ),
                        pair(
                          ['新到旧', '旧到新'],
                          nextOldest,
                          (value) => nextOldest = value,
                        ),
                        if (!phone && nextAdded)
                          Text(
                            '旧照片没有入库记录时，添加时间使用现存文件时间。',
                            style: TextStyle(fontSize: 12, color: p.secondary),
                          ),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => refresh(() {
                                nextAdded = false;
                                nextOldest = false;
                              }),
                              child: const Text('重置'),
                            ),
                            const Spacer(),
                            SizedBox(
                              width: 108,
                              child: FilledButton(
                                onPressed: () => Navigator.pop(sheet, true),
                                child: const Text('应用'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    if (accepted == true && mounted) {
      setState(() {
        added = nextAdded;
        oldest = nextOldest;
      });
      if (phone) await loadPhone();
    }
  }

  Future<void> actions(Json row) async {
    if (phone) return;
    final photo = state.photos.firstWhere((photo) => photo.path == row['id']);
    final marked = state.starredPhotos.contains(photo.starKey);
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(photo.name)),
            ListTile(
              title: Text(marked ? '取消星标' : '标记星标'),
              onTap: () => Navigator.pop(sheet, 'star'),
            ),
            ListTile(
              title: const Text('只看星标照片'),
              onTap: () => Navigator.pop(sheet, 'filter'),
            ),
          ],
        ),
      ),
    );
    try {
      if (result == 'star') await state.starPhoto(photo, !marked);
      if (result == 'filter' && mounted) {
        setState(() => filter = filter == 'starred' ? '' : 'starred');
      }
    } catch (failure) {
      if (mounted) report(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final p = HuePalette.of(context),
          compact = MediaQuery.sizeOf(context).height < 480;
      final rows = phone
          ? phonePhotos
                .where(
                  (row) => (row['name'] as String).toLowerCase().contains(
                    query.toLowerCase(),
                  ),
                )
                .toList()
          : state.photos
                .where(
                  (photo) =>
                      photo.name.toLowerCase().contains(query.toLowerCase()) &&
                      (filter != 'starred' ||
                          state.starredPhotos.contains(photo.starKey)),
                )
                .map(
                  (photo) => <String, dynamic>{
                    'id': photo.path,
                    'name': photo.name,
                    'raw': photo.info['raw'] == true,
                    'date': photo.info['addedAt'] ?? 0,
                    'photo': photo,
                  },
                )
                .toList();
      if (!phone && oldest) {
        rows.sort((a, b) => (a['date'] as int).compareTo(b['date'] as int));
      }
      return Scaffold(
        appBar: HueHeader(
          title: '相册',
          compact: compact,
          actions: [
            HueIconButton(
              kind: HueIconKind.search,
              label: '搜索照片',
              iconSize: 20,
              onPressed: search,
            ),
            PopupMenuButton<String>(
              tooltip: '相册更多操作',
              padding: EdgeInsets.zero,
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: p.card,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: HueIcon(
                    HueIconKind.more,
                    size: 20,
                    color: p.secondary,
                  ),
                ),
              ),
              onSelected: (value) {
                if (value == 'raw') {
                  unawaited(pick());
                } else if (value == 'permission') {
                  unawaited(permission());
                } else if (value == 'stars') {
                  setState(() => filter = filter == 'starred' ? '' : 'starred');
                } else if (phone) {
                  unawaited(loadPhone());
                } else {
                  unawaited(state.refreshStars());
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'refresh', child: Text('刷新')),
                const PopupMenuItem(value: 'raw', child: Text('RAW 显影')),
                if (!phone)
                  PopupMenuItem(
                    value: 'stars',
                    child: Text(filter == 'starred' ? '显示全部照片' : '只看星标照片'),
                  ),
                if (phone)
                  const PopupMenuItem(value: 'permission', child: Text('权限设置')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 12 : 20,
                0,
                compact ? 12 : 20,
                4,
              ),
              child: CapsuleSwitch(
                labels: const ['应用相册', '手机相册'],
                selected: phone ? 1 : 0,
                onSelected: source,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          phone && access == 'none'
                              ? '未授权'
                              : query.isNotEmpty
                              ? '匹配 ${rows.length} 张 · $query'
                              : '共 ${rows.length} 张',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: p.secondary,
                          ),
                        ),
                      ),
                    ),
                    HueIconButton(
                      kind: HueIconKind.sort,
                      label:
                          '排序，${added ? '添加时间' : '拍摄时间'}，${oldest ? '旧到新' : '新到旧'}',
                      disc: false,
                      iconSize: 20,
                      onPressed: sort,
                    ),
                  ],
                ),
              ),
            ),
            if (importing || loading)
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: rows.isEmpty
                  ? LayoutBuilder(
                      builder: (context, bounds) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: (bounds.maxHeight - 104).clamp(
                              0,
                              double.infinity,
                            ),
                          ),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 16 : 32,
                              vertical: compact ? 8 : 24,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (!compact)
                                  HueIcon(
                                    HueIconKind.album,
                                    size: 40,
                                    color: p.secondary,
                                  ),
                                SizedBox(height: compact ? 0 : 20),
                                Text(
                                  query.isNotEmpty
                                      ? '没有匹配的照片'
                                      : loading
                                      ? '正在整理照片'
                                      : phone
                                      ? '浏览手机照片'
                                      : '这里还没有照片',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 20,
                                    height: 1.35,
                                    fontWeight: FontWeight.w700,
                                    color: p.ink,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  error.isNotEmpty
                                      ? error
                                      : phone
                                      ? '允许访问后，即可在这里浏览照片。'
                                      : '编辑或同步保存的照片会出现在这里。',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15,
                                    height: 1.35,
                                    color: p.secondary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 13,
                                      letterSpacing: .1,
                                    ),
                                  ),
                                  onPressed: importing
                                      ? null
                                      : phone
                                      ? permission
                                      : () => source(1),
                                  child: Text(phone ? '允许访问照片' : '浏览手机照片'),
                                ),
                                if (phone)
                                  SizedBox(
                                    height: 48,
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(48, 48),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                        ),
                                      ),
                                      onPressed: importing ? null : pick,
                                      child: Text(
                                        '选择指定照片',
                                        style: TextStyle(
                                          fontSize: 12,
                                          letterSpacing: .6,
                                          decoration: TextDecoration.underline,
                                          color: p.ink,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : _PhotoMasonry(
                      rows: rows,
                      phone: phone,
                      core: state.core,
                      onOpen: open,
                      onLongPress: actions,
                      onMore: more ? () => loadPhone(next: true) : null,
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class _PhotoMasonry extends StatelessWidget {
  const _PhotoMasonry({
    required this.rows,
    required this.phone,
    required this.core,
    required this.onOpen,
    required this.onLongPress,
    this.onMore,
  });
  final List<Json> rows;
  final bool phone;
  final HueviaCore core;
  final Future<void> Function(Json) onOpen, onLongPress;
  final VoidCallback? onMore;

  Widget tile(BuildContext context, Json row, double ratio) {
    final p = HuePalette.of(context);
    final image = phone
        ? _GalleryThumbnail(core: core, id: row['id'] as String)
        : row['raw'] == true
        ? ColoredBox(
            color: p.container,
            child: Center(
              child: HueIcon(HueIconKind.file, size: 36, color: p.secondary),
            ),
          )
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
                        path
                            .extension(row['name'] as String)
                            .replaceFirst('.', '')
                            .toUpperCase(),
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
      sections.add((label, const [], last - first));
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
        112 + hueNavigationInset(context),
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
