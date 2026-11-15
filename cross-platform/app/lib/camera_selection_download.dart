import 'package:flutter/material.dart';

import 'theme.dart';

/// The approved circular download action, local to selected camera photos.
class CameraSelectionDownload extends StatelessWidget {
  const CameraSelectionDownload({
    super.key,
    required this.count,
    required this.onPressed,
  });

  final int count;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: '下载所选 $count 张照片',
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: '下载所选 $count 张照片',
        child: SizedBox(
          key: const Key('camera-selection-download'),
          width: 56,
          height: 56,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Material(
                  color: const Color(0xff242420),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onPressed,
                    customBorder: const CircleBorder(),
                    excludeFromSemantics: true,
                    child: const Center(
                      child: Icon(
                        Icons.download_rounded,
                        size: 28,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -3,
                top: -4,
                child: IgnorePointer(
                  child: Container(
                    width: count > 99 ? 29 : 24,
                    height: count > 99 ? 29 : 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p.card,
                      shape: BoxShape.circle,
                      border: Border.all(color: p.surface, width: 2),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: p.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
