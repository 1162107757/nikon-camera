import 'dart:async';

/// One render in flight and one replaceable pending snapshot. Interactive
/// frames remain useful during a drag; a final request accepts only its result.
class LatestPreviewQueue<S, R> {
  LatestPreviewQueue({
    required this.render,
    required this.isCurrent,
    required this.onFrame,
    required this.onError,
    required this.discard,
  });

  final Future<R> Function(S snapshot, bool interactive) render;
  final bool Function(S snapshot) isCurrent;
  final void Function(S snapshot, R result, bool interactive, bool latest)
  onFrame;
  final void Function(S snapshot, Object error, StackTrace stack) onError;
  final Future<void> Function(R result) discard;
  _PreviewJob<S>? _pending, _latest;
  bool _running = false, _closed = false;
  int _epoch = 0;

  Future<void> offer(S snapshot, {required bool interactive}) {
    if (_closed) return Future.value();
    final job = _PreviewJob(snapshot, interactive, _epoch);
    _pending?.done.complete();
    _pending = _latest = job;
    if (!_running) {
      _running = true;
      // Capture local-edit queue positions after the synchronous change handler
      // has enqueued its matching region mutation.
      scheduleMicrotask(_drain);
    }
    return job.done.future;
  }

  void reset() {
    _epoch++;
    _pending?.done.complete();
    _pending = _latest = null;
  }

  void close() {
    _closed = true;
    reset();
  }

  bool _valid(_PreviewJob<S> job) =>
      !_closed && job.epoch == _epoch && isCurrent(job.snapshot);

  Future<void> _drain() async {
    while (_pending != null) {
      final job = _pending!;
      _pending = null;
      try {
        if (!_valid(job)) continue;
        final result = await render(job.snapshot, job.interactive);
        final latest = identical(_latest, job);
        if (_valid(job) &&
            (latest || job.interactive && _latest?.interactive == true)) {
          onFrame(job.snapshot, result, job.interactive, latest);
        } else {
          await discard(result);
        }
      } catch (error, stack) {
        // A superseded failure must not replace a newer usable preview.
        if (_valid(job) && identical(_latest, job)) {
          onError(job.snapshot, error, stack);
        }
      } finally {
        job.done.complete();
      }
    }
    _running = false;
  }
}

class _PreviewJob<S> {
  _PreviewJob(this.snapshot, this.interactive, this.epoch);
  final S snapshot;
  final bool interactive;
  final int epoch;
  final done = Completer<void>();
}
