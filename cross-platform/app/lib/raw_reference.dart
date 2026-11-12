import 'dart:io';

import 'package:path/path.dart' as p;

import 'domain.dart';

/// Portable description only; native adapters recheck bytes and source identity.
class RawJpegReference {
  const RawJpegReference(this.path, this.name, this.sha256, this.sourceSha);
  final String path, name, sha256, sourceSha;
  static RawJpegReference? restore(Json info, String root) {
    final stored = info['rawJpegReference'];
    if (stored is! Map) return null;
    final value = object(stored);
    final relative = value['relativePath'];
    if (relative is! String || p.isAbsolute(relative)) return null;
    try {
      return checked({
        ...value,
        'path': p.normalize(
          p.join(root, relative.replaceAll('/', p.separator)),
        ),
      }, root);
    } on AppFailure {
      return null;
    }
  }

  static RawJpegReference checked(Json value, String root, {String? name}) {
    final path = value['path'],
        sha = value['sha256'],
        source = value['sourceSha'];
    if (root.isEmpty ||
        path is! String ||
        !p.isWithin(p.join(root, 'originals'), path) ||
        sha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        source is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(source)) {
      throw const AppFailure('JPEG 参考记录无效，请重新选择。');
    }
    return RawJpegReference(
      path,
      name ?? value['name'] as String? ?? p.basename(path),
      sha,
      source,
    );
  }

  Json get payload => {'path': path, 'sha256': sha256, 'sourceSha': sourceSha};
  Json stored(String root) => {
    'relativePath': p.relative(path, from: root).replaceAll('\\', '/'),
    'name': name,
    'sha256': sha256,
    'sourceSha': sourceSha,
  };
  Future<bool> exists() => File(path).exists();
}
