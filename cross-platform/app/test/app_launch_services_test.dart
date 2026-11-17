import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/app_launch_services.dart';

void main() {
  test(
    'mandatory update is scheduled while anonymous usage is still pending',
    () async {
      final usage = Completer<void>();
      var prompts = 0;
      await coordinateLaunchChecks(
        usage: usage.future,
        update: Future<void>.value(),
        mandatory: () => true,
        notify: () => prompts++,
      );
      expect(prompts, 1);
      expect(usage.isCompleted, isFalse);
      usage.complete();
      await Future<void>.delayed(Duration.zero);
      expect(prompts, 1);
    },
  );
  test(
    'optional reminder waits for probability sync and tolerates usage failure',
    () async {
      final usage = Completer<void>();
      var prompts = 0;
      final ready = coordinateLaunchChecks(
        usage: usage.future,
        update: Future<void>.value(),
        mandatory: () => false,
        notify: () => prompts++,
      );
      await Future<void>.delayed(Duration.zero);
      expect(prompts, 0);
      usage.completeError(StateError('offline'));
      await ready;
      expect(prompts, 1);
    },
  );
  test(
    'same version can remind again next launch after an earlier dismissal',
    () {
      final first = LaunchUpdateGate(draw: .2);
      expect(first.eligible(mandatory: false, probability: .5), isTrue);
      first.shown = true;
      expect(first.eligible(mandatory: false, probability: .5), isFalse);
      expect(
        LaunchUpdateGate(draw: .2).eligible(mandatory: false, probability: .5),
        isTrue,
      );
    },
  );
  test('one draw per launch; probability boundaries and mandatory updates', () {
    final gate = LaunchUpdateGate(draw: .7);
    expect(gate.eligible(mandatory: false, probability: .5), isFalse);
    expect(gate.eligible(mandatory: false, probability: .5), isFalse);
    expect(gate.eligible(mandatory: false, probability: 0), isFalse);
    expect(gate.eligible(mandatory: false, probability: 1), isTrue);
    gate.shown = true;
    expect(gate.eligible(mandatory: true, probability: 0), isTrue);
  });
  test(
    'anonymous ID is a random UUID and has no account or hardware identifier',
    () {
      final ids = List.generate(100, (_) => newUsageId());
      expect(ids.toSet(), hasLength(100));
      for (final id in ids) {
        expect(
          id,
          matches(
            RegExp(
              r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
            ),
          ),
        );
      }
    },
  );
}
