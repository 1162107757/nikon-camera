import 'dart:async';

import 'package:flutter/foundation.dart';

import 'domain.dart';

/// Local project defaults and processing receipts are durable in the shared core.
class ProjectPresetsModel extends ChangeNotifier {
  ProjectPresetsModel(this.state)
    : owner = state.session['user']?['id'] as String? ?? '' {
    state.addListener(accountChanged);
  }
  final AppState state;
  final String owner;
  List<Json> projects = [];
  Json? project;
  String selected = '', phase = '';
  String? error, job;
  bool busy = false, stopped = false, invalid = false, _alive = true;
  double? progress;
  int _sequence = 0;
  StreamSubscription<dynamic>? _events;
  int get pending => tasks.where((task) => task['status'] == 'queued').length;
  int get failed => tasks.where((task) => task['status'] == 'error').length;
  List<Json> get tasks =>
      (project?['tasks'] as List? ?? []).map(object).toList();
  List<Json> get photos =>
      (project?['photos'] as List? ?? []).map(object).toList();
  bool get current =>
      _alive &&
      !invalid &&
      (state.session['user']?['id'] as String? ?? '') == owner &&
      state.session['logoutPending'] != true;
  void changed() {
    if (_alive) notifyListeners();
  }

  void accountChanged() {
    if (current) return;
    invalid = true;
    project = null;
    projects = [];
    error = '账号已改变，请重新打开拍摄项目。';
    unawaited(stop());
    changed();
  }

  void check() {
    if (!current) throw const AppFailure('账号已改变，请重新打开拍摄项目。');
    if (stopped) throw const AppFailure('已停止处理，原图与已完成成品仍保留。');
  }

  Future<Json> call(String operation, [Json payload = const {}]) async {
    check();
    final identity =
        'project-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
    job = identity;
    try {
      final result = await state.core.call(operation, {
        'owner': owner,
        ...payload,
      }, identity);
      check();
      return result;
    } finally {
      if (job == identity) job = null;
    }
  }

  Future<void> read() async {
    final result = await call('project.list');
    projects = (result['items'] as List).map(object).toList();
    if (!projects.any((row) => row['id'] == selected)) {
      selected = projects.isEmpty ? '' : projects.first['id'] as String;
    }
    project = selected.isEmpty
        ? null
        : await call('project.open', {'projectId': selected});
  }

  Future<void> refresh() => work(() async {
    await read();
  });
  Future<void> work(Future<void> Function() action) async {
    if (busy || !current) return;
    busy = true;
    stopped = false;
    error = null;
    changed();
    try {
      await action();
    } catch (failure) {
      if (current && !stopped) error = '$failure';
    } finally {
      busy = false;
      progress = null;
      phase = '';
      changed();
    }
  }

  Future<void> select(String id) => work(() async {
    selected = id;
    await read();
  });
  Future<void> create(String name) => work(() async {
    final created = await call('project.create', {'name': name});
    selected = created['id'] as String;
    await read();
  });
  Future<void> rename(String name) => work(() async {
    await call('project.rename', {'projectId': selected, 'name': name});
    await read();
  });
  Future<void> setPreset(String id) => work(() async {
    await call('project.setPreset', {'projectId': selected, 'presetId': id});
    await read();
  });
  Future<void> addPhotos(List<Photo> photos) => work(() async {
    if (photos.isEmpty || photos.length > 100) {
      throw const AppFailure('请选择 1–100 张 JPEG。');
    }
    for (final photo in photos) {
      phase = '加入 ${photo.name}';
      changed();
      await call('project.add', {
        'projectId': selected,
        'path': photo.path,
        'name': photo.name,
      });
    }
    await read();
  });
  void event(dynamic event) {
    if (!current ||
        !busy ||
        stopped ||
        event is! Map ||
        event['jobId'] != job) {
      return;
    }
    final value = event['progress'];
    if (value is num && value.isFinite && value >= 0 && value <= 1) {
      progress = value.toDouble();
      changed();
    }
  }

  /// An explicit run never changes the current photo draft or redraws a saved item.
  Future<void> process({
    bool enqueue = false,
    bool retry = false,
  }) => work(() async {
    final projectId = selected;
    if (enqueue) await call('project.enqueue', {'projectId': projectId});
    if (retry) await call('project.retry', {'projectId': projectId});
    await read();
    _events = state.core.operationProgress.listen(event, onError: (_) {});
    try {
      final queue = tasks.where((task) => task['status'] == 'queued').toList();
      for (final task in queue) {
        check();
        final key = task['key'];
        String? lease;
        try {
          phase = '准备 ${task['name']}';
          progress = null;
          changed();
          final frozen = await call('project.begin', {
            'projectId': projectId,
            'key': key,
          });
          if (frozen['done'] == true) continue;
          lease = frozen['lease'] as String;
          phase = '套用 ${task['presetName']} · ${task['name']}';
          progress = 0;
          changed();
          final saved = await call('media.export', {
            'path': frozen['path'],
            'recipe': frozen['recipe'],
            'size': 'full',
            'snapshot': true,
            'expectedSourceSha': frozen['sourceSha'],
          });
          phase = '保存项目处理记录';
          progress = null;
          changed();
          await call('project.finish', {
            'projectId': projectId,
            'key': key,
            'lease': lease,
            'versionId': saved['id'],
          });
        } catch (failure) {
          // The original may already be saved as an immutable version. Retrying
          // the same frozen export reuses that version instead of adding a copy.
          if (lease != null && current) {
            final message = '$failure';
            await state.core
                .call('project.fail', {
                  'owner': owner,
                  'projectId': projectId,
                  'key': key,
                  'lease': lease,
                  'error': message.length > 1800
                      ? message.substring(0, 1800)
                      : message,
                })
                .catchError((_) => <String, dynamic>{});
          }
          if (!current || stopped) break;
          error = '$failure';
        }
      }
    } finally {
      await _events?.cancel();
      _events = null;
      if (current) {
        stopped = false;
        await read();
      }
    }
  });
  Future<Json> result(Json task) =>
      call('project.result', {'projectId': selected, 'key': task['key']});
  Future<void> stop() async {
    stopped = true;
    changed();
    final active = job;
    if (active != null) {
      try {
        await state.core.cancel(active);
      } catch (_) {
        /* Next boundary also checks. */
      }
    }
  }

  @override
  void dispose() {
    state.removeListener(accountChanged);
    _alive = false;
    unawaited(stop());
    unawaited(_events?.cancel());
    super.dispose();
  }
}
