import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'raw_reference.dart';

class BatchPhoto {
  BatchPhoto(this.row);
  final Json row;
  Photo? photo;
  Json? recipe;
  String? output, error;
  String phase = '等待处理';
}

/// A bounded, sequential queue. Each recipe is frozen before any export starts;
/// retries keep that recipe and never export a completed item twice.
class BatchExport extends ChangeNotifier {
  BatchExport(this.state, List<Json> rows, {required this.phone})
    : owner = state.session['user']?['id'] as String? ?? '',
      items = rows.map(BatchPhoto.new).toList() {
    if (rows.isEmpty ||
        rows.length > 100 ||
        rows.map((row) => row['id']).toSet().length != rows.length) {
      throw const AppFailure('请选择 1–100 张不同的照片。');
    }
    state.addListener(accountChanged);
  }
  final AppState state;
  final bool phone;
  final String owner;
  final List<BatchPhoto> items;
  bool busy = false, locked = false, stopped = false, accountInvalid = false;
  bool _alive = true;
  String? job, preset;
  String size = 'full';
  int strength = 100;
  int _recipeBytes = 0;
  int get completed => items.where((item) => item.output != null).length;
  int get failed => items.where((item) => item.error != null).length;
  void changed() {
    if (_alive) notifyListeners();
  }

  void accountChanged() {
    if ((state.session['user']?['id'] as String? ?? '') != owner) {
      accountInvalid = true;
      unawaited(cancel());
    }
  }

  void check() {
    if (!_alive || stopped) throw const AppFailure('批量处理已停止。');
    if (accountInvalid ||
        (state.session['user']?['id'] as String? ?? '') != owner) {
      throw const AppFailure('账号已改变，请重新选择照片。');
    }
  }

  Future<Json> call(String operation, Json payload) async {
    check();
    final identity = 'batch-${DateTime.now().microsecondsSinceEpoch}';
    job = identity;
    try {
      return await state.core.call(operation, payload, identity);
    } finally {
      if (job == identity) job = null;
    }
  }

  Future<void> cancel() async {
    stopped = true;
    final identity = job;
    changed();
    if (identity != null) {
      try {
        await state.core.cancel(identity);
      } catch (_) {
        /* The next boundary also checks the stopped flag. */
      }
    }
  }

  Future<void> prepare(BatchPhoto item) async {
    if (item.photo == null) {
      if (phone) {
        item.phase = '导入原图';
        changed();
        final result = await call('gallery.import', {'id': item.row['id']});
        check();
        final info = await call('media.info', {'path': result['path']});
        check();
        item.photo = await state.registerPhoto(
          result['path'] as String,
          result['name'] as String,
          info,
        );
      } else {
        item.photo = state.photos.firstWhere(
          (photo) => photo.path == item.row['id'],
          orElse: () => throw const AppFailure('照片已不在应用相册中。'),
        );
      }
    }
    if (item.photo!.info['raw'] == true) {
      item.phase = '显影 RAW';
      changed();
      final raw = item.photo!;
      final reference = RawJpegReference.restore(raw.info, state.core.root);
      String? temporary;
      try {
        final result = await call('media.rawDevelop', {
          'path': raw.path,
          'owner': owner,
          if (reference != null) 'reference': reference.payload,
          'settings': {
            'whiteBalance': 'CAMERA',
            'colorMode': 'CAMERA_JPEG',
            'temperature': 5500,
            'tint': 0,
            'exposure': 0,
            'highlights': 2,
            'quality': 3,
            ...?raw.info['lastDevelopment'] as Map<String, dynamic>?,
          },
        });
        temporary = result['path'] as String;
        check();
        final working = await state.importPhoto(
          XFile(temporary),
          displayName: '${p.basenameWithoutExtension(raw.name)}.jpg',
        );
        check();
        item.photo = await state.updatePhoto(working, {
          'rawSource': raw.path,
          'rawSourceSha': result['sourceSha'],
          'development': result['settings'],
          'rawColorStatus': result['rawColorStatus'],
        });
        await state.updatePhoto(raw, {'lastDevelopment': result['settings']});
      } finally {
        if (temporary != null &&
            p.isWithin(p.join(state.core.root, 'raw-editor'), temporary)) {
          try {
            await File(temporary).delete();
          } on FileSystemException {
            /* disposable */
          }
        }
      }
    }
    if (item.recipe == null) {
      item.phase = '读取编辑';
      changed();
      final saved = await call('draft.load', {
        'path': item.photo!.path,
        'owner': owner,
      });
      check();
      final recipe = saved['recipe'] == null
          ? Recipe().data
          : object(saved['recipe']);
      final encoded = jsonEncode({
        ...recipe,
        if (preset != null) 'presetId': preset,
        if (preset != null) 'strength': strength,
      });
      final bytes = utf8.encode(encoded).length;
      if (bytes > 1024 * 1024 || _recipeBytes + bytes > 4 * 1024 * 1024) {
        throw const AppFailure('本批次编辑数据较多，请返回并减少选择的照片数量。');
      }
      item.recipe = object(jsonDecode(encoded));
      _recipeBytes += bytes;
    }
  }

  Future<void> run({
    String? presetId,
    int amount = 100,
    String exportSize = 'full',
  }) async {
    if (busy || accountInvalid || completed == items.length) return;
    if (!locked) {
      if (amount < 0 ||
          amount > 100 ||
          !['full', 'share'].contains(exportSize)) {
        throw const AppFailure('批量导出设置无效。');
      }
      preset = presetId;
      strength = amount;
      size = exportSize;
      locked = true;
    }
    stopped = false;
    busy = true;
    changed();
    try {
      // Snapshot all recipes first, so edits made during a long export cannot
      // silently change the later members of this batch.
      for (final item in items.where((item) => item.output == null)) {
        check();
        item.error = null;
        try {
          await prepare(item);
        } catch (failure) {
          if (stopped || accountInvalid || !_alive) break;
          item.error = '$failure';
          item.phase = '未完成';
          changed();
        }
      }
      for (final item in items.where(
        (item) => item.output == null && item.error == null,
      )) {
        check();
        item.phase = '导出 JPEG';
        changed();
        try {
          final result = await call('media.export', {
            'path': item.photo!.path,
            'recipe': item.recipe!,
            'owner': owner,
            'size': size,
          });
          item.output = result['path'] as String;
          item.phase = '已保存成品';
          changed();
        } catch (failure) {
          if (stopped || accountInvalid || !_alive) break;
          item.error = '$failure';
          item.phase = '未完成';
          changed();
        }
      }
    } on AppFailure {
      if (!stopped && !accountInvalid && _alive) rethrow;
    } finally {
      busy = false;
      changed();
    }
  }

  @override
  void dispose() {
    _alive = false;
    state.removeListener(accountChanged);
    unawaited(cancel());
    super.dispose();
  }
}
