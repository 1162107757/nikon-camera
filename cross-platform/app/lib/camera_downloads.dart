import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'camera_transfer.dart';
import 'original_files.dart';

/// Persistent intentions belong to shared storage; a transport reply alone
/// cannot complete a queue item. Native camera.download writes the SHA receipt.
class CameraDownloads extends ChangeNotifier with WidgetsBindingObserver {
  CameraDownloads(this.state) {
    _stopRevision = state.connectionProtection.stopRevision;
    state.addListener(accountChanged);
    state.connectionProtection.addListener(protectionChanged);
    WidgetsBinding.instance.addObserver(this);
  }
  final AppState state;
  List<Json> queues = [];
  List<Json> issues = [];
  Json? current;
  String? error, job;
  String phase = 'idle';
  int index = 0, received = 0, total = 0;
  bool busy = false, stopped = false, alive = true, bindingNeeded = false;
  int generation = 0;
  int _stopRevision = 0;
  String owner = '';
  Future<void>? running;
  StreamSubscription<dynamic>? events;
  bool foreground = true;
  String get currentOwner => state.session['user']?['id'] as String? ?? '';
  List<Json> get items =>
      (current?['items'] as List? ?? []).map(object).toList();
  int get done => items
      .where((row) => row['phase'] == 'completed' || row['phase'] == 'skipped')
      .length;
  void changed() {
    if (alive) notifyListeners();
  }

  void check(int epoch) {
    if (!alive ||
        stopped ||
        generation != epoch ||
        owner != currentOwner ||
        state.session['logoutPending'] == true) {
      throw const AppFailure('下载队列已暂停或账号已变化。');
    }
  }

  Future<Json> call(String op, Json payload, int epoch) async {
    check(epoch);
    final identity = 'camera-queue-${DateTime.now().microsecondsSinceEpoch}';
    job = identity;
    try {
      final result = await state.core.call(op, payload, identity);
      check(epoch);
      return result;
    } finally {
      if (job == identity) job = null;
    }
  }

  Future<void> restore() async {
    final expected = currentOwner;
    final result = await state.core.call('downloads.list', {'owner': expected});
    if (!alive ||
        expected != currentOwner ||
        state.session['logoutPending'] == true) {
      return;
    }
    queues = (result['items'] as List).map(object).toList();
    issues = (result['issues'] as List? ?? []).map(object).toList();
    if (!busy) owner = expected;
    changed();
  }

  Future<void> create(Json status, List<Json> selection, Json target) async {
    if (busy || state.cameraLiveActive || state.cameraManualTransferActive) {
      throw const AppFailure('请先停止当前相机传输。');
    }
    if (status['connected'] != true || selection.isEmpty) {
      throw const AppFailure('请先连接相机并选择照片。');
    }
    final expected = currentOwner;
    final value = await state.core.call('downloads.create', {
      'owner': expected,
      'cameraId': status['downloadCameraId'],
      'session': status['session'],
      'trusted': status['downloadTrusted'] == true,
      'items': selection,
      'target': target,
    });
    if (!alive ||
        expected != currentOwner ||
        state.session['logoutPending'] == true) {
      throw const AppFailure('账号已改变，下载队列未显示。');
    }
    current = value;
    await restore();
  }

  Future<void> resume(String id) {
    if (busy ||
        !alive ||
        state.cameraLiveActive ||
        state.cameraManualTransferActive) {
      return Future.value();
    }
    owner = currentOwner;
    _stopRevision = state.connectionProtection.stopRevision;
    stopped = false;
    bindingNeeded = false;
    error = null;
    final epoch = ++generation;
    busy = true;
    phase = 'preparing';
    changed();
    final future = run(id, epoch);
    running = future;
    return future;
  }

  Future<void> run(String id, int epoch) async {
    String? itemId;
    events = state.core.operationProgress.listen((event) {
      if (!busy ||
          stopped ||
          event is! Map ||
          event['jobId'] != job ||
          phase != 'receiving') {
        return;
      }
      final value = event['progress'];
      if (value is num && value.isFinite && value >= 0 && value <= 1) {
        final bytes = (total * value).round();
        if (bytes >= received) {
          received = bytes;
          changed();
        }
      }
    }, onError: (_) {});
    try {
      current = await call('downloads.get', {'owner': owner, 'id': id}, epoch);
      final target = object(current!['target']);
      if (target['kind'] == 'system') {
        final permission = await state.core.gallerySavePermission();
        check(epoch);
        if (permission['granted'] != true) {
          throw const AppFailure('请允许保存照片，或改从应用原图选择其他位置。');
        }
        if (state.core.platform == 'ios') {
          var access = await state.core.call('gallery.access');
          check(epoch);
          if (!['full', 'limited'].contains(access['access'])) {
            access = await state.core.galleryPermission();
            check(epoch);
          }
          if (!['full', 'limited'].contains(access['access'])) {
            throw const AppFailure('队列保存需要可读授权以核对原字节，也可选择 Files 文件夹。');
          }
        }
      }
      await state.connectionProtection.setActive('downloads', true);
      check(epoch);
      current = await call('downloads.resume', {
        'owner': owner,
        'id': id,
      }, epoch);
      for (index = 0; index < items.length; index++) {
        check(epoch);
        final row = items[index];
        if (row['phase'] == 'completed' || row['phase'] == 'skipped') continue;
        itemId = row['id'] as String;
        received = 0;
        total = row['bytes'] as int;
        Json receipt;
        if (row['receipt'] is Map) {
          receipt = object(row['receipt']);
          phase = 'validating';
          changed();
        } else {
          phase = 'checking';
          changed();
          final status = await call('camera.status', {}, epoch);
          if (status['connected'] != true) {
            throw const AppFailure('请重新连接原相机后继续；已完成的照片会保留。');
          }
          if (status['downloadCameraId'] != current!['cameraId'] ||
              !(current!['trusted'] == true &&
                      status['downloadTrusted'] == true ||
                  status['session'] == current!['session'])) {
            bindingNeeded = true;
            throw const AppFailure('相机身份或会话已变化，请先核对当前相机。');
          }
          Json? match;
          var offset = 0;
          do {
            final found = await call('camera.resolve', {
              'session': status['session'],
              'descriptor': row['descriptor'],
              'handle': row['handle'],
              'offset': offset,
            }, epoch);
            if (found['match'] is Map) {
              match = object(found['match']);
              break;
            }
            if (found['hasMore'] != true) break;
            final next = found['nextOffset'];
            if (next is! int || next <= offset) {
              throw const AppFailure('相机目录核对没有继续前进，请重新读取。');
            }
            offset = next;
          } while (true);
          if (match == null) throw const AppFailure('原照片已移除或描述已变化，未下载其他同名照片。');
          current = await call('downloads.item', {
            'owner': owner,
            'id': id,
            'itemId': itemId,
            'phase': 'receiving',
          }, epoch);
          phase = 'receiving';
          changed();
          receipt = await call('camera.download', {
            'owner': owner,
            'queueId': id,
            'itemId': itemId,
            'session': status['session'],
            'handle': match['handle'],
            'raw': row['raw'] == true,
          }, epoch);
          // Re-read the native durable receipt rather than completing from a
          // transient reply. A killed Dart isolate resumes at this point.
          current = await call('downloads.get', {
            'owner': owner,
            'id': id,
          }, epoch);
          final stored = items.firstWhere(
            (value) => value['id'] == itemId,
          )['receipt'];
          if (stored is! Map || stored['sha256'] != receipt['sha256']) {
            throw const AppFailure('接收收据尚未保存，队列保持未完成。');
          }
          receipt = object(stored);
        }
        final path = receipt['path'], sha = receipt['sha256'];
        if (path is! String ||
            sha is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
            !p.isWithin(p.join(state.core.root, 'originals'), path) ||
            p.basename(path) != '$sha.${row['raw'] == true ? 'nef' : 'jpg'}' ||
            receipt['bytes'] != total ||
            receipt['raw'] != row['raw'] ||
            !await File(path).exists()) {
          throw const AppFailure('已接收的原件记录无效，请核对原文件。');
        }
        phase = 'importing';
        received = total;
        changed();
        final info = await call('media.info', {'path': path}, epoch);
        info['cameraSource'] = {
          'cameraId': current!['cameraId'],
          'descriptor': row['descriptor'],
          'storage': row['storage'],
          'trusted': current!['trusted'] == true,
        };
        await state.registerPhoto(path, row['name'] as String, info);
        check(epoch);
        Json? publication;
        if (target['kind'] != 'app') {
          phase = 'publishing';
          changed();
          publication = await call(
            target['kind'] == 'folder'
                ? 'files.publishOriginal'
                : 'gallery.publishOriginal',
            {
              'owner': owner,
              'path': path,
              'expectedSourceSha': sha,
              'filename': row['name'],
              'operationId': itemId,
              if (target['kind'] == 'folder') 'targetId': target['id'],
              'verifyReadback': true,
            },
            epoch,
          );
        }
        current = await call('downloads.item', {
          'owner': owner,
          'id': id,
          'itemId': itemId,
          'phase': 'completed',
          'publication': ?publication,
        }, epoch);
      }
      current = await call('downloads.finish', {
        'owner': owner,
        'id': id,
      }, epoch);
      phase = 'done';
    } catch (failure) {
      if (alive && owner == currentOwner) {
        if (!stopped) error = '$failure';
        phase = 'paused';
        try {
          if (!stopped && itemId != null) {
            final text = '$failure';
            current = await state.core.call('downloads.item', {
              'owner': owner,
              'id': id,
              'itemId': itemId,
              'phase': 'failed',
              'error': text.length > 500 ? text.substring(0, 500) : text,
            });
          }
          current = await state.core.call('downloads.pause', {
            'owner': owner,
            'id': id,
          });
        } catch (_) {
          /* The original journal remains recoverable. */
        }
      }
    } finally {
      await events?.cancel();
      events = null;
      job = null;
      busy = false;
      await state.connectionProtection.setActive('downloads', false);
      if (alive && owner == currentOwner) {
        try {
          await restore();
        } catch (_) {}
      }
      changed();
    }
  }

  Future<void> bindCurrent() async {
    if (busy || current == null) return;
    final status = await state.core.call('camera.status');
    if (status['connected'] != true) throw const AppFailure('请先连接并核对相机。');
    current = await state.core.call('downloads.bind', {
      'owner': currentOwner,
      'id': current!['id'],
      'cameraId': status['downloadCameraId'],
      'session': status['session'],
      'trusted': status['downloadTrusted'] == true,
      'confirmed': true,
    });
    bindingNeeded = false;
    error = null;
    changed();
  }

  Future<void> stop() async {
    if (!busy || stopped) return;
    stopped = true;
    phase = 'stopping';
    changed();
    final identity = job;
    if (identity != null) {
      try {
        await state.core.cancel(identity);
      } catch (_) {}
    }
    await running;
  }

  Future<void> skip(String id, String itemId) async {
    if (busy) return;
    current = await state.core.call('downloads.item', {
      'owner': currentOwner,
      'id': id,
      'itemId': itemId,
      'phase': 'skipped',
    });
    await restore();
  }

  void accountChanged() {
    if (owner != currentOwner || state.session['logoutPending'] == true) {
      if (busy) unawaited(stop());
      ++generation;
      current = null;
      queues = [];
      issues = [];
      if (!busy) owner = currentOwner;
      changed();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    protectionChanged();
  }

  void protectionChanged() {
    if (!alive) return;
    final revision = state.connectionProtection.stopRevision;
    if (revision > _stopRevision) {
      _stopRevision = revision;
      if (busy) {
        error = '已从系统通知停止下载队列。';
        unawaited(stop());
      }
      return;
    }
    if (!foreground && busy && !state.connectionProtection.backgroundAllowed) {
      unawaited(stop());
    }
  }

  @override
  void dispose() {
    alive = false;
    unawaited(stop());
    state.removeListener(accountChanged);
    state.connectionProtection.removeListener(protectionChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class CameraDownloadsPage extends StatefulWidget {
  const CameraDownloadsPage({super.key, required this.state});
  final AppState state;
  @override
  State<CameraDownloadsPage> createState() => _CameraDownloadsPageState();
}

class _CameraDownloadsPageState extends State<CameraDownloadsPage> {
  CameraDownloads get queue => widget.state.cameraDownloads;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      await queue.restore();
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$failure')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('相机下载队列'),
      actions: [
        IconButton(
          tooltip: '刷新记录',
          onPressed: queue.busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: queue,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('已接收的原件保留在应用内。中断后重新连接并核对原相机，只重试未完成项。'),
          if (queue.issues.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '有 ${queue.issues.length} 项下载记录无法读取，其他有效任务仍可继续。${queue.issues.first['error'] ?? ''}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (queue.current != null) ...[
            const SizedBox(height: 16),
            Text('已完成 ${queue.done} / ${queue.items.length}'),
            if (queue.busy)
              LinearProgressIndicator(
                value: queue.total > 0 && queue.phase == 'receiving'
                    ? queue.received / queue.total
                    : null,
              ),
            if (queue.busy)
              Text(
                '${queue.phase == 'receiving'
                    ? '接收原文件'
                    : queue.phase == 'checking'
                    ? '核对相机目录'
                    : queue.phase == 'publishing'
                    ? '保存到目标位置'
                    : '校验与保存'} · ${cameraByteCount(queue.received)} / ${cameraByteCount(queue.total)}',
              ),
            if (queue.error != null)
              Text(
                queue.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (queue.bindingNeeded)
              OutlinedButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('核对当前相机'),
                      content: const Text(
                        '请确认连接的是原相机和原存储卡。仍将逐张核对稳定描述，名称相同不会代替原照片。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('已核对'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    try {
                      await queue.bindCurrent();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  }
                },
                child: const Text('核对并绑定当前相机'),
              ),
            FilledButton(
              onPressed: queue.busy
                  ? () => unawaited(queue.stop())
                  : queue.current!['phase'] == 'done'
                  ? null
                  : () =>
                        unawaited(queue.resume(queue.current!['id'] as String)),
              child: Text(queue.busy ? '停止队列' : '继续未完成项'),
            ),
          ],
          if (queue.queues.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('还没有下载队列。请在相机照片中多选并接收。'),
            ),
          for (final item in queue.queues)
            ListTile(
              title: Text('${item['done']} / ${item['count']} 张'),
              subtitle: Text(item['phase'] == 'done' ? '已完成' : '已保存，可继续'),
              trailing: const Icon(Icons.chevron_right),
              enabled: !queue.busy,
              onTap: () async {
                queue.current = await widget.state.core.call('downloads.get', {
                  'owner': queue.currentOwner,
                  'id': item['id'],
                });
                queue.error = null;
                queue.changed();
              },
            ),
        ],
      ),
    ),
  );
}

Future<Json?> chooseDownloadTarget(BuildContext context, AppState state) async {
  final kind = await showDialog<String>(
    context: context,
    builder: (c) => SimpleDialog(
      title: const Text('接收原文件到哪里'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(c, 'app'),
          child: const Text('应用相册'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(c, 'system'),
          child: const Text('应用相册 + 系统相册'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(c, 'folder'),
          child: const Text('应用相册 + 选择文件夹'),
        ),
      ],
    ),
  );
  if (kind == null) return null;
  if (kind == 'folder') {
    final chosen = await OriginalFiles.chooseTarget(
      state.session['user']?['id'] as String? ?? '',
    );
    if (chosen == null) return null;
    return {'kind': kind, ...chosen};
  }
  return {'kind': kind};
}
