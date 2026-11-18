import 'dart:math';
import 'dart:typed_data';

typedef NikonBlockEncryption = Future<Uint8List> Function(Uint8List block);

/// Nikon smart-device BLE wire format. A new identity is generated for Huevia.
/// Reference: https://github.com/hurui200320/nsg/blob/master/doc/nikon-z-gps.md
class NikonLocationProtocol {
  static const _salts = [
    (0x704066e4, 0x0433d552),
    (0xed4b8fac, 0x15f7e47b),
    (0x24471f11, 0x8b5ea1fc),
    (0x05960c31, 0x2b8c7f41),
    (0xfda588c1, 0xeba8b1f3),
    (0x99166056, 0x1bd3d550),
    (0xcd32687f, 0xa9e28a30),
    (0x2a8fe834, 0xdec7ebf4),
  ];

  static Uint8List randomBytes() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(8, (_) => random.nextInt(256)));
  }

  static Uint8List createIdentity() => randomBytes()..[0] = 1;

  static Uint8List hello(Uint8List identity, Uint8List nonce) {
    if (identity.length != 8 || identity.first != 1 || nonce.length != 8) {
      throw const FormatException('蓝牙配对资料无效。');
    }
    return Uint8List.fromList([1, ...nonce, ...identity]);
  }

  static Future<Uint8List> respond(
    Uint8List nonce,
    Uint8List challenge,
    NikonBlockEncryption encrypt,
  ) async {
    if (nonce.length != 8 || challenge.length != 17 || challenge.first != 2) {
      throw const FormatException('相机返回了无效的蓝牙配对请求。');
    }
    final cameraNonce = Uint8List.sublistView(challenge, 1, 9);
    final expected = Uint8List.sublistView(challenge, 9);
    for (final reverse in [false, true]) {
      final camera = _words(cameraNonce, reverse);
      final phone = _words(nonce, reverse);
      for (final salt in _salts) {
        final answer = await _mac([salt, camera, phone], encrypt);
        if (_same(answer, expected)) {
          return Uint8List.fromList([
            3,
            ...nonce,
            ...await _mac([salt, phone, camera], encrypt),
          ]);
        }
      }
    }
    throw const FormatException('无法确认相机的配对响应，请在机身重新开始配对。');
  }

  static String confirm(Uint8List confirm) {
    // Some Nikon bodies return a fresh timestamp at stage 4.
    if (confirm.length != 17 || confirm.first != 4) {
      throw const FormatException('相机未确认蓝牙配对。');
    }
    final serial = String.fromCharCodes(confirm.sublist(9))
        .replaceFirst(RegExp(r'[\x00 ]+$'), '');
    if (!RegExp(r'^[0-9]{6,8}$').hasMatch(serial)) {
      throw const FormatException('无法确认相机序列号。');
    }
    return serial;
  }

  static Uint8List clientName() => Uint8List(32)..setAll(0, 'Huevia'.codeUnits);

  static (int, int) _words(Uint8List bytes, bool reverse) {
    final data = ByteData.sublistView(bytes);
    return (data.getUint32(reverse ? 4 : 0), data.getUint32(reverse ? 0 : 4));
  }

  static Future<Uint8List> _mac(
    List<(int, int)> words,
    NikonBlockEncryption encrypt,
  ) async {
    var left = 0x01020304, right = 0x05060708;
    late Uint8List encrypted;
    for (final (a, b) in words) {
      final block = ByteData(8)
        ..setUint32(0, left ^ a)
        ..setUint32(4, right ^ b);
      encrypted = await encrypt(block.buffer.asUint8List());
      if (encrypted.length != 8) throw const FormatException('配对校验失败。');
      (left, right) = _words(encrypted, false);
    }
    return encrypted;
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  static Uint8List location({
    required double latitude,
    required double longitude,
    required double? altitude,
    required DateTime time,
    int? satellites,
  }) {
    if (!latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180 ||
        (altitude != null && (!altitude.isFinite || altitude.abs() > 65535))) {
      throw const FormatException('手机定位数据无效。');
    }
    final utc = time.toUtc();
    final packet = ByteData(41)..setUint16(0, 0x007f, Endian.little);
    final bytes = packet.buffer.asUint8List();
    void coordinate(int offset, double degrees, int positive, int negative) {
      final value = (degrees.abs() * 600000).floor();
      bytes.setAll(offset, [
        degrees < 0 ? negative : positive,
        value ~/ 600000,
        value ~/ 10000 % 60,
        value ~/ 100 % 100,
        value % 100,
      ]);
    }

    coordinate(2, latitude, 78, 83);
    coordinate(7, longitude, 69, 87);
    bytes[12] = satellites?.clamp(0, 255) ?? 4;
    bytes[13] = altitude != null && altitude < 0 ? 77 : 80;
    packet.setUint16(14, altitude?.abs().truncate() ?? 0, Endian.little);
    packet.setUint16(16, utc.year, Endian.little);
    bytes.setAll(18, [
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
      utc.millisecond ~/ 10,
      1,
    ]);
    bytes.setAll(25, 'WGS-84'.codeUnits);
    return bytes;
  }
}
