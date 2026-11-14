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
    this.key, {
    this.loan,
  });
  final String path, sha, token, key;
  final int width, height;
  final _DetailDocumentLoan? loan;
}

class _DetailDocumentLoan {
  _DetailDocumentLoan(this._release);
  VoidCallback? _release;
  int _readers = 0;
  bool _retired = false;
  bool retainRead() {
    if (_retired) return false;
    _readers++;
    return true;
  }

  void releaseRead() {
    assert(_readers > 0);
    _readers--;
    _releaseIfUnused();
  }

  void retire() {
    _retired = true;
    _releaseIfUnused();
  }

  void _releaseIfUnused() {
    if (!_retired || _readers != 0) return;
    final release = _release;
    _release = null;
    release?.call();
  }
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

class _DetailReplacement {
  _DetailReplacement(this.previous, this.next, this.generation);
  final _DetailConfiguration previous, next;
  final int generation;
  final result = Completer<bool>();
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

/// Single-consumption, same-profile pixels for an editor's child workspace.
/// The image handle is independent. A full document, when present, remains
/// owned by its original controller until this handoff/borrower releases it.
class EditingDetailHandoff {
  EditingDetailHandoff._(
    this._owner,
    this._sourcePath,
    this._root,
    this._configuration,
    this._tile,
    this._image,
    this._document,
    this._viewportRegion,
    this._requestedRegion,
  );
  final String _owner, _sourcePath, _root;
  final _DetailConfiguration _configuration;
  final EditingDetailTile _tile;
  final Rect? _viewportRegion, _requestedRegion;
  ui.Image? _image;
  _DetailDocument? _document;

  EditingDetailHandoff? _take() {
    if (_image == null) return null;
    final result = EditingDetailHandoff._(
      _owner,
      _sourcePath,
      _root,
      _configuration,
      _tile,
      _image,
      _document,
      _viewportRegion,
      _requestedRegion,
    );
    _image = null;
    _document = null;
    return result;
  }

  /// Safe after adoption: consumed resources belong to the receiving controller.
  void dispose() {
    final image = _image, document = _document;
    _image = null;
    _document = null;
    image?.dispose();
    document?.loan?.retire();
  }
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
  _DetailReplacement? _replacement;
  EditingDetailHandoff? _pendingHandoff;
  Rect? _tileViewportRegion, _tileRequestedRegion;
  Timer? _timer, _replacementGuard;
  String? _job, _error, _inspectedSha, _tileConfigurationKey;
  bool _disposed = false, _enabled = true, _pumping = false, _ready = false;
  bool _loading = false, _cancelRequested = false;
  int _generation = 0,
      _viewportSerial = 0,
      _jobSerial = 0,
      _installationEpoch = 0;
  Future<void>? _pumpFuture;
  final _owned = <String>{}, _retired = <String>{}, _deleting = <String>{};
  final _leases = <String, int>{};
  final _deleteDone = <String, Completer<void>>{};

  EditingDetailTile? get tile => _current && _enabled ? _tile : null;
  bool get loading => _current && _enabled && _loading;
  String? get error => _current ? _error : null;
  bool get hasDetail => tile != null;
  int get ownedFileCount => _owned.length;
  bool get enabled => _enabled;
  bool get replacementPending => _replacement != null;
  bool get handoffPending => _pendingHandoff != null;
  bool get _current => !_disposed && isCurrent();

  /// Capture independent image handles without pausing this controller.
  /// Only locally owned full files can be lent, so loans cannot form a cycle.
  EditingDetailHandoff? captureHandoff() {
    final config = _configuration, shown = tile;
    if (replacementPending ||
        !_enabled ||
        !_current ||
        config == null ||
        shown == null ||
        _tileConfigurationKey != config.key ||
        shown.revision != config.revision ||
        shown.frameIdentity != config.frameIdentity ||
        !_shaPattern.hasMatch(shown.sourceSha) ||
        (config.expectedSha.isNotEmpty &&
            config.expectedSha != shown.sourceSha)) {
      return null;
    }
    final image = shown.image.clone();
    _DetailDocument? borrowed;
    final document = _document;
    if (document != null &&
        document.loan == null &&
        document.key == config.key &&
        document.sha == shown.sourceSha &&
        _owned.contains(document.path) &&
        !_retired.contains(document.path) &&
        !_deleting.contains(document.path) &&
        File(document.path).existsSync()) {
      final path = document.path;
      _lease(path);
      borrowed = _DetailDocument(
        path,
        document.sha,
        document.token,
        document.width,
        document.height,
        document.key,
        loan: _DetailDocumentLoan(() => _unlease(path)),
      );
    }
    return EditingDetailHandoff._(
      owner,
      p.normalize(sourcePath),
      p.normalize(core.root),
      config,
      shown,
      image,
      borrowed,
      _tileViewportRegion,
      _tileRequestedRegion,
    );
  }

  bool _matchesHandoff(EditingDetailHandoff handoff) {
    final config = _configuration, image = handoff._image;
    return _current &&
        _enabled &&
        !replacementPending &&
        config != null &&
        image != null &&
        handoff._owner == owner &&
        p.equals(handoff._sourcePath, p.normalize(sourcePath)) &&
        p.equals(handoff._root, p.normalize(core.root)) &&
        handoff._configuration.key == config.key &&
        handoff._configuration.expectedSha == config.expectedSha &&
        handoff._configuration.outputSize == config.outputSize &&
        (config.expectedSha.isEmpty ||
            config.expectedSha == handoff._tile.sourceSha) &&
        image.width == handoff._tile.width &&
        image.height == handoff._tile.height &&
        image.width <= maxTileEdge &&
        image.height <= maxTileEdge &&
        image.width * image.height <= _maximumTilePixels;
  }

  /// Consume a same-profile handoff once. When layout is not known yet the
  /// private clone waits for the first actual viewport. A same-profile tile may
  /// cover only part of that viewport; the ordinary frame remains underneath,
  /// and strict _tileCovers checks drive the remaining ROI/density upgrade.
  bool adoptHandoff(EditingDetailHandoff? handoff) {
    if (handoff == null) return false;
    if (!_matchesHandoff(handoff)) {
      handoff.dispose();
      return false;
    }
    final consumed = handoff._take()!;
    _pendingHandoff?.dispose();
    _pendingHandoff = null;
    if (_viewport == null) {
      _pendingHandoff = consumed;
      return true;
    }
    return _adoptHandoffNow(consumed);
  }

  void _adoptDocument(EditingDetailHandoff handoff) {
    final borrowed = handoff._document;
    handoff._document = null;
    if (borrowed == null) return;
    if (!_safePath(borrowed.path) ||
        !File(borrowed.path).existsSync() ||
        _deleting.contains(borrowed.path)) {
      borrowed.loan?.retire();
      return;
    }
    final current = _document;
    if (current != null &&
        current.key == borrowed.key &&
        current.sha == borrowed.sha &&
        current.width == borrowed.width &&
        current.height == borrowed.height) {
      borrowed.loan?.retire();
      return;
    }
    _retireDocument(current);
    if (_owned.contains(borrowed.path)) {
      // A return handoff can contain this controller's own still-leased file.
      // Reclaim ownership instead of borrowing from ourselves.
      _retired.remove(borrowed.path);
      _document = _DetailDocument(
        borrowed.path,
        borrowed.sha,
        borrowed.token,
        borrowed.width,
        borrowed.height,
        borrowed.key,
      );
      borrowed.loan?.retire();
    } else {
      _document = borrowed;
    }
  }

  bool _adoptHandoffNow(EditingDetailHandoff handoff) {
    if (!_matchesHandoff(handoff)) {
      handoff.dispose();
      return false;
    }
    // Retire work started before this explicit same-profile cache transfer.
    // Its late full result must not overwrite the borrowed document/lease.
    _generation++;
    _installationEpoch++;
    _timer?.cancel();
    _ready = false;
    _cancel();
    _adoptDocument(handoff);
    final shown = handoff._tile;
    final old = _tile, config = _configuration!;
    _tile = EditingDetailTile(
      image: handoff._image!,
      path: shown.path,
      region: shown.region,
      width: shown.width,
      height: shown.height,
      sourceSize: shown.sourceSize,
      revision: config.revision,
      frameIdentity: config.frameIdentity,
      sourceSha: shown.sourceSha,
      requestedMaxEdge: shown.requestedMaxEdge,
    );
    handoff._image = null;
    _tileConfigurationKey = config.key;
    _tileViewportRegion = handoff._viewportRegion;
    _tileRequestedRegion = handoff._requestedRegion;
    _error = null;
    _changed();
    if (old != null) {
      old.image.dispose();
      _retire(old.path);
    }
    _schedule();
    return true;
  }

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

  /// Stage a frozen frame while its caller continues displaying the old frame.
  /// A true completion precedes the tile notification in the same event turn,
  /// so an awaiting parent can commit its already-decoded base frame before the
  /// next paint. Ordinary [configure] never opts in to holding previous pixels.
  Future<bool> prepareReplacement({
    required Json recipe,
    required int revision,
    required String frameIdentity,
    required Size outputSize,
    String expectedSourceSha = '',
    String? viewMode,
  }) {
    if (_disposed) return Future<bool>.value(false);
    if (!_current) {
      invalidate();
      return Future<bool>.value(false);
    }
    final shown = tile, previous = _configuration, viewport = _viewport;
    if (!_enabled || shown == null || previous == null || viewport == null) {
      return Future<bool>.value(false);
    }
    final sha = expectedSourceSha.isEmpty ? shown.sourceSha : expectedSourceSha;
    if (!_validSize(outputSize) ||
        frameIdentity.isEmpty ||
        !_shaPattern.hasMatch(sha) ||
        sha != shown.sourceSha) {
      invalidate();
      return Future<bool>.value(false);
    }
    late final _DetailConfiguration next;
    try {
      final raw = _rawExtensions.contains(
        p.extension(sourcePath).toLowerCase(),
      );
      next = _DetailConfiguration(
        operation: raw ? 'media.rawDetail' : 'media.detailRender',
        payload: object(
          jsonDecode(
            jsonEncode({
              'recipe': recipe,
              'viewMode': ?viewMode,
              if (raw) 'settings': <String, dynamic>{},
            }),
          ),
        ),
        revision: revision,
        frameIdentity: frameIdentity,
        outputSize: outputSize,
        expectedSha: sha,
      );
    } catch (_) {
      invalidate();
      return Future<bool>.value(false);
    }
    if (!_requiresDetail(next, viewport)) return Future<bool>.value(false);
    // A newer explicit stage may supersede a still-held target, but its base
    // remains the last accepted frame rather than the abandoned target.
    _finishReplacement(false, clearPrevious: false);
    final baseline = _configuration!;
    _applyConfiguration(next, holdPrevious: true);
    final replacement = _replacement = _DetailReplacement(
      baseline,
      next,
      _generation,
    );
    // isCurrent is intentionally a callback, not a Listenable. A held native
    // job must still release the future promptly if the owner/page disappears.
    _replacementGuard = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!_current) invalidate();
    });
    return replacement.result.future;
  }

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
    _applyConfiguration(next);
  }

  void _applyConfiguration(
    _DetailConfiguration next, {
    bool holdPrevious = false,
  }) {
    final deferred = _pendingHandoff;
    if (deferred != null &&
        (deferred._configuration.key != next.key ||
            deferred._configuration.expectedSha != next.expectedSha ||
            deferred._configuration.outputSize != next.outputSize)) {
      _clearPendingHandoff();
    }
    if (!holdPrevious) _finishReplacement(false);
    final old = _configuration;
    _configuration = next;
    if (old?.key != next.key) {
      _generation++;
      _installationEpoch++;
      _cancel();
      if (!holdPrevious) _clearTile();
      final previous = _document;
      _document = null;
      _retireDocument(previous);
    } else if (old?.revision != next.revision ||
        old?.frameIdentity != next.frameIdentity ||
        old?.outputSize != next.outputSize) {
      // A same-recipe full file is reusable, but an old frame cannot install a tile.
      _viewportSerial++;
      _installationEpoch++;
      if (!holdPrevious) _clearTile();
    }
    _error = null;
    _schedule();
  }

  /// Hosts pause during active scalar/brush work without falsifying their zoom.
  void setEnabled(bool value) {
    if (_disposed || _enabled == value) return;
    _enabled = value;
    if (!value) {
      _clearPendingHandoff();
      _finishReplacement(false);
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
      _clearPendingHandoff();
      _finishReplacement(false);
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
    final deferred = _pendingHandoff;
    if (deferred != null) {
      _pendingHandoff = null;
      _adoptHandoffNow(deferred);
      return;
    }
    if (!_needsDetail) {
      _finishReplacement(false);
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
    return _requiresDetail(config, viewport);
  }

  bool _requiresDetail(_DetailConfiguration config, _DetailViewport viewport) {
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
    if (!_needsDetail) {
      _finishReplacement(false);
      return;
    }
    _timer = Timer(debounce, () {
      _timer = null;
      if (!_needsDetail) {
        _finishReplacement(false);
        return;
      }
      _ready = true;
      if (!_pumping) _pumpFuture = _pump();
    });
  }

  /// Useful when closing an editor; no new work is started by this getter.
  Future<void> get pending => _pumpFuture ?? Future<void>.value();

  bool _isReplacement(_DetailConfiguration config, int generation) {
    final replacement = _replacement;
    return replacement != null &&
        replacement.generation == generation &&
        replacement.next.key == config.key &&
        replacement.next.revision == config.revision &&
        replacement.next.frameIdentity == config.frameIdentity;
  }

  void _finishReplacement(
    bool accepted, {
    bool clearPrevious = true,
    bool notify = true,
  }) {
    final replacement = _replacement;
    if (replacement == null) return;
    _replacement = null;
    _replacementGuard?.cancel();
    _replacementGuard = null;
    if (!accepted) {
      _timer?.cancel();
      _ready = false;
      _generation++;
      _installationEpoch++;
      _viewportSerial++;
      _cancel();
      _configuration = replacement.previous;
      final abandoned = _document;
      if (abandoned != null && abandoned.key != replacement.previous.key) {
        _document = null;
        _retireDocument(abandoned);
      }
      if (clearPrevious) _clearTile(notify: notify);
    }
    replacement.result.complete(accepted);
  }

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
            if (_isReplacement(config, generation)) _finishReplacement(false);
            continue;
          }
          final viewport = _viewport!;
          final request = _requestedRegion(viewport, document);
          if (_tileCovers(latest, viewport, request)) {
            if (_isReplacement(config, generation)) _finishReplacement(true);
            continue;
          }
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
            if (_isReplacement(config, generation)) _finishReplacement(false);
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
    final previous = _document;
    _document = document;
    if (previous != null && previous.path != document.path) {
      _retireDocument(previous);
    }
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
        _tileConfigurationKey == config.key &&
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
    final loan = document.loan;
    if (loan == null) {
      _lease(document.path);
    } else if (!loan.retainRead()) {
      throw const AppFailure('借用的细节文件已释放。');
    }
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
      if (loan == null) {
        _unlease(document.path);
      } else {
        loan.releaseRead();
      }
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
      _tileConfigurationKey = config.key;
      _error = null;
      if (_isReplacement(config, generation)) _finishReplacement(true);
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
  void _retireDocument(_DetailDocument? document) {
    if (document == null) return;
    final loan = document.loan;
    if (loan == null) {
      _retire(document.path);
    } else {
      loan.retire();
    }
  }

  void _clearPendingHandoff() {
    _pendingHandoff?.dispose();
    _pendingHandoff = null;
  }

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
    final pending = _deleteDone[file];
    if (pending != null) {
      await pending.future;
      return;
    }
    if (!_owned.contains(file) ||
        !_safePath(file) ||
        (_leases[file] ?? 0) > 0 ||
        !_deleting.add(file)) {
      return;
    }
    final done = Completer<void>();
    _deleteDone[file] = done;
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
      _deleteDone.remove(file);
      done.complete();
    }
  }

  Future<void> _collectRetired() async {
    for (final file in _retired.toList()) {
      await _remove(file);
    }
  }

  void _clearTile({bool notify = true}) {
    final old = _tile;
    _tile = null;
    _tileViewportRegion = null;
    _tileRequestedRegion = null;
    _tileConfigurationKey = null;
    if (old != null) {
      if (notify) _changed();
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
    _clearPendingHandoff();
    _finishReplacement(false);
    _timer?.cancel();
    _ready = false;
    _generation++;
    _installationEpoch++;
    _viewportSerial++;
    _configuration = null;
    _inspectedSha = null;
    _cancel();
    _clearTile();
    final full = _document;
    _document = null;
    _retireDocument(full);
    _setLoading(false);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _clearPendingHandoff();
    _finishReplacement(false, notify: false);
    _disposed = true;
    _timer?.cancel();
    _replacementGuard?.cancel();
    _ready = false;
    _generation++;
    _installationEpoch++;
    _viewportSerial++;
    _configuration = null;
    _cancel();
    final shown = _tile;
    _tile = null;
    shown?.image.dispose();
    final document = _document;
    _document = null;
    _retireDocument(document);
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
