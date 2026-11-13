import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

import 'domain.dart';
import 'raw_reference.dart';

class BatchPhoto {
  BatchPhoto(this.row)
    : operation = List.generate(
        16,
        (_) => Random.secure().nextInt(256),
      ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final Json row;
  Photo? photo;
  Json? recipe;
  String? output, error;
  String operation;
  Json? version, receipt;
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
    restore();
  }
  final AppState state;
  final bool phone;
  final String owner;
  final List<BatchPhoto> items;
  bool busy = false, locked = false, stopped = false, accountInvalid = false;
  bool _alive = true;
  String? job, preset;
  String? recoveryError;
  String size = 'full';
  int strength = 100;
  int _recipeBytes = 0;
  bool saveToGallery = false;
  Future<void> _writes = Future.value();
  File get journal => File(
    p.join(
      state.core.root,
      'batch-operations',
      '${sha256.convert(utf8.encode(jsonEncode([owner, phone, items.map((i) => i.row['id']).toList()])))}.json',
    ),
  );
  int get published => items.where((item) => item.receipt != null).length;
  bool get done =>
      completed == items.length &&
      (!saveToGallery || published == items.length);
  void restore() {
    if (!p.isAbsolute(state.core.root)) return;
    try {
      final file = journal;
      if (!file.existsSync() || file.lengthSync() > 6 * 1024 * 1024) return;
      final value = object(jsonDecode(file.readAsStringSync()));
      if (value['owner'] != owner ||
          value['phone'] != phone ||
          value['schema'] != 1) {
        return;
      }
      final rows = value['items'] as List;
      if (rows.length != items.length) return;
      for (var i = 0; i < rows.length; i++) {
        final row = object(rows[i]), item = items[i];
        if (row['id'] != item.row['id'] ||
            !RegExp(r'^[0-9a-f]{32}$')
                .hasMatch(row['operation'] as String? ?? '')) {
          return;
        }
        item.operation = row['operation'] as String;
        if (row['photo'] != null) {
          final photo = Photo.fromJson(object(row['photo']));
          if (p.isWithin(p.join(state.core.root, 'originals'), photo.path) &&
              File(photo.path).existsSync()) {
            item.photo = photo;
          }
        }
        if (row['recipe'] != null) item.recipe = object(row['recipe']);
        if (row['version'] != null) {
          final version = object(row['version']), output = version['path'];
          if (output is String &&
              p.isWithin(p.join(state.core.root, 'photo-versions'), output) &&
              File(output).existsSync()) {
            item.version = version;
            item.output = output;
          }
        }
        if (item.output != null && row['receipt'] != null) {
          item.receipt = object(row['receipt']);
        }
        item.phase = item.receipt != null
            ? '已保存到系统相册'
            : item.output != null
            ? '已保存成品'
            : '等待继续';
      }
      preset = value['preset'] as String?;
      strength = value['strength'] as int? ?? 100;
      size = value['size'] as String? ?? 'full';
      saveToGallery = value['saveToGallery'] == true;
      locked = value['locked'] == true;
      _recipeBytes = items
          .where((i) => i.recipe != null)
          .fold(0, (v, i) => v + utf8.encode(jsonEncode(i.recipe)).length);
    } catch (_) {
      recoveryError = '上次批量任务记录无法完整读取，请核对系统相册后新建任务。';
      locked = true;
    }
  }

  Future<void> persist() {
    if (!p.isAbsolute(state.core.root)) {
      return Future.error(const AppFailure('应用存储尚未准备好。'));
    }
    final value = jsonEncode({
      'schema': 1,
      'owner': owner,
      'phone': phone,
      'preset': preset,
      'strength': strength,
      'size': size,
      'saveToGallery': saveToGallery,
      'locked': locked,
      'items': [
        for (final i in items)
          {
            'id': i.row['id'],
            'operation': i.operation,
            'photo': i.photo?.toJson(),
            'recipe': i.recipe,
            'version': i.version,
            'receipt': i.receipt,
          },
      ],
    });
    final file = journal;
    final next = _writes.then((_) async {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.part');
      await temp.writeAsString(value, flush: true);
      await temp.rename(file.path);
    });
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void invalidateRecipe(BatchPhoto item) {
    if (locked) return;
    if (item.recipe != null) {
      _recipeBytes -= utf8.encode(jsonEncode(item.recipe)).length;
    }
    item.recipe = null;
    changed();
  }

  Future<void> newTask() async {
    if (busy || accountInvalid) return;
    for (final item in items) {
      item.operation = List.generate(
        16,
        (_) => Random.secure().nextInt(256),
      ).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      item.recipe = item.version = item.receipt = null;
      item.output = item.error = null;
      item.phase = '等待处理';
    }
    _recipeBytes = 0;
    recoveryError = null;
    locked = false;
    stopped = false;
    await persist();
    changed();
  }

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
        final result = await call('gallery.import', {
          'id': item.row['id'],
          'batchSelection': true,
        });
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
    bool systemAlbum = false,
  }) async {
    if (busy || accountInvalid || done) return;
    if (recoveryError != null) throw AppFailure(recoveryError!);
    if (!locked) {
      if (amount < 0 ||
          amount > 100 ||
          !['full', 'share'].contains(exportSize)) {
        throw const AppFailure('批量导出设置无效。');
      }
      preset = presetId;
      strength = amount;
      size = exportSize;
      saveToGallery = systemAlbum;
      locked = true;
    }
    stopped = false;
    busy = true;
    changed();
    try {
      if (saveToGallery) {
        final access = await state.core.gallerySavePermission();
        check();
        if (access['granted'] != true) {
          throw const AppFailure('请允许保存照片到系统相册后重试。');
        }
      }
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
      await persist();
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
          item.version = object(result);
          item.phase = '已保存成品';
          await persist();
          changed();
        } catch (failure) {
          if (stopped || accountInvalid || !_alive) break;
          item.error = '$failure';
          item.phase = '未完成';
          changed();
        }
      }
      if (saveToGallery) {
        for (final item in items.where(
          (i) => i.version != null && i.receipt == null,
        )) {
          check();
          item.error = null;
          item.phase = '保存到系统相册';
          changed();
          try {
            await persist();
            final receipt = await call('gallery.publish', {
              'owner': owner,
              'id': item.version!['id'],
              'filename': '${p.basenameWithoutExtension(item.photo!.name)}.jpg',
              'extraCopy': true,
              'operationId': item.operation,
            });
            if (receipt['published'] != true ||
                (receipt['uri'] ?? receipt['identifier']) is! String) {
              throw const AppFailure('系统相册尚未确认保存，请重试。');
            }
            item.receipt = receipt;
            item.phase = '已保存到系统相册';
            await persist();
            changed();
          } catch (failure) {
            if (stopped || accountInvalid || !_alive) break;
            item.error = '$failure';
            item.phase = '相册保存未完成';
            changed();
            break;
          }
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
