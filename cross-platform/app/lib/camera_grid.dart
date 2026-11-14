import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'camera_previews.dart';
import 'camera_transfer.dart';
import 'camera_raw_pairing.dart';
import 'camera_photo_sort.dart';
import 'domain.dart';

/// Original AlbumPanel: square cells, 8dp gaps, 14dp corners, format badge.
class CameraPhotoGrid extends StatelessWidget {
  const CameraPhotoGrid({
    super.key,
    required this.items,
    required this.previews,
    required this.transfer,
    required this.onDownload,
    this.onMore,
    this.selection,
    this.onSelect,
    this.sliver = false,
    this.order = CameraPhotoSort.cameraOrder,
  });
  final List<Json> items;
  final CameraPreviews previews;
  final CameraTransfer transfer;
  final Future<void> Function(Json) onDownload;
  final Future<List<Json>> Function()? onMore;
  final Set<int>? selection;
  final void Function(Json)? onSelect;
  final bool sliver;
  final CameraPhotoSort order;
  @override
  Widget build(BuildContext context) => sliver
      ? SliverLayoutBuilder(
          builder: (context, bounds) => grid(context, bounds.crossAxisExtent),
        )
      : LayoutBuilder(
          builder: (context, bounds) => grid(context, bounds.maxWidth),
        );

  Widget grid(BuildContext context, double width) {
    final columns = ((width + 8) / 176).floor().clamp(2, 8);
    final edge = (width - (columns - 1) * 8) / columns;
    final layout = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: .92,
    );
    final cells = SliverChildBuilderDelegate((context, index) {
      final item = items[index];
      final selected = selection?.contains(item['handle']) == true;
      return Semantics(
        button: true,
        label: '${item['name']}，相机照片',
        selected: selection == null ? null : selected,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Material(
            child: InkWell(
              onTap: selection != null
                  ? () => onSelect?.call(item)
                  : () => Navigator.of(context, rootNavigator: true).push<void>(
                      MaterialPageRoute(
                        builder: (_) => CameraPhotoViewer(
                          photo: item,
                          order: order,
                          previews: previews,
                          transfer: transfer,
                          onDownload: () => onDownload(item),
                          photos: items,
                          onDownloadPhoto: onDownload,
                          onMore: onMore,
                        ),
                      ),
                    ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraThumbnail(
                    key: ValueKey('${previews.hashCode}/${item['handle']}'),
                    previews: previews,
                    photo: item,
                    size: edge,
                  ),
                  Positioned(
                    right: 6,
                    top: 6,
                    child: selection == null
                        ? const SizedBox.shrink()
                        : Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white,
                            shadows: const [
                              Shadow(color: Colors.black54, blurRadius: 4),
                            ],
                          ),
                  ),
                  Positioned(
                    left: 9,
                    right: 9,
                    bottom: 10,
                    child: Text(
                      item['name'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 5)],
                      ),
                    ),
                  ),
                  if (selection == null && item['raw'] == true)
                    Positioned(
                      right: 7,
                      top: 7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 3,
                          ),
                          child: Text(
                            'NEF',
                            style: TextStyle(fontSize: 9, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }, childCount: items.length);
    return sliver
        ? SliverGrid(gridDelegate: layout, delegate: cells)
        : GridView.custom(
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: layout,
            childrenDelegate: cells,
          );
  }
}

class CameraPhotoViewer extends StatefulWidget {
  const CameraPhotoViewer({
    super.key,
    required this.photo,
    required this.previews,
    required this.transfer,
    required this.onDownload,
    this.photos,
    this.onDownloadPhoto,
    this.onMore,
    this.order = CameraPhotoSort.cameraOrder,
  });
  final Json photo;
  final CameraPhotoSort order;
  final CameraPreviews previews;
  final CameraTransfer transfer;
  final Future<void> Function() onDownload;
  final List<Json>? photos;
  final Future<void> Function(Json)? onDownloadPhoto;
  final Future<List<Json>> Function()? onMore;
  @override
  State<CameraPhotoViewer> createState() => _CameraPhotoViewerState();
}

class _CameraPhotoViewerState extends State<CameraPhotoViewer> {
  late Future<CameraPreview> image;
  late List<Json> photos;
  late String session;
  late int generation;
  int index = 0;
  bool loadingMore = false,
      exhausted = false,
      downloading = false,
      pairing = false;
  String? navigationError;
  Json get photo => photos[index];
  bool get actionBusy => widget.transfer.busy || downloading || pairing;
  bool get valid =>
      session.isNotEmpty &&
      photo['handle'] is int &&
      (photo['handle'] as int) > 0 &&
      !widget.previews.disposed &&
      widget.previews.session == session &&
      widget.previews.generation == generation;
  @override
  void initState() {
    super.initState();
    final handles = <int>{};
    photos = (widget.photos ?? [widget.photo])
        .where(
          (row) =>
              row['handle'] is int &&
              (row['handle'] as int) > 0 &&
              handles.add(row['handle'] as int),
        )
        .map((row) => Map<String, dynamic>.unmodifiable(row))
        .toList();
    photos = sortedCameraPhotos(photos, widget.order);
    index = photos.indexWhere((row) => row['handle'] == widget.photo['handle']);
    if (index < 0) {
      photos.insert(0, Map<String, dynamic>.unmodifiable(widget.photo));
      index = 0;
    }
    session = widget.previews.session;
    generation = widget.previews.generation;
    widget.previews.addListener(sessionChanged);
    widget.transfer.addListener(sessionChanged);
    load();
  }

  void sessionChanged() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  void load({bool refresh = false}) {
    image = widget.previews.load(photo, refresh: refresh);
    if (index > 0) unawaited(widget.previews.load(photos[index - 1]));
    if (index + 1 < photos.length) {
      unawaited(widget.previews.load(photos[index + 1]));
    }
  }

  Future<void> move(int delta) async {
    if (!valid || actionBusy || loadingMore) return;
    var target = index + delta;
    if (target >= photos.length && widget.onMore != null && !exhausted) {
      setState(() {
        loadingMore = true;
        navigationError = null;
      });
      try {
        final rows = await widget.onMore!();
        if (!mounted || !valid) return;
        final currentHandle = photo['handle'];
        final handles = photos.map((row) => row['handle']).toSet();
        final added = rows
            .where((row) => handles.add(row['handle']))
            .map((row) => Map<String, dynamic>.unmodifiable(row))
            .toList();
        photos = sortedCameraPhotos([...photos, ...added], widget.order);
        index = photos.indexWhere((row) => row['handle'] == currentHandle);
        target = index + delta;
        exhausted = added.isEmpty;
      } catch (failure) {
        if (mounted) setState(() => navigationError = '$failure');
        return;
      } finally {
        if (mounted) setState(() => loadingMore = false);
      }
    }
    if (!mounted ||
        !valid ||
        actionBusy ||
        target < 0 ||
        target >= photos.length) {
      return;
    }
    setState(() {
      index = target;
      navigationError = null;
      load();
    });
  }

  Future<void> receive() async {
    if (!valid ||
        actionBusy ||
        loadingMore ||
        widget.onDownloadPhoto == null &&
            photo['handle'] != widget.photo['handle']) {
      return;
    }
    final selected = photo;
    setState(() {
      downloading = true;
      navigationError = null;
    });
    try {
      await (widget.onDownloadPhoto?.call(selected) ?? widget.onDownload());
    } catch (failure) {
      if (mounted && valid) setState(() => navigationError = '$failure');
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  Future<void> pairRaw() async {
    if (!valid || actionBusy || loadingMore || photo['raw'] == true) return;
    final selectedHandle = photo['handle'] as int;
    setState(() => pairing = true);
    widget.previews.pause();
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CameraRawPairingPage(
            state: widget.transfer.state,
            session: session,
            jpegHandle: selectedHandle,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => pairing = false);
      if (mounted && valid) widget.previews.resume();
    }
  }

  @override
  void dispose() {
    widget.previews.removeListener(sessionChanged);
    widget.transfer.removeListener(sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('相机预览')),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) => Column(
          children: [
            Expanded(
              child: !valid
                  ? const Center(child: Text('相机会话已变化，请返回并刷新照片。'))
                  : FutureBuilder<CameraPreview>(
                      key: ValueKey('$session/$generation/${photo['handle']}'),
                      future: image,
                      builder: (context, snapshot) {
                        final path = snapshot.data?.path;
                        if (path != null) {
                          return InteractiveViewer(
                            child: Center(
                              child: Image.file(
                                File(path),
                                fit: BoxFit.contain,
                                cacheWidth: 1280,
                                semanticLabel: '${photo['name']} 相机预览',
                              ),
                            ),
                          );
                        }
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        return Center(
                          child: TextButton(
                            onPressed: actionBusy || loadingMore
                                ? null
                                : () => setState(() => load(refresh: true)),
                            child: const Text('重试相机预览'),
                          ),
                        );
                      },
                    ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: bounds.maxHeight * .65),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AnimatedBuilder(
                  animation: widget.transfer,
                  builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${photo['name']}', textAlign: TextAlign.center),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: '上一张',
                            onPressed:
                                valid &&
                                    !actionBusy &&
                                    !loadingMore &&
                                    index > 0
                                ? () => unawaited(move(-1))
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Flexible(
                            child: Text(
                              loadingMore
                                  ? '正在读取下一页'
                                  : '${index + 1} / ${photos.length}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          IconButton(
                            tooltip: '下一张',
                            onPressed:
                                valid &&
                                    !actionBusy &&
                                    !loadingMore &&
                                    (index + 1 < photos.length ||
                                        widget.onMore != null && !exhausted)
                                ? () => unawaited(move(1))
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      if (navigationError != null)
                        Text(
                          navigationError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      CameraTransferCard(transfer: widget.transfer),
                      if (photo['raw'] != true)
                        TextButton.icon(
                          onPressed: !valid || actionBusy || loadingMore
                              ? null
                              : pairRaw,
                          icon: const Icon(Icons.raw_on_outlined),
                          label: const Text('核对并接收对应 RAW'),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        child: FilledButton.icon(
                          onPressed:
                              actionBusy ||
                                  loadingMore ||
                                  !valid ||
                                  widget.onDownloadPhoto == null &&
                                      photo['handle'] != widget.photo['handle']
                              ? null
                              : () => unawaited(receive()),
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('接收原文件'),
                        ),
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
  );
}
