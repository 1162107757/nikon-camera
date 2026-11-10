import 'dart:io';

import 'package:flutter/material.dart';

import 'domain.dart';

Rect? shareAnchor(BuildContext context) {
  final box = context.findRenderObject();
  return box is RenderBox && box.hasSize && !box.size.isEmpty
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
}

void report(BuildContext context, Object error) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$error'), behavior: SnackBarBehavior.floating),
    );
  }
}

class PresetImage extends StatelessWidget {
  const PresetImage({super.key, required this.preset});
  final Preset preset;
  @override
  Widget build(BuildContext context) {
    Widget fallback() => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Center(
        child: Text(
          preset.format,
          style: TextStyle(
            fontSize: 28,
            letterSpacing: 2,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
    final uri = Uri.tryParse(preset.preview);
    if (uri == null) return fallback();
    if (uri.scheme == 'https' && uri.userInfo.isEmpty) {
      return Image.network(
        preset.preview,
        fit: BoxFit.cover,
        cacheWidth: 480,
        errorBuilder: (_, _, _) => fallback(),
        excludeFromSemantics: true,
      );
    }
    if (uri.scheme == 'file') {
      return Image.file(
        File.fromUri(uri),
        fit: BoxFit.cover,
        cacheWidth: 480,
        errorBuilder: (_, _, _) => fallback(),
        excludeFromSemantics: true,
      );
    }
    return fallback();
  }
}
