import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/export_settings_model.dart';
import 'package:huevia/original_save.dart';

import 'export_save_test.dart' show SaveState;

class OriginalCore extends HueviaCore {
  final calls = <Json>[];
  final cancelled = <String>[];
  bool permitted = true, fail = false, badReceipt = false;
  Completer<Json>? pending;
  @override
  Future<Json> gallerySavePermission() async => {'granted': permitted};
  @override
  Future<void> cancel(String identity) async {
    cancelled.add(identity);
  }

  @override
  Future<Json> call(String op, [Json payload = const {}, String? jobId]) async {
    expect(op, 'gallery.publishOriginal');
    calls.add(exportCopy(payload));
    if (pending != null) return pending!.future;
    if (fail) throw const AppFailure('storage full');
    return badReceipt ? {} : {'published': true, 'uri': 'content://own/1'};
  }
}

void main() {
  (OriginalCore, SaveState, OriginalSave) fixture() {
    final core = OriginalCore();
    final actual = SaveState(core);
    final save = OriginalSave(actual, '', '/own/a.jpg', 'a' * 64, 'own.jpg');
    addTearDown(() {
      save.dispose();
      actual.dispose();
    });
    return (core, actual, save);
  }

  test('original save has no rendering and retries one immutable publication action', () async {
    final (core, _, save) = fixture();
    core.fail = true;
    await save.run();
    expect(save.done, false);
    expect(save.error, contains('storage full'));
    final first = core.calls.single;
    expect(first['expectedSourceSha'], 'a' * 64);
    expect(first['operationId'], matches(r'^[0-9a-f]{32}$'));
    expect(
      first.keys,
      unorderedEquals([
        'owner',
        'path',
        'expectedSourceSha',
        'filename',
        'operationId',
      ]),
    );
    core.fail = false;
    await save.run();
    expect(save.done, true);
    expect(core.calls.last, first);
    await save.run();
    expect(core.calls.length, 2);
  });
  test('denied permission does not stage or publish an original', () async {
    final (core, _, save) = fixture();
    core.permitted = false;
    await save.run();
    expect(core.calls, isEmpty);
    expect(save.error, contains('允许'));
    core.permitted = true;
    await save.run();
    expect(save.done, true);
  });
  test('separate confirmed actions have independent receipt keys', () {
    final (_, _, first) = fixture();
    final (_, _, second) = fixture();
    expect(first.operation, isNot(second.operation));
  });
  test(
    'owner change cancels a native save and hides a late acknowledgement',
    () async {
      final (core, state, save) = fixture();
      core.pending = Completer<Json>();
      final running = save.run();
      await Future<void>.delayed(Duration.zero);
      state.logout();
      expect(save.invalid, true);
      expect(save.source, isEmpty);
      expect(save.filename, isEmpty);
      expect(core.cancelled, isNotEmpty);
      core.pending!.complete({'published': true, 'identifier': 'own'});
      await running;
      expect(save.receipt, isNull);
      expect(save.error, isNull);
    },
  );
  test(
    'stopping a save retains its action for retry after an ambiguous result',
    () async {
      final (core, _, save) = fixture();
      core.pending = Completer<Json>();
      final running = save.run();
      await Future<void>.delayed(Duration.zero);
      await save.cancel();
      core.pending!.complete({'published': true, 'uri': 'content://own/1'});
      await running;
      expect(save.done, false);
      core.pending = null;
      await save.run();
      expect(save.done, true);
      expect(core.calls.last, core.calls.first);
    },
  );
  test('a missing system receipt stays retryable', () async {
    final (core, _, save) = fixture();
    core.badReceipt = true;
    await save.run();
    expect(save.done, false);
    expect(save.error, contains('尚未确认'));
  });
}
