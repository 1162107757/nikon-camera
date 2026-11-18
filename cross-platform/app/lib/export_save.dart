import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import 'domain.dart';
import 'export_settings_model.dart';

bool validExportTarget(String? targetId) =>
    targetId == null || RegExp(r'^[0-9a-f]{32}$').hasMatch(targetId);

Future<Json> publishExport(
  Future<Json> Function(String, Json) call, {
  required String owner,
  required Object? version,
  required String originalName,
  required String operation,
  String? targetId,
  bool orderedFilename = true,
}) async {
  final receipt = await call(
    targetId == null ? 'gallery.publish' : 'files.publishExport',
    {
      'owner': owner,
      'id': version,
      'filename': '${path.basenameWithoutExtension(originalName)}.jpg',
      'operationId': operation,
      if (orderedFilename) 'orderedFilename': true,
      if (targetId == null) 'extraCopy': true else 'targetId': targetId,
    },
  );
  final address = receipt['uri'] ?? receipt['identifier'];
  final filename = receipt['filename'];
  final folderVerified =
      targetId == null ||
      (receipt['verified'] == true &&
          receipt['targetId'] == targetId &&
          filename is String &&
          filename.isNotEmpty);
  if (receipt['published'] != true ||
      address is! String ||
      address.isEmpty ||
      !folderVerified) {
    throw AppFailure(
      targetId == null ? '系统相册尚未确认保存，请重试此任务。' : '文件夹尚未确认保存，请重试此任务。',
    );
  }
  return exportCopy(receipt);
}

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

/// The accepted recipes, destination and publication actions stay frozen across retries.
/// A failed publication stops the queue before another large JPEG is staged.
class ExportSave extends ChangeNotifier {
  ExportSave(
    this.state,
    this.owner,
    List<ExportItem> values, {
    this.targetId,
    this.targetName,
  }) : items = values.map(ExportSaveItem.new).toList() {
    if (items.isEmpty || items.length > 100) {
      throw const AppFailure('请选择 1–100 个导出版本。');
    }
    if (!validExportTarget(targetId)) {
      throw const AppFailure('文件夹授权记录无效，请重新选择。');
    }
    state.addListener(accountChanged);
  }
  final AppState state;
  final String owner;
  final String? targetId, targetName;
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
      error = null;
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
      if (targetId == null) {
        final access = await state.core.gallerySavePermission();
        check();
        if (access['granted'] != true) {
          throw const AppFailure('请允许保存照片到系统相册后重试。');
        }
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
              throw const AppFailure('成品记录无效，未完成保存。');
            }
            item.version = exportCopy(value);
          }
          item.phase = targetId == null ? '保存到手机相册' : '保存到文件夹';
          changed();
          final receipt = await publishExport(
            call,
            owner: owner,
            version: item.version!['id'],
            originalName: item.input.photo.name,
            operation: item.operation,
            targetId: targetId,
          );
          check();
          item.receipt = receipt;
          item.phase = targetId == null ? '已保存到相册' : '已保存到文件夹';
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
