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
import '../test/ui_preferences_test.dart' as ui_preferences;
import '../test/batch_export_test.dart' as batch_export;
import '../test/help_test.dart' as help;
import '../test/preview_templates_test.dart' as preview_templates;
import '../test/editor_workspace_test.dart' as editor_workspace;
import '../test/border_panel_test.dart' as border_panel;
import '../test/community_state_test.dart' as community_state;
import '../test/community_ui_test.dart' as community_ui;
import '../test/submission_ui_test.dart' as submission_ui;
import '../test/account_profile_test.dart' as account_profile;
import '../test/local_adjustments_test.dart' as local_adjustments;
import '../test/local_editor_test.dart' as local_editor;
import '../test/selection_mask_test.dart' as selection_mask;
import '../test/selection_editor_test.dart' as selection_editor;
import '../test/selection_workspace_test.dart' as selection_workspace;

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
  ui_preferences.main();
  batch_export.main();
  help.main();
  preview_templates.main();
  editor_workspace.main();
  border_panel.main();
  community_state.main();
  community_ui.main();
  submission_ui.main();
  account_profile.main();
  local_adjustments.main();
  local_editor.main();
  selection_mask.main();
  selection_editor.main();
  selection_workspace.main();
}
