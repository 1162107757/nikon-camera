import 'package:flutter/material.dart';

import 'camera_photo_sort.dart';
import 'theme.dart';

class CameraPhotoToolbar extends StatelessWidget {
  const CameraPhotoToolbar({
    super.key,
    required this.count,
    this.missingTimeCount = 0,
    required this.hasMore,
    required this.inventoryReady,
    required this.raw,
    required this.selecting,
    required this.order,
    required this.onRawChanged,
    required this.onOrderChanged,
    required this.onSelection,
  });
  final int count, missingTimeCount;
  final bool hasMore, inventoryReady, raw, selecting;
  final CameraPhotoSort order;
  final ValueChanged<bool>? onRawChanged;
  final ValueChanged<CameraPhotoSort>? onOrderChanged;
  final VoidCallback? onSelection;

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    final title = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('相机照片', style: TextStyle(fontSize: 12)),
        const SizedBox(width: 7),
        Flexible(
          child: Semantics(
            label: inventoryReady
                ? '已读取 $count 张${hasMore ? '，可继续加载' : ''}'
                : '照片目录尚未读取',
            child: Text(
              inventoryReady ? '$count${hasMore ? '+' : ''} 张' : '未读取',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: p.secondary),
            ),
          ),
        ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'RAW 原片',
          toggled: raw,
          child: InkWell(
            onTap: onRawChanged == null ? null : () => onRawChanged!(!raw),
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('RAW 原片', style: TextStyle(fontSize: 11)),
                  SizedBox(
                    width: 43,
                    height: 48,
                    child: ExcludeSemantics(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Switch.adaptive(
                          key: const Key('camera-raw-switch'),
                          value: raw,
                          onChanged: onRawChanged,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        PopupMenuButton<CameraPhotoSort>(
          key: const Key('camera-photo-sort'),
          tooltip: '排序：${order.label}',
          enabled: onOrderChanged != null,
          initialValue: order,
          onSelected: onOrderChanged,
          constraints: const BoxConstraints(minWidth: 240, maxWidth: 290),
          itemBuilder: (_) => [
            PopupMenuItem<CameraPhotoSort>(
              enabled: false,
              child: Text(
                count > 0 && missingTimeCount == count
                    ? '相机未提供可用拍摄时间，可按名称排序'
                    : missingTimeCount > 0
                    ? '仅排序已读取照片；$missingTimeCount 张缺少时间'
                    : '排序已读取的照片，新页按当前规则插入',
                style: const TextStyle(fontSize: 11),
              ),
            ),
            for (final value in CameraPhotoSort.values)
              CheckedPopupMenuItem(
                value: value,
                checked: order == value,
                child: Text(value.label),
              ),
          ],
          icon: Icon(Icons.swap_vert_rounded, size: 20, color: p.ink),
          padding: EdgeInsets.zero,
          style: const ButtonStyle(
            minimumSize: WidgetStatePropertyAll(Size(44, 48)),
          ),
        ),
        TextButton(
          onPressed: onSelection,
          style: TextButton.styleFrom(
            foregroundColor: p.ink,
            minimumSize: const Size(44, 48),
            padding: const EdgeInsets.symmetric(horizontal: 3),
          ),
          child: Text(
            selecting ? '取消' : '选择',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth < 310 ||
            MediaQuery.textScalerOf(context).scale(12) > 15) {
          return Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            children: [
              SizedBox(width: 125, child: title),
              actions,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: title),
            const SizedBox(width: 6),
            actions,
          ],
        );
      },
    );
  }
}
