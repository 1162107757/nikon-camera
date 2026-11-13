import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'theme.dart';

String _operation() => List.generate(
  16,
  (_) => Random.secure().nextInt(256),
).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

class AlbumDeletePage extends StatefulWidget {
  const AlbumDeletePage({
    super.key,
    required this.state,
    required this.rows,
    required this.phone,
    this.onDeleted,
  });
  final AppState state;
  final List<Json> rows;
  final bool phone;
  final ValueChanged<Set<String>>? onDeleted;
  @override
  State<AlbumDeletePage> createState() => _AlbumDeletePageState();
}

class _AlbumDeletePageState extends State<AlbumDeletePage> {
  late final String owner =
      widget.state.session['user']?['id'] as String? ?? '';
  late final List<Json> items = widget.rows
      .map(
        (r) => <String, dynamic>{
          'id': r['id'],
          'name': r['name'],
          'systemOperation': _operation(),
          'versionOperation': _operation(),
          'originalOperation': _operation(),
          'done': false,
        },
      )
      .toList();
  bool originals = false,
      versions = false,
      system = false,
      locked = false,
      busy = false,
      stopped = false,
      invalid = false;
  String? job, error;
  late final File journal = File(
    p.join(
      widget.state.core.root,
      'album-delete-tasks',
      '${sha256.convert(utf8.encode(jsonEncode([owner, widget.phone, widget.rows.map((r) => r['id']).toList()])))}.json',
    ),
  );
  int get completed => items.where((i) => i['done'] == true).length;
  @override
  void initState() {
    super.initState();
    system = widget.phone;
    versions = !widget.phone;
    restore();
    widget.state.addListener(accountChanged);
  }

  void accountChanged() {
    if ((widget.state.session['user']?['id'] as String? ?? '') != owner ||
        widget.state.session['logoutPending'] == true) {
      invalid = true;
      unawaited(stop());
      if (mounted) setState(() {});
    }
  }

  void restore() {
    try {
      if (!journal.existsSync() || journal.lengthSync() > 512 * 1024) return;
      final value = object(jsonDecode(journal.readAsStringSync()));
      if (value['owner'] != owner ||
          value['phone'] != widget.phone ||
          value['locked'] != true) {
        return;
      }
      final saved = (value['items'] as List).map(object).toList();
      if (saved.length != items.length ||
          List.generate(
            items.length,
            (i) => saved[i]['id'] == items[i]['id'],
          ).contains(false)) {
        return;
      }
      for (var i = 0; i < items.length; i++) {
        items[i].addAll(saved[i]);
      }
      originals = value['originals'] == true;
      versions = value['versions'] == true;
      system = value['system'] == true;
      locked = true;
    } catch (_) {
      /* Unreadable records cannot authorize a delete. */
    }
  }

  Future<void> persist() async {
    await journal.parent.create(recursive: true);
    final temp = File('${journal.path}.part');
    await temp.writeAsString(
      jsonEncode({
        'owner': owner,
        'phone': widget.phone,
        'locked': locked,
        'originals': originals,
        'versions': versions,
        'system': system,
        'items': items,
      }),
      flush: true,
    );
    await temp.rename(journal.path);
  }

  void check() {
    if (!mounted || invalid || stopped) throw const AppFailure('删除任务已停止。');
  }

  Future<Json> call(String op, Json payload) async {
    check();
    final id = 'album-delete-${DateTime.now().microsecondsSinceEpoch}';
    job = id;
    try {
      final result = await widget.state.core.call(op, {
        'owner': owner,
        ...payload,
      }, id);
      check();
      return result;
    } finally {
      if (job == id) job = null;
    }
  }

  Future<void> stop() async {
    stopped = true;
    if (job != null) {
      try {
        await widget.state.core.cancel(job!);
      } catch (_) {
        /* The next transaction boundary also checks stopped. */
      }
    }
  }

  Future<void> start() async {
    if (busy || invalid || (!originals && !versions && !system)) return;
    if (!locked) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: Text('删除选中的 ${items.length} 张照片？'),
          content: Text(
            [
              if (originals) '应用内原图',
              if (versions) '应用内成品版本',
              if (system) widget.phone ? '选中的系统相册照片' : '有保存记录的系统相册副本',
            ].join('、'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('按所选范围删除'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      locked = true;
    }
    setState(() {
      busy = true;
      stopped = false;
      error = null;
    });
    try {
      await persist();
      // Freeze every source and selected version before the first destructive call.
      for (final item in items.where(
        (i) => i['done'] != true && i['prepared'] != true,
      )) {
        check();
        if (!widget.phone) {
          final draft = await call('draft.load', {'path': item['id']});
          item['sourceSha'] = draft['sourceSha'];
          final saved = await call('version.list', {'path': item['id']});
          item['versionIds'] = (saved['items'] as List)
              .map((v) => object(v)['id'])
              .toList();
          if (system) {
            final copies = await call('gallery.publishedCopies', {
              'versionIds': item['versionIds'],
              'path': item['id'],
              'sourceSha': item['sourceSha'],
            });
            item['systemIds'] = copies['ids'] ?? [];
          }
        } else {
          item['systemIds'] = [item['id']];
        }
        item['prepared'] = true;
        await persist();
      }
      for (final item in items.where((i) => i['done'] != true)) {
        check();
        item.remove('error');
        try {
          if (system && item['systemDone'] != true) {
            final ids = item['systemIds'] as List;
            for (var offset = 0; offset < ids.length; offset += 100) {
              final range = ids.sublist(offset, min(offset + 100, ids.length));
              final base = item['systemOperation'] as String;
              final op = offset == 0
                  ? base
                  : sha256
                        .convert(utf8.encode('$base-$offset'))
                        .toString()
                        .substring(0, 32);
              await call('gallery.delete', {'ids': range, 'operationId': op});
            }
            item['systemDone'] = true;
            await persist();
          }
          if (versions && item['versionsDone'] != true) {
            await call('album.deleteVersions', {
              'path': item['id'],
              'expectedSourceSha': item['sourceSha'],
              'versionIds': item['versionIds'],
              'operationId': item['versionOperation'],
            });
            item['versionsDone'] = true;
            await persist();
          }
          if (originals && item['originalDone'] != true) {
            await call('album.deleteOriginal', {
              'path': item['id'],
              'expectedSourceSha': item['sourceSha'],
              'operationId': item['originalOperation'],
            });
            item['originalDone'] = true;
            await persist();
            await widget.state.removePhotos({item['id'] as String});
          }
          item['done'] = true;
          if (originals || widget.phone && system) {
            widget.onDeleted?.call({item['id'] as String});
          }
          await persist();
          if (mounted) setState(() {});
        } catch (failure) {
          if (stopped || invalid || !mounted) break;
          item['error'] = '$failure';
          await persist();
          if (mounted) setState(() {});
        }
      }
    } catch (failure) {
      if (mounted && !stopped) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> newScope() async {
    if (busy) return;
    for (final item in items) {
      final id = item['id'], name = item['name'];
      item.clear();
      item.addAll({
        'id': id,
        'name': name,
        'systemOperation': _operation(),
        'versionOperation': _operation(),
        'originalOperation': _operation(),
        'done': false,
      });
    }
    locked = false;
    stopped = false;
    originals = false;
    versions = !widget.phone;
    system = widget.phone;
    error = null;
    await persist();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: const HueHeader(title: '删除范围', back: true),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '已选择 ${items.length} 张',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text('每张按系统副本、成品版本、原图的顺序处理。某一步失败时，后续范围会保留；重试沿用原任务。'),
          if (!widget.phone) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('应用内原图'),
              value: originals,
              onChanged: locked ? null : (v) => setState(() => originals = v!),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('应用内成品版本'),
              value: versions,
              onChanged: locked ? null : (v) => setState(() => versions = v!),
            ),
          ],
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(widget.phone ? '选中的系统相册照片' : '有保存记录的系统相册副本'),
            subtitle: const Text('系统可能再次要求确认或相册授权。'),
            value: system,
            onChanged: locked || widget.phone
                ? null
                : (v) => setState(() => system = v!),
          ),
          if (busy) const LinearProgressIndicator(),
          Text('已完成 $completed/${items.length}${stopped ? ' · 已停止' : ''}'),
          if (invalid) const Text('账号已改变，请返回重新选择。'),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          for (final item in items)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item['name'] as String),
              subtitle: Text(
                item['error'] as String? ??
                    (item['done'] == true ? '已按所选范围删除' : '等待处理'),
              ),
              trailing: item['done'] == true
                  ? const Icon(Icons.check_circle_outline)
                  : null,
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: busy
              ? OutlinedButton(
                  onPressed: stopped ? null : () => unawaited(stop()),
                  child: Text(stopped ? '正在停止…' : '停止后续删除'),
                )
              : completed == items.length && !widget.phone && !originals
              ? OutlinedButton(
                  onPressed: () => unawaited(newScope()),
                  child: const Text('选择新的删除范围'),
                )
              : FilledButton(
                  onPressed:
                      invalid ||
                          completed == items.length ||
                          (!originals && !versions && !system)
                      ? null
                      : () => unawaited(start()),
                  child: Text(locked ? '重试未完成项' : '删除所选范围'),
                ),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    unawaited(stop());
    super.dispose();
  }
}
