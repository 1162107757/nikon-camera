import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/camera_test.dart' as camera;
import '../test/camera_previews_test.dart' as previews;
import '../test/session_race_test.dart' as races;
import '../test/camera_transfer_test.dart' as transfer;
import '../test/editor_presets_test.dart' as filters;
import '../test/camera_navigation_test.dart' as navigation;
import '../test/camera_viewer_layout_test.dart' as viewer;
import '../test/project_presets_test.dart' as projects;
import '../test/raw_reference_test.dart' as raw_reference;
import '../test/raw_reference_ui_test.dart' as raw_reference_ui;
import '../test/app_stability_test.dart' as stability;
import '../test/camera_live_test.dart' as live;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  camera.main();
  previews.main();
  races.main();
  transfer.main();
  filters.main();
  navigation.main();
  viewer.main();
  projects.main();
  raw_reference.main();
  raw_reference_ui.main();
  stability.main();
  live.main();
}
