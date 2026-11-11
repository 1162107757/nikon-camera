import 'dart:io';

import 'package:flutter/material.dart';

final appearanceMode = ValueNotifier(ThemeMode.system);
Future<void> readAppearance(String root) async {
  if (root.isEmpty) return;
  final file = File('$root/appearance.txt');
  if (await file.exists()) {
    final mode = await file.readAsString();
    appearanceMode.value = ThemeMode.values.firstWhere(
      (value) => value.name == mode,
      orElse: () => ThemeMode.system,
    );
  }
}

Future<void> setAppearance(String root, ThemeMode mode) async {
  final file = File('$root/appearance.txt');
  await file.writeAsString(mode.name, flush: true);
  appearanceMode.value = mode;
}
