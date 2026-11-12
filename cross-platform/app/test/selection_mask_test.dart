import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/selection_mask.dart';

import 'fixtures/local_selection_original.dart';

void main() {
  final reference = object(jsonDecode(originalSelectionVectorsJson));
  final cases = reference['cases'] as List;
  for (final raw in cases) {
    final fixture = object(raw);
    test('Selection coverage agrees with original Java: ${fixture['name']}', () {
      final coverage = SelectionCoverage(
        object(fixture['region']),
        (fixture['width'] as num).toDouble(),
        (fixture['height'] as num).toDouble(),
      );
      final columns = fixture['columns'] as int,
          rows = fixture['rows'] as int,
          samples = fixture['samples'] as List;
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < columns; x++) {
          expect(
            coverage.weight(x / (columns - 1), y / (rows - 1)),
            closeTo((samples[y * columns + x] as num).toDouble(), 1e-11),
            reason:
                'source sample ($x,$y) at ${fixture['width']}×${fixture['height']}',
          );
        }
      }
      expect(coverage.weight(double.nan, .5), 0);
      expect(coverage.weight(-.01, .5), 0);
      expect(coverage.weight(.5, 1.01), 0);
    });
  }
  test(
    'Selection overlay stays bounded and uses premultiplied original cyan',
    () {
      final fixture = object(
        cases.firstWhere(
          (raw) => object(raw)['name'] == 'ordered-inverted-6400x4000',
        ),
      );
      final result = buildSelectionMask({
        'region': fixture['region'],
        'width': 6400,
        'height': 4000,
      });
      expect(result['width'], 320);
      expect(result['height'], 200);
      expect(result['hasCoverage'], true);
      final bytes = result['bytes'] as List<int>;
      expect(bytes, hasLength(320 * 200 * 4));
      for (var i = 0; i < bytes.length; i += 4) {
        final alpha = bytes[i + 3];
        expect(alpha, inInclusiveRange(0, 38));
        expect(bytes[i], (121 * alpha / 255).round());
        expect(bytes[i + 1], (213 * alpha / 255).round());
        expect(bytes[i + 2], (239 * alpha / 255).round());
      }
    },
  );
  test('Empty inverted selections do not cover the photo and reject unbounded inputs', () {
    final fixture = object(
      cases.firstWhere(
        (raw) => object(raw)['name'] == 'empty-inverted-6400x4000',
      ),
    );
    final result = buildSelectionMask({
      'region': fixture['region'],
      'width': 64,
      'height': 32,
    });
    expect(result['hasCoverage'], false);
    expect((result['bytes'] as List<int>).every((value) => value == 0), true);
    expect(
      () => SelectionCoverage({}, double.infinity, 32),
      throwsFormatException,
    );
    expect(
      () => SelectionCoverage({'strokes': List.filled(65, {})}, 32, 32),
      throwsFormatException,
    );
  });
}
