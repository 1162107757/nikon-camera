import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/light_workspace.dart';

void main() {
  test('zero light strength leaves the original masks untouched', () {
    expect(
      lightMasks(
        style: 0,
        amount: 0,
        angle: 0,
        size: .5,
        warmth: 40,
        center: const Offset(.5, .5),
      ),
      isEmpty,
    );
  });
  test('light presets use bounded source coordinates and signed exposure', () {
    for (var style = 0; style < 4; style++) {
      for (final angle in [0.0, 90.0, 180.0, 270.0, 360.0]) {
        final mask = lightMasks(
          style: style,
          amount: 100,
          angle: angle,
          size: .3,
          warmth: -50,
          center: const Offset(0, 1),
        ).single;
        for (final key in ['x0', 'y0', 'x1', 'y1']) {
          expect(mask[key], inInclusiveRange(0, 1));
        }
        expect(mask['kind'], style == 1 ? 'linear' : 'radial');
        expect(mask['exposure'], style == 3 ? lessThan(0) : greaterThan(0));
        expect(mask['temperature'], -50);
      }
    }
  });
  test('side light direction rotates without changing intensity', () {
    final a = lightMasks(
      style: 1,
      amount: 50,
      angle: 0,
      size: .5,
      warmth: 0,
      center: const Offset(.5, .5),
    ).single;
    final b = lightMasks(
      style: 1,
      amount: 50,
      angle: 90,
      size: .5,
      warmth: 0,
      center: const Offset(.5, .5),
    ).single;
    expect(a['y0'], a['y1']);
    expect(b['x0'], closeTo(b['x1'] as double, .00001));
    expect(a['exposure'], b['exposure']);
  });
}
