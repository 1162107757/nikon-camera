import 'dart:convert';
import 'dart:typed_data';

/// Original synthetic Bayer ramp; no camera/user photographs are distributed.
/// Tags follow Adobe's public DNG 1.4 TIFF/CFA and color-matrix specification.
Uint8List syntheticDng({String? identity}) {
  const width = 256, height = 192;
  Uint8List words(List<int> values, int size) {
    final data = ByteData(values.length * size);
    for (var i = 0; i < values.length; i++) {
      if (size == 2) {
        data.setUint16(i * size, values[i], Endian.little);
      } else {
        data.setInt32(i * size, values[i], Endian.little);
      }
    }
    return data.buffer.asUint8List();
  }

  Uint8List rational(List<double> values) => words([
    for (final value in values) ...[(value * 1000000).round(), 1000000],
  ], 4);
  final tags = <int, (int, int, Uint8List)>{};
  void short(int tag, List<int> value) =>
      tags[tag] = (3, value.length, words(value, 2));
  void long(int tag, List<int> value) =>
      tags[tag] = (4, value.length, words(value, 4));
  void bytes(int tag, List<int> value) =>
      tags[tag] = (1, value.length, Uint8List.fromList(value));
  void text(int tag, String value) {
    final data = Uint8List.fromList([...ascii.encode(value), 0]);
    tags[tag] = (2, data.length, data);
  }

  long(254, [0]);
  long(256, [width]);
  long(257, [height]);
  short(258, [16]);
  short(259, [1]);
  short(262, [32803]);
  text(271, 'Huevia Test');
  text(272, 'Synthetic Bayer');
  long(273, [0]);
  short(274, [1]);
  short(277, [1]);
  long(278, [height]);
  long(279, [width * height * 2]);
  short(284, [1]);
  if (identity != null) text(305, identity);
  short(33421, [2, 2]);
  bytes(33422, [0, 1, 1, 2]);
  bytes(50706, [1, 4, 0, 0]);
  bytes(50707, [1, 3, 0, 0]);
  text(50708, 'Huevia Synthetic Bayer');
  short(50713, [1, 1]);
  tags[50714] = (5, 1, rational([0]));
  long(50717, [4095]);
  long(50719, [0, 0]);
  long(50720, [width, height]);
  tags[50721] = (
    10,
    9,
    rational([
      3.2404542,
      -1.5371385,
      -.4985314,
      -.969266,
      1.8760108,
      .041556,
      .0556434,
      -.2040259,
      1.0572252,
    ]),
  );
  tags[50728] = (5, 3, rational([1, 1, 1]));
  short(50778, [21]);
  long(50829, [0, 0, height, width]);
  final keys = tags.keys.toList()..sort();
  var offset = 8 + 2 + keys.length * 12 + 4;
  for (final tag in keys) {
    if (tags[tag]!.$3.length > 4) offset += (tags[tag]!.$3.length + 1) & ~1;
  }
  final pixels = offset;
  long(273, [pixels]);
  final result = Uint8List(pixels + width * height * 2),
      output = ByteData.sublistView(result);
  result.setAll(0, [73, 73, 42, 0, 8, 0, 0, 0]);
  output.setUint16(8, keys.length, Endian.little);
  offset = 8 + 2 + keys.length * 12 + 4;
  for (var i = 0; i < keys.length; i++) {
    final tag = keys[i], value = tags[tag]!, at = 10 + i * 12;
    output.setUint16(at, tag, Endian.little);
    output.setUint16(at + 2, value.$1, Endian.little);
    output.setUint32(at + 4, value.$2, Endian.little);
    if (value.$3.length <= 4) {
      result.setAll(at + 8, value.$3);
    } else {
      output.setUint32(at + 8, offset, Endian.little);
      result.setAll(offset, value.$3);
      offset += (value.$3.length + 1) & ~1;
    }
  }
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      output.setUint16(
        pixels + (y * width + x) * 2,
        x >= 208 ? 4095 : (x / 207 * 3800).round(),
        Endian.little,
      );
    }
  }
  return result;
}
