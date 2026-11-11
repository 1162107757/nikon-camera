import 'package:flutter_test/flutter_test.dart';
import 'editor_device_test.dart' show DeviceWidgetsBinding;
import '../test/photos_test.dart' as photos;

void main() {
  final binding = DeviceWidgetsBinding();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  photos.main();
}
