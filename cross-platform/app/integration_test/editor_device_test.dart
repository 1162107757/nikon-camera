import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/editor_test.dart' as editor;
import '../test/photos_test.dart' as photos;
import '../test/recipes_test.dart' as recipes;
import '../test/shared_app_test.dart' as shared_app;
import '../test/copy_adjustments_test.dart' as copy_adjustments;
import '../test/versions_test.dart' as versions;
import '../test/account_search_test.dart' as account_search;
import '../test/session_race_test.dart' as session_race;
import '../test/shell_overlays_test.dart' as shell_overlays;

// Reuse the actual widget regressions on Android when the Windows test engine
// cannot finish. Native image/RAW behavior has its separate integration suite.
class DeviceWidgetsBinding extends IntegrationTestWidgetsFlutterBinding {
  // These are viewport/layout tests. Keep their simulated text input instead
  // of opening the device IME over the intentionally narrow test viewport.
  @override
  bool get registerTestTextInput => true;
}

void main() {
  final binding = DeviceWidgetsBinding();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  editor.main();
  photos.main();
  recipes.main();
  shared_app.main();
  copy_adjustments.main();
  versions.main();
  account_search.main();
  session_race.main();
  shell_overlays.main();
}
