import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/editor_parameter_icons.dart';
import 'package:huevia/hue_icons.dart';

void main() {
  testWidgets(
    'Adjustment and advanced tools render distinct readable symbols',
    (tester) async {
      final tools = <String, HueIconKind>{
        ...editorAdjustmentIcons,
        for (final item in editorAdvancedIcons.entries)
          'advanced-${item.key}': item.value,
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Wrap(
              children: [
                for (final item in tools.entries)
                  RepaintBoundary(
                    key: ValueKey(item.key),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: HueIcon(item.value, size: 26, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final signatures = <String, String>{};
      for (final name in tools.keys) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(ValueKey(name)),
        );
        final bytes = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          try {
            return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                .buffer
                .asUint8List();
          } finally {
            image.dispose();
          }
        });
        expect(bytes, isNotNull);
        var ink = 0;
        for (var i = 3; i < bytes!.length; i += 4) {
          if (bytes[i] > 16) ink++;
        }
        expect(ink, greaterThan(40), reason: '$name must paint a visible icon');
        final signature = sha256.convert(bytes).toString();
        expect(
          signatures[signature],
          isNull,
          reason: '$name repeats the actual pixels of ${signatures[signature]}',
        );
        signatures[signature] = name;
      }
      expect(tester.takeException(), isNull);
    },
  );
}
