import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'domain.dart';
import 'theme.dart';

class LegacyMigrationPage extends StatefulWidget {
  const LegacyMigrationPage({super.key, required this.state});
  final AppState state;
  @override
  State<LegacyMigrationPage> createState() => _LegacyMigrationPageState();
}

class _LegacyMigrationPageState extends State<LegacyMigrationPage> {
  static const picker = MethodChannel('cc.huevia/legacy-files');
  late final String owner =
      widget.state.session['user']?['id'] as String? ?? '';
  Json preview = {};
  List<Json> checkedPhotos = [], records = [];
  String message = '', error = '', job = '';
  bool busy = false, includeAccount = false;
  int generation = 0;
  double? progress;
  StreamSubscription<dynamic>? events;

  @override
  void initState() {
    super.initState();
    events = widget.state.core.operationProgress.listen((event) {
      if (mounted &&
          event is Map &&
          event['jobId'] == job &&
          event['progress'] is num) {
        setState(() => progress = (event['progress'] as num).toDouble());
      }
    }, onError: (_) {});
    unawaited(loadRecords());
  }

  @override
  void dispose() {
    generation++;
    unawaited(events?.cancel());
    if (job.isNotEmpty) unawaited(widget.state.core.cancel(job));
    if (preview['transaction'] is String) {
      unawaited(
        widget.state.core
            .call('legacy.discard', {
              'owner': owner,
              'transaction': preview['transaction'],
            })
            .catchError((Object _) => <String, dynamic>{}),
      );
    }
    super.dispose();
  }

  Future<void> loadRecords() async {
    try {
      final result = await widget.state.core.call('legacy.status', {
        'owner': owner,
      });
      if (mounted) {
        setState(
          () => records = (result['items'] as List).map(object).toList(),
        );
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    }
  }

  Future<void> discardPreview() async {
    if (preview['transaction'] is! String) return;
    await widget.state.core.call('legacy.discard', {
      'owner': owner,
      'transaction': preview['transaction'],
    });
    preview = {};
    checkedPhotos = [];
  }

  Future<void> inspect({bool iosPresets = false}) async {
    if (busy) return;
    final attempt = ++generation;
    setState(() {
      busy = true;
      error = '';
      message = '请选择旧版资料';
      progress = null;
    });
    try {
      final selected = await picker.invokeMapMethod<String, dynamic>('pick', {
        'iosPresets': iosPresets,
      });
      if (!mounted ||
          attempt != generation ||
          selected == null ||
          selected['cancelled'] == true) {
        return;
      }
      await discardPreview();
      job = 'legacy-${DateTime.now().microsecondsSinceEpoch}';
      setState(() => message = '正在核对导出清单、文件字节和草稿…');
      final result = await widget.state.core.call('legacy.inspect', {
        'owner': owner,
        'path': selected['path'],
        'iosPresets': selected['iosPresets'] == true,
      }, job);
      if (!mounted || attempt != generation) return;
      preview = result;
      final photos = (result['photos'] as List).map(object).toList();
      final checked = <Json>[];
      for (var i = 0; i < photos.length; i++) {
        if (!mounted || attempt != generation) return;
        setState(() {
          message = '正在解码核对照片 ${i + 1}/${photos.length}';
          progress = i / photos.length;
        });
        final photo = photos[i];
        final info = await widget.state.core.call('media.info', {
          'path': photo['path'],
        }, job);
        checked.add({
          'sha256': photo['sha256'],
          'info': {...info, 'addedAt': DateTime.now().millisecondsSinceEpoch},
        });
      }
      if (mounted && attempt == generation) {
        setState(() {
          checkedPhotos = checked;
          includeAccount = result['accountMatch'] == true;
          message = '资料预检完成，请核对范围后迁入。';
        });
      }
    } catch (failure) {
      if (mounted && attempt == generation) {
        setState(
          () => error = failure is PlatformException
              ? failure.message ?? '系统文件读取未完成。'
              : '$failure',
        );
      }
      try {
        await discardPreview();
      } catch (_) {}
    } finally {
      job = '';
      if (mounted && attempt == generation) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  Future<void> commit() async {
    if (busy || preview.isEmpty) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('迁入核对后的资料？'),
        content: const Text(
          '已有同名或同身份资料会保留。迁入后可在本页撤回；如果之后又新增或编辑了资料，自动撤回会停止以保护这些更改。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('迁入资料'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      busy = true;
      error = '';
      message = '正在迁入资料并保留回滚副本…';
      progress = 0;
    });
    job = 'legacy-commit-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final receipt = await widget.state.core.call('legacy.commit', {
        'owner': owner,
        'transaction': preview['transaction'],
        'includeAccountData': includeAccount,
        'photos': checkedPhotos,
      }, job);
      preview = {};
      checkedPhotos = [];
      await widget.state.initialize();
      await loadRecords();
      if (mounted) {
        setState(
          () => message = '迁入完成，已保留 ${receipt['preserved']} 项既有文件。请核对预设、照片和项目。',
        );
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
      await loadRecords();
    } finally {
      job = '';
      if (mounted) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  Future<void> rollback(Json record) async {
    if (busy) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('撤回这次迁入？'),
        content: const Text('仅在迁入后的资料尚未改变时自动撤回。原始导出包会保留，旧版安装的数据不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('核对并撤回'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      busy = true;
      error = '';
      message = '正在核对并撤回迁入…';
    });
    try {
      await widget.state.core.call('legacy.rollback', {
        'owner': owner,
        'transaction': record['transaction'],
      });
      await widget.state.initialize();
      await loadRecords();
      if (mounted) setState(() => message = '已撤回这次迁入。');
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
      message = '正在导出本机可见预设、原片、草稿和项目…';
    });
    job = 'legacy-export-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final result = await widget.state.core.call('legacy.export', {
        'owner': owner,
      }, job);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(result['path'] as String)],
          subject: 'Huevia 资料导出包',
          sharePositionOrigin: Rect.fromLTWH(
            24,
            MediaQuery.sizeOf(context).height / 2,
            1,
            1,
          ),
        ),
      );
      if (mounted) setState(() => message = '导出包已生成；请在分享菜单中存到文件或其他设备。');
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      job = '';
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = preview['account'] is Map
        ? object(preview['account'])
        : <String, dynamic>{};
    final projects = preview['projects'] as List? ?? const [];
    final photos = preview['photos'] as List? ?? const [];
    return Scaffold(
      appBar: const HueHeader(title: '旧版资料迁入', back: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('把旧版资料带过来', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Text(
              'Android：先在原安装的专用迁出版本中导出 ZIP，再到这里选择文件。请保留原安装和导出包。\niOS：原版 Presets 文件夹已开放文件共享，可通过“文件”或电脑导出后选择；旧版显示名保存在其设置中，无法随文件读取时使用文件名。',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ? null : inspect,
              child: const Text('选择资料导出包'),
            ),
            if (Platform.isIOS)
              TextButton(
                onPressed: busy ? null : () => inspect(iosPresets: true),
                child: const Text('选择旧版 iOS Presets 文件夹'),
              ),
            TextButton(
              onPressed: busy ? null : export,
              child: const Text('导出本机资料'),
            ),
            if (busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(value: progress),
              ),
            if (message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(message),
              ),
            if (error.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (preview.isNotEmpty && !busy) ...[
              const Divider(height: 32),
              Text('待迁入清单', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Text(
                '预设 ${preview['presets']} 项 · 照片 ${photos.length} 张\n草稿 ${preview['drafts']} 份 · 项目 ${projects.length} 个',
              ),
              if (account.isNotEmpty)
                Text(
                  '原账号：${account['nickname'] ?? account['username'] ?? account['provider'] ?? '已记录'}',
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: includeAccount,
                onChanged: preview['accountMatch'] == true
                    ? (value) => setState(() => includeAccount = value == true)
                    : null,
                title: const Text('关联同一账号的预设、草稿和项目默认'),
                subtitle: Text(
                  preview['accountMatch'] == true
                      ? '仅迁入资料；密码和旧会话不迁入'
                      : '请重新登录导出包中的同一账号后再迁入专属资料',
                ),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('核对照片与项目名称'),
                children: [
                  for (final row in photos.take(100))
                    ListTile(
                      dense: true,
                      title: Text(object(row)['name'] as String),
                    ),
                  for (final row in projects.take(100))
                    ListTile(
                      dense: true,
                      title: Text('项目：${object(row)['name']}'),
                    ),
                  if (photos.length > 100 || projects.length > 100)
                    const ListTile(title: Text('此处展示前 100 项；完整清单保留在原导出包中。')),
                ],
              ),
              FilledButton(onPressed: commit, child: const Text('迁入已核对资料')),
            ],
            if (records.isNotEmpty) ...[
              const Divider(height: 32),
              Text('迁入记录', style: Theme.of(context).textTheme.titleMedium),
              for (final record in records.reversed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    record['status'] == 'complete'
                        ? '迁入完成'
                        : record['status'] == 'rolledBack'
                        ? '已撤回'
                        : '迁入中断，可核对撤回',
                  ),
                  subtitle: Text('${record['transaction']}'),
                  isThreeLine: false,
                  trailing: record['status'] == 'rolledBack'
                      ? null
                      : TextButton(
                          onPressed: busy ? null : () => rollback(record),
                          child: const Text('撤回'),
                        ),
                ),
            ],
            const SizedBox(height: 24),
            const Text(
              '原片按 SHA-256 核对并去重，已有草稿和预设资料优先保留。账号密码、QQ 授权凭据和旧会话不会进入导出包；iOS 无法直接读取另一个安装的沙盒或 Keychain。项目的旧下载队列与系统相册发布凭据需重新建立。',
            ),
          ],
        ),
      ),
    );
  }
}
