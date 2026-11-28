import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'domain.dart';
import 'widgets.dart';

class ExportAlbum {
  const ExportAlbum([this.path]) : collectionId = null, collectionTitle = null;
  const ExportAlbum.collection(this.collectionId, this.collectionTitle)
    : path = null;
  final String? path;
  final String? collectionId, collectionTitle;

  String get name =>
      collectionTitle ??
      (path == null
          ? '默认相册（相机预设）'
          : path!.substring(0, path!.length - 1).split('/').last);
}

bool validExportAlbum(String? path) {
  if (path == null) return true;
  if (path.length > 512 ||
      !path.endsWith('/') ||
      !(path.startsWith('Pictures/') || path.startsWith('DCIM/'))) {
    return false;
  }
  final invalid = RegExp(r'[\x00-\x1f\x7f-\x9f\\:*?"<>|]');
  return path
      .substring(0, path.length - 1)
      .split('/')
      .every(
        (part) =>
            part.trim().isNotEmpty &&
            !part.startsWith('.') &&
            !invalid.hasMatch(part),
      );
}

const _lastAlbumKey = 'export.lastAndroidAlbum';

Future<ExportAlbum?> chooseExportAlbum(
  BuildContext context,
  HueviaCore core, {
  bool iosCollections = false,
}) async {
  if (core.platform == 'ios' && iosCollections) {
    return hueDialog<ExportAlbum>(
      context: context,
      builder: (_) => _ExportAlbumDialog(core: core, collections: true),
    );
  }
  if (core.platform != 'android') return const ExportAlbum();
  final selected = await hueDialog<ExportAlbum>(
    context: context,
    builder: (_) => _ExportAlbumDialog(core: core),
  );
  if (selected != null) {
    unawaited(_rememberAlbum(selected));
  }
  return selected;
}

Future<void> _rememberAlbum(ExportAlbum album) async {
  try {
    await SharedPreferencesAsync().setString(_lastAlbumKey, album.path ?? '');
  } catch (_) {
    // Saving the selected photo does not depend on local preferences.
  }
}

class _ExportAlbumDialog extends StatefulWidget {
  const _ExportAlbumDialog({required this.core, this.collections = false});
  final HueviaCore core;
  final bool collections;

  @override
  State<_ExportAlbumDialog> createState() => _ExportAlbumDialogState();
}

class _ExportAlbumDialogState extends State<_ExportAlbumDialog> {
  Future<Json> readLocations() => widget.core.call(
    widget.collections ? 'gallery.exportCollections' : 'gallery.exportAlbums',
  );
  late Future<Json> albums = readLocations();
  bool requesting = false;
  String? permissionError, last;

  @override
  void initState() {
    super.initState();
    if (!widget.collections) unawaited(_loadLastAlbum());
  }

  Future<void> _loadLastAlbum() async {
    try {
      final saved = await SharedPreferencesAsync().getString(_lastAlbumKey);
      if (mounted && saved != null) setState(() => last = saved);
    } catch (_) {
      // The picker stays usable when local preferences are unavailable.
    }
  }

  Future<void> readAlbums() async {
    setState(() {
      requesting = true;
      permissionError = null;
    });
    try {
      await widget.core.galleryPermission();
      if (mounted) {
        setState(() => albums = readLocations());
      }
    } catch (failure) {
      if (mounted) setState(() => permissionError = '$failure');
    } finally {
      if (mounted) setState(() => requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('选择手机相册'),
    content: SizedBox(
      width: 360,
      height: MediaQuery.sizeOf(context).height * .40,
      child: FutureBuilder<Json>(
        future: albums,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final items = data?['items'] is List
              ? data!['items'] as List
              : const [];
          final choices = [
            if (widget.collections)
              const ExportAlbum.collection(null, '系统照片图库')
            else
              const ExportAlbum(),
            if (widget.collections) ...[
              for (final row in items.whereType<Map>())
                if (row['id'] is String && row['title'] is String)
                  ExportAlbum.collection(
                    row['id'] as String,
                    row['title'] as String,
                  ),
            ] else ...[
              for (final path in items.whereType<String>().toSet())
                if (path != 'Pictures/相机预设/' && validExportAlbum(path))
                  ExportAlbum(path),
            ],
          ];
          final counts = <String, int>{};
          final previous = choices.indexWhere(
            (album) => (album.path ?? '') == last,
          );
          if (previous > 0) choices.insert(0, choices.removeAt(previous));
          for (final album in choices) {
            counts.update(album.name, (count) => count + 1, ifAbsent: () => 1);
          }
          return ListView.builder(
            itemCount: choices.length + 1,
            itemBuilder: (context, index) {
              if (index < choices.length) {
                final album = choices[index];
                final usedLast = (album.path ?? '') == last;
                final details = [
                  if (usedLast) '上次使用',
                  if (album.path != null && counts[album.name]! > 1)
                    album.path!,
                ];
                return ListTile(
                  title: Text(album.name),
                  subtitle: details.isEmpty ? null : Text(details.join(' · ')),
                  onTap: requesting
                      ? null
                      : () => Navigator.pop(context, album),
                );
              }
              if (requesting ||
                  snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LinearProgressIndicator(),
                );
              }
              if (snapshot.hasError) return const Text('暂时无法读取手机相册。');
              if (permissionError case final message?) return Text(message);
              if (data?['supported'] == true && data?['readable'] != true) {
                return TextButton(
                  onPressed: readAlbums,
                  child: const Text('允许读取相册以查看其他位置'),
                );
              }
              if (data?['supported'] == true && choices.length == 1) {
                return const Text('当前没有其他可选相册。');
              }
              return const SizedBox.shrink();
            },
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ],
  );
}
