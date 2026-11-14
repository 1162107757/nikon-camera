import 'dart:io';

import 'package:huevia/camera_photo_sort.dart';

void main() {
  var checks = 0;
  void verify(bool condition, String message) {
    checks++;
    if (!condition) throw StateError(message);
  }

  List<String> names(List<Map<String, dynamic>> rows) => [
    for (final row in rows) row['name'] as String,
  ];
  final source = <Map<String, dynamic>>[
    {'handle': 1, 'name': 'DSC_10.JPG', 'capturedAt': '20261114T130000'},
    {'handle': 2, 'name': 'DSC_2.JPG', 'capturedAt': '20261114T120000'},
    {'handle': 3, 'name': 'DSC_1.JPG', 'capturedAt': ''},
    {'handle': 4, 'name': 'DSC_3.JPG', 'capturedAt': '20260230T120000'},
    {'handle': 5, 'name': 'DSC_20.JPG', 'capturedAt': '20261114T130000'},
  ];
  verify(
    identical(sortedCameraPhotos(source, CameraPhotoSort.cameraOrder), source),
    'Camera order must retain the source list.',
  );
  verify(
    names(sortedCameraPhotos(source, CameraPhotoSort.newest)).join(',') ==
        'DSC_10.JPG,DSC_20.JPG,DSC_2.JPG,DSC_1.JPG,DSC_3.JPG',
    'Newest must be stable and keep absent/invalid dates last.',
  );
  verify(
    names(sortedCameraPhotos(source, CameraPhotoSort.oldest)).join(',') ==
        'DSC_2.JPG,DSC_10.JPG,DSC_20.JPG,DSC_1.JPG,DSC_3.JPG',
    'Oldest must also keep absent/invalid dates last.',
  );
  verify(
    names(sortedCameraPhotos(source, CameraPhotoSort.nameAscending))
            .join(',') ==
        'DSC_1.JPG,DSC_2.JPG,DSC_3.JPG,DSC_10.JPG,DSC_20.JPG',
    'Filename numbers must use natural order.',
  );
  verify(
    names(sortedCameraPhotos(source, CameraPhotoSort.nameDescending))
            .join(',') ==
        'DSC_20.JPG,DSC_10.JPG,DSC_3.JPG,DSC_2.JPG,DSC_1.JPG',
    'Descending filename order.',
  );
  verify(
    source.map((row) => row['handle']).join(',') == '1,2,3,4,5',
    'Sorting must not change pagination input order.',
  );
  verify(
    cameraCaptureTime('20261114T120000+0800') == DateTime.utc(2026, 11, 14, 4),
    'PTP timezone must be honored.',
  );
  verify(
    cameraCaptureTime('2026-11-14T04:00:00Z') ==
        cameraCaptureTime('20261114T120000+0800'),
    'ISO and PTP instants must compare equally.',
  );
  verify(cameraCaptureTime('20240229T120000') != null, 'Leap day is valid.');
  for (final invalid in <Object?>[
    null,
    123,
    '',
    'unknown',
    '20260229T120000',
    '20261131T120000',
    '20261114T240000',
    '20261114T126000',
    '20261114T120060',
    '20261114T120000+9999',
  ]) {
    verify(
      cameraCaptureTime(invalid) == null,
      'Invalid date must stay unknown: $invalid',
    );
  }
  final same = <Map<String, dynamic>>[
    {'handle': 6, 'name': 'dsc_02.jpg'},
    {'handle': 7, 'name': 'DSC_2.JPG'},
  ];
  verify(
    sortedCameraPhotos(
          same,
          CameraPhotoSort.nameAscending,
        ).map((row) => row['handle']).join(',') ==
        '6,7',
    'Case/number ties keep camera order.',
  );
  final nextPage = [
    ...source,
    <String, dynamic>{
      'handle': 8,
      'name': 'DSC_4.JPG',
      'capturedAt': '20261114T123000',
    },
  ];
  verify(
    sortedCameraPhotos(nextPage, CameraPhotoSort.oldest)[1]['handle'] == 8,
    'New page must insert into the selected ordering.',
  );
  verify(
    sortedCameraPhotos([], CameraPhotoSort.newest).isEmpty,
    'Empty camera list.',
  );
  verify(
    source[3]['capturedAt'] == '20260230T120000',
    'Invalid metadata must remain unchanged.',
  );
  stdout.writeln(
    'PASS $checks camera photo sorting checks (pure Dart; no Flutter or camera runtime).',
  );
}
