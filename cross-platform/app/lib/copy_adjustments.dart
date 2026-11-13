import 'dart:async';

import 'package:flutter/material.dart';

import 'domain.dart';

void showCopyReceipt(
  BuildContext context,
  HueviaCore core,
  String owner,
  Json receipt, {
  bool Function()? isCurrent,
}) {
  final messenger = ScaffoldMessenger.of(context);
  final changed = receipt['changed'] as int,
      skipped = receipt['skipped'] as int;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        '已复制到 $changed 张照片${skipped == 0 ? '' : '，$skipped 张已有相同设置'}',
      ),
      duration: const Duration(seconds: 8),
      action: changed == 0
          ? null
          : SnackBarAction(
              label: '撤销',
              onPressed: () async {
                if (isCurrent?.call() == false) return;
                try {
                  final result = await core.call('photo.copyUndo', {
                    'owner': owner,
                    'receipt': receipt['receipt'],
                  });
                  if (messenger.mounted && isCurrent?.call() != false) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          '已撤销 ${result['restored']} 张${result['keptNewer'] == 0 ? '' : '，其余照片保留了后续修改'}',
                        ),
                      ),
                    );
                  }
                } catch (failure) {
                  if (messenger.mounted) {
                    messenger.showSnackBar(SnackBar(content: Text('$failure')));
                  }
                }
              },
            ),
    ),
  );
}

class CopyAdjustmentsPage extends StatefulWidget {
  const CopyAdjustmentsPage({
    super.key,
    required this.state,
    required this.source,
    required this.recipe,
    required this.owner,
    this.isCurrent,
  });
  final AppState state;
  final Photo source;
  final Json recipe;
  final String owner;
  final bool Function()? isCurrent;
  @override
  State<CopyAdjustmentsPage> createState() => _CopyAdjustmentsPageState();
}

class _CopyAdjustmentsPageState extends State<CopyAdjustmentsPage> {
  late final List<Photo> targets = widget.state.photos
      .where(
        (photo) =>
            photo.path != widget.source.path && photo.info['raw'] != true,
      )
      .toList();
  final Set<String> selected = {};
  bool basic = true, curves = true, colour = true, busy = false;
  String? error, job;
  double progress = 0;
  StreamSubscription<dynamic>? events;
  bool get current =>
      mounted &&
      widget.isCurrent?.call() != false &&
      widget.state.session['logoutPending'] != true &&
      (widget.state.session['user']?['id'] as String? ?? '') == widget.owner;

  void ownerChanged() {
    if (current || !mounted) return;
    if (job != null) unawaited(widget.state.core.cancel(job!));
    setState(() {
      selected.clear();
      targets.clear();
      busy = false;
      error = '照片或账号已变化，请返回重新打开。';
    });
  }

  @override
  void initState() {
    super.initState();
    widget.state.addListener(ownerChanged);
    events = HueviaCore.progress.listen((event) {
      final value = object(event);
      if (mounted && value['jobId'] == job) {
        setState(() => progress = (value['progress'] as num).toDouble());
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    widget.state.removeListener(ownerChanged);
    unawaited(events?.cancel());
    if (job != null) unawaited(widget.state.core.cancel(job!));
    super.dispose();
  }

  Future<void> apply() async {
    if (!current || busy || selected.isEmpty || !basic && !curves && !colour) {
      return;
    }
    final identity = 'copy-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      busy = true;
      error = null;
      job = identity;
      progress = 0;
    });
    try {
      final result = await widget.state.core.call('photo.copy', {
        'owner': widget.owner,
        'path': widget.source.path,
        'recipe': widget.recipe,
        'paths': List<String>.from(selected),
        'basic': basic,
        'curves': curves,
        'colour': colour,
      }, identity);
      if (mounted && current) {
        setState(() {
          busy = false;
          job = null;
        });
        Navigator.pop(context, result);
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          job = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('复制调节')),
      body: !current
          ? const Center(child: Text('照片或账号已变化，请返回重新打开。'))
          : SafeArea(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('来源：${widget.source.name}'),
                          const SizedBox(height: 8),
                          const Text('目标照片保留各自的滤镜、强度、构图、边框与局部编辑。'),
                          const SizedBox(height: 16),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('基础调节与去灰'),
                            value: basic,
                            onChanged: busy
                                ? null
                                : (value) => setState(() => basic = value!),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('四通道曲线'),
                            value: curves,
                            onChanged: busy
                                ? null
                                : (value) => setState(() => curves = value!),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('HSL 与调色盘'),
                            value: colour,
                            onChanged: busy
                                ? null
                                : (value) => setState(() => colour = value!),
                          ),
                          const Divider(height: 32),
                          Text('选择目标照片 · ${selected.length}/100'),
                          const SizedBox(height: 8),
                          if (targets.isNotEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: busy
                                    ? null
                                    : () => setState(() {
                                        if (selected.length ==
                                            targets.take(100).length) {
                                          selected.clear();
                                        } else {
                                          selected
                                            ..clear()
                                            ..addAll(
                                              targets
                                                  .take(100)
                                                  .map((photo) => photo.path),
                                            );
                                        }
                                      }),
                                child: Text(
                                  selected.length == targets.take(100).length
                                      ? '取消选择'
                                      : '选择前 ${targets.length.clamp(1, 100)} 张',
                                ),
                              ),
                            ),
                          if (targets.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Text('还没有其他可编辑照片。可先导入照片，或将 RAW 显影至编辑器。'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList.builder(
                      itemCount: targets.length,
                      itemBuilder: (context, index) {
                        final photo = targets[index];
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(photo.name),
                          subtitle: Text(
                            '${photo.info['width']} × ${photo.info['height']}',
                          ),
                          value: selected.contains(photo.path),
                          onChanged:
                              busy ||
                                  !selected.contains(photo.path) &&
                                      selected.length >= 100
                              ? null
                              : (value) => setState(() {
                                  value == true
                                      ? selected.add(photo.path)
                                      : selected.remove(photo.path);
                                }),
                        );
                      },
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    sliver: SliverToBoxAdapter(
                      child: error == null
                          ? const SizedBox()
                          : Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: busy
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: progress == 0 ? null : progress,
                    ),
                    TextButton(
                      onPressed: job == null
                          ? null
                          : () => widget.state.core.cancel(job!),
                      child: const Text('取消复制'),
                    ),
                  ],
                )
              : FilledButton(
                  onPressed: selected.isEmpty || !basic && !curves && !colour
                      ? null
                      : apply,
                  child: Text('应用到 ${selected.length} 张照片'),
                ),
        ),
      ),
    ),
  );
}
