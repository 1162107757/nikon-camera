import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'domain.dart';
import 'widgets.dart';

class PhotosPage extends StatefulWidget {
  const PhotosPage({super.key, required this.state});
  final AppState state;
  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> {
  AppState get state => widget.state;
  String query = '', filter = 'all';
  final Set<String> pendingStars = {};
  String? starError;
  bool importing = false;
  @override
  void initState() {
    super.initState();
    unawaited(loadStars());
  }

  Future<void> loadStars() async {
    try {
      await state.refreshStars();
      if (mounted) setState(() => starError = null);
    } catch (failure) {
      if (mounted) setState(() => starError = '$failure');
    }
  }

  Future<void> star(Photo photo) async {
    if (pendingStars.contains(photo.id)) return;
    setState(() => pendingStars.add(photo.id));
    try {
      await state.starPhoto(
        photo,
        !state.starredPhotos.contains(photo.starKey),
      );
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) setState(() => pendingStars.remove(photo.id));
    }
  }

  Future<void> import(BuildContext context) async {
    if (importing) return;
    setState(() => importing = true);
    try {
      final photo = await state.pickPhoto();
      if (photo == null) return;
      if (context.mounted) context.push(photo.editorLocation);
    } catch (error) {
      if (context.mounted) report(context, error);
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final items = state.photos
          .where(
            (photo) =>
                photo.name.toLowerCase().contains(query.toLowerCase()) &&
                (filter != 'raw' || photo.info['raw'] == true) &&
                (filter != 'starred' ||
                    state.starredPhotos.contains(photo.starKey)),
          )
          .toList();
      return Scaffold(
        appBar: AppBar(
          title: const Text('照片'),
          bottom: importing
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(3),
                  child: LinearProgressIndicator(),
                )
              : null,
          actions: [
            IconButton(
              onPressed: importing ? null : () => import(context),
              tooltip: '导入照片或 RAW',
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: state.photos.isEmpty
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.photo_library_outlined, size: 40),
                        const SizedBox(height: 16),
                        const Text('从一张照片开始'),
                        const SizedBox(height: 8),
                        const Text(
                          '导入照片或 RAW，调出你喜欢的色彩。',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: importing ? null : () => import(context),
                          child: const Text('选择照片'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: '搜索照片',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: (value) => setState(() => query = value),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Row(
                        children: [
                          for (final choice in [
                            ('all', '全部'),
                            ('starred', '星标'),
                            ('raw', 'RAW'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(choice.$2),
                                selected: filter == choice.$1,
                                onSelected: (_) =>
                                    setState(() => filter = choice.$1),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (starError != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(child: Text('星标读取失败：$starError')),
                            TextButton(
                              onPressed: loadStars,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: items.isEmpty
                          ? const Center(child: Text('没有符合条件的照片'))
                          : ListView.separated(
                              padding: const EdgeInsets.all(20),
                              itemCount: items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final photo = items[index];
                                return Card(
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    leading: photo.info['raw'] == true
                                        ? const Icon(
                                            Icons.raw_on_outlined,
                                            size: 40,
                                          )
                                        : ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Image.file(
                                              File(photo.path),
                                              width: 56,
                                              height: 56,
                                              fit: BoxFit.cover,
                                              cacheWidth: 144,
                                              errorBuilder: (_, _, _) => const Icon(
                                                Icons
                                                    .image_not_supported_outlined,
                                              ),
                                            ),
                                          ),
                                    title: Text(photo.name),
                                    subtitle: Text(
                                      '${photo.info['width']} × ${photo.info['height']}${photo.info['raw'] == true ? ' · RAW' : ''}',
                                    ),
                                    trailing: IconButton(
                                      tooltip:
                                          state.starredPhotos.contains(
                                            photo.starKey,
                                          )
                                          ? '取消星标'
                                          : '标记星标',
                                      onPressed: pendingStars.contains(photo.id)
                                          ? null
                                          : () => star(photo),
                                      icon: Icon(
                                        state.starredPhotos.contains(
                                              photo.starKey,
                                            )
                                            ? Icons.star_rounded
                                            : Icons.star_outline_rounded,
                                      ),
                                    ),
                                    onTap: () =>
                                        context.push(photo.editorLocation),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
        ),
      );
    },
  );
}
