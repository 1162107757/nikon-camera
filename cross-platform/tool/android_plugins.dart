// Use the pinned Flutter SDK's own generator before direct local Gradle builds.
// It excludes dev-only plugins in release mode and restores them for tests.
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/base/template.dart';
import 'package:flutter_tools/src/isolated/mustache_template.dart';
import 'package:flutter_tools/src/context_runner.dart';
import 'package:flutter_tools/src/flutter_plugins.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3 || !['debug', 'release'].contains(args[1])) {
    throw ArgumentError('Expected app directory, debug/release, Flutter SDK');
  }
  Cache.flutterRoot = args[2];
  await runInContext(() async {
    final project = FlutterProject.fromDirectory(globals.fs.directory(args[0]));
    await injectPlugins(
      project,
      releaseMode: args[1] == 'release',
      androidPlatform: true,
    );
    globals.logger.printStatus('Android plugins generated for ${args[1]}');
  }, overrides: {TemplateRenderer: () => const MustacheTemplateRenderer()});
}
