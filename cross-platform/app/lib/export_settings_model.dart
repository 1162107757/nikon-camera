import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'domain.dart';

Json exportCopy(Json value) => object(jsonDecode(jsonEncode(value)));

class ExportVariant {
  ExportVariant(this.id, this.label, {Json? recipe})
    : _recipe = recipe == null ? null : exportCopy(recipe);
  final String id, label;
  Json? _recipe, _description;
  bool get ready => _recipe != null && _description != null;
  Json get recipe => exportCopy(_recipe!);
  Json get description => exportCopy(_description!);
}

class ExportItem {
  ExportItem(
    this.id,
    this.label,
    this.photo,
    Json recipe,
    Json description,
    Json options,
  ) : recipe = exportCopy(recipe),
      description = exportCopy(description),
      options = exportCopy(options);
  final String id, label;
  final Photo photo;
  final Json recipe, description, options;
}

/// Frozen original/current/saved recipes for the original quick-save sheet.
/// Inspection uses the read-only core descriptor, never draft.save or export.
class ExportSettings extends ChangeNotifier {
  ExportSettings({
    required this.state,
    required this.photo,
    required this.owner,
    required Json recipe,
    required this.isCurrent,
  }) {
    variants.addAll([
      ExportVariant('current', '当前编辑', recipe: recipe),
      ExportVariant('original', '原图', recipe: Recipe().data),
    ]);
    state.addListener(accountChanged);
  }
  final AppState state;
  final Photo photo;
  final String owner;
  final bool Function() isCurrent;
  final variants = <ExportVariant>[];
  final selected = <String>{'current'};
  final _resolving = <String, Future<ExportVariant>>{};
  Future<void> _tail = Future.value();
  Json _source = {};
  String? _job, sourceSha, error;
  bool loading = false, freezing = false, stale = false, _disposed = false;
  int _sequence = 0;
  int quality = 3;
  bool get current =>
      !_disposed &&
      !stale &&
      state.session['logoutPending'] != true &&
      (state.session['user']?['id'] as String? ?? '') == owner &&
      isCurrent();
  bool get enabled => current && !loading && !freezing;
  List<ExportVariant> get chosen =>
      variants.where((v) => selected.contains(v.id)).toList();
  void changed() {
    if (!_disposed) notifyListeners();
  }

  void check() {
    if (!current) throw const AppFailure('照片或账号已变化，请重新打开导出设置。');
  }

  void accountChanged() {
    if (!current) invalidate();
  }

  void invalidate() {
    if (_disposed || stale) return;
    stale = true;
    for (final variant in variants) {
      variant._recipe = variant._description = null;
    }
    variants.clear();
    selected.clear();
    _source = {};
    sourceSha = error = null;
    if (_job != null) unawaited(state.core.cancel(_job!).catchError((_) {}));
    changed();
  }

  @override
  void dispose() {
    if (_disposed) return;
    state.removeListener(accountChanged);
    _disposed = true;
    if (_job != null) unawaited(state.core.cancel(_job!).catchError((_) {}));
    for (final variant in variants) {
      variant._recipe = variant._description = null;
    }
    variants.clear();
    selected.clear();
    _source = {};
    super.dispose();
  }

  Future<Json> request(String operation, Json input) {
    final reply = Completer<Json>();
    _tail = _tail.then((_) async {
      final job =
          'export-settings-${DateTime.now().microsecondsSinceEpoch}-${++_sequence}';
      try {
        check();
        _job = job;
        final result = await state.core.call(operation, input, job);
        check();
        reply.complete(exportCopy(result));
      } catch (failure, stack) {
        reply.completeError(failure, stack);
      } finally {
        if (_job == job) _job = null;
      }
    });
    return reply.future;
  }

  Future<void> load() async {
    if (loading || freezing || !current) return;
    loading = true;
    error = null;
    changed();
    try {
      for (final variant in variants) {
        variant._description = null;
      }
      _source = await request('media.info', {'path': photo.path});
      await resolve('current');
      await resolve('original');
      final result = await request('version.list', {
        'owner': owner,
        'path': photo.path,
      });
      final rows = result['items'];
      if (rows is! List) throw const AppFailure('成品版本列表无效，请重试。');
      check();
      final existing = {for (final v in variants) v.id: v};
      variants.removeWhere((v) => v.id.startsWith('saved:'));
      final seen = <String>{};
      for (final value in rows) {
        if (value is! Map) continue;
        final row = object(value), id = row['id'];
        if (row['error'] != null ||
            id is! String ||
            id.isEmpty ||
            id.length > 64 ||
            !seen.add(id)) {
          continue;
        }
        final key = 'saved:$id';
        variants.add(
          existing[key] ?? ExportVariant(key, row['name'] as String? ?? '成品版本'),
        );
      }
      selected.removeWhere((id) => !variants.any((v) => v.id == id));
      if (selected.isEmpty) selected.add('current');
    } catch (failure) {
      if (current) error = '$failure';
    } finally {
      loading = false;
      changed();
    }
  }

  Future<ExportVariant> resolve(String id) {
    final pending = _resolving[id];
    if (pending != null) return pending;
    final reply = Completer<ExportVariant>();
    _resolving[id] = reply.future;
    unawaited(_resolve(id, reply));
    return reply.future;
  }

  Future<void> _resolve(String id, Completer<ExportVariant> reply) async {
    try {
      check();
      final matches = variants.where((v) => v.id == id);
      if (matches.isEmpty) throw const AppFailure('导出版本已变化，请重新选择。');
      final variant = matches.single;
      if (!variant.ready) {
        if (variant._recipe == null) {
          final saved = await request('version.recipe', {
            'owner': owner,
            'id': id.substring(6),
          });
          if (sourceSha == null || saved['sourceSha'] != sourceSha) {
            throw const AppFailure('成品版本与这张原图不匹配。');
          }
          if (saved['recipe'] is! Map) throw const AppFailure('成品版本的编辑数据无效。');
          variant._recipe = exportCopy(object(saved['recipe']));
        }
        final descriptor = await request('export.describe', {
          'path': photo.path,
          'owner': owner,
          'recipe': variant.recipe,
          'width': _source['width'],
          'height': _source['height'],
          'orientation': _source['orientation'] ?? 1,
        });
        if (sourceSha != null && descriptor['sourceSha'] != sourceSha) {
          throw const AppFailure('原图已变化，请重新打开导出设置。');
        }
        sourceSha ??= descriptor['sourceSha'] as String;
        final qualities = descriptor['qualities'];
        if (qualities is! List ||
            qualities.length != 4 ||
            qualities.any((v) => v is! Map)) {
          throw const AppFailure('导出画质数据无效。');
        }
        variant._description = exportCopy(descriptor);
      }
      check();
      reply.complete(variant);
    } catch (failure, stack) {
      reply.completeError(failure, stack);
    } finally {
      _resolving.remove(id);
      changed();
    }
  }

  void select(String id, bool value) {
    if (!enabled || !variants.any((v) => v.id == id)) return;
    if (selected.contains(id) == value) return;
    if (value && selected.length >= 100) {
      throw const AppFailure('每次最多导出 100 个版本。');
    }
    if (value) {
      selected.add(id);
    } else {
      selected.remove(id);
    }
    error = null;
    changed();
  }

  void chooseQuality(int index) {
    if (!enabled || index < 0 || index > 3) return;
    quality = index;
    changed();
  }

  Future<List<ExportItem>> freezeSelected({Json? options}) async {
    check();
    if (loading || freezing || selected.isEmpty) {
      throw const AppFailure('请先选择需要导出的版本。');
    }
    freezing = true;
    error = null;
    changed();
    try {
      final ids = chosen.map((v) => v.id).toList(), frozenQuality = quality;
      final items = <ExportItem>[];
      var bytes = 0;
      for (final id in ids) {
        final variant = await resolve(id), recipe = variant.recipe;
        final length = utf8.encode(jsonEncode(recipe)).length;
        bytes += length;
        if (length > 1024 * 1024 || bytes > 4 * 1024 * 1024) {
          throw const AppFailure('所选版本的编辑数据较多，请减少选择后重试。');
        }
        var descriptor = variant.description;
        final selectedOptions = options == null
            ? object((descriptor['qualities'] as List)[frozenQuality])
            : exportCopy(options);
        if (options != null) {
          final mode = options['size'];
          if (!['full', 'share', 'custom'].contains(mode)) {
            throw const AppFailure('导出尺寸设置无效。');
          }
          if (mode == 'custom') {
            descriptor = await request('export.describe', {
              'path': photo.path,
              'owner': owner,
              'recipe': recipe,
              'width': _source['width'],
              'height': _source['height'],
              'orientation': _source['orientation'] ?? 1,
              'batch': ids.length > 1,
              'longEdge': options['longEdge'],
              'quality': options['quality'],
            });
            if (descriptor['sourceSha'] != sourceSha) {
              throw const AppFailure('原图已变化，请重新打开导出设置。');
            }
          }
        }
        items.add(
          ExportItem(variant.id, variant.label, photo, recipe, descriptor, {
            'expectedSourceSha': descriptor['sourceSha'],
            for (final key in ['size', 'longEdge', 'quality'])
              if (selectedOptions[key] != null) key: selectedOptions[key],
          }),
        );
      }
      check();
      return List.unmodifiable(items);
    } catch (failure) {
      if (current) error = '$failure';
      rethrow;
    } finally {
      freezing = false;
      changed();
    }
  }
}
