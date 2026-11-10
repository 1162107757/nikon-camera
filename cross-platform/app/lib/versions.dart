import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'widgets.dart';

class VersionsPage extends StatefulWidget {
  const VersionsPage({
    super.key,
    required this.core,
    required this.owner,
    this.path,
  });
  final HueviaCore core;
  final String owner;
  final String? path;
  @override
  State<VersionsPage> createState() => _VersionsPageState();
}

class _VersionsPageState extends State<VersionsPage> {
  List<Json> versions = [];
  bool loading = true, busy = false;
  String? error, job;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    if (job != null) unawaited(widget.core.cancel(job!));
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.core.call('version.list', {
        'owner': widget.owner,
        if (widget.path != null) 'path': widget.path,
      });
      if (mounted) {
        setState(
          () => versions = (result['items'] as List).map(object).toList(),
        );
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> act(String action, Json version) async {
    if (busy) return;
    if (action == 'delete') {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('删除这个成品版本？'),
          content: const Text('保留原图与当前编辑。此操作无法撤销。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('删除成品'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    final identity = 'version-${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      busy = true;
      job = identity;
    });
    try {
      final payload = {
        'owner': widget.owner,
        'id': version['id'],
        if (widget.path != null) 'path': widget.path,
      };
      if (action == 'delete') {
        await widget.core.call('version.delete', payload, identity);
        if (mounted) await load();
      } else if (action == 'restore') {
        final result = await widget.core.call(
          'version.recipe',
          payload,
          identity,
        );
        if (mounted) Navigator.pop(context, object(result['recipe']));
      } else {
        final checked = await widget.core.call(
          'version.open',
          payload,
          identity,
        );
        if (!mounted) return;
        if (action == 'share') {
          await SharePlus.instance.share(
            ShareParams(
              sharePositionOrigin: shareAnchor(context),
              files: [XFile(checked['path'] as String)],
              text: '${checked['name']} · Huevia',
            ),
          );
        } else {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => VersionPreviewPage(
                core: widget.core,
                owner: widget.owner,
                version: checked,
              ),
            ),
          );
        }
      }
    } catch (failure) {
      if (mounted) report(context, failure);
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('成品版本'),
      actions: [
        IconButton(
          onPressed: busy || loading ? null : load,
          tooltip: '刷新版本',
          icon: const Icon(Icons.refresh),
        ),
      ],
      bottom: busy || loading
          ? const PreferredSize(
              preferredSize: Size.fromHeight(3),
              child: LinearProgressIndicator(),
            )
          : null,
    ),
    body: SafeArea(
      child: error != null
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(error!),
                    TextButton(onPressed: load, child: const Text('重试')),
                  ],
                ),
              ),
            )
          : versions.isEmpty
          ? const Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: Text('导出后会在这里保留成品与当时的配方。'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: versions.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final version = versions[index];
                final invalid = version['error'] != null;
                final time = DateTime.fromMillisecondsSinceEpoch(
                  version['createdAt'] as int,
                ).toLocal();
                final date =
                    '${time.year}/${time.month}/${time.day} '
                    '${time.hour.toString().padLeft(2, '0')}:'
                    '${time.minute.toString().padLeft(2, '0')}';
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(version['name'] as String),
                    subtitle: Text(
                      invalid
                          ? version['error'] as String
                          : '${version['width']} × ${version['height']} · $date'
                                '${version['sourceAvailable'] == false ? '\n原文件不可用，成品仍可查看和分享。' : ''}',
                    ),
                    onTap: busy || invalid ? null : () => act('view', version),
                    trailing: PopupMenuButton<String>(
                      enabled: !busy,
                      tooltip: '版本操作',
                      onSelected: (action) => act(action, version),
                      itemBuilder: (_) => [
                        if (!invalid) ...[
                          const PopupMenuItem(
                            value: 'view',
                            child: Text('查看成品'),
                          ),
                          const PopupMenuItem(
                            value: 'share',
                            child: Text('分享成品'),
                          ),
                          if (widget.path != null)
                            PopupMenuItem(
                              value: 'restore',
                              enabled: version['sourceAvailable'] != false,
                              child: const Text('恢复此配方'),
                            ),
                        ],
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除成品'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    ),
  );
}

class VersionPreviewPage extends StatefulWidget {
  const VersionPreviewPage({
    super.key,
    required this.core,
    required this.owner,
    required this.version,
  });
  final HueviaCore core;
  final String owner;
  final Json version;
  @override
  State<VersionPreviewPage> createState() => _VersionPreviewPageState();
}

class _VersionPreviewPageState extends State<VersionPreviewPage> {
  String? preview, error;
  late final job = 'saved-preview-${DateTime.now().microsecondsSinceEpoch}';
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final result = await widget.core.call('media.originalPreview', {
        'path': widget.version['path'],
        'owner': widget.owner,
      }, job);
      final path = result['path'] as String;
      if (mounted) {
        setState(() => preview = path);
      } else {
        await discard(path);
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    }
  }

  Future<void> discard(String path) async {
    if (!p.isWithin(p.join(widget.core.root, 'previews'), path)) return;
    try {
      await FileImage(File(path)).evict();
      await File(path).delete();
    } on FileSystemException {
      // Only an owned disposable preview is removed.
    }
  }

  @override
  void dispose() {
    unawaited(widget.core.cancel(job));
    if (preview != null) unawaited(discard(preview!));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('已保存成品')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: error != null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(error!),
                    )
                  : preview == null
                  ? const CircularProgressIndicator()
                  : Image.file(
                      File(preview!),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Text('无法读取成品预览。'),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              '${widget.version['width']} × ${widget.version['height']} · '
              '${widget.version['name']}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  );
}
