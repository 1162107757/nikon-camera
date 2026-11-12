import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/local_adjustments.dart';

class RegionQueueCore extends HueviaCore {
  final requests = <Json>[];
  final replies = <Completer<Json>>[];
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) {
    expect(operation, 'local.change');
    requests.add(object(jsonDecode(jsonEncode(payload))));
    final reply = Completer<Json>();
    replies.add(reply);
    return reply.future;
  }
}

void main() {
  test(
    'region samples serialize fingerprints and freeze each history position',
    () async {
      final core = RegionQueueCore();
      final accepted = <Json>[];
      final queue = LocalAdjustmentQueue(
        core: core,
        initial: {'localData': 'initial', 'sha256': 'sha-0'},
        isCurrent: () => true,
        onAccepted: accepted.add,
      );
      final before = Recipe();
      queue.fillSnapshot(before);
      final settings = {'values': List.filled(17, 1)};
      final first = queue.change('one', {'adjustments': settings});
      final middle = Recipe();
      queue.fillSnapshot(middle);
      (settings['values'] as List)[0] = 99;
      final second = queue.change('two', {'adjustments': settings});
      await Future<void>.delayed(Duration.zero);
      expect(core.requests, hasLength(1));
      expect(object(core.requests.first['value'])['adjustments'], {
        'values': List.filled(17, 1),
      });
      core.replies.first.complete({'localData': 'first', 'sha256': 'sha-1'});
      await first;
      await Future<void>.delayed(Duration.zero);
      expect(core.requests[1]['expectedSha'], 'sha-1');
      expect(core.requests[1]['localData'], 'first');
      expect(core.requests[1]['regionId'], 'two');
      core.replies[1].complete({'localData': 'second', 'sha256': 'sha-2'});
      await second;
      expect(before.data['localData'], 'initial');
      expect(middle.data['localData'], 'first');
      expect(queue.state['localData'], 'second');
      expect(accepted, hasLength(2));
      queue.close();
    },
  );

  test(
    'account changes discard in-flight results and prevent later commands',
    () async {
      final core = RegionQueueCore();
      var current = true;
      final accepted = <Json>[];
      final queue = LocalAdjustmentQueue(
        core: core,
        initial: {'localData': 'initial', 'sha256': 'sha-0'},
        isCurrent: () => current,
        onAccepted: accepted.add,
      );
      final first = queue.change('one', {});
      final second = queue.change('two', {});
      final firstFailure = expectLater(first, throwsA(isA<AppFailure>()));
      final secondFailure = expectLater(second, throwsA(isA<AppFailure>()));
      await Future<void>.delayed(Duration.zero);
      current = false;
      core.replies.single.complete({
        'localData': 'private-old-user',
        'sha256': 'sha-1',
      });
      await Future.wait([firstFailure, secondFailure]);
      expect(accepted, isEmpty);
      expect(core.requests, hasLength(1));
      expect(queue.state['localData'], 'initial');
      queue.close();
    },
  );

  test(
    'failed binary validation stops the queue without changing the draft',
    () async {
      final core = RegionQueueCore();
      final queue = LocalAdjustmentQueue(
        core: core,
        initial: {'localData': 'initial', 'sha256': 'sha-0'},
        isCurrent: () => true,
        onAccepted: (_) => fail('invalid edit accepted'),
      );
      final first = queue.change('one', {});
      final second = queue.change('one', {});
      final firstFailure = expectLater(first, throwsA(isA<AppFailure>()));
      final secondFailure = expectLater(second, throwsA(isA<AppFailure>()));
      await Future<void>.delayed(Duration.zero);
      core.replies.single.completeError(
        const AppFailure('fingerprint changed'),
      );
      await Future.wait([firstFailure, secondFailure]);
      expect(core.requests, hasLength(1));
      expect(queue.state['localData'], 'initial');
      queue.close();
    },
  );
}
