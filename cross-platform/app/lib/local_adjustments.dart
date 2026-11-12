import 'dart:async';
import 'dart:convert';

import 'domain.dart';

/// Serializes tentative region edits against the original binary fingerprint.
/// Snapshots retain the queue position at which they were taken, so a fast
/// slider followed by another command cannot put stale local data in history.
class LocalAdjustmentQueue {
  LocalAdjustmentQueue({
    required this.core,
    required Json initial,
    required this.isCurrent,
    required this.onAccepted,
  }) : _state = _copy(initial),
       _tail = Future.value(_copy(initial));

  final HueviaCore core;
  final bool Function() isCurrent;
  final void Function(Json) onAccepted;
  Json _state;
  Future<Json> _tail;
  int _generation = 0;
  bool _closed = false;

  Json get state => _copy(_state);
  Future<Json> get settled => _tail;
  static Json _copy(Json value) => object(jsonDecode(jsonEncode(value)));

  Future<Json> change(String regionId, Json patch) {
    final generation = _generation;
    final frozen = _copy(patch);
    final next = _tail.then((previous) async {
      if (_closed || generation != _generation || !isCurrent()) {
        throw const AppFailure('编辑状态已改变，请重新操作。');
      }
      final result = await core.call('local.change', {
        'localData': previous['localData'],
        'expectedSha': previous['sha256'],
        'action': 'setRegion',
        'regionId': regionId,
        'value': frozen,
      });
      if (_closed || generation != _generation || !isCurrent()) {
        throw const AppFailure('编辑状态已改变，请重新操作。');
      }
      _state = _copy(result);
      onAccepted(_copy(result));
      return result;
    });
    _tail = next;
    // Consumers may wait for the whole gesture rather than every sample.
    unawaited(next.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    return next;
  }

  void fillSnapshot(Recipe snapshot) {
    final position = _tail;
    unawaited(
      position.then<void>((value) {
        snapshot.data['localData'] = value['localData'];
      }, onError: (Object _, StackTrace _) {}),
    );
  }

  void close() {
    _closed = true;
    _generation++;
  }
}
