import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/photo_collage_test.dart' as collage;
import '../test/light_workspace_test.dart' as light;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  collage.main();
  light.main();
}
