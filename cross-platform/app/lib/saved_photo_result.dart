import 'package:flutter/material.dart';

import 'domain.dart';
import 'export_album.dart';
import 'widgets.dart';

String systemAlbumLabel(HueviaCore core, [String? path]) =>
    core.platform == 'android' ? ExportAlbum(path).name : '手机相册';

class SavedPhotoResult extends StatelessWidget {
  const SavedPhotoResult({
    super.key,
    required this.core,
    required this.receipt,
    this.destination,
    this.fallbackName,
  });

  final HueviaCore core;
  final Json receipt;
  final String? destination, fallbackName;

  @override
  Widget build(BuildContext context) {
    final name = receipt['filename'];
    final uri = receipt['uri'];
    final location = receipt['hasLocation'];
    final openUri =
        core.platform == 'android' &&
            receipt['published'] == true &&
            uri is String &&
            RegExp(
              r'^content://media/(external|external_primary)/images/media/[0-9]+$',
            ).hasMatch(uri)
        ? uri
        : null;
    final details = [
      ?destination,
      if (location == true) '已保存文件含位置信息',
      if (location == false) '已保存文件无位置信息',
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (name is String && name.isNotEmpty)
          Text(name)
        else if (fallbackName != null)
          Text(fallbackName!),
        if (details.isNotEmpty)
          Text(
            details.join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (openUri != null)
          TextButton(
            onPressed: () async {
              try {
                await core.openPublishedPhoto(openUri);
              } catch (failure) {
                if (context.mounted) report(context, failure);
              }
            },
            child: const Text('查看已保存照片'),
          ),
      ],
    );
  }
}
