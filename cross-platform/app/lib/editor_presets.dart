import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';

/// Online recipes stay in the native photo history, separate from My Presets.
class EditorPresets extends ChangeNotifier {
  EditorPresets(this.state, this.photo)
    : owner = state.session['user']?['id'] as String? ?? '';
  final AppState state;
  final Photo photo;
  final String owner;
  List<Preset> online = [];
  bool loading = false, alive = true;
  String? error;
  String notice = '';
  final Map<String, Future<String>> _prepared = {};
  final Map<String, Future<String>> _images = {};
  final Set<String> _files = {};
  Future<void> _queue = Future.value();
  String? _job;
  int _serial = 0;
  bool get valid =>
      alive &&
      (state.session['user']?['id'] as String? ?? '') == owner &&
      state.session['logoutPending'] != true;
  void check() {
    if (!valid) throw const AppFailure('账号已改变，请重新打开照片。');
  }

  String identity(Preset preset) =>
      preset.online ? preset.data['sha256'] as String : preset.id;

  Future<void> load() async {
    if (loading || !valid) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final value = await state.core.call('editor.catalog');
      check();
      if (!['ok', 'cached'].contains(value['status'])) {
        throw AppFailure(value['message'] as String? ?? '在线滤镜加载失败，请重试。');
      }
      final distinct = <String, Preset>{};
      for (final item in value['items'] as List) {
        final preset = Preset(object(item), online: true);
        distinct.putIfAbsent(identity(preset), () => preset);
      }
      online = distinct.values.toList();
      notice = value['status'] == 'cached' ? '正在显示离线缓存' : '';
    } catch (failure) {
      if (valid) error = '$failure';
    } finally {
      loading = false;
      if (valid) notifyListeners();
    }
  }

  Future<String> prepare(Preset preset) async {
    check();
    final id = identity(preset);
    if (!preset.online) return id;
    final previous = _prepared[id];
    if (previous != null) return previous;
    final pending = () async {
      final result = await state.core.call('editor.prepare', {
        'path': photo.path,
        'owner': owner,
        'preset': preset.data,
      });
      check();
      if (result['id'] != id) throw const AppFailure('滤镜身份已变化，请刷新后重试。');
      return id;
    }();
    _prepared[id] = pending;
    try {
      return await pending;
    } catch (_) {
      _prepared.remove(id);
      rethrow;
    }
  }

  Future<String> thumbnail(Preset? preset, Json recipe) {
    final frozen = object(jsonDecode(jsonEncode(recipe)));
    frozen['presetId'] = preset == null ? '' : identity(preset);
    frozen['presetName'] = preset?.name ?? '无滤镜';
    frozen['strength'] = preset == null ? 0 : 100;
    final key = jsonEncode(frozen);
    return _images.putIfAbsent(key, () {
      final pending = _queue.then((_) async {
        check();
        if (preset != null) await prepare(preset);
        check();
        final job =
            'filter-thumb-${DateTime.now().microsecondsSinceEpoch}-${_serial++}';
        _job = job;
        try {
          final result = await state.core.call('media.reviewPreview', {
            'path': photo.path,
            'owner': owner,
            'recipe': frozen,
            'maxEdge': 160,
          }, job);
          final path = result['path'];
          if (path is! String ||
              !p.isWithin(p.join(state.core.root, 'previews'), path)) {
            throw const AppFailure('滤镜预览记录无效。');
          }
          if (!valid) {
            await _remove(path);
            check();
          }
          _files.add(path);
          while (_files.length > 48) {
            final expired = _files.first;
            _files.remove(expired);
            unawaited(_remove(expired));
            _images.clear();
          }
          return path;
        } finally {
          if (_job == job) _job = null;
        }
      });
      _queue = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
      return pending;
    });
  }

  void retryThumbnails() {
    _images.clear();
  }

  Future<void> _remove(String path) async {
    try {
      await FileImage(File(path)).evict();
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      /* Private thumbnails can be reclaimed on next launch. */
    }
  }

  @override
  void dispose() {
    alive = false;
    if (_job != null) unawaited(state.core.cancel(_job!));
    for (final file in _files) {
      unawaited(_remove(file));
    }
    _files.clear();
    _images.clear();
    _prepared.clear();
    super.dispose();
  }
}

class EditorPresetThumbnail extends StatefulWidget {
  const EditorPresetThumbnail({
    super.key,
    required this.catalog,
    required this.preset,
    required this.recipe,
  });
  final EditorPresets catalog;
  final Preset? preset;
  final Json recipe;
  @override
  State<EditorPresetThumbnail> createState() => _EditorPresetThumbnailState();
}

class _EditorPresetThumbnailState extends State<EditorPresetThumbnail> {
  late Future<String> image = widget.catalog.thumbnail(
    widget.preset,
    widget.recipe,
  );
  late String signature = jsonEncode(widget.recipe);
  @override
  void didUpdateWidget(EditorPresetThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = jsonEncode(widget.recipe);
    if (oldWidget.catalog != widget.catalog ||
        oldWidget.preset != widget.preset ||
        signature != next) {
      signature = next;
      image = widget.catalog.thumbnail(widget.preset, widget.recipe);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: image,
    builder: (context, result) {
      if (result.hasData) {
        return Image.file(
          File(result.data!),
          width: 68,
          fit: BoxFit.cover,
          cacheWidth: 160,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.broken_image_outlined, color: Colors.white54),
        );
      }
      return Center(
        child: result.hasError
            ? IconButton(
                tooltip: '重试滤镜预览',
                icon: const Icon(Icons.refresh, color: Colors.white54),
                onPressed: () => setState(() {
                  widget.catalog.retryThumbnails();
                  image = widget.catalog.thumbnail(
                    widget.preset,
                    widget.recipe,
                  );
                }),
              )
            : const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5),
              ),
      );
    },
  );
}
