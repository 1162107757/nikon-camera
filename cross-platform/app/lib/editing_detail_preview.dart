import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';

/// The visible part of an image, expressed in that image's own 0..1 plane.
/// Gesture/brush coordinates and the host's transformation are never changed.
Rect editingDetailVisibleRegion(Rect imageFrame, Rect viewportClip) {
  if (!_finiteRect(imageFrame) ||
      !_finiteRect(viewportClip) ||
      imageFrame.isEmpty) {
    return Rect.zero;
  }
  final visible = imageFrame.intersect(viewportClip);
  if (visible.isEmpty) return Rect.zero;
  return _unitRect(
    Rect.fromLTRB(
      (visible.left - imageFrame.left) / imageFrame.width,
      (visible.top - imageFrame.top) / imageFrame.height,
      (visible.right - imageFrame.left) / imageFrame.width,
      (visible.bottom - imageFrame.top) / imageFrame.height,
    ),
  );
}

bool _finiteRect(Rect value) =>
    value.left.isFinite &&
    value.top.isFinite &&
    value.right.isFinite &&
    value.bottom.isFinite;

Rect _unitRect(Rect value) {
  if (!_finiteRect(value) || value.isEmpty) return Rect.zero;
  final clipped = value.intersect(const Rect.fromLTWH(0, 0, 1, 1));
  return clipped.isEmpty ? Rect.zero : clipped;
}

Object? _canonicalDetailValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonicalDetailValue(value[key])};
  }
  if (value is List) return value.map(_canonicalDetailValue).toList();
  return value;
}

class _DetailConfiguration {
  _DetailConfiguration({
    required this.operation,
    required this.payload,
    required this.revision,
    required this.frameIdentity,
    required this.outputSize,
    required this.expectedSha,
  }) : key = jsonEncode([
         operation,
         expectedSha,
         // A 640/1280 preview of the same composition shares its full file.
         (outputSize.aspectRatio * 100).round(),
         _canonicalDetailValue(payload),
       ]);
  final String operation, frameIdentity, expectedSha, key;
  final Json payload;
  final int revision;
  final Size outputSize;
}

class _DetailViewport {
  const _DetailViewport(this.region, this.zoom, this.pixels, this.serial);
  final Rect region;
  final double zoom;
  final Size pixels;
  final int serial;
}

class _DetailDocument {
  const _DetailDocument(
    this.path,
    this.sha,
    this.token,
    this.width,
    this.height,
    this.key,
  );
  final String path, sha, token, key;
  final int width, height;
}

class _DetailTileRequest {
  const _DetailTileRequest(
    this.region,
    this.maxEdge,
    this.densityX,
    this.densityY,
    this.visibleDensity,
  );
  final Rect region;
  final int maxEdge;
  final double densityX, densityY, visibleDensity;
}

/// A predecoded, bounded tile. The controller owns [image]; callers must not
/// dispose it. RawImage clones it for the lifetime of its RenderImage.
class EditingDetailTile {
  const EditingDetailTile({
    required this.image,
    required this.path,
    required this.region,
    required this.width,
    required this.height,
    required this.sourceSize,
    required this.revision,
    required this.frameIdentity,
    required this.sourceSha,
    required this.requestedMaxEdge,
  });
  final ui.Image image;
  final String path, frameIdentity, sourceSha;
  final Rect region;
  final Size sourceSize;
  final int width, height, revision, requestedMaxEdge;
}

/// Read-only, latest-only detail for existing editing canvases.
///
/// Only detail tiles (<=2048, <=4MP) are decoded by Flutter. Full-resolution
/// files remain native-owned render outputs on disk; viewport motion reuses
/// their token instead of rendering the whole photograph again. This notifier
/// never writes a draft/version or drives the ordinary preview's progress UI.
class EditingDetailPreviewController extends ChangeNotifier {
  EditingDetailPreviewController({
    required this.core,
    required this.owner,
    required this.sourcePath,
    required this.isCurrent,
    int maxTileEdge = 1536,
    this.debounce = const Duration(milliseconds: 120),
  }) : maxTileEdge = maxTileEdge.clamp(256, 2048);

  final HueviaCore core;
  final String owner, sourcePath;
  final bool Function() isCurrent;
  final int maxTileEdge;
  final Duration debounce;
  static const _maximumTilePixels = 4 * 1024 * 1024;
  static const _maximumEncodedTileBytes = 32 * 1024 * 1024;
  static const _maximumOwnedFiles = 4;
  static final _shaPattern = RegExp(r'^[0-9a-f]{64}$', caseSensitive: false);
  static final _filePattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(jpg|jpeg|png)$',
    caseSensitive: false,
  );

  _DetailConfiguration? _configuration;
  _DetailViewport? _viewport;
  _DetailDocument? _document;
  EditingDetailTile? _tile;
  Rect? _tileViewportRegion, _tileRequestedRegion;
  Timer? _timer;
  String? _job, _error, _inspectedSha;
  bool _disposed = false, _enabled = true, _pumping = false, _ready = false;
  bool _loading = false, _cancelRequested = false;
  int _generation = 0,
      _viewportSerial = 0,
      _jobSerial = 0,
      _installationEpoch = 0;
  Future<void>? _pumpFuture;
  final _owned = <String>{}, _retired = <String>{}, _deleting = <String>{};
  final _leases = <String, int>{};

  EditingDetailTile? get tile => _current && _enabled ? _tile : null;
  bool get loading => _current && _enabled && _loading;
  String? get error => _current ? _error : null;
  bool get hasDetail => tile != null;
  int get ownedFileCount => _owned.length;
  bool get enabled => _enabled;
  bool get _current => !_disposed && isCurrent();

  /// Frozen recipe for the frame actually displayed, not the next live value.
  void configure({
    required Json recipe,
    required int revision,
    required String frameIdentity,
    required Size outputSize,
    String expectedSourceSha = '',
    String? viewMode,
  }) => _configure(
    _rawExtensions.contains(p.extension(sourcePath).toLowerCase())
        ? 'media.rawDetail'
        : 'media.detailRender',
    {
      'recipe': recipe,
      'viewMode': ?viewMode,
      if (_rawExtensions.contains(p.extension(sourcePath).toLowerCase()))
        'settings': <String, dynamic>{},
    },
    revision,
    frameIdentity,
    outputSize,
    expectedSourceSha,
  );

  /// RAW reference is the existing structured JPEG/reference matching DTO.
  void configureRaw({
    required Json settings,
    Json? reference,
    required int revision,
    required String frameIdentity,
    required Size outputSize,
    String expectedSourceSha = '',
  }) => _configure(
    'media.rawDetail',
    {'settings': settings, 'reference': ?reference},
    revision,
    frameIdentity,
    outputSize,
    expectedSourceSha,
  );

  void _configure(
    String operation,
    Json payload,
    int revision,
    String frame,
    Size size,
    String sha,
  ) {
    if (_disposed) return;
    if (!_current || !_validSize(size) || frame.isEmpty) {
      invalidate();
      return;
    }
    late final _DetailConfiguration next;
    try {
      next = _DetailConfiguration(
        operation: operation,
        payload: object(jsonDecode(jsonEncode(payload))),
        revision: revision,
        frameIdentity: frame,
        outputSize: size,
        expectedSha: sha,
      );
    } catch (_) {
      invalidate();
      _error = '细节预览参数无效。';
      _changed();
      return;
    }
    final old = _configuration;
    _configuration = next;
    if (old?.key != next.key) {
      _generation++;
      _installationEpoch++;
      _cancel();
      _clearTile();
      final previous = _document;
      _document = null;
      if (previous != null) _retire(previous.path);
    } else if (old?.revision != revision ||
        old?.frameIdentity != frame ||
        old?.outputSize != size) {
      // A same-recipe full file is reusable, but an old frame cannot install a tile.
      _viewportSerial++;
      _installationEpoch++;
      _clearTile();
    }
    _error = null;
    _schedule();
  }

  /// Hosts pause during active scalar/brush work without falsifying their zoom.
  void setEnabled(bool value) {
    if (_disposed || _enabled == value) return;
    _enabled = value;
    if (!value) {
      _timer?.cancel();
      _ready = false;
      _viewportSerial++;
      _installationEpoch++;
      _cancel();
      _clearTile();
      _setLoading(false);
    } else {
      _schedule();
    }
  }

  /// [viewportPixelSize] is the visible photo area in physical pixels, excluding
  /// letterboxing. [visibleRegion] is normalized in that exact photo plane.
  void setViewport({
    required Rect visibleRegion,
    required double zoom,
    required Size viewportPixelSize,
  }) {
    if (_disposed) return;
    final region = _unitRect(visibleRegion);
    if (!_current ||
        region.isEmpty ||
        !zoom.isFinite ||
        zoom <= 0 ||
        !_validSize(viewportPixelSize)) {
      _viewport = null;
      _viewportSerial++;
      _timer?.cancel();
      _ready = false;
      _cancel();
      _clearTile();
      _setLoading(false);
      return;
    }
    final old = _viewport;
    if (old?.region == region &&
        old?.zoom == zoom &&
        old?.pixels == viewportPixelSize) {
      return;
    }
    _viewport = _DetailViewport(
      region,
      zoom,
      viewportPixelSize,
      ++_viewportSerial,
    );
    if (!_needsDetail) {
      _timer?.cancel();
      _ready = false;
      _cancel();
      _clearTile();
      _setLoading(false);
      return;
    }
    _schedule();
  }

  bool get _needsDetail {
    final config = _configuration, viewport = _viewport;
    if (!_current || !_enabled || config == null || viewport == null) {
      return false;
    }
    final visiblePixels = Size(
      config.outputSize.width * viewport.region.width,
      config.outputSize.height * viewport.region.height,
    );
    return viewport.zoom > 1.01 ||
        viewport.pixels.width / visiblePixels.width > 1.1 ||
        viewport.pixels.height / visiblePixels.height > 1.1;
  }

  void _schedule() {
    _timer?.cancel();
    _ready = false;
    if (!_needsDetail) return;
    _timer = Timer(debounce, () {
      _timer = null;
      _ready = true;
      if (!_pumping) _pumpFuture = _pump();
    });
  }

  /// Useful when closing an editor; no new work is started by this getter.
  Future<void> get pending => _pumpFuture ?? Future<void>.value();

  Future<void> _pump() async {
    if (_pumping || !_ready || !_needsDetail) return;
    _pumping = true;
    try {
      while (_ready && _needsDetail) {
        _ready = false;
        final config = _configuration!;
        final generation = _generation;
        _setLoading(true);
        try {
          await _collectRetired();
          if (_owned.length >= _maximumOwnedFiles) {
            throw const AppFailure('临时细节文件仍在释放，继续显示普通预览。');
          }
          var document = _document;
          if (document == null || document.key != config.key) {
            document = await _renderDocument(config, generation);
            if (document == null) continue;
          }
          if (!_matchesContent(config, generation) || !_needsDetail) continue;
          final latest = _configuration!;
          // A source no larger than the ordinary raster offers no new pixels.
          if (document.width <= latest.outputSize.width &&
              document.height <= latest.outputSize.height) {
            continue;
          }
          final viewport = _viewport!;
          final request = _requestedRegion(viewport, document);
          if (_tileCovers(latest, viewport, request)) continue;
          await _renderTile(
            document,
            latest,
            generation,
            viewport,
            request,
            _installationEpoch,
          );
        } catch (failure) {
          if (_matchesContent(config, generation)) {
            _error = '$failure';
            _changed();
          }
        } finally {
          _setLoading(false);
        }
      }
    } finally {
      _pumping = false;
      if (_ready && _needsDetail) _pumpFuture = _pump();
    }
  }

  bool _matchesContent(_DetailConfiguration config, int generation) =>
      _current &&
      generation == _generation &&
      config.key == _configuration?.key;

  Future<Json> _call(String operation, Json payload) async {
    final job =
        'editing-detail-${DateTime.now().microsecondsSinceEpoch}-${_jobSerial++}';
    _job = job;
    _cancelRequested = false;
    try {
      return await core.call(operation, payload, job);
    } finally {
      if (_job == job) {
        _job = null;
        _cancelRequested = false;
      }
    }
  }

  Future<_DetailDocument?> _renderDocument(
    _DetailConfiguration config,
    int generation,
  ) async {
    var sha = config.expectedSha;
    if (sha.isEmpty) {
      sha = _inspectedSha ?? '';
      if (sha.isEmpty) {
        final source = await _call('source.inspect', {
          'owner': owner,
          'path': sourcePath,
        });
        sha = source['sourceSha'] as String? ?? '';
        if (!_matchesContent(config, generation)) return null;
        if (_shaPattern.hasMatch(sha)) _inspectedSha = sha;
      }
    }
    if (!_shaPattern.hasMatch(sha)) {
      throw const AppFailure('原图校验信息尚未就绪，继续显示普通预览。');
    }
    if (!_matchesContent(config, generation) || !_needsDetail) return null;
    final result = await _call(config.operation, {
      ...config.payload,
      'owner': owner,
      'path': sourcePath,
      'expectedSourceSha': sha,
    });
    final file = _claim(result);
    final width = _dimension(result['width']),
        height = _dimension(result['height']);
    final token = result['detailToken'];
    if (file == null ||
        result['sourceSha'] != sha ||
        result['fullResolution'] != true ||
        token is! String ||
        token.isEmpty ||
        width == null ||
        height == null) {
      if (file != null) _retire(file);
      throw const AppFailure('未取得有效的只读全尺寸细节文件。');
    }
    if (!_matchesContent(config, generation)) {
      _retire(file);
      return null;
    }
    final size = _configuration!.outputSize;
    final tolerance = 2 / math.min(size.width, size.height) + .002;
    if (((width / height) / size.aspectRatio - 1).abs() > tolerance) {
      _retire(file);
      throw const AppFailure('细节构图与当前照片不一致，继续显示普通预览。');
    }
    final document = _DetailDocument(
      file,
      sha,
      token,
      width,
      height,
      config.key,
    );
    _document = document;
    return document;
  }

  static const _rawExtensions = {
    '.nef',
    '.nrw',
    '.arw',
    '.cr2',
    '.cr3',
    '.dng',
    '.raf',
    '.rw2',
    '.orf',
    '.pef',
    '.srw',
  };

  _DetailTileRequest _requestedRegion(
    _DetailViewport viewport,
    _DetailDocument document,
  ) {
    _DetailTileRequest? best;
    for (final padding in const [.12, .06, 0.0]) {
      final region = _unitRect(
        Rect.fromLTRB(
          viewport.region.left - viewport.region.width * padding,
          viewport.region.top - viewport.region.height * padding,
          viewport.region.right + viewport.region.width * padding,
          viewport.region.bottom + viewport.region.height * padding,
        ),
      );
      // Match SharedDetailTiles.Plan's pixel rounding and power-of-two decode.
      // Spending only a fit-sized edge can halve the available source detail;
      // use the bounded tile budget and reduce overscan at a sample boundary.
      final left = (region.left * document.width).floor(),
          top = (region.top * document.height).floor(),
          right = (region.right * document.width).ceil(),
          bottom = (region.bottom * document.height).ceil();
      final width = right - left, height = bottom - top;
      var sample = 1;
      while ((math.max(width, height) + sample - 1) ~/ sample > maxTileEdge) {
        sample *= 2;
      }
      final densityX =
              ((width + sample - 1) ~/ sample) * document.width / width,
          densityY =
              ((height + sample - 1) ~/ sample) * document.height / height;
      final visibleDensity = math.min(
        densityX * viewport.region.width / viewport.pixels.width,
        densityY * viewport.region.height / viewport.pixels.height,
      );
      final request = _DetailTileRequest(
        region,
        maxTileEdge,
        densityX,
        densityY,
        visibleDensity,
      );
      // Prefer pan overscan only while it can still fill the physical screen.
      // If even source pixels are insufficient, retain the densest real pixels.
      if (visibleDensity >= 1 - 1e-9) return request;
      if (best == null || visibleDensity > best.visibleDensity + 1e-9) {
        best = request;
      }
    }
    return best!;
  }

  bool _tileCovers(
    _DetailConfiguration config,
    _DetailViewport viewport,
    _DetailTileRequest request,
  ) {
    final current = _tile;
    final document = _document;
    if (!(current != null &&
        document != null &&
        current.revision == config.revision &&
        current.frameIdentity == config.frameIdentity &&
        current.region.left <= viewport.region.left &&
        current.region.top <= viewport.region.top &&
        current.region.right >= viewport.region.right &&
        current.region.bottom >= viewport.region.bottom)) {
      return false;
    }
    // Identical requests have already reached the native decoder's bounded
    // result. Do not loop trying to exceed a source/decoder ceiling.
    if (_tileViewportRegion == viewport.region &&
        _tileRequestedRegion == request.region &&
        current.requestedMaxEdge >= request.maxEdge) {
      return true;
    }
    // Containment alone is insufficient: zooming into a fit tile must acquire
    // denser source pixels. At sample=1 an already-full-pixel tile is reusable.
    final densityX = current.width / current.region.width;
    final densityY = current.height / current.region.height;
    return densityX + 2 / current.region.width >= request.densityX &&
        densityY + 2 / current.region.height >= request.densityY;
  }

  Future<void> _renderTile(
    _DetailDocument document,
    _DetailConfiguration config,
    int generation,
    _DetailViewport viewport,
    _DetailTileRequest request,
    int installationEpoch,
  ) async {
    final requested = request.region;
    _lease(document.path);
    late final Json result;
    try {
      result = await _call('media.detailTile', {
        'owner': owner,
        'path': document.path,
        'detailToken': document.token,
        'expectedSourceSha': document.sha,
        'maxEdge': request.maxEdge,
        'region': {
          'left': requested.left,
          'top': requested.top,
          'right': requested.right,
          'bottom': requested.bottom,
        },
      });
    } finally {
      _unlease(document.path);
    }
    final file = _claim(result);
    ui.Image? decoded;
    var installed = false;
    try {
      final width = _dimension(result['pixelWidth'] ?? result['width']);
      final height = _dimension(result['pixelHeight'] ?? result['height']);
      final sourceWidth = _dimension(result['sourceWidth']),
          sourceHeight = _dimension(result['sourceHeight']);
      final region = _returnedRegion(result['region']);
      if (file == null ||
          result['sourceSha'] != document.sha ||
          result['detailToken'] != document.token ||
          width == null ||
          height == null ||
          width > request.maxEdge ||
          height > request.maxEdge ||
          width * height > _maximumTilePixels ||
          sourceWidth != document.width ||
          sourceHeight != document.height ||
          region == null ||
          region.left > requested.left + 1 / document.width ||
          region.top > requested.top + 1 / document.height ||
          region.right < requested.right - 1 / document.width ||
          region.bottom < requested.bottom - 1 / document.height) {
        throw const AppFailure('未取得有效的可见区域细节。');
      }
      if (!_canInstall(config, generation, viewport, installationEpoch)) return;
      _lease(file);
      try {
        decoded = await _decodeTile(file, width, height);
      } finally {
        _unlease(file);
      }
      if (!_canInstall(config, generation, viewport, installationEpoch)) return;
      final old = _tile;
      _tile = EditingDetailTile(
        image: decoded,
        path: file,
        region: region,
        width: width,
        height: height,
        sourceSize: Size(document.width.toDouble(), document.height.toDouble()),
        revision: config.revision,
        frameIdentity: config.frameIdentity,
        sourceSha: document.sha,
        requestedMaxEdge: request.maxEdge,
      );
      installed = true;
      _tileViewportRegion = viewport.region;
      _tileRequestedRegion = request.region;
      _error = null;
      _changed();
      // RawImage/RenderImage own their clone until the replacement is painted.
      if (old != null) {
        old.image.dispose();
        _retire(old.path);
      }
    } finally {
      if (!installed) {
        decoded?.dispose();
        if (file != null) _retire(file);
      }
    }
  }

  bool _canInstall(
    _DetailConfiguration config,
    int generation,
    _DetailViewport viewport,
    int installationEpoch,
  ) =>
      _matchesContent(config, generation) &&
      installationEpoch == _installationEpoch &&
      _needsDetail &&
      config.revision == _configuration?.revision &&
      config.frameIdentity == _configuration?.frameIdentity &&
      viewport.serial == _viewport?.serial;

  Future<ui.Image> _decodeTile(String path, int width, int height) async {
    final file = File(path);
    if (await file.length() > _maximumEncodedTileBytes) {
      throw const AppFailure('细节图块超出内存预算。');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      await file.readAsBytes(),
    );
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width != width ||
          descriptor.height != height ||
          width > maxTileEdge ||
          height > maxTileEdge ||
          width * height > _maximumTilePixels) {
        throw const AppFailure('细节图块尺寸与只读回执不一致。');
      }
      codec = await descriptor.instantiateCodec(
        targetWidth: width,
        targetHeight: height,
      );
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }

  int? _dimension(Object? value) => value is int && value > 0 ? value : null;

  Rect? _returnedRegion(Object? value) {
    if (value is! Map) return null;
    final map = object(value);
    if (['left', 'top', 'right', 'bottom'].any((key) => map[key] is! num)) {
      return null;
    }
    final rect = Rect.fromLTRB(
      (map['left'] as num).toDouble(),
      (map['top'] as num).toDouble(),
      (map['right'] as num).toDouble(),
      (map['bottom'] as num).toDouble(),
    );
    if (!_finiteRect(rect) ||
        rect.isEmpty ||
        rect.left < 0 ||
        rect.top < 0 ||
        rect.right > 1 ||
        rect.bottom > 1) {
      return null;
    }
    return rect;
  }

  bool _safePath(String path) =>
      !p.equals(p.normalize(path), p.normalize(sourcePath)) &&
      p.isWithin(
        p.normalize(p.join(core.root, 'previews')),
        p.normalize(path),
      ) &&
      _filePattern.hasMatch(p.basename(path));

  String? _claim(Json result) {
    final file = result['path'];
    if (result['temporary'] != true ||
        file is! String ||
        !_safePath(file) ||
        _owned.contains(file) ||
        file == _configuration?.frameIdentity) {
      return null;
    }
    _owned.add(file);
    return file;
  }

  void _lease(String file) => _leases[file] = (_leases[file] ?? 0) + 1;
  void _unlease(String file) {
    final count = (_leases[file] ?? 1) - 1;
    if (count <= 0) {
      _leases.remove(file);
      if (_retired.contains(file)) unawaited(_remove(file));
    } else {
      _leases[file] = count;
    }
  }

  void _retire(String file) {
    if (!_owned.contains(file)) return;
    _retired.add(file);
    if ((_leases[file] ?? 0) == 0) unawaited(_remove(file));
  }

  Future<void> _remove(String file) async {
    if (!_owned.contains(file) ||
        !_safePath(file) ||
        (_leases[file] ?? 0) > 0 ||
        !_deleting.add(file)) {
      return;
    }
    try {
      final type = await FileSystemEntity.type(file, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        _owned.remove(file);
        _retired.remove(file);
        return;
      }
      if (type != FileSystemEntityType.file) return;
      final resolved = await File(file).resolveSymbolicLinks();
      if (!p.equals(p.normalize(file), p.normalize(resolved)) ||
          (_leases[file] ?? 0) > 0) {
        return;
      }
      await File(file).delete();
      _owned.remove(file);
      _retired.remove(file);
    } on FileSystemException {
      // Bounded: a later request retries cleanup before allocating another file.
    } finally {
      _deleting.remove(file);
    }
  }

  Future<void> _collectRetired() async {
    for (final file in _retired.toList()) {
      await _remove(file);
    }
  }

  void _clearTile() {
    final old = _tile;
    _tile = null;
    _tileViewportRegion = null;
    _tileRequestedRegion = null;
    if (old != null) {
      _changed();
      old.image.dispose();
      _retire(old.path);
    }
  }

  void _cancel() {
    final job = _job;
    if (job == null || _cancelRequested) return;
    _cancelRequested = true;
    unawaited(core.cancel(job).catchError((Object _) {}));
  }

  void _setLoading(bool value) {
    if (_disposed || _loading == value) return;
    _loading = value;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  /// Drop private pixels immediately on owner/source/page invalidation.
  void invalidate() {
    if (_disposed) return;
    _timer?.cancel();
    _ready = false;
    _generation++;
    _installationEpoch++;
    _viewportSerial++;
    _configuration = null;
    _cancel();
    _clearTile();
    final full = _document;
    _document = null;
    if (full != null) _retire(full.path);
    _setLoading(false);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _ready = false;
    _generation++;
    _installationEpoch++;
    _viewportSerial++;
    _configuration = null;
    _cancel();
    final shown = _tile;
    _tile = null;
    shown?.image.dispose();
    _document = null;
    for (final path in _owned.toList()) {
      _retire(path);
    }
    super.dispose();
  }
}

bool _validSize(Size value) =>
    value.width.isFinite &&
    value.height.isFinite &&
    value.width > 0 &&
    value.height > 0;

/// Put this in the exact image-plane Stack, above the ordinary preview and below
/// brush/face/crop overlays. It never consumes a pointer or changes the matrix.
class EditingDetailTileLayer extends StatelessWidget {
  const EditingDetailTileLayer({super.key, required this.controller});
  final EditingDetailPreviewController controller;
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final tile = controller.tile;
        if (tile == null) return const SizedBox.expand();
        return LayoutBuilder(
          builder: (context, bounds) => ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fromRect(
                  rect: Rect.fromLTRB(
                    tile.region.left * bounds.maxWidth,
                    tile.region.top * bounds.maxHeight,
                    tile.region.right * bounds.maxWidth,
                    tile.region.bottom * bounds.maxHeight,
                  ),
                  child: RawImage(
                    image: tile.image,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
