import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/camera_test.dart' as camera;
import '../test/camera_previews_test.dart' as previews;
import '../test/session_race_test.dart' as races;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  camera.main();
  previews.main();
  races.main();
}
