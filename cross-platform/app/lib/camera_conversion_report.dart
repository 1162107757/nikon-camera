import 'package:flutter/material.dart';

import 'domain.dart';
import 'theme.dart';

/// A wrapping table fits the import confirmation even on narrow phones.
/// The report is informative; only the normal explicit write confirms import.
class CameraConversionReport extends StatelessWidget {
  const CameraConversionReport({super.key, required this.report});

  final Json report;

  List<String> entries(String key) => (report[key] as List? ?? const [])
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final palette = HuePalette.of(context);
    final omitted = entries('omitted'), approximated = entries('approximated');
    final retained = entries('retained');
    final rows = [
      for (final value in omitted) (value, '跳过'),
      for (final value in approximated) (value, '近似转换'),
    ];
    Widget cell(String text, {bool heading = false}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: palette.ink,
          fontWeight: heading ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
    return Column(
      key: const Key('np3-conversion-report'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('NP3 兼容情况', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('下列不支持的参数会跳过，仍可继续导入兼容部分。原文件保留。'),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 12),
          Table(
            key: const Key('np3-compatibility-table'),
            columnWidths: const {0: FlexColumnWidth(3), 1: FlexColumnWidth(1)},
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            border: TableBorder.all(color: Theme.of(context).dividerColor),
            children: [
              TableRow(
                decoration: BoxDecoration(color: palette.container),
                children: [
                  cell('参数与说明', heading: true),
                  cell('处理', heading: true),
                ],
              ),
              for (final row in rows)
                TableRow(children: [cell(row.$1), cell(row.$2)]),
            ],
          ),
        ],
        if (retained.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('可导入：${retained.join('、')}。'),
        ],
        const SizedBox(height: 8),
        const Text('转换后的机身效果请试拍确认。'),
      ],
    );
  }
}
