import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/latest_preview_queue.dart';

class PreviewHarness {
  final started = <int>[];
  final frames = <int>[];
  final discarded = <int>[];
  final errors = <Object>[];
  final gates = <int, Completer<int>>{};
  bool current = true;
  int inFlight = 0, maximumInFlight = 0;
  late final queue = LatestPreviewQueue<int, int>(
    render: (snapshot, interactive) async {
      started.add(snapshot);
      inFlight++;
      if (inFlight > maximumInFlight) maximumInFlight = inFlight;
      try {
        return await (gates[snapshot] = Completer<int>()).future;
      } finally {
        inFlight--;
      }
    },
    isCurrent: (_) => current,
    onFrame: (snapshot, result, interactive, latest) => frames.add(result),
    onError: (_, error, stack) => errors.add(error),
    discard: (result) async => discarded.add(result),
  );

  Future<void> tick() => Future<void>.delayed(Duration.zero);
}

void main() {
  test(
    'Continuous drag publishes frames and keeps only the latest pending sample',
    () async {
      final h = PreviewHarness();
      final first = h.queue.offer(1, interactive: true);
      await h.tick();
      unawaited(h.queue.offer(2, interactive: true));
      unawaited(h.queue.offer(3, interactive: true));
      h.gates[1]!.complete(1);
      await first;
      expect(h.frames, [1]);
      expect(h.started, [1, 3]);
      unawaited(h.queue.offer(4, interactive: true));
      unawaited(h.queue.offer(5, interactive: true));
      h.gates[3]!.complete(3);
      await h.tick();
      expect(h.frames, [1, 3]);
      expect(h.started, [1, 3, 5]);
      h.gates[5]!.complete(5);
      await h.tick();
      expect(h.frames, [1, 3, 5]);
      expect(h.maximumInFlight, 1);
      h.queue.close();
    },
  );

  test('Release drops the slow interactive frame and renders the exact final snapshot', () async {
    final h = PreviewHarness();
    final first = h.queue.offer(10, interactive: true);
    await h.tick();
    unawaited(h.queue.offer(20, interactive: true));
    final finalFrame = h.queue.offer(37, interactive: false);
    h.gates[10]!.complete(10);
    await first;
    expect(h.frames, isEmpty);
    expect(h.discarded, [10]);
    expect(h.started, [10, 37]);
    h.gates[37]!.complete(37);
    await finalFrame;
    expect(h.frames, [37]);
    expect(h.maximumInFlight, 1);
    h.queue.close();
  });

  test(
    'Reset fences a previous photo even if a new drag starts before it returns',
    () async {
      final h = PreviewHarness();
      final old = h.queue.offer(1, interactive: true);
      await h.tick();
      h.queue.reset();
      final next = h.queue.offer(2, interactive: true);
      h.gates[1]!.complete(1);
      await old;
      expect(h.frames, isEmpty);
      h.gates[2]!.complete(2);
      await next;
      expect(h.frames, [2]);
      expect(h.discarded, [1]);
      h.queue.close();
    },
  );

  test('Owner invalidation drops the in-flight result and never starts pending work', () async {
    final h = PreviewHarness();
    final old = h.queue.offer(1, interactive: true);
    await h.tick();
    final pending = h.queue.offer(2, interactive: true);
    h.current = false;
    h.gates[1]!.complete(1);
    await old;
    await pending;
    expect(h.frames, isEmpty);
    expect(h.started, [1]);
    expect(h.discarded, [1]);
    h.queue.close();
  });

  test(
    'Leaving closes the queue and discards late results without publishing',
    () async {
      final h = PreviewHarness();
      final old = h.queue.offer(1, interactive: true);
      await h.tick();
      final pending = h.queue.offer(2, interactive: false);
      h.queue.close();
      await pending;
      h.gates[1]!.complete(1);
      await old;
      await h.queue.offer(3, interactive: false);
      expect(h.started, [1]);
      expect(h.frames, isEmpty);
      expect(h.discarded, [1]);
    },
  );

  test(
    'Superseded failure cannot overwrite the final frame or stall the worker',
    () async {
      final h = PreviewHarness();
      final old = h.queue.offer(1, interactive: true);
      await h.tick();
      final next = h.queue.offer(2, interactive: false);
      h.gates[1]!.completeError(StateError('old render'));
      await old;
      expect(h.errors, isEmpty);
      h.gates[2]!.complete(2);
      await next;
      expect(h.frames, [2]);
      final failed = h.queue.offer(3, interactive: false);
      await h.tick();
      h.gates[3]!.completeError(StateError('current render'));
      await failed;
      expect(h.errors.single, isA<StateError>());
      h.queue.close();
    },
  );
}
