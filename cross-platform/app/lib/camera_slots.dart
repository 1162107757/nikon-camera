import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import 'domain.dart';
import 'theme.dart';
import 'widgets.dart';
import 'legacy_glass_sheet.dart';

class CameraSlotsPage extends StatefulWidget {
  const CameraSlotsPage({
    super.key,
    required this.state,
    this.initialPreset,
    this.importOwner,
    this.embedded = false,
    this.file,
    this.name,
  });
  final AppState state;
  final Preset? initialPreset;
  final String? importOwner;
  final bool embedded;
  final String? file, name;
  @override
  State<CameraSlotsPage> createState() => _CameraSlotsPageState();
}

class _CameraSlotsPageState extends State<CameraSlotsPage> {
  Json data = {};
  String? error;
  bool busy = false, leaving = false, choosing = false;
  int selectedTarget = 201, middle = 4, clarity = 0;
  String? sourcePath, sourceName;
  int? sourceTarget;
  Json parameters = {}, resultRecord = {};
  bool resultVisible = false;
  String resultKind = 'write',
      resultName = '',
      resultTarget = '',
      resultError = '';
  String transport = '';
  bool invalid = false;
  BuildContext? modalContext;
  late final String owner =
      widget.importOwner ??
      (widget.state.session['user']?['id'] as String? ?? '');
  bool get current =>
      mounted &&
      !leaving &&
      !invalid &&
      widget.state.session['logoutPending'] != true &&
      (widget.state.session['user']?['id'] as String? ?? '') == owner;
  String session = '';
  HueviaCore get core => widget.state.core;
  List<Json> get slots => (data['items'] as List? ?? []).map(object).toList();
  Json get action => data['action'] is Map ? object(data['action']) : {};
  bool get importing =>
      widget.initialPreset != null ||
      sourcePath != null ||
      sourceTarget != null;
  Json? get selectedSlot {
    for (final slot in slots) {
      if (slot['target'] == selectedTarget) return slot;
    }
    return null;
  }

  String get presetName => widget.initialPreset?.name ?? sourceName ?? '';
  bool get pending =>
      action['pending'] == true ||
      action['parametersPending'] == true ||
      (resultVisible && resultError.isNotEmpty);

  @override
  void initState() {
    super.initState();
    sourcePath = widget.file;
    sourceName =
        widget.name ??
        (widget.file == null ? null : path.basename(widget.file!));
    widget.state.addListener(accountChanged);
    unawaited(open());
  }

  void accountChanged() {
    if ((widget.state.session['user']?['id'] as String? ?? '') == owner &&
        widget.state.session['logoutPending'] != true) {
      return;
    }
    if (invalid) return;
    invalid = true;
    final expected = session;
    if (expected.isNotEmpty) {
      unawaited(
        core
            .call('camera.slots.close', {'session': expected})
            .catchError((_) => <String, dynamic>{}),
      );
    }
    if (mounted) {
      setState(() {
        data = {};
        resultRecord = {};
        resultVisible = false;
        busy = false;
        choosing = false;
        error = '账号已改变，请关闭后重新打开相机预设槽位。';
      });
    }
  }

  Future<void> run(Future<void> Function() operation) async {
    if (busy || !current) return;
    if (widget.state.cameraDownloadsActive ||
        widget.state.cameraManualTransferActive) {
      setState(() => error = '请先停止相机接收队列，再操作相机预设槽位。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await operation();
    } catch (failure) {
      if (current) error = '$failure';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open() => run(() async {
    if (session.isEmpty) {
      final status = await core.call('camera.status');
      if (!current) return;
      if (status['connected'] != true) {
        throw const AppFailure('请先通过 Wi-Fi 或 USB 连接尼康相机。');
      }
      session = status['session'] as String;
      transport = status['transport'] as String? ?? '';
    }
    final opened = await core.call('camera.slots.open', {'session': session});
    final openedSession = opened['session'] as String;
    if (!current) {
      await core.call('camera.slots.close', {'session': openedSession});
      return;
    }
    data = opened;
    session = openedSession;
    if (!slots.any((slot) => slot['target'] == selectedTarget) &&
        slots.isNotEmpty) {
      selectedTarget = slots.first['target'] as int;
    }
  });

  Future<void> refresh({bool reconcile = false}) => run(() async {
    final value = await core.call(
      reconcile ? 'camera.slots.reconcile' : 'camera.slots.refresh',
      {'session': session},
    );
    if (!current) return;
    data = value;
    if (resultVisible) {
      resultRecord = action;
      resultError = '';
    }
  });

  Future<void> prepare(Json slot, String kind) async {
    if (busy || choosing || !current) return;
    setState(() => choosing = true);
    try {
      await prepareAction(slot, kind);
    } catch (failure) {
      if (current) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => choosing = false);
    }
  }

  Future<void> prepareAction(Json slot, String kind) async {
    Json payload = {'session': session, 'target': slot['target'], 'kind': kind};
    if (kind == 'write' && widget.initialPreset != null) {
      final file = await core.call('library.export', {
        'id': widget.initialPreset!.id,
        'owner': owner,
      });
      if (!current) return;
      payload['path'] = file['path'];
    } else if (kind == 'write') {
      if (sourcePath != null) {
        payload['path'] = sourcePath;
      } else if (sourceTarget != null) {
        payload['source'] = sourceTarget;
      } else {
        throw const AppFailure('请先选择导入来源。');
      }
    }
    if (kind == 'write') {
      payload.addAll({
        'middleQuarter': middle,
        'clarityQuarter': clarity,
        'parameters': Map<String, dynamic>.of(parameters),
      });
    }
    Json? plan;
    await run(() async {
      plan = await core.call('camera.slots.prepare', payload);
    });
    if (!mounted || !current || plan == null) return;
    final confirmation = plan!;
    var closing = false;
    final confirmed = await showDialog<bool>(
      context: modalContext ?? context,
      builder: (context) => PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) closing = true;
        },
        child: AlertDialog(
          title: Text(
            kind == 'delete'
                ? '删除 ${confirmation['targetLabel']}？'
                : '${confirmation['overwrite'] == true ? '覆盖' : '写入'} ${confirmation['targetLabel']}？',
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('相机：${data['model']}'),
                Text(
                  '当前：${confirmation['beforeName'] == '' ? '空槽位' : confirmation['beforeName']}',
                ),
                if (kind == 'write') Text('写入：${confirmation['name']}'),
                if (confirmation['explanation'] is String &&
                    confirmation['explanation'] != '')
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(confirmation['explanation'] as String),
                  ),
                if (confirmation['parameterSummary'] is String)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text('拍摄参数：${confirmation['parameterSummary']}'),
                  ),
                const SizedBox(height: 12),
                Text(
                  kind == 'delete'
                      ? '删除后无法由应用撤销。执行后会读取 C1–C9，核对目标为空且其他槽位未变化。'
                      : '原槽位内容将被覆盖。写入前再次核对槽位，写入后精确读回；结果不明时不会自动重复写入。',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (closing) return;
                closing = true;
                Navigator.pop(context, false);
              },
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                if (closing) return;
                closing = true;
                Navigator.pop(context, true);
              },
              child: Text(kind == 'delete' ? '确认删除此槽位' : '确认写入此槽位'),
            ),
          ],
        ),
      ),
    );
    if (!current || confirmed != true) return;
    resultRecord = {};
    resultKind = kind;
    resultName = confirmation['name'] as String? ?? presetName;
    resultTarget =
        confirmation['targetLabel'] as String? ?? 'C${selectedTarget - 200}';
    resultError = '';
    var attempted = false;
    await run(() async {
      attempted = true;
      final value = await core.call('camera.slots.execute', {
        'session': session,
        'confirmationId': confirmation['confirmationId'],
        'confirmed': true,
      });
      if (!current) return;
      data = value;
      resultRecord = action;
    });
    if (!attempted) return;
    if (current) {
      setState(() {
        resultVisible = true;
        resultError = error ?? '';
      });
    }
  }

  Future<void> chooseSource() async {
    if (busy || choosing || !current) return;
    setState(() => choosing = true);
    try {
      final sources = slots
          .where(
            (item) => item['empty'] != true && item['target'] != selectedTarget,
          )
          .toList();
      var closing = false;
      void complete(BuildContext sheet, int value) {
        if (closing) return;
        closing = true;
        Navigator.pop(sheet, value);
      }

      final source = await showLegacyGlassSheet<int>(
        modalContext ?? context,
        builder: (context) => PopScope(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) closing = true;
          },
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ListTile(title: Text('选择导入来源')),
                  ListTile(
                    leading: const Icon(Icons.file_open_outlined),
                    title: const Text('从文件选择 NCP'),
                    subtitle: const Text('沿用原版兼容适配；写入前展示完整适配说明'),
                    onTap: () => complete(context, 0),
                  ),
                  for (final item in sources)
                    ListTile(
                      leading: const Icon(Icons.copy_outlined),
                      title: Text('复制 ${item['label']} · ${item['name']}'),
                      onTap: () => complete(context, item['target'] as int),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      );
      if (!current || source == null) return;
      if (source == 0) {
        final selected = await core.pickFile(preset: true);
        if (!current || selected == null) return;
        setState(() {
          sourcePath = selected['path'] as String;
          sourceName =
              selected['name'] as String? ?? path.basename(sourcePath!);
          sourceTarget = null;
        });
      } else {
        final item = sources.firstWhere((slot) => slot['target'] == source);
        setState(() {
          sourceTarget = source;
          sourceName = item['name'] as String;
          sourcePath = null;
        });
      }
    } catch (failure) {
      if (current) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => choosing = false);
    }
  }

  Future<T?> guardedDialog<T>(
    Widget Function(BuildContext, void Function(T?)) builder,
  ) {
    var closing = false;
    return showDialog<T>(
      context: modalContext ?? context,
      builder: (dialog) => PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) closing = true;
        },
        child: builder(dialog, (value) {
          if (closing) return;
          closing = true;
          Navigator.pop(dialog, value);
        }),
      ),
    );
  }

  Future<Json?> tuningChoices() async {
    int middle = this.middle, clarity = this.clarity;
    return guardedDialog<Json>(
      (context, close) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('查看并调整兼容设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('以下为本次导入值，不修改原始预设。'),
                const SizedBox(height: 12),
                const Text('中等范围锐化'),
                DropdownButton<int>(
                  isExpanded: true,
                  value: middle,
                  items: [
                    for (var q = -20; q <= 20; q++)
                      DropdownMenuItem(value: q, child: Text(_quarter(q))),
                  ],
                  onChanged: (value) => update(() => middle = value!),
                ),
                const Text('清晰度'),
                DropdownButton<int>(
                  isExpanded: true,
                  value: clarity,
                  items: [
                    for (var q = -20; q <= 20; q++)
                      DropdownMenuItem(value: q, child: Text(_quarter(q))),
                  ],
                  onChanged: (value) => update(() => clarity = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => close(null), child: const Text('取消')),
            FilledButton(
              onPressed: () =>
                  close({'middleQuarter': middle, 'clarityQuarter': clarity}),
              child: const Text('保存设置'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> finish() async {
    if (busy || choosing || leaving) return;
    leaving = true;
    try {
      if (data['session'] != null) {
        await core.call('camera.slots.close', {'session': session});
      }
    } catch (failure) {
      error = '$failure';
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> acknowledge() async {
    final confirmed = await guardedDialog<bool>(
      (context, close) => AlertDialog(
        title: const Text('已在相机核对槽位结果？'),
        content: Text(
          '请在原相机检查 ${action['targetLabel']}，并核对其他槽位。此确认只解除待核对状态，不会再次写入或自动还原。',
        ),
        actions: [
          TextButton(onPressed: () => close(false), child: const Text('继续核对')),
          FilledButton(
            onPressed: () => close(true),
            child: const Text('已在相机核对'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    await run(() async {
      final value = await core.call('camera.slots.acknowledge', {
        'session': session,
        'confirmedOnCamera': true,
        'actionId': action['actionId'],
      });
      if (!current) return;
      data = value;
      if (resultVisible) {
        resultRecord = action;
        resultError = '';
      }
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    if (!leaving && !invalid && data['session'] != null) {
      unawaited(
        core
            .call('camera.slots.close', {'session': session})
            .catchError((_) => <String, dynamic>{}),
      );
    }
    super.dispose();
  }

  Future<void> editTuning() async {
    if (busy || choosing || !current) return;
    setState(() => choosing = true);
    try {
      final value = await tuningChoices();
      if (!current || value == null) return;
      setState(() {
        middle = value['middleQuarter'] as int;
        clarity = value['clarityQuarter'] as int;
      });
    } finally {
      if (mounted) setState(() => choosing = false);
    }
  }

  String get parameterSummary {
    if (parameters.isEmpty) return '不调整';
    return [
      if (parameters['whiteBalance'] != null)
        '白平衡 ${_whiteBalances[parameters['whiteBalance']] ?? parameters['whiteBalance']}',
      if (parameters['kelvin'] != null) '${parameters['kelvin']} K',
      if (parameters['exposureMilliEv'] != null)
        '曝光补偿 ${((parameters['exposureMilliEv'] as num) / 1000).toStringAsFixed(1)} EV',
    ].join(' / ');
  }

  static const _whiteBalances = <int, String>{
    -1: '不调整',
    2: '自动',
    4: '晴天',
    0x8010: '阴天',
    0x8011: '阴影',
    6: '白炽灯',
    5: '荧光灯',
    7: '闪光灯',
    0x8012: '指定色温',
  };
  static const _exposure = [
    -3000,
    -2667,
    -2333,
    -2000,
    -1667,
    -1333,
    -1000,
    -667,
    -333,
    0,
    333,
    667,
    1000,
    1333,
    1667,
    2000,
    2333,
    2667,
    3000,
  ];

  Future<void> editParameters() async {
    if (busy || choosing || !current) return;
    setState(() => choosing = true);
    var wb = parameters['whiteBalance'] as int? ?? -1;
    var kelvin = parameters['kelvin'] as int? ?? 5000;
    var ev = parameters['exposureMilliEv'] as int? ?? -99999;
    try {
      final value = await guardedDialog<Json>(
        (dialog, close) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('拍摄参数 · 可选'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '默认不调整；所选值影响后续拍摄。',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  const Text('白平衡'),
                  DropdownButton<int>(
                    key: const ValueKey('slot-white-balance'),
                    isExpanded: true,
                    value: wb,
                    items: [
                      for (final item in _whiteBalances.entries)
                        DropdownMenuItem(
                          value: item.key,
                          child: Text(item.value),
                        ),
                    ],
                    onChanged: (value) => update(() => wb = value!),
                  ),
                  if (wb == 0x8012) ...[
                    const Text('色温'),
                    DropdownButton<int>(
                      key: const ValueKey('slot-kelvin'),
                      isExpanded: true,
                      value: kelvin,
                      items: [
                        for (var k = 2500; k <= 10000; k += 100)
                          DropdownMenuItem(value: k, child: Text('$k K')),
                      ],
                      onChanged: (value) => update(() => kelvin = value!),
                    ),
                  ],
                  const Text('曝光补偿'),
                  DropdownButton<int>(
                    key: const ValueKey('slot-exposure'),
                    isExpanded: true,
                    value: ev,
                    items: [
                      const DropdownMenuItem(value: -99999, child: Text('不调整')),
                      for (final value in _exposure)
                        DropdownMenuItem(
                          value: value,
                          child: Text(
                            '${(value / 1000).toStringAsFixed(1)} EV',
                          ),
                        ),
                    ],
                    onChanged: (value) => update(() => ev = value!),
                  ),
                  const Text(
                    '不支持的项会跳过；原值保存在导入报告。',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => close(null), child: const Text('取消')),
              TextButton(
                onPressed: () => close(<String, dynamic>{}),
                child: const Text('全部不调整'),
              ),
              FilledButton(
                onPressed: () => close(<String, dynamic>{
                  if (wb != -1) 'whiteBalance': wb,
                  if (wb == 0x8012) 'kelvin': kelvin,
                  if (ev != -99999) 'exposureMilliEv': ev,
                }),
                child: const Text('保存选择'),
              ),
            ],
          ),
        ),
      );
      if (current && value != null) setState(() => parameters = value);
    } finally {
      if (mounted) setState(() => choosing = false);
    }
  }

  Widget presetCard(BuildContext context) {
    final p = HuePalette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.container,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 80,
              height: 88,
              child: widget.initialPreset == null
                  ? ColoredBox(
                      color: p.card,
                      child: HueIcon(
                        HueIconKind.presets,
                        color: p.secondary,
                        size: 32,
                      ),
                    )
                  : PresetImage(
                      preset: widget.initialPreset!,
                      core: core,
                      owner: owner,
                      showBadge: true,
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  presetName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  sourceName ??
                      widget.initialPreset?.data['originalFileName']
                          as String? ??
                      '$presetName.${widget.initialPreset?.format.toLowerCase() ?? 'ncp'}',
                  style: TextStyle(fontSize: 12, color: p.secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget information(
    BuildContext context,
    String title,
    String description, {
    bool checked = false,
  }) {
    final p = HuePalette.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.container,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          HueIcon(
            checked ? HueIconKind.check : HueIconKind.camera,
            size: 28,
            color: p.secondary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: p.secondary),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget grid(BuildContext context) {
    final p = HuePalette.of(context);
    final indexed = {for (final slot in slots) slot['target'] as int: slot};
    return Column(
      children: [
        for (var row = 0; row < 3; row++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var col = 0; col < 3; col++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 4,
                    ),
                    child: Builder(
                      builder: (context) {
                        final target = 201 + row * 3 + col,
                            slot = indexed[target];
                        final label = 'C${target - 200}';
                        final name = slot == null
                            ? '不可用'
                            : slot['empty'] == true
                            ? '空槽位'
                            : slot['name'] as String? ?? '';
                        final active = target == selectedTarget;
                        return Semantics(
                          button: true,
                          selected: active,
                          enabled:
                              slot != null &&
                              current &&
                              !busy &&
                              !choosing &&
                              !pending &&
                              data['consumed'] != true,
                          label: '$label · $name',
                          excludeSemantics: true,
                          child: Material(
                            color: active ? p.primaryContainer : p.card,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: active
                                  ? BorderSide(color: p.primary, width: 2)
                                  : BorderSide.none,
                            ),
                            child: InkWell(
                              key: ValueKey('camera-slot-$target'),
                              borderRadius: BorderRadius.circular(16),
                              onTap:
                                  slot == null ||
                                      busy ||
                                      choosing ||
                                      !current ||
                                      pending ||
                                      data['consumed'] == true
                                  ? null
                                  : () =>
                                        setState(() => selectedTarget = target),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 64,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 8,
                                  ),
                                  child: Center(
                                    child: Text(
                                      '$label\n$name',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: active
                                            ? p.onPrimaryContainer
                                            : p.ink,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget primaryAction(
    BuildContext context, {
    Key? key,
    required String label,
    VoidCallback? onPressed,
  }) {
    final p = HuePalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        color: onPressed == null ? p.container : null,
        gradient: onPressed == null
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [p.action, Color(p.dark ? 0xffdad0c5 : 0xff27241f)],
              ),
      ),
      child: FilledButton(
        key: key,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: p.onAction,
          disabledForegroundColor: p.secondary,
          shadowColor: Colors.transparent,
          minimumSize: const Size(double.infinity, 48),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        child: Text(label),
      ),
    );
  }

  Widget footer(
    BuildContext context, {
    required Widget action,
    required String note,
  }) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          action,
          const SizedBox(height: 6),
          Text(
            note,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: HuePalette.of(context).secondary,
            ),
          ),
        ],
      ),
    ),
  );

  Widget resultPage(BuildContext context) {
    final p = HuePalette.of(context);
    final phase = resultRecord['phase'];
    final verified =
        resultError.isEmpty &&
        (resultRecord['presetVerified'] == true ||
            (resultRecord['pending'] != true &&
                resultRecord['presetVerified'] != false &&
                (phase == 'verified' || phase == 'verifiedByReadback')));
    final unknown =
        resultError.isNotEmpty ||
        (!verified && resultRecord['pending'] == true);
    final title = verified
        ? '${resultKind == 'delete' ? '已删除' : '已保存到'} $resultTarget'
        : unknown
        ? '结果待核对'
        : phase == 'unchangedByReadback'
        ? '槽位未改变'
        : phase == 'rejected'
        ? '${resultKind == 'delete' ? '删除' : '导入'}失败'
        : '操作未完成';
    final parameterResult = resultRecord['parameterResult'] is Map
        ? object(resultRecord['parameterResult'])
        : <String, dynamic>{};
    final parametersManuallyChecked =
        resultRecord['parametersManuallyChecked'] == true;
    final parametersPending =
        resultRecord['parametersPending'] == true ||
        (parameterResult['uncertain'] == true && !parametersManuallyChecked);
    return Column(
      children: [
        if (busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 36, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: verified ? p.primary : p.container,
                      shape: BoxShape.circle,
                    ),
                    child: HueIcon(
                      verified ? HueIconKind.check : HueIconKind.camera,
                      color: verified ? p.onPrimary : p.primary,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (resultName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      resultName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                if (verified &&
                    resultKind != 'delete' &&
                    widget.initialPreset != null)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 24, bottom: 20),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(
                          width: 200,
                          height: 160,
                          child: PresetImage(
                            preset: widget.initialPreset!,
                            core: core,
                            owner: owner,
                            showBadge: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (verified) ...[
                  information(
                    context,
                    '已读回核对',
                    resultKind == 'delete' ? '目标槽位已清空，其他槽位符合预期。' : '预设已成功保存到相机',
                    checked: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 24, bottom: 8),
                    child: Text(
                      resultKind == 'delete'
                          ? '删除后无法由应用撤销。'
                          : '请在相机中选择 $resultTarget，并试拍确认效果。',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: p.secondary),
                    ),
                  ),
                  if (resultKind != 'delete')
                    Text(
                      '兼容适配，实际效果仍需拍摄确认。',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: p.secondary),
                    ),
                ] else ...[
                  Text(
                    resultError.isNotEmpty
                        ? resultError
                        : resultRecord['message'] as String? ??
                              '尚未取得预设写入及全部槽位读回一致的结果，不会自动重复写入。',
                    style: TextStyle(fontSize: 15, color: p.ink),
                  ),
                  if (unknown)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('相机可能已执行操作。请只读核对，勿重复导入。'),
                    ),
                ],
                if (parameterResult.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      '${parametersManuallyChecked
                          ? '拍摄参数 · 已在相机手动核对\n原始检查记录：'
                          : parametersPending
                          ? '拍摄参数待核对'
                          : '拍摄参数'}\n${parameterResult['detail'] ?? ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: parameterResult['uncertain'] == true
                            ? Theme.of(context).colorScheme.error
                            : p.secondary,
                      ),
                    ),
                  ),
                if (verified &&
                    parameters.isNotEmpty &&
                    parameterResult.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text(
                      '拍摄参数未执行；本次仅核对了预设。',
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (data['connected'] == true)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      '相机保持连接，可继续导入',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12),
                    ),
                  )
                else if (verified)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('继续操作前，请重新连接相机。', textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
        ),
        footer(
          context,
          action: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (unknown || parametersPending) ...[
                FilledButton(
                  onPressed: busy || !current
                      ? null
                      : () => refresh(reconcile: true),
                  child: const Text('只读核对相机'),
                ),
                TextButton(
                  onPressed: busy || !current ? null : acknowledge,
                  child: const Text('我已在相机手动核对'),
                ),
              ],
              FilledButton(
                onPressed: busy || choosing ? null : finish,
                child: const Text('完成'),
              ),
            ],
          ),
          note: verified ? '不会自动切换相机当前预设' : '未确认结果前不会再次写入',
        ),
      ],
    );
  }

  Widget buildPage(BuildContext context) {
    modalContext = context;
    final p = HuePalette.of(context), slot = selectedSlot;
    final enabled =
        current && !busy && !choosing && !pending && data['consumed'] != true;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(finish());
      },
      child: Scaffold(
        backgroundColor: widget.embedded ? Colors.transparent : p.surface,
        appBar: HueHeader(
          title: resultVisible
              ? (resultKind == 'delete' ? '删除结果' : '导入结果')
              : importing
              ? '确认导入'
              : '相机预设槽位',
          compact: MediaQuery.sizeOf(context).height < 480,
          navigation: HueIconButton(
            kind: HueIconKind.back,
            label: '返回',
            disc: false,
            onPressed: busy || choosing ? null : finish,
          ),
        ),
        body: invalid
            ? Center(child: Text(error ?? '账号已改变'))
            : resultVisible
            ? resultPage(context)
            : Column(
                children: [
                  if (busy) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      children: [
                        if (importing) ...[
                          const SizedBox(height: 10),
                          presetCard(context),
                          const SizedBox(height: 16),
                        ],
                        information(
                          context,
                          data['model'] as String? ?? '正在读取相机',
                          '${transport == 'usb'
                              ? 'USB'
                              : transport == 'wifi'
                              ? 'Wi-Fi'
                              : '相机连接'} · 导入前复查槽位',
                        ),
                        const SizedBox(height: 24),
                        Text(
                          importing ? '选择存储位置' : '机内预设槽位',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        grid(context),
                        if (slot != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              !importing
                                  ? '选择非空槽位后可删除；导入或删除前都会再次确认。'
                                  : slot['empty'] == true
                                  ? '此槽位为空，可直接导入。也可选择已用槽位进行覆盖。'
                                  : '将替换「${slot['name']}」。原槽位内容会被覆盖。',
                              style: TextStyle(
                                fontSize: 12,
                                color: !importing || slot['empty'] == true
                                    ? p.secondary
                                    : Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (importing) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                            decoration: BoxDecoration(
                              color: p.container,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    const Expanded(
                                      child: Text(
                                        '兼容适配',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: enabled ? editTuning : null,
                                      child: const Text('调整 ›'),
                                    ),
                                  ],
                                ),
                                Text(
                                  '中等范围锐化 ${_quarter(middle)} / 清晰度 ${_quarter(clarity)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: p.secondary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  sourceTarget == null
                                      ? '保留曲线、锐化、饱和度与色相；机身效果仍需试拍确认。'
                                      : '按当前相机槽位数据复制，不会自动应用此预设。',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '拍摄参数',
                                      style: TextStyle(fontSize: 15),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      parameterSummary,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: p.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: enabled ? editParameters : null,
                                child: const Text('选择 ›'),
                              ),
                            ],
                          ),
                          Text(
                            '可选调节机身参数，不能替代丢失的调色效果。',
                            style: TextStyle(fontSize: 12, color: p.secondary),
                          ),
                        ],
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                          ),
                        if (action['pending'] == true) ...[
                          const Text(
                            '上次操作结果待核对',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            action['message'] as String? ??
                                '相机可能已执行操作，不会自动重复写入。',
                          ),
                          TextButton(
                            onPressed: busy || !current
                                ? null
                                : () => refresh(reconcile: true),
                            child: const Text('只读核对上次操作'),
                          ),
                          TextButton(
                            onPressed: busy || !current ? null : acknowledge,
                            child: const Text('我已在相机手动核对'),
                          ),
                        ],
                        if (data['consumed'] == true)
                          const Text('本次连接已尝试一次操作。继续操作前，请明确重新连接并读取槽位。'),
                        TextButton(
                          onPressed: busy || choosing || !current
                              ? null
                              : data.isEmpty || data['consumed'] == true
                              ? open
                              : refresh,
                          child: Text(
                            data.isEmpty || data['consumed'] == true
                                ? '重新连接并读取槽位'
                                : '只读刷新槽位',
                          ),
                        ),
                      ],
                    ),
                  ),
                  footer(
                    context,
                    action: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        primaryAction(
                          context,

                          key: const ValueKey('camera-slot-import'),
                          onPressed:
                              !enabled ||
                                  data['canWrite'] != true ||
                                  slot == null
                              ? null
                              : importing
                              ? () => prepare(slot, 'write')
                              : chooseSource,
                          label: importing
                              ? '${slot?['empty'] == true ? '导入到' : '覆盖'} C${selectedTarget - 200}${slot?['empty'] == true ? '' : '…'}'
                              : '导入预设',
                        ),
                        if (!importing && slot != null && slot['empty'] != true)
                          TextButton(
                            key: const ValueKey('camera-slot-delete'),
                            onPressed: enabled && data['canDelete'] == true
                                ? () => prepare(slot, 'delete')
                                : null,
                            child: Text('删除 C${selectedTarget - 200}'),
                          ),
                      ],
                    ),
                    note: importing
                        ? '导入时保持连接，请勿在相机上更改槽位'
                        : '选择非空槽位后可删除；每次操作都需确认',
                  ),
                ],
              ),
      ),
    );
  }

  static String _quarter(int value) =>
      (value / 4).toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  @override
  Widget build(BuildContext context) => Theme(
    data: hueviaTheme(Theme.of(context).brightness, home: false),
    child: Builder(builder: buildPage),
  );
}
