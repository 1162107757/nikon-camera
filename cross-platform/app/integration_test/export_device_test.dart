import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/export_settings_model_test.dart' as model;
import '../test/export_save_test.dart' as save;
import '../test/export_settings_test.dart' as forms;
import '../test/original_save_test.dart' as originals;

class ExportDeviceBinding extends IntegrationTestWidgetsFlutterBinding {
  @override
  bool get registerTestTextInput => true;
}

void main() {
  final binding = ExportDeviceBinding();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  model.main();
  save.main();
  forms.main();
  originals.main();
}
