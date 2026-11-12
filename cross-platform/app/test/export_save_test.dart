import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/export_save.dart';
import 'package:huevia/export_settings_model.dart';

class SaveCore extends HueviaCore {
  final calls = <(String, Json)>[];
  bool failPublish = false, permitted = true;
  Completer<Json>? pending;
  final cancelled = <String>[];
  @override
  Future<Json> gallerySavePermission() async => {'granted': permitted};
  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
  }

  @override
  Future<Json> call(String op, [Json payload = const {}, String? jobId]) async {
    calls.add((op, exportCopy(payload)));
    if (op == 'media.export') {
      return {'id': 'a' * 64, 'path': '/private/final.jpg'};
    }
    if (op == 'gallery.publish') {
      if (pending != null) return pending!.future;
      if (failPublish) throw const AppFailure('storage full');
      return {
        'published': true,
        'uri': 'content://media/external/images/media/1',
      };
    }
    throw StateError(op);
  }
}

class SaveState extends AppState {
  SaveState(super.core);
  void logout() {
    session = {'logoutPending': true};
    notifyListeners();
  }
}

void main() {
  ExportItem item(String id) => ExportItem(
    id,
    id,
    const Photo('/own/source.jpg', 'own.jpg', {}),
    {'schema': 1},
    {'sourceSha': 'b' * 64},
    {'size': 'custom', 'quality': 80, 'longEdge': 1280},
  );
  (SaveCore, SaveState, ExportSave) fixture(List<ExportItem> items) {
    final core = SaveCore();
    final actual = SaveState(core);
    final queue = ExportSave(actual, '', items);
    addTearDown(() {
      queue.dispose();
      actual.dispose();
    });
    return (core, actual, queue);
  }

  test('failed album publication stops the queue and retries the same frozen version and operation', () async {
    final original = item('first');
    final (core, _, queue) = fixture([original, item('second')]);
    original.recipe['presetId'] = 'changed';
    original.options['quality'] = 95;
    core.failPublish = true;
    await queue.run();
    expect(queue.completed, 0);
    expect(core.calls.map((c) => c.$1), ['media.export', 'gallery.publish']);
    final published = core.calls.last.$2;
    expect(published['extraCopy'], true);
    expect(published['operationId'], matches(r'^[0-9a-f]{32}$'));
    expect(core.calls.first.$2['snapshot'], true);
    expect(core.calls.first.$2['quality'], 80);
    expect(object(core.calls.first.$2['recipe'])['presetId'], isNull);
    core.failPublish = false;
    await queue.run();
    expect(queue.completed, 2);
    final publications = core.calls
        .where((c) => c.$1 == 'gallery.publish')
        .map((c) => c.$2)
        .toList();
    expect(publications[1], published);
    expect(publications[2]['operationId'], isNot(published['operationId']));
    expect(core.calls.where((c) => c.$1 == 'media.export').length, 2);
    final count = core.calls.length;
    await queue.run();
    expect(core.calls.length, count);
  });
  test('a new explicit export gets a different album operation for identical settings', () async {
    final (_, _, first) = fixture([item('current')]);
    final (_, _, second) = fixture([item('current')]);
    expect(first.items.single.operation, isNot(second.items.single.operation));
  });
  test('permission denial never renders or saves and can be retried', () async {
    final (core, _, queue) = fixture([item('current')]);
    core.permitted = false;
    await queue.run();
    expect(core.calls, isEmpty);
    expect(queue.error, contains('允许'));
    core.permitted = true;
    await queue.run();
    expect(queue.done, true);
  });
  test('owner change cancels a live publication and suppresses its late acknowledgement', () async {
    final (core, state, queue) = fixture([item('current')]);
    core.pending = Completer<Json>();
    final running = queue.run();
    await Future<void>.delayed(Duration.zero);
    expect(queue.items.single.version, isNotNull);
    state.logout();
    await Future<void>.delayed(Duration.zero);
    expect(core.cancelled, isNotEmpty);
    core.pending!.complete({
      'published': true,
      'uri': 'content://media/external/images/media/1',
    });
    await running;
    expect(queue.invalid, true);
    expect(queue.items.single.version, isNull);
    expect(queue.items.single.receipt, isNull);
    final count = core.calls.length;
    await queue.run();
    expect(core.calls.length, count);
  });
}
