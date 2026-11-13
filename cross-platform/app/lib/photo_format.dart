import 'package:path/path.dart' as p;

const _photoExtensions = {
  'jpg',
  'jpeg',
  'png',
  'heic',
  'heif',
  'webp',
  'tif',
  'tiff',
  'bmp',
  'gif',
  'avif',
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
  'raw',
};

String? _fileFormat(String value) {
  final uri = Uri.tryParse(value);
  final filePath = uri != null && uri.hasScheme && uri.scheme.length > 1
      ? uri.path
      : value;
  final extension = p.posix
      .extension(filePath.replaceAll('\\', '/'))
      .replaceFirst('.', '')
      .toLowerCase();
  return _photoExtensions.contains(extension) ? extension.toUpperCase() : null;
}

/// The working source path is authoritative; platform asset IDs may need a name.
String photoFormatLabel({required String filePath, required String name}) =>
    _fileFormat(filePath) ?? _fileFormat(name) ?? '照片';

String photoEditorFormatLabel({
  required String filePath,
  required String name,
  String? rawSourcePath,
}) {
  final current = photoFormatLabel(filePath: filePath, name: name);
  final source = rawSourcePath == null || rawSourcePath == filePath
      ? null
      : _fileFormat(rawSourcePath);
  return '$current · 编辑照片${source == null ? '' : ' · 来源 $source'}';
}
