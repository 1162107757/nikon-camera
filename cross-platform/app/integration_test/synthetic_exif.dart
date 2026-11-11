import 'dart:typed_data';

/// Attach an own minimal EXIF IFD to a generated JPEG, removing prior EXIF only.
/// Other APP segments, compressed scan bytes and the source file are retained.
Uint8List jpegWithOrientation(Uint8List jpeg, int orientation) {
  if (jpeg.length < 4 ||
      jpeg[0] != 255 ||
      jpeg[1] != 216 ||
      orientation < 1 ||
      orientation > 8) {
    throw const FormatException(
      'Expected a generated JPEG and EXIF orientation 1–8',
    );
  }
  final result = BytesBuilder(copy: false)..add([255, 216]);
  final tiff = [
    73,
    73,
    42,
    0,
    8,
    0,
    0,
    0,
    1,
    0,
    18,
    1,
    3,
    0,
    1,
    0,
    0,
    0,
    orientation,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ];
  final payload = [69, 120, 105, 102, 0, 0, ...tiff];
  result.add([255, 225, 0, payload.length + 2, ...payload]);
  var offset = 2;
  while (offset + 4 <= jpeg.length) {
    if (jpeg[offset] != 255) {
      throw const FormatException('Invalid generated JPEG marker');
    }
    final marker = jpeg[offset + 1];
    if (marker == 218 || marker == 217) {
      result.add(jpeg.sublist(offset));
      return result.takeBytes();
    }
    final length = jpeg[offset + 2] * 256 + jpeg[offset + 3];
    final end = offset + length + 2;
    if (length < 2 || end > jpeg.length) {
      throw const FormatException('Invalid generated JPEG segment');
    }
    final exif =
        marker == 225 &&
        length >= 8 &&
        jpeg[offset + 4] == 69 &&
        jpeg[offset + 5] == 120 &&
        jpeg[offset + 6] == 105 &&
        jpeg[offset + 7] == 102 &&
        jpeg[offset + 8] == 0 &&
        jpeg[offset + 9] == 0;
    if (!exif) result.add(jpeg.sublist(offset, end));
    offset = end;
  }
  throw const FormatException('Generated JPEG has no compressed scan');
}
