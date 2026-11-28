import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;

import 'batch_export.dart';
import 'domain.dart';
import 'editor_presets.dart';

/// The model owns both the decoded image and its disposable preview file.
class AlbumPresetPreviewFrame {
  const AlbumPresetPreviewFrame({
    required this.path,
    required this.width,
    required this.height,
    required this.sourceSha,
    required this.image,
  });

  final String path, sourceSha;
  final int width, height;
  final ui.Image image;
}

class _PreparedPhoto {
  const _PreparedPhoto(this.photo, this.recipe);
  final Photo photo;
  final Json recipe;
}

class _MainPreview {
  _MainPreview(this.item, this.preset, this.strength, this.revision);
  final BatchPhoto item;
  final Preset? preset;
  final int strength, revision;
  final done = Completer<void>();
}

class _ThumbnailPreview {
  _ThumbnailPreview(this.item, this.preset, this.photoEpoch, this.key);
  final BatchPhoto item;
  final Preset? preset;
  final int photoEpoch;
  final String key;
  final done = Completer<AlbumPresetPreviewFrame?>();
}

class _PreviewRetired implements Exception {}

class _ThumbnailDeferred implements Exception {}

/// One worker for imports, recipe preparation, large previews and thumbnails.
/// Main-image changes replace pending main work and run before queued thumbnails.
/// This model never starts an export or writes an editing draft.
class AlbumPresetPreview extends ChangeNotifier {
  AlbumPresetPreview(this.state, this.batch, {required this.isCurrent})
    : owner = batch.owner {
    state.addListener(_accountChanged);
  }

  final AppState state;
  final BatchExport batch;
  final bool Function() isCurrent;
  final String owner;
  BatchPhoto? selectedItem;
  Preset? selectedPreset;
  int strength = 100;
  AlbumPresetPreviewFrame? frame;
  String? error;
  bool busy = false;

  bool _alive = true, _stopping = false, _running = false, _preparing = false;
  int _revision = 0, _photoEpoch = 0, _serial = 0;
  String? _job;
  _MainPreview? _pendingMain;
  final _pendingThumbnails = <String, _ThumbnailPreview>{};
  final _thumbnails = <String, Future<AlbumPresetPreviewFrame?>>{};
  final _thumbnailFrames = <String, AlbumPresetPreviewFrame>{};
  final _prepared = <BatchPhoto, _PreparedPhoto>{};
  final _catalogs = <String, EditorPresets>{};
  final _images = <ui.Image>{};
  final _thumbnailImages = <ui.Image>{};
  final _mainImages = <String, ui.Image>{};
  final _ownedFiles = <String>{};
  final _mainFiles = <String>[];
  Completer<void>? _idle;
  Future<void>? _stopFuture;

  bool get valid =>
      _alive &&
      !_stopping &&
      isCurrent() &&
      state.session['logoutPending'] != true &&
      (state.session['user']?['id'] as String? ?? '') == owner;

  void _check() {
    if (!valid) throw _PreviewRetired();
    if (batch.busy || batch.locked) {
      throw const AppFailure('批量任务已开始，请关闭预览后继续。');
    }
  }

  void _changed() {
    if (_alive) notifyListeners();
  }

  void _accountChanged() {
    if (state.session['logoutPending'] == true ||
        (state.session['user']?['id'] as String? ?? '') != owner) {
      unawaited(stop());
    }
  }

  Future<void> update({
    required BatchPhoto item,
    Preset? preset,
    int strength = 100,
  }) {
    if (!valid) return Future.value();
    if (!batch.items.contains(item) || strength < 0 || strength > 100) {
      return Future.error(const AppFailure('预览设置无效。'));
    }
    if (!identical(selectedItem, item)) {
      _photoEpoch++;
      frame = null;
      for (final request in _pendingThumbnails.values) {
        request.done.complete(null);
      }
      _pendingThumbnails.clear();
      _thumbnails.clear();
      _thumbnailFrames.clear();
      for (final catalog in _catalogs.values) {
        catalog.dispose();
      }
      _catalogs.clear();
      for (final image in _thumbnailImages.toList()) {
        _releaseImage(image);
      }
      _thumbnailImages.clear();
    }
    selectedItem = item;
    final frozenPreset = _freezePreset(preset);
    selectedPreset = frozenPreset;
    this.strength = strength;
    error = null;
    busy = true;
    _pendingMain?.done.complete();
    final request = _MainPreview(item, frozenPreset, strength, ++_revision);
    _pendingMain = request;
    _changed();
    _start();
    return request.done.future;
  }

  /// Thumbnails always show the selected photo and the preset at full strength.
  /// A failed thumbnail can be requested again; it does not fail the main image.
  Future<AlbumPresetPreviewFrame?> thumbnail(Preset? preset) {
    final item = selectedItem;
    if (!valid || item == null) return Future.value();
    final identity = preset == null
        ? ''
        : preset.online
        ? preset.data['sha256']
        : preset.id;
    final key = jsonEncode([item.row['id'], identity]);
    return _thumbnails.putIfAbsent(key, () {
      final request = _ThumbnailPreview(
        item,
        _freezePreset(preset),
        _photoEpoch,
        key,
      );
      _pendingThumbnails[key] = request;
      _start();
      return request.done.future;
    });
  }

  Preset? _freezePreset(Preset? preset) => preset == null
      ? null
      : Preset(
          object(jsonDecode(jsonEncode(preset.data))),
          online: preset.online,
        );

  void _start() {
    if (_running || !valid) return;
    _running = true;
    _idle = Completer<void>();
    unawaited(_drain());
  }

  Future<void> _drain() async {
    try {
      while (valid) {
        final main = _pendingMain;
        if (main != null) {
          _pendingMain = null;
          try {
            await _renderMain(main);
          } catch (failure) {
            if (valid && main.revision == _revision) error = '$failure';
          } finally {
            if (!main.done.isCompleted) main.done.complete();
            if (main.revision == _revision) {
              busy = _pendingMain != null;
              _changed();
            }
          }
          continue;
        }
        if (_pendingThumbnails.isEmpty) break;
        final thumbnail = _pendingThumbnails.values.first;
        _pendingThumbnails.remove(thumbnail.key);
        AlbumPresetPreviewFrame? result;
        bool deferred = false;
        try {
          result = await _renderThumbnail(thumbnail);
        } on _ThumbnailDeferred {
          deferred = true;
          _pendingThumbnails[thumbnail.key] = thumbnail;
        } catch (_) {
          _thumbnails.remove(thumbnail.key);
        } finally {
          if (!deferred && !thumbnail.done.isCompleted) {
            thumbnail.done.complete(result);
          }
        }
      }
    } finally {
      _running = false;
      _idle?.complete();
      if (valid && (_pendingMain != null || _pendingThumbnails.isNotEmpty)) {
        _start();
      } else if (!valid && !_stopping) {
        unawaited(stop());
      }
    }
  }

  Future<_PreparedPhoto> _prepare(BatchPhoto item) async {
    _check();
    final cached = _prepared[item];
    if (cached != null) return cached;
    _preparing = true;
    try {
      // Reuse phone imports and RAW working copies without freezing the export.
      await batch.prepare(item);
      _check();
      final photo = item.photo;
      if (photo == null || item.recipe == null) {
        throw const AppFailure('照片还没有准备好，请重试。');
      }
      final prepared = _PreparedPhoto(
        photo,
        object(jsonDecode(jsonEncode(item.recipe))),
      );
      _prepared[item] = prepared;
      while (_prepared.length > 1 &&
          _prepared.values.fold<int>(
                0,
                (size, value) =>
                    size + utf8.encode(jsonEncode(value.recipe)).length,
              ) >
              4 * 1024 * 1024) {
        _prepared.remove(_prepared.keys.first);
      }
      return prepared;
    } finally {
      batch.invalidateRecipe(item);
      _preparing = false;
    }
  }

  EditorPresets _catalog(Photo photo) =>
      _catalogs.putIfAbsent(photo.path, () => EditorPresets(state, photo));

  Future<Json> _call(String operation, Json payload) async {
    _check();
    final job =
        'album-preset-${DateTime.now().microsecondsSinceEpoch}-${_serial++}';
    _job = job;
    try {
      // Return a late preview's path to its caller so it can still be reclaimed.
      return await state.core.call(operation, payload, job);
    } finally {
      if (_job == job) _job = null;
    }
  }

  Future<String> _identity(Photo photo, [String? expected]) async {
    final value = await _call('source.inspect', {
      'path': photo.path,
      'owner': owner,
      'expectedSourceSha': ?expected,
    });
    _check();
    final sha = value['sourceSha'];
    if (sha is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha) ||
        expected != null && sha != expected) {
      throw const AppFailure('原图身份已变化，请重新选择照片。');
    }
    return sha;
  }

  Future<Json> _recipe(
    _PreparedPhoto prepared,
    Preset? preset,
    int amount,
  ) async {
    final id = preset == null
        ? ''
        : await _catalog(prepared.photo).prepare(preset);
    _check();
    return {
      ...object(jsonDecode(jsonEncode(prepared.recipe))),
      'presetId': id,
      'presetName': preset?.name ?? '无预设',
      'strength': preset == null ? 0 : amount,
    };
  }

  Future<AlbumPresetPreviewFrame> _decode(
    String path,
    String sha, [
    Json? result,
  ]) async {
    if (!p.isAbsolute(path) ||
        !p.isWithin(p.join(state.core.root, 'previews'), path)) {
      throw const AppFailure('预览文件不在临时图片目录中。');
    }
    final bytes = await File(path).readAsBytes();
    if (bytes.isEmpty || bytes.length > 32 * 1024 * 1024) {
      throw const AppFailure('预览图片大小无效。');
    }
    final codec = await ui.instantiateImageCodec(bytes);
    ui.Image? image;
    try {
      image = (await codec.getNextFrame()).image;
      if (image.width > 1280 ||
          image.height > 1280 ||
          result != null &&
              (result['width'] != image.width ||
                  result['height'] != image.height)) {
        throw const AppFailure('预览图片尺寸校验失败。');
      }
      _check();
      _images.add(image);
      if (result == null) {
        _thumbnailImages.add(image);
      } else {
        _mainImages[path] = image;
      }
      return AlbumPresetPreviewFrame(
        path: path,
        width: image.width,
        height: image.height,
        sourceSha: sha,
        image: image,
      );
    } catch (_) {
      image?.dispose();
      rethrow;
    } finally {
      codec.dispose();
    }
  }

  Future<void> _renderMain(_MainPreview request) async {
    final prepared = await _prepare(request.item);
    if (request.revision != _revision) return;
    final sha = await _identity(prepared.photo);
    final recipe = await _recipe(prepared, request.preset, request.strength);
    if (request.revision != _revision) return;
    String? path;
    bool installed = false;
    try {
      final result = await _call('media.reviewPreview', {
        'path': prepared.photo.path,
        'owner': owner,
        'recipe': recipe,
        'maxEdge': 1280,
        'snapshot': true,
        'expectedSourceSha': sha,
      });
      path = result['path'] as String?;
      if (path == null) throw const AppFailure('没有收到预览图片。');
      if (p.isWithin(p.join(state.core.root, 'previews'), path)) {
        _ownedFiles.add(path);
      }
      await _identity(prepared.photo, sha);
      final next = await _decode(path, sha, result);
      if (request.revision != _revision || !valid) return;
      frame = next;
      error = null;
      _mainFiles.add(path);
      installed = true;
      while (_mainFiles.length > 2) {
        final expired = _mainFiles.removeAt(0);
        if (expired != path) await _removeFile(expired);
      }
      _changed();
    } finally {
      if (!installed && path != null && _ownedFiles.contains(path)) {
        await _removeFile(path);
      }
    }
  }

  Future<AlbumPresetPreviewFrame?> _renderThumbnail(
    _ThumbnailPreview request,
  ) async {
    final prepared = await _prepare(request.item);
    if (request.photoEpoch != _photoEpoch) return null;
    if (_pendingMain != null) throw _ThumbnailDeferred();
    final sha = await _identity(prepared.photo);
    if (request.preset != null) {
      await _catalog(prepared.photo).prepare(request.preset!);
    }
    _check();
    if (request.photoEpoch != _photoEpoch) return null;
    if (_pendingMain != null) throw _ThumbnailDeferred();
    final catalog = _catalog(prepared.photo);
    late final String path;
    try {
      path = await catalog.thumbnail(request.preset, prepared.recipe);
    } catch (_) {
      // EditorPresets retains thumbnail Futures, including failed ones. Clear
      // that inner cache as well, so a second user request really renders again.
      catalog.retryThumbnails();
      rethrow;
    }
    _check();
    await _identity(prepared.photo, sha);
    if (request.photoEpoch != _photoEpoch) return null;
    final next = await _decode(path, sha);
    if (request.photoEpoch != _photoEpoch || !valid) {
      _thumbnailImages.remove(next.image);
      _releaseImage(next.image);
      return null;
    }
    _thumbnailFrames[request.key] = next;
    while (_thumbnailFrames.length > 48) {
      final key = _thumbnailFrames.keys.first;
      final expired = _thumbnailFrames.remove(key)!;
      _thumbnails.remove(key);
      _thumbnailImages.remove(expired.image);
      _releaseImage(expired.image);
    }
    return next;
  }

  void _releaseImage(ui.Image image) {
    if (!_images.remove(image)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) => image.dispose());
    SchedulerBinding.instance.scheduleFrame();
  }

  Future<void> _removeFile(String path) async {
    if (!_ownedFiles.remove(path)) return;
    final image = _mainImages.remove(path);
    if (image != null) _releaseImage(image);
    try {
      await FileImage(File(path)).evict();
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Only this model's private preview can remain for normal cache cleanup.
    }
  }

  /// Terminal: stop before starting batch.run, and create a new model to reopen.
  Future<void> stop() {
    final previous = _stopFuture;
    if (previous != null) return previous;
    final done = Completer<void>();
    _stopFuture = done.future;
    unawaited(
      _stop().then<void>(
        (_) => done.complete(),
        onError: (Object failure, StackTrace stack) =>
            done.completeError(failure, stack),
      ),
    );
    return done.future;
  }

  Future<void> _stop() async {
    _stopping = true;
    _revision++;
    frame = null;
    busy = false;
    _pendingMain?.done.complete();
    _pendingMain = null;
    for (final request in _pendingThumbnails.values) {
      if (!request.done.isCompleted) request.done.complete(null);
    }
    _pendingThumbnails.clear();
    _changed();
    final job = _job ?? (_preparing ? batch.job : null);
    if (job != null) {
      try {
        await state.core.cancel(job);
      } catch (_) {
        /* Idle is still awaited. */
      }
    }
    for (final catalog in _catalogs.values) {
      catalog.dispose();
    }
    _catalogs.clear();
    if (_running) await _idle?.future;
    for (final path in _ownedFiles.toList()) {
      await _removeFile(path);
    }
    final images = _images.toList();
    _images.clear();
    _thumbnailImages.clear();
    _mainImages.clear();
    // Give listeners one frame to detach RawImage before disposing its handle.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      for (final image in images) {
        image.dispose();
      }
    });
    SchedulerBinding.instance.scheduleFrame();
    _thumbnails.clear();
    _thumbnailFrames.clear();
    _prepared.clear();
  }

  @override
  void dispose() {
    state.removeListener(_accountChanged);
    unawaited(stop());
    _alive = false;
    super.dispose();
  }
}
