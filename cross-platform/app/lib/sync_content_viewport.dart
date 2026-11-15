import 'package:flutter/material.dart';

import 'theme.dart';

/// Keeps scrolling photos below the fixed Sync tabs, with a soft viewport edge.
class SyncContentViewport extends StatelessWidget {
  const SyncContentViewport({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final surface = HuePalette.of(context).surface;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ClipRect(
        key: const Key('sync-content-viewport'),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 12,
              child: IgnorePointer(
                child: DecoratedBox(
                  key: const Key('sync-content-top-fade'),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [surface, surface.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
