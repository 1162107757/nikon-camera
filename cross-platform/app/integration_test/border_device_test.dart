import 'package:flutter_test/flutter_test.dart';
import 'editor_device_test.dart' show DeviceWidgetsBinding;
import '../test/border_panel_test.dart' as border;

void main() {
  final binding = DeviceWidgetsBinding();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  border.main();
}
