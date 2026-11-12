import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'domain.dart';
import 'legacy_local_editor.dart';

class _LocalFrameRequest {
  const _LocalFrameRequest(
    this.sequence,
    this.key,
    this.tools,
    this.interactive,
    this.force,
  );
  final int sequence;
  final String key;
  final Json tools;
  final bool interactive;
  final bool force;
}

/// One native preview at a time, with only the newest pending tool snapshot.
/// Validation always starts from the frozen original binary, preserving opaque
/// portrait, region and patch groups without writing a draft.
class LegacyLocalPreview extends ChangeNotifier {
  LegacyLocalPreview({
    required this.core,
    required this.photo,
    required this.owner,
    required Json recipe,
    required Json localState,
    required Json initialFrame,
    required this.isCurrent,
    required this.discard,
  }) : _recipe = toolsCopy(recipe),
       _base = toolsCopy(localState),
       _state = toolsCopy(localState),
       _frame = toolsCopy(initialFrame) {
    _lastTools = toolsCopy({
      'masks': _base['masks'] ?? [],
      'clones': _base['clones'] ?? [],
    });
    _requestedKey = _acceptedKey = _key(_lastTools, false);
    _frameLocalData = _base['localData'] as String;
  }

  final HueviaCore core;
  final Photo photo;
  final String owner;
  final Json _recipe, _base;
  final bool Function() isCurrent;
  final Future<void> Function(String? path) discard;
  Json? _frame;
  Json _state;
  late Json _lastTools;
  late String _requestedKey, _acceptedKey, _frameLocalData;
  _LocalFrameRequest? _pending;
  bool _processing = false,
      _disposed = false,
      _stale = false,
      _finalFrame = true;
  bool _requestedInteractive = false;
  int _sequence = 0;
  String? _job;
  Object? error;

  Json? get frame => _frame == null ? null : toolsCopy(_frame!);
  bool get busy => _processing || _pending != null;
  bool get ready =>
      _current &&
      !busy &&
      !_requestedInteractive &&
      _finalFrame &&
      error == null &&
      _frame != null &&
      _requestedKey == _acceptedKey;
  Json get result {
    if (!ready) throw const AppFailure('请等待最新局部预览完成。');
    return toolsCopy(_state);
  }

  bool get _current => !_disposed && !_stale && isCurrent();
  static String _key(Json tools, bool interactive) =>
      '${jsonEncode(tools)}|${interactive ? 'interactive' : 'final'}';

  void offer(Json tools, {required bool interactive, bool force = false}) {
    if (!_current) return;
    final frozen = toolsCopy(tools), key = _key(tools, interactive);
    _lastTools = frozen;
    if (!force && key == _requestedKey && error == null) return;
    _requestedKey = key;
    _requestedInteractive = interactive;
    error = null;
    _pending = _LocalFrameRequest(++_sequence, key, frozen, interactive, force);
    notifyListeners();
    if (!_processing) unawaited(_drain());
  }

  void retry() {
    if (!_current || busy) return;
    _requestedKey = '';
    offer(_lastTools, interactive: false, force: true);
  }

  Future<void> _drain() async {
    if (_processing || !_current) return;
    _processing = true;
    notifyListeners();
    try {
      while (_current && _pending != null) {
        final request = _pending!;
        _pending = null;
        final prefix =
            'local-tools-${DateTime.now().microsecondsSinceEpoch}-${request.sequence}';
        try {
          _job = '$prefix-validate';
          final next = await core.call('local.change', {
            'localData': _base['localData'],
            'expectedSha': _base['sha256'],
            'action': 'replaceTools',
            'value': request.tools,
          }, _job);
          if (!_current) return;
          if (request.sequence != _sequence) continue;
          final localData = next['localData'] as String;
          if (!request.force &&
              _frame != null &&
              _frameLocalData == localData &&
              (_finalFrame || request.interactive)) {
            _state = toolsCopy(next);
            _acceptedKey = request.key;
            continue;
          }
          _job = '$prefix-render';
          final rendered = await core.call('media.localPreview', {
            'path': photo.path,
            'owner': owner,
            'recipe': {..._recipe, 'localData': localData},
            'maxEdge': request.interactive ? 768 : 1280,
          }, _job);
          if (!_current || request.sequence != _sequence) {
            unawaited(discard(rendered['path'] as String?));
            continue;
          }
          final old = _frame?['path'] as String?;
          _frame = toolsCopy(rendered);
          _state = toolsCopy(next);
          _frameLocalData = localData;
          _finalFrame = !request.interactive;
          _acceptedKey = request.key;
          error = null;
          if (old != rendered['path']) unawaited(discard(old));
          notifyListeners();
        } catch (failure) {
          if (_current && request.sequence == _sequence) {
            error = failure;
            notifyListeners();
          }
        } finally {
          _job = null;
        }
      }
    } finally {
      _processing = false;
      if (_current) notifyListeners();
    }
  }

  void invalidate() {
    if (_disposed || _stale) return;
    _stale = true;
    _sequence++;
    _pending = null;
    if (_job != null) unawaited(core.cancel(_job!));
    final old = _frame?['path'] as String?;
    _frame = null;
    _state = {};
    _lastTools = {};
    unawaited(discard(old));
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _sequence++;
    _pending = null;
    if (_job != null) unawaited(core.cancel(_job!));
    unawaited(discard(_frame?['path'] as String?));
    _frame = null;
    super.dispose();
  }
}
