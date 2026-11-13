import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';

/// The UIKit XCTest cases exercise missing/detached caches and cancellation.
/// This check uses the actual foreground scene of the running Flutter engine.
Future<void> verifyCameraForegroundPresentation(HueviaCore core) async {
  if (!Platform.isIOS) return;
  final report = await core.call('camera.diagnostics');
  final presentation = object(report['presentation']);
  expect(presentation['snapshotOnMainThread'], true);
  expect(presentation['applicationForeground'], true);
  expect(presentation['foregroundActive'], true);
  expect(presentation['activeSceneCount'], greaterThan(0));
  expect(presentation['eligibleWindowCount'], greaterThan(0));
  expect(
    presentation['presenterAvailable'],
    true,
    reason: 'An active Flutter scene must work even if its registrar had no attached controller at plugin registration.',
  );
  // Only booleans/counts are reported: no endpoint, SSID, identifier or token.
  debugPrint('iOS camera foreground presentation: $presentation');
}
