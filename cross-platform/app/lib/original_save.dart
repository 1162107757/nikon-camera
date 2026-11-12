import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'domain.dart';

/// One confirmed original-JPEG action. Retries keep the same native receipt key.
class OriginalSave extends ChangeNotifier {
  OriginalSave(
    this.state,
    this.owner,
    this.source,
    this.sourceSha,
    this.filename,
  ) : operation = List.generate(
        16,
        (_) => Random.secure().nextInt(256),
      ).map((b) => b.toRadixString(16).padLeft(2, '0')).join() {
    state.addListener(accountChanged);
  }
  final AppState state;
  final String owner, operation;
  String source, sourceSha, filename;
  bool busy = false, stopped = false, invalid = false, _alive = true;
  String? error, job;
  Json? receipt;
  int _attempt = 0;
  bool get done => receipt != null;
  bool get current =>
      _alive &&
      !invalid &&
      state.session['logoutPending'] != true &&
      (state.session['user']?['id'] as String? ?? '') == owner;
  void changed() {
    if (_alive) notifyListeners();
  }

  void accountChanged() {
    if (!current) {
      invalid = true;
      source = sourceSha = filename = '';
      receipt = null;
      error = null;
      unawaited(cancel());
    }
  }

  void check() {
    if (!current || stopped) throw const AppFailure('保存已停止，请重新打开照片。');
  }

  Future<void> run() async {
    if (busy || !current || done) return;
    stopped = false;
    busy = true;
    error = null;
    changed();
    try {
      final permission = await state.core.gallerySavePermission();
      check();
      if (permission['granted'] != true) {
        throw const AppFailure('请允许保存照片到系统相册后重试。');
      }
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceSha)) {
        throw const AppFailure('原始文件信息已变化，请重新打开照片。');
      }
      final identity = 'original-$operation-${_attempt++}';
      job = identity;
      final value = await state.core.call('gallery.publishOriginal', {
        'owner': owner,
        'path': source,
        'expectedSourceSha': sourceSha,
        'filename': filename,
        'operationId': operation,
      }, identity);
      check();
      final address = value['uri'] ?? value['identifier'];
      if (value['published'] != true || address is! String || address.isEmpty) {
        throw const AppFailure('系统相册尚未确认保存，请重试此任务。');
      }
      receipt = Map<String, dynamic>.from(value);
    } catch (failure) {
      if (current && !stopped) error = '$failure';
    } finally {
      job = null;
      busy = false;
      changed();
    }
  }

  Future<void> cancel() async {
    stopped = true;
    changed();
    final identity = job;
    if (identity != null) {
      try {
        await state.core.cancel(identity);
      } catch (_) {
        // The native source and receipt guards also apply after cancellation.
      }
    }
  }

  @override
  void dispose() {
    state.removeListener(accountChanged);
    _alive = false;
    unawaited(cancel());
    source = sourceSha = filename = '';
    receipt = null;
    super.dispose();
  }
}
