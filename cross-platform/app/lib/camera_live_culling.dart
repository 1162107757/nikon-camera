import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'album_batch.dart';
import 'domain.dart';
import 'legacy_dialog.dart';
import 'theme.dart';
import 'widgets.dart';

/// Review only the originals committed to the selected shooting project.
class CameraLiveCullingPage extends StatefulWidget {
  const CameraLiveCullingPage({
    super.key,
    required this.state,
    required this.projectId,
  });

  final AppState state;
  final String projectId;

  @override
  State<CameraLiveCullingPage> createState() => _CameraLiveCullingPageState();
}

class _CameraLiveCullingPageState extends State<CameraLiveCullingPage> {
  AppState get state => widget.state;
  late final String _owner;
  late List<Photo> _library;
  late Set<String> _stars;
  Set<String> _projectPaths = {};
  List<Photo> _photos = [];
  String? _lastReceived, _anchor, _error;
  bool _invalid = false, _loading = false, _reload = false;
  bool _starsReady = false, _savingStar = false, _starredOnly = false;

  bool get _current =>
      mounted &&
      !_invalid &&
      state.cameraLive.currentOwner == _owner &&
      state.session['logoutPending'] != true;

  List<Photo> get _starred =>
      _photos.where((photo) => _stars.contains(photo.starKey)).toList();

  @override
  void initState() {
    super.initState();
    final live = state.cameraLive;
    _owner = live.currentOwner;
    _library = state.photos;
    _stars = state.starredPhotos;
    state.addListener(_stateChanged);
    live.addListener(_received);
    _lastReceived = _latestPath;
    unawaited(_refresh());
  }

  @override
  void dispose() {
    state.removeListener(_stateChanged);
    state.cameraLive.removeListener(_received);
    super.dispose();
  }

  String? get _latestPath {
    final live = state.cameraLive;
    if (live.projectId != widget.projectId || live.owner != _owner) return null;
    return live.latestPhoto?.path;
  }

  void _received() {
    if (!_current) return;
    final latest = _latestPath;
    if (latest == null || latest == _lastReceived) return;
    _lastReceived = latest;
    unawaited(_refresh());
  }

  void _stateChanged() {
    if (_invalid) return;
    if (!_current) {
      setState(() {
        _invalid = true;
        _photos = [];
      });
      return;
    }
    if (identical(_library, state.photos) &&
        identical(_stars, state.starredPhotos)) {
      return;
    }
    setState(() {
      if (!identical(_library, state.photos)) {
        _library = state.photos;
        _filterProject();
      }
      _stars = state.starredPhotos;
    });
  }

  void _filterProject() {
    final indexed = {for (final photo in _library) photo.path: photo};
    _photos = [for (final path in _projectPaths) ?indexed[path]];
  }

  Future<void> _refresh() async {
    if (!_current) return;
    if (_loading) {
      _reload = true;
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      do {
        _reload = false;
        final value = await state.core.call('project.open', {
          'owner': _owner,
          'projectId': widget.projectId,
        });
        if (!_current) return;
        setState(() {
          _projectPaths = {
            for (final row in (value['photos'] as List).map(object))
              if (row['path'] case final String path) path,
          };
          _filterProject();
          _anchor ??= _photos.firstOrNull?.path;
          _error = null;
        });
        if (!_starsReady) {
          final result = await state.core.call('photo.stars');
          if (!_current) return;
          state.acceptPhotoStars(
            _owner,
            List<String>.from(result['keys'] as List),
          );
          _starsReady = true;
        }
      } while (_reload && _current);
    } catch (_) {
      if (_current) {
        setState(() => _error = '暂时无法读取选片记录，请刷新重试。');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleStar(Photo photo, List<Photo> visible, int index) async {
    if (!_current || !_starsReady || _savingStar) return;
    final starred = _stars.contains(photo.starKey);
    final replacement = index + 1 < visible.length
        ? visible[index + 1].path
        : index > 0
        ? visible[index - 1].path
        : null;
    setState(() => _savingStar = true);
    try {
      final result = await state.core.call('photo.star', {
        'owner': _owner,
        'path': photo.path,
        'starred': !starred,
      });
      if (!_current) return;
      // In the filtered view, removing this star advances to a nearby photo.
      if (starred && _starredOnly && (_anchor ?? photo.path) == photo.path) {
        _anchor = replacement;
      }
      state.acceptPhotoStars(_owner, List<String>.from(result['keys'] as List));
    } catch (failure) {
      if (mounted && _current) report(context, failure);
    } finally {
      if (mounted) setState(() => _savingStar = false);
    }
  }

  Future<void> _exportStarred() async {
    if (!_current || !_starsReady || _savingStar) return;
    final photos = _starred;
    if (photos.isEmpty) return;
    const limit = 100; // Existing batch export limit.
    int? start = 0;
    if (photos.length > limit) {
      start = await hueChoice<int>(
        context: context,
        title: '选择本次导出的照片',
        selected: 0,
        choices: [
          for (var index = 0; index < photos.length; index += limit)
            (
              index,
              '第 ${index + 1}–${math.min(index + limit, photos.length)} 张',
            ),
        ],
      );
    }
    if (!mounted || !_current || start == null) return;
    final batch = photos.skip(start).take(limit).toList();
    final currentPaths = _starred.map((photo) => photo.path).toSet();
    if (batch.any((photo) => !currentPaths.contains(photo.path))) {
      report(context, '选片已变化，请重新导出。');
      return;
    }
    await hueRootPage<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BatchExportPage(
          state: state,
          rows: [
            for (final photo in batch)
              {
                'id': photo.path,
                'name': photo.name,
                'raw': photo.info['raw'] == true,
              },
          ],
          phone: false,
          saveToGallery: true,
          currentEffects: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = HuePalette.of(context);
    final starred = _starred;
    final visible = _starredOnly ? starred : _photos;
    final index = math.max(
      0,
      visible.indexWhere((photo) => photo.path == _anchor),
    );
    final photo = visible.isEmpty ? null : visible[index];
    final marked = photo != null && _stars.contains(photo.starKey);
    void move(int step) {
      final next = index + step;
      if (next >= 0 && next < visible.length) {
        setState(() => _anchor = visible[next].path);
      }
    }

    return Scaffold(
      appBar: HueHeader(
        title: '拍摄选片',
        back: true,
        actions: [
          if (_current)
            IconButton(
              key: const Key('live-cull-refresh'),
              tooltip: '刷新接收记录',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: !_current
          ? const Center(child: Text('账号已改变，请重新打开拍摄项目。'))
          : SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text('全部 ${_photos.length}'),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text('已选 ${starred.length}'),
                          enabled: _starsReady,
                        ),
                      ],
                      selected: {_starredOnly},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) => setState(() {
                        _starredOnly = selection.single;
                        if (_starredOnly &&
                            !starred.any((photo) => photo.path == _anchor)) {
                          _anchor = starred.firstOrNull?.path ?? _anchor;
                        }
                      }),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Semantics(liveRegion: true, child: Text(_error!)),
                    ),
                  Expanded(
                    child: photo == null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: _loading
                                  ? const CircularProgressIndicator()
                                  : Text(
                                      _starredOnly
                                          ? '还没有标记星标的照片'
                                          : '项目收到照片后会显示在这里',
                                      textAlign: TextAlign.center,
                                    ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: _CullPreview(
                                key: ValueKey(photo.path),
                                state: state,
                                owner: _owner,
                                photo: photo,
                                onSwipe: move,
                              ),
                            ),
                          ),
                  ),
                  if (photo != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: '上一张',
                            onPressed: index == 0 ? null : () => move(-1),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Expanded(
                            child: Text(
                              '${index + 1}/${visible.length}  ·  ${photo.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: palette.secondary),
                            ),
                          ),
                          IconButton(
                            key: const Key('live-cull-star'),
                            tooltip: marked ? '取消选片星标' : '标记选片星标',
                            isSelected: marked,
                            onPressed: !_starsReady || _savingStar
                                ? null
                                : () => _toggleStar(photo, visible, index),
                            icon: const Icon(Icons.star_border_rounded),
                            selectedIcon: const Icon(Icons.star_rounded),
                          ),
                          IconButton(
                            tooltip: '下一张',
                            onPressed: index + 1 == visible.length
                                ? null
                                : () => move(1),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: FilledButton.icon(
                      key: const Key('live-cull-export'),
                      onPressed:
                          _starsReady && starred.isNotEmpty && !_savingStar
                          ? _exportStarred
                          : null,
                      icon: const Icon(Icons.download_rounded),
                      label: Text('导出已选 ${starred.length} 张'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CullPreview extends StatefulWidget {
  const _CullPreview({
    super.key,
    required this.state,
    required this.owner,
    required this.photo,
    required this.onSwipe,
  });

  final AppState state;
  final String owner;
  final Photo photo;
  final ValueChanged<int> onSwipe;

  @override
  State<_CullPreview> createState() => _CullPreviewState();
}

class _CullPreviewState extends State<_CullPreview> {
  final _transform = TransformationController();
  Offset? _tap;
  bool _zoomed = false;
  double _dragDistance = 0;
  bool get _raw => widget.photo.info['raw'] == true;
  late final Future<String> _image = _readImage();

  Future<String> _readImage() async {
    if (!_raw) return widget.photo.path;
    final state = widget.state;
    final live = state.cameraLive;
    final preview = live.latestPreviewPath;
    if (live.owner == widget.owner &&
        live.latestPhoto?.path == widget.photo.path &&
        preview != null) {
      return preview;
    }
    final result = await state.core.call('media.rawThumbnail', {
      'owner': widget.owner,
      'path': widget.photo.path,
    });
    final path = result['path'];
    if (path is! String ||
        !p.isWithin(p.join(state.core.root, 'raw-thumbnails'), path)) {
      throw const AppFailure('RAW 预览路径无效。');
    }
    return path;
  }

  @override
  void initState() {
    super.initState();
    _transform.addListener(_scaleChanged);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _scaleChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _zoom(Offset point) {
    const scale = 2.5;
    _transform.value = _zoomed
        ? Matrix4.identity()
        : (Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(
            point.dx * (1 - scale),
            point.dy * (1 - scale),
            0,
          ));
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: FutureBuilder<String>(
      future: _image,
      builder: (context, snapshot) {
        const unavailable = Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('预览暂不可用，原图已保留', style: TextStyle(color: Colors.white)),
          ),
        );
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final path = snapshot.data;
        return LayoutBuilder(
          builder: (context, bounds) {
            final center = bounds.biggest.center(Offset.zero);
            return Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTapDown: path == null
                      ? null
                      : (event) => _tap = event.localPosition,
                  onDoubleTap: path == null
                      ? null
                      : () => _zoom(_tap ?? center),
                  onHorizontalDragStart: _zoomed
                      ? null
                      : (_) => _dragDistance = 0,
                  onHorizontalDragUpdate: _zoomed
                      ? null
                      : (details) => _dragDistance += details.primaryDelta ?? 0,
                  onHorizontalDragEnd: _zoomed
                      ? null
                      : (details) {
                          final velocity = details.primaryVelocity ?? 0;
                          final movement = _dragDistance.abs() >= 48
                              ? _dragDistance
                              : velocity.abs() > 240
                              ? velocity
                              : 0;
                          if (movement != 0) {
                            widget.onSwipe(movement < 0 ? 1 : -1);
                          }
                        },
                  child: path == null
                      ? unavailable
                      : InteractiveViewer(
                          transformationController: _transform,
                          panEnabled: _zoomed,
                          maxScale: 6,
                          child: Center(
                            child: Image(
                              image: ResizeImage(
                                FileImage(File(path)),
                                width: 4096,
                                height: 4096,
                                policy: ResizeImagePolicy.fit,
                              ),
                              fit: BoxFit.contain,
                              semanticLabel: widget.photo.name,
                              errorBuilder: (_, _, _) => unavailable,
                            ),
                          ),
                        ),
                ),
                if (path != null)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      tooltip: _zoomed ? '恢复预览大小' : '放大照片预览',
                      onPressed: () => _zoom(center),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                      icon: Icon(
                        _zoomed
                            ? Icons.zoom_out_rounded
                            : Icons.zoom_in_rounded,
                      ),
                    ),
                  ),
                if (_raw && path != null)
                  const Positioned(
                    bottom: 8,
                    left: 8,
                    child: ColoredBox(
                      color: Colors.black54,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          'RAW 预览',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}
