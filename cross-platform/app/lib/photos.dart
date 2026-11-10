import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'domain.dart';
import 'widgets.dart';

class PhotosPage extends StatelessWidget {
  const PhotosPage({super.key, required this.state});
  final AppState state;
  Future<void> import(BuildContext context) async {
    try {
      final selected = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: '照片与 RAW',
            extensions: [
              'jpg',
              'jpeg',
              'png',
              'heic',
              'heif',
              'webp',
              'nef',
              'nrw',
              'dng',
              'arw',
              'cr2',
              'cr3',
              'raf',
              'rw2',
              'orf',
              'pef',
              'srw',
            ],
            uniformTypeIdentifiers: ['public.image', 'public.camera-raw-image'],
          ),
        ],
      );
      if (selected == null) return;
      final photo = await state.importPhoto(selected);
      if (context.mounted) context.push('/edit/${state.photos.indexOf(photo)}');
    } catch (error) {
      if (context.mounted) report(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('照片'),
      actions: [
        IconButton(
          onPressed: () => import(context),
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
                      onPressed: () => import(context),
                      child: const Text('选择照片'),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: state.photos.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final photo = state.photos[index];
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    leading: photo.info['raw'] == true
                        ? const Icon(Icons.raw_on_outlined, size: 40)
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(photo.path),
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              cacheWidth: 144,
                              errorBuilder: (_, _, _) => const Icon(
                                Icons.image_not_supported_outlined,
                              ),
                            ),
                          ),
                    title: Text(photo.name),
                    subtitle: Text(
                      '${photo.info['width']} × ${photo.info['height']}${photo.info['raw'] == true ? ' · RAW' : ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/edit/$index'),
                  ),
                );
              },
            ),
    ),
  );
}
