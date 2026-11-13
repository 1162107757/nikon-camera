import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/connection_protection.dart';
import 'package:huevia/camera_live.dart';
import 'package:huevia/domain.dart';

import 'camera_live_test.dart' as live_fixture;

class ProtectionProbe extends CameraConnectionProtection {
  ProtectionProbe(super.core);
  final requests = <(String, Json, Completer<Json>)>[];
  bool disposing = false;
  @override
  Future<Json> invoke(String method, [Json payload = const {}]) {
    if (disposing) return Future.value({});
    final result = Completer<Json>();
    requests.add((method, Map<String, dynamic>.of(payload), result));
    return result.future;
  }

  @override
  void dispose() {
    disposing = true;
    super.dispose();
  }
}

class ProtectedLiveState extends AppState {
  ProtectedLiveState(live_fixture.LiveCore super.core) {
    session = {
      'user': {'id': 'owner'},
    };
    controller = CameraLive(
      this,
      automatic: true,
      interval: const Duration(hours: 1),
    );
  }
  late final CameraLive controller;
  final received = <String>[];
  @override
  CameraLive get cameraLive => controller;
  @override
  bool get cameraLiveActive => controller.active;
  @override
  Future<Photo> registerPhoto(String path, String name, Json info) async {
    received.add(path);
    return Photo(path, name, info);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

Future<void> until(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(ready(), true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('permission inactive never forwards a background command', () async {
    final protection = ProtectionProbe(HueviaCore()..platform = 'ios');
    addTearDown(protection.dispose);
    protection.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(protection.requests, isEmpty);
    protection.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(protection.requests.single.$2['foreground'], true);
    protection.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(protection.requests, hasLength(1));
    protection.requests.single.$3.complete({'enabled': false});
    await Future<void>.delayed(Duration.zero);
    expect(protection.requests, hasLength(1));
  });
  test('foreground commands are serialized and a delayed background command is followed by the latest resumed state', () async {
    final protection = ProtectionProbe(HueviaCore()..platform = 'ios');
    addTearDown(protection.dispose);
    protection.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(protection.requests.single.$2['foreground'], false);
    protection.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(
      protection.requests,
      hasLength(1),
      reason:
          'Native background and foreground writes must never run concurrently',
    );
    protection.requests.single.$3.complete({'foreground': false});
    await until(() => protection.requests.length == 2);
    expect(protection.requests.last.$2['foreground'], true);
    protection.requests.last.$3.complete({'foreground': true});
    await until(() => protection.status['foreground'] == true);
    protection.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(protection.requests, hasLength(2));
  });
  test(
    'superseded foreground transitions do not replay an obsolete state',
    () async {
      final protection = ProtectionProbe(HueviaCore()..platform = 'android');
      addTearDown(protection.dispose);
      protection.didChangeAppLifecycleState(AppLifecycleState.paused);
      protection.didChangeAppLifecycleState(AppLifecycleState.resumed);
      protection.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(protection.requests, hasLength(1));
      protection.requests.single.$3.complete({'foreground': false});
      await Future<void>.delayed(Duration.zero);
      expect(protection.requests, hasLength(1));
      expect(protection.status['foreground'], false);
    },
  );
  test('expired native event wins over an earlier active response', () async {
    final core = HueviaCore()..platform = 'ios';
    final protection = ProtectionProbe(core);
    addTearDown(protection.dispose);
    final pending = protection.setActive('live', true);
    expect(protection.requests.single.$2['active'], true);
    protection.accept({
      'enabled': true,
      'available': true,
      'limited': true,
      'expired': true,
      'backgroundAllowed': false,
    });
    protection.requests.single.$3.complete({
      'enabled': true,
      'backgroundAllowed': true,
    });
    await pending;
    expect(protection.backgroundAllowed, false);
    expect(protection.limited, true);
    expect(protection.status['expired'], true);
  });
  test('out-of-order actor replies cannot restore protection after the last actor stopped', () async {
    final core = HueviaCore()..platform = 'android';
    final protection = ProtectionProbe(core);
    addTearDown(protection.dispose);
    final start = protection.setActive('downloads', true),
        stop = protection.setActive('downloads', false);
    protection.requests[1].$3.complete({
      'enabled': true,
      'backgroundAllowed': false,
    });
    await stop;
    protection.requests[0].$3.complete({
      'enabled': true,
      'backgroundAllowed': true,
    });
    await start;
    expect(protection.actors, isEmpty);
    expect(protection.backgroundAllowed, false);
  });
  test('notification stop ends idle foreground live and is never replayed on foreground', () async {
    final core = live_fixture.LiveCore()..usePreset = false;
    final state = ProtectedLiveState(core), live = state.controller;
    addTearDown(() async {
      await live.stop();
      state.dispose();
      await core.events.close();
    });
    state.connectionProtection.accept({
      'enabled': true,
      'backgroundAllowed': true,
      'stopRevision': 7,
    });
    await live.start('project-one', '拍摄');
    expect(live.phase, CameraLivePhase.watching);
    state.connectionProtection.accept({
      'enabled': false,
      'backgroundAllowed': false,
      'stopRevision': 7,
    });
    expect(live.active, true);
    state.connectionProtection.accept({
      'enabled': false,
      'backgroundAllowed': false,
      'stopRevision': 8,
    });
    await until(() => live.phase == CameraLivePhase.stopped);
    expect(live.active, false);
    expect(core.calls, containsAll(['project.live.stop', 'camera.live.stop']));
    core.visible = [live_fixture.shot(2)];
    live.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await live.pollOnce();
    expect(core.downloads, 0);
    state.connectionProtection.accept({
      'enabled': false,
      'backgroundAllowed': false,
    });
    expect(state.connectionProtection.stopRevision, 8);
    state.connectionProtection.accept({
      'enabled': true,
      'backgroundAllowed': true,
      'stopRevision': 6,
    });
    expect(state.connectionProtection.stopRevision, 8);
  });
  test('malformed protection events suspend background work and foreground state is forwarded', () async {
    final core = HueviaCore()..platform = 'ios';
    final protection = ProtectionProbe(core);
    addTearDown(protection.dispose);
    protection.accept({'enabled': true, 'backgroundAllowed': true});
    protection.accept('{bad-json');
    expect(protection.backgroundAllowed, false);
    expect(protection.warning, contains('状态无效'));
    protection.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(protection.requests.last.$1, 'foreground');
    expect(protection.requests.last.$2['foreground'], false);
    protection.requests.last.$3.complete({
      'enabled': true,
      'backgroundAllowed': false,
      'expired': true,
    });
    await Future<void>.delayed(Duration.zero);
    protection.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(protection.requests.last.$2['foreground'], true);
    protection.requests.last.$3.complete({
      'enabled': true,
      'backgroundAllowed': true,
    });
    await Future<void>.delayed(Duration.zero);
    expect(protection.backgroundAllowed, true);
  });
  test('protected background live expires without polling and automatically reconciles on foreground', () async {
    final core = live_fixture.LiveCore()..usePreset = false;
    final state = ProtectedLiveState(core), live = state.controller;
    addTearDown(() async {
      await live.stop();
      state.dispose();
      await core.events.close();
    });
    state.connectionProtection.accept({
      'enabled': true,
      'available': true,
      'limited': true,
      'backgroundAllowed': true,
    });
    await live.start('project-one', '拍摄');
    live.didChangeAppLifecycleState(AppLifecycleState.paused);
    core.visible = [live_fixture.shot(2)];
    await live.pollOnce();
    expect(live.completed, 1);
    expect(core.downloads, 1);
    state.connectionProtection.accept({
      'enabled': true,
      'backgroundAllowed': false,
      'expired': true,
    });
    expect(live.phase, CameraLivePhase.paused);
    final before = core.calls.length;
    core.visible = [live_fixture.shot(3)];
    await live.pollOnce();
    expect(core.calls.length, before);
    expect(core.downloads, 1);
    live.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await until(() => !live.working && live.completed == 2);
    expect(core.downloads, 2);
    expect(state.received, hasLength(2));
    expect(live.phase, CameraLivePhase.watching);
  });
  test('foreground arrival before canceled download returns still resumes live automatically', () async {
    final core = live_fixture.LiveCore()..usePreset = false;
    final state = ProtectedLiveState(core), live = state.controller;
    addTearDown(() async {
      await live.stop();
      state.dispose();
      await core.events.close();
    });
    state.connectionProtection.accept({
      'enabled': true,
      'backgroundAllowed': true,
    });
    await live.start('project-one', '拍摄');
    live.didChangeAppLifecycleState(AppLifecycleState.paused);
    final gate = Completer<void>();
    core.downloadGate = gate;
    core.visible = [live_fixture.shot(2)];
    final polling = live.pollOnce();
    await until(() => core.downloads == 1);
    state.connectionProtection.accept({
      'enabled': true,
      'backgroundAllowed': false,
      'expired': true,
    });
    expect(core.calls, contains('cancel'));
    live.didChangeAppLifecycleState(AppLifecycleState.resumed);
    core.downloadGate = null;
    gate.completeError(
      const AppFailure('Native background deadline canceled this receive'),
    );
    await polling;
    await until(() => !live.working && live.completed == 1);
    expect(live.phase, CameraLivePhase.watching);
    expect(state.received, hasLength(1));
    expect(core.completed, hasLength(1));
  });
}
