import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'domain.dart';
import 'export_settings_model.dart';

class ExportSaveItem {
  ExportSaveItem(ExportItem input)
    : input = ExportItem(
        input.id,
        input.label,
        input.photo,
        input.recipe,
        input.description,
        input.options,
      ),
      operation = List.generate(
        16,
        (_) => Random.secure().nextInt(256),
      ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final ExportItem input;
  final String operation;
  Json? version, receipt;
  String? error;
  String phase = '等待导出';
}

/// The accepted recipes and each album action stay frozen across retries.
/// A failed publication stops the queue before another large JPEG is staged.
class ExportSave extends ChangeNotifier {
  ExportSave(this.state, this.owner, List<ExportItem> values)
    : items = values.map(ExportSaveItem.new).toList() {
    if (items.isEmpty || items.length > 100) {
      throw const AppFailure('请选择 1–100 个导出版本。');
    }
    state.addListener(accountChanged);
  }
  final AppState state;
  final String owner;
  final List<ExportSaveItem> items;
  bool busy = false, stopped = false, invalid = false, _alive = true;
  String? job, error;
  int get completed => items.where((i) => i.receipt != null).length;
  bool get done => completed == items.length;
  void changed() {
    if (_alive) notifyListeners();
  }

  void accountChanged() {
    if (state.session['logoutPending'] == true ||
        (state.session['user']?['id'] as String? ?? '') != owner) {
      invalid = true;
      for (final item in items) {
        item.version = item.receipt = null;
        item.error = null;
        item.input.recipe.clear();
        item.input.description.clear();
        item.input.options.clear();
      }
      unawaited(cancel());
    }
  }

  void check() {
    if (!_alive || stopped) throw const AppFailure('导出已停止，已保存的照片仍保留。');
    if (invalid ||
        state.session['logoutPending'] == true ||
        (state.session['user']?['id'] as String? ?? '') != owner) {
      throw const AppFailure('账号已变化，请重新打开照片。');
    }
  }

  Future<Json> call(String op, Json payload) async {
    check();
    final identity = 'save-${DateTime.now().microsecondsSinceEpoch}';
    job = identity;
    try {
      final value = await state.core.call(op, payload, identity);
      check();
      return value;
    } finally {
      if (job == identity) job = null;
    }
  }

  Future<void> cancel() async {
    stopped = true;
    changed();
    if (job != null) {
      try {
        await state.core.cancel(job!);
      } catch (_) {
        /* boundary checks too */
      }
    }
  }

  Future<void> run() async {
    if (busy || invalid || done || !_alive) return;
    stopped = false;
    busy = true;
    error = null;
    changed();
    try {
      final access = await state.core.gallerySavePermission();
      check();
      if (access['granted'] != true) {
        throw const AppFailure('请允许保存照片到系统相册后重试。');
      }
      for (final item in items.where((i) => i.receipt == null)) {
        check();
        item.error = null;
        try {
          if (item.version == null) {
            item.phase = '生成 JPEG';
            changed();
            final value = await call('media.export', {
              'path': item.input.photo.path,
              'owner': owner,
              'recipe': item.input.recipe,
              ...item.input.options,
              'snapshot': true,
            });
            final id = value['id'];
            if (id is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(id)) {
              throw const AppFailure('成品记录无效，未保存到相册。');
            }
            item.version = exportCopy(value);
          }
          item.phase = '保存到手机相册';
          changed();
          final receipt = await call('gallery.publish', {
            'owner': owner,
            'id': item.version!['id'],
            'filename': item.input.photo.name,
            'extraCopy': true,
            'operationId': item.operation,
          });
          if (receipt['published'] != true ||
              (receipt['uri'] ?? receipt['identifier']) is! String ||
              (receipt['uri'] ?? receipt['identifier']) == '') {
            throw const AppFailure('系统相册尚未确认保存，请重试此任务。');
          }
          item.receipt = exportCopy(receipt);
          item.phase = '已保存到相册';
          changed();
        } catch (failure) {
          if (invalid || !_alive || stopped) break;
          item.error = '$failure';
          item.phase = '未完成';
          error = '$failure';
          changed();
          break;
        }
      }
    } catch (failure) {
      if (_alive && !invalid && !stopped) error = '$failure';
    } finally {
      busy = false;
      changed();
    }
  }

  @override
  void dispose() {
    state.removeListener(accountChanged);
    _alive = false;
    unawaited(cancel());
    for (final item in items) {
      item.version = item.receipt = null;
    }
    super.dispose();
  }
}
