import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'domain.dart';

/// One confirmed original-byte action. Retries keep the same native receipt key and target.
class OriginalSave extends ChangeNotifier {
  OriginalSave(
    this.state,
    this.owner,
    this.source,
    this.sourceSha,
    this.filename, {
    this.targetId,
  }) : operation = List.generate(
         16,
         (_) => Random.secure().nextInt(256),
       ).map((b) => b.toRadixString(16).padLeft(2, '0')).join() {
    state.addListener(accountChanged);
  }
  final AppState state;
  final String owner, operation;
  final String? targetId;
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
      if (targetId == null) {
        if (defaultTargetPlatform == TargetPlatform.iOS &&
            filename.toLowerCase().endsWith('.nef')) {
          var read = await state.core.call('gallery.access');
          check();
          if (read['access'] != 'full' && read['access'] != 'limited') {
            read = await state.core.galleryPermission();
            check();
          }
          if (read['access'] != 'full' && read['access'] != 'limited') {
            throw const AppFailure('NEF 相册保存需要读取权限以核对原字节，也可选择 Files 保存。');
          }
        }
        final permission = await state.core.gallerySavePermission();
        check();
        if (permission['granted'] != true) {
          throw const AppFailure('请允许保存照片到系统相册后重试。');
        }
      } else if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(targetId!)) {
        throw const AppFailure('文件夹授权记录无效，请重新选择。');
      }
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceSha)) {
        throw const AppFailure('原始文件信息已变化，请重新打开照片。');
      }
      final identity = 'original-$operation-${_attempt++}';
      job = identity;
      final value = await state.core.call(
        targetId == null ? 'gallery.publishOriginal' : 'files.publishOriginal',
        {
          'owner': owner,
          'path': source,
          'expectedSourceSha': sourceSha,
          'filename': filename,
          'operationId': operation,
          'targetId': ?targetId,
        },
        identity,
      );
      check();
      final address = value['uri'] ?? value['identifier'];
      if (value['published'] != true || address is! String || address.isEmpty) {
        throw const AppFailure('系统相册尚未确认保存，请重试此任务。');
      }
      if (targetId != null &&
          (value['verified'] != true ||
              value['sha256'] != sourceSha ||
              value['targetId'] != targetId)) {
        throw const AppFailure('文件夹保存尚未通过原字节读回核对，请重试此任务。');
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
