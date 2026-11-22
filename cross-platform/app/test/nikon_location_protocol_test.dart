import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/nikon_location_protocol.dart';

Uint8List bytes(String hex) => Uint8List.fromList([
  for (var offset = 0; offset < hex.length; offset += 2)
    int.parse(hex.substring(offset, offset + 2), radix: 16),
]);

String hex(List<int> values) =>
    values.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('Nikon pairing matches independent Blowfish known answers', () async {
    final inputs = {
      '714265e00135d25a': 'd85c2a43d9c7e7a1',
      '4aff9e860f201fa8': 'd95af5d525922a9f',
      'c878c69170f45d17': '439d2cc8a97d5918',
      'c97e19078ca19029': 'de7589118506fb25',
      '4cd63dd453e1032c': '83e47b4b5dfb2b0b',
    };
    final nonce = bytes('1122334455667788');
    expect(
      hex(NikonLocationProtocol.hello(bytes('01ddccbb66554433'), nonce)),
      '01112233445566778801ddccbb66554433',
    );
    final response = await NikonLocationProtocol.respond(
      nonce,
      bytes('0292a3b4c5d6e7f809439d2cc8a97d5918'),
      (block) async => bytes(inputs[hex(block)]!),
    );
    expect(hex(response), '03112233445566778883e47b4b5dfb2b0b');
    await expectLater(
      NikonLocationProtocol.respond(
        nonce,
        bytes('0292a3b4c5d6e7f809439d2cc8a97d5918'),
        (_) async => Uint8List(8),
      ),
      throwsFormatException,
    );
    expect(
      NikonLocationProtocol.confirm(
        bytes('04a1a2a3a4a5a6a7a83132333435363700'),
      ),
      '1234567',
    );
  });

  test('GPS wire payload preserves hemisphere, altitude, UTC and datum', () {
    final gps = NikonLocationProtocol.location(
      latitude: -33.875,
      longitude: 151.2075,
      altitude: -64,
      time: DateTime.utc(2026, 11, 18, 7, 42, 36, 170),
      satellites: 8,
    );
    expect(
      hex(gps),
      '7f00532134320045970c2d00084d4000ea070b12072a2411015747532d383400000000000000000000',
    );
    expect(
      () => NikonLocationProtocol.location(
        latitude: 91,
        longitude: 0,
        altitude: 0,
        time: DateTime.utc(2026),
      ),
      throwsFormatException,
    );
  });
}
