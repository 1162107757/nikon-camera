import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'domain.dart';
import 'theme.dart';
import 'widgets.dart';

class PersonalPresetSyncButton extends StatefulWidget {
  const PersonalPresetSyncButton({super.key, required this.state});

  final AppState state;

  @override
  State<PersonalPresetSyncButton> createState() =>
      _PersonalPresetSyncButtonState();
}

class _PersonalPresetSyncButtonState extends State<PersonalPresetSyncButton> {
  late Future<int>? conflicts = readConflicts();

  String get owner => widget.state.session['user']?['id'] as String? ?? '';
  bool get leaving => widget.state.session['logoutPending'] == true;

  Future<int>? readConflicts() {
    if (owner.isEmpty || leaving) return null;
    return widget.state.core
        .call('personal.status', {'owner': owner})
        .then((status) => status['conflicts'] as int? ?? 0);
  }

  Future<void> open() async {
    if (owner.isEmpty) {
      context.push('/account');
      return;
    }
    await hueRootPage<void>(
      context,
      MaterialPageRoute(builder: (_) => PersonalSyncPage(state: widget.state)),
    );
    if (!mounted) return;
    final updated = readConflicts();
    setState(() {
      conflicts = updated;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = HuePalette.of(context);
    final colors = Theme.of(context).colorScheme;
    final label = owner.isEmpty ? '登录同步' : '预设同步';
    return FutureBuilder<int>(
      future: conflicts,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Tooltip(
          message: owner.isEmpty ? '登录后可同步云端预设' : '打开个人预设同步',
          child: TextButton(
            onPressed: leaving ? null : open,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: EdgeInsets.zero,
              foregroundColor: palette.ink,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Container(
              key: const ValueKey('preset-sync-capsule'),
              constraints: const BoxConstraints(minHeight: 27),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: ShapeDecoration(
                color: palette.card,
                shape: StadiumBorder(side: BorderSide(color: palette.outline)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_sync_outlined, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    DecoratedBox(
                      decoration: ShapeDecoration(
                        color: colors.errorContainer,
                        shape: const StadiumBorder(),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          semanticsLabel: '$count 项同步差异待处理',
                          style: TextStyle(
                            color: colors.onErrorContainer,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class PersonalSyncPage extends StatefulWidget {
  const PersonalSyncPage({super.key, required this.state});
  final AppState state;
  @override
  State<PersonalSyncPage> createState() => _PersonalSyncPageState();
}

class _PersonalSyncPageState extends State<PersonalSyncPage> {
  late final String owner =
      widget.state.session['user']?['id'] as String? ?? '';
  Json status = {};
  String? error, job;
  String message = '';
  bool busy = false;
  double progress = 0;
  StreamSubscription<dynamic>? events;
  @override
  void initState() {
    super.initState();
    events = HueviaCore.progress.listen((event) {
      final value = object(event);
      if (mounted && value['jobId'] == job) {
        setState(() => progress = (value['progress'] as num).toDouble());
      }
    }, onError: (_) {});
    unawaited(run('personal.status'));
  }

  @override
  void dispose() {
    unawaited(events?.cancel());
    if (job != null) unawaited(widget.state.core.cancel(job!));
    super.dispose();
  }

  Future<void> run(
    String operation, {
    Json extras = const {},
    bool synchronize = false,
  }) async {
    if (busy) return;
    final identity = 'personal-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      busy = true;
      error = null;
      job = identity;
      progress = 0;
      message = '';
    });
    try {
      var value = await widget.state.core.call(operation, {
        ...extras,
        'owner': owner,
      }, identity);
      if (synchronize) {
        value = await widget.state.core.call('personal.sync', {
          'owner': owner,
        }, identity);
      }
      await widget.state.refreshLibrary();
      if (mounted) {
        setState(() {
          status = value;
          if (operation == 'personal.sync' || synchronize) message = '同步已完成。';
        });
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

  Future<void> synchronize() async {
    if (status['consentNeeded'] != true) {
      await run('personal.sync');
      return;
    }
    final include = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('选择同步范围'),
        content: Text(
          '本机有 ${status['unclaimed'] ?? 0} 个尚未归属账号的预设。是否将它们加入当前账号？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('仅同步账号预设'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('加入并同步'),
          ),
        ],
      ),
    );
    if (include != null && mounted) {
      await run(
        'personal.consent',
        extras: {'includeExisting': include},
        synchronize: true,
      );
    }
  }

  Future<void> resolve() async {
    final local = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('处理同步差异'),
        content: Text(
          '有 ${status['conflicts']} 个预设在本机和云端均有修改。选择要保留的版本，然后重新同步。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('稍后处理'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('保留云端版本'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('保留本机版本'),
          ),
        ],
      ),
    );
    if (local != null && mounted) {
      await run(
        'personal.resolve',
        extras: {'keepLocal': local},
        synchronize: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('个人预设同步')),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.cloud_sync_outlined, size: 48),
          const SizedBox(height: 20),
          Text('在你的设备之间继续', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text('同步当前账号的预设文件、名称、分类和备注。退出登录后，账号预设会从本机列表隐藏。'),
          const SizedBox(height: 24),
          if (busy) ...[
            LinearProgressIndicator(value: progress > 0 ? progress : null),
            const SizedBox(height: 16),
          ],
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(message),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton.icon(
            onPressed: busy ? null : synchronize,
            icon: const Icon(Icons.sync_rounded),
            label: Text(busy ? '正在处理' : '立即同步'),
          ),
          if ((status['conflicts'] as int? ?? 0) > 0) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: busy ? null : resolve,
              child: Text('处理 ${status['conflicts']} 项差异'),
            ),
          ],
          if (busy)
            TextButton(
              onPressed: () {
                final current = job;
                if (current != null) {
                  unawaited(widget.state.core.cancel(current));
                }
              },
              child: const Text('取消后续同步'),
            ),
          const SizedBox(height: 24),
          const Text('在预设库移除已归属账号的预设后，下次同步也会将其从当前账号的云端移除。'),
        ],
      ),
    ),
  );
}
