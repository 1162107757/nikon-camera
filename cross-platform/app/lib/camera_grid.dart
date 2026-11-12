import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'camera_previews.dart';
import 'camera_transfer.dart';
import 'domain.dart';

/// Original AlbumPanel: square cells, 8dp gaps, 14dp corners, format badge.
class CameraPhotoGrid extends StatelessWidget {
  const CameraPhotoGrid({
    super.key,
    required this.items,
    required this.previews,
    required this.transfer,
    required this.onDownload,
  });
  final List<Json> items;
  final CameraPreviews previews;
  final CameraTransfer transfer;
  final Future<void> Function(Json) onDownload;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final columns = ((bounds.maxWidth + 8) / 112).floor().clamp(3, 8);
      final edge = (bounds.maxWidth - (columns - 1) * 8) / columns;
      return GridView.builder(
        shrinkWrap: true,
        primary: false,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Semantics(
            button: true,
            label: '${item['name']}，相机照片',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Material(
                child: InkWell(
                  onTap: () =>
                      Navigator.of(context, rootNavigator: true).push<void>(
                        MaterialPageRoute(
                          builder: (_) => CameraPhotoViewer(
                            photo: item,
                            previews: previews,
                            transfer: transfer,
                            onDownload: () => onDownload(item),
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
                        left: 8,
                        bottom: 8,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xb3232521),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            child: Text(
                              (item['raw'] == true ||
                                      (item['name'] as String)
                                          .toLowerCase()
                                          .endsWith('.nef'))
                                  ? 'NEF'
                                  : 'JPEG',
                              style: const TextStyle(
                                fontSize: 10,
                                height: 1.3,
                                color: Colors.white,
                              ),
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
        },
      );
    },
  );
}

class CameraPhotoViewer extends StatefulWidget {
  const CameraPhotoViewer({
    super.key,
    required this.photo,
    required this.previews,
    required this.transfer,
    required this.onDownload,
  });
  final Json photo;
  final CameraPreviews previews;
  final CameraTransfer transfer;
  final Future<void> Function() onDownload;
  @override
  State<CameraPhotoViewer> createState() => _CameraPhotoViewerState();
}

class _CameraPhotoViewerState extends State<CameraPhotoViewer> {
  late Future<CameraPreview> image = widget.previews.load(widget.photo);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('相机预览')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: FutureBuilder<CameraPreview>(
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
                        semanticLabel: '${widget.photo['name']} 相机预览',
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Center(
                  child: TextButton(
                    onPressed: () => setState(
                      () => image = widget.previews.load(
                        widget.photo,
                        refresh: true,
                      ),
                    ),
                    child: const Text('重试相机预览'),
                  ),
                );
              },
            ),
          ),
          Flexible(
            flex: 0,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CameraTransferCard(transfer: widget.transfer),
            ),
          ),
          AnimatedBuilder(
            animation: widget.transfer,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton.icon(
                onPressed: widget.transfer.busy
                    ? null
                    : () => unawaited(widget.onDownload()),
                icon: const Icon(Icons.download_outlined),
                label: const Text('接收原文件'),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
