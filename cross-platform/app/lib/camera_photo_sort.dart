/// Metadata-only ordering; no camera requests and no mutation of page cursors.
enum CameraPhotoSort {
  cameraOrder('相机顺序'),
  newest('拍摄时间 · 新到旧'),
  oldest('拍摄时间 · 旧到新'),
  nameAscending('名称 · 升序'),
  nameDescending('名称 · 降序');

  const CameraPhotoSort(this.label);
  final String label;
}

DateTime? cameraCaptureTime(Object? value) {
  if (value is! String) return null;
  final match = RegExp(
    r'^(\d{4})-?(\d{2})-?(\d{2})[T ](\d{2}):?(\d{2}):?(\d{2})(?:\.(\d{1,6}))?(Z|[+-]\d{2}:?\d{2})?$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i]!)];
  final [year, month, day, hour, minute, second] = parts;
  if (year < 1 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    return null;
  }
  final check = DateTime.utc(year, month, day, hour, minute, second);
  if (check.year != year || check.month != month || check.day != day) {
    return null;
  }
  final fraction = match[7] == null ? '' : '.${match[7]}';
  final zone = match[8] ?? 'Z';
  if (zone != 'Z') {
    final offset = zone.replaceAll(':', '');
    if (int.parse(offset.substring(1, 3)) > 23 ||
        int.parse(offset.substring(3, 5)) > 59) {
      return null;
    }
  }
  return DateTime.tryParse(
    '${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}$fraction$zone',
  );
}

int _compareNames(String left, String right) {
  final pattern = RegExp(r'\d+|\D+');
  final a = pattern.allMatches(left.toLowerCase()).map((m) => m[0]!).toList();
  final b = pattern.allMatches(right.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < a.length && i < b.length; i++) {
    final an = BigInt.tryParse(a[i]), bn = BigInt.tryParse(b[i]);
    final compared = an != null && bn != null
        ? an.compareTo(bn)
        : a[i].compareTo(b[i]);
    if (compared != 0) return compared;
  }
  return a.length.compareTo(b.length);
}

List<Map<String, dynamic>> sortedCameraPhotos(
  List<Map<String, dynamic>> photos,
  CameraPhotoSort order,
) {
  if (order == CameraPhotoSort.cameraOrder) return photos;
  final indexed = photos.asMap().entries.toList();
  final times = {
    if (order == CameraPhotoSort.newest || order == CameraPhotoSort.oldest)
      for (final entry in indexed)
        entry.key: cameraCaptureTime(entry.value['capturedAt']),
  };
  indexed.sort((a, b) {
    int compared;
    if (order == CameraPhotoSort.newest || order == CameraPhotoSort.oldest) {
      final at = times[a.key], bt = times[b.key];
      // Missing or invalid timestamps stay last in either direction.
      if (at == null || bt == null) {
        compared = at == null ? (bt == null ? 0 : 1) : -1;
      } else {
        compared = order == CameraPhotoSort.newest
            ? bt.compareTo(at)
            : at.compareTo(bt);
      }
    } else {
      compared = _compareNames(
        a.value['name'] as String? ?? '',
        b.value['name'] as String? ?? '',
      );
      if (order == CameraPhotoSort.nameDescending) compared = -compared;
    }
    return compared == 0 ? a.key.compareTo(b.key) : compared;
  });
  return [for (final entry in indexed) entry.value];
}
