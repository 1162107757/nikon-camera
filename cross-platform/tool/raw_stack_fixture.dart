import 'dart:io';

import '../app/integration_test/synthetic_dng.dart';

void main(List<String> args) {
  final output = File(args.single);
  output.parent.createSync(recursive: true);
  output.writeAsBytesSync(syntheticDng());
}
