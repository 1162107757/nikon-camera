import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/project_presets.dart';
import 'package:huevia/project_presets_model.dart';
import 'package:huevia/theme.dart';

class ProjectCore extends HueviaCore {
  ProjectCore() {
    root = '/private';
  }
  final calls = <(String, Json)>[];
  final cancelled = <String>[];
  final events = StreamController<dynamic>.broadcast(sync: true);
  final exports = <String, int>{};
  List<Json> tasks = [];
  List<Json> photos = [
    {'path': '/private/originals/one.jpg', 'name': 'one.jpg'},
    {'path': '/private/originals/two.jpg', 'name': 'two.jpg'},
  ];
  bool failSecond = true;
  Completer<Json>? exportDelay;
  String? lastJob;
  Json snapshot() => object(
    jsonDecode(
      jsonEncode({
        'id': 'project',
        'name': '拍摄项目',
        'createdAt': 1,
        'presetId': 'a' * 64,
        'presetName': '项目预设',
        'photos': photos,
        'tasks': tasks,
      }),
    ),
  );
  @override
  Stream<dynamic> get operationProgress => events.stream;
  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, object(jsonDecode(jsonEncode(payload)))));
    switch (operation) {
      case 'project.list':
        return {
          'items': [snapshot()],
        };
      case 'project.open':
        return snapshot();
      case 'project.enqueue':
        for (final name in ['one', 'two']) {
          if (!tasks.any((task) => task['key'] == name)) {
            tasks.add({
              'key': name,
              'name': '$name.jpg',
              'status': 'queued',
              'presetId': 'a' * 64,
              'presetName': '项目快照',
              'error': '',
            });
          }
        }
        return snapshot();
      case 'project.retry':
        for (final task in tasks) {
          if (task['status'] == 'error') task['status'] = 'queued';
        }
        return snapshot();
      case 'project.begin':
        final key = payload['key'] as String;
        tasks.firstWhere((task) => task['key'] == key)['status'] = 'processing';
        return {
          'lease': 'lease-$key',
          'path': '/private/originals/$key.jpg',
          'sourceSha': '$key-sha',
          'recipe': {
            'presetId': 'a' * 64,
            'presetName': '项目快照',
            'strength': 100,
          },
        };
      case 'media.export':
        final path = payload['path'] as String;
        exports.update(path, (count) => count + 1, ifAbsent: () => 1);
        lastJob = jobId;
        if (exportDelay != null) return exportDelay!.future;
        if (path.endsWith('two.jpg') && failSecond) {
          throw const AppFailure('第二张处理中断');
        }
        return {'id': path.endsWith('one.jpg') ? 'one-result' : 'two-result'};
      case 'project.finish':
        tasks.firstWhere((task) => task['key'] == payload['key'])['status'] =
            'saved';
        return snapshot();
      case 'project.fail':
        tasks.firstWhere((task) => task['key'] == payload['key'])
          ..['status'] = 'error'
          ..['error'] = payload['error'];
        return snapshot();
      default:
        throw AppFailure(operation);
    }
  }
}

class ProjectState extends AppState {
  ProjectState(super.core);
  void switchOwner() {
    session = {
      'user': {'id': 'another'},
    };
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Project retry keeps frozen recipes and never renders an already saved result', () async {
    final core = ProjectCore();
    final model = ProjectPresetsModel(ProjectState(core));
    await model.refresh();
    await model.process(enqueue: true);
    expect(
      model.tasks.where((task) => task['status'] == 'saved'),
      hasLength(1),
    );
    expect(model.failed, 1);
    core.failSecond = false;
    await model.process(retry: true);
    expect(model.tasks.every((task) => task['status'] == 'saved'), true);
    expect(core.exports['/private/originals/one.jpg'], 1);
    expect(core.exports['/private/originals/two.jpg'], 2);
    final render = core.calls
        .firstWhere((call) => call.$1 == 'media.export')
        .$2;
    expect(render['snapshot'], true);
    expect(render['expectedSourceSha'], 'one-sha');
    expect(render['recipe']['presetId'], 'a' * 64);
    expect(core.calls.any((call) => call.$1 == 'draft.save'), false);
    model.dispose();
    model.state.dispose();
    await core.events.close();
  });
  for (final leave in ['stop', 'account', 'dispose']) {
    test('Late native export is not committed after project $leave', () async {
      final core = ProjectCore()..exportDelay = Completer<Json>();
      final model = ProjectPresetsModel(ProjectState(core));
      await model.refresh();
      final running = model.process(enqueue: true);
      await Future<void>.delayed(Duration.zero);
      expect(core.lastJob, isNotNull);
      core.events.add({'jobId': 'unrelated', 'progress': .7});
      expect(model.progress, 0);
      core.events.add({'jobId': core.lastJob, 'progress': .4});
      expect(model.progress, .4);
      core.events.add({'jobId': core.lastJob, 'progress': double.nan});
      expect(model.progress, .4);
      if (leave == 'stop') await model.stop();
      if (leave == 'account') (model.state as ProjectState).switchOwner();
      if (leave == 'dispose') model.dispose();
      core.exportDelay!.complete({'id': 'late-result'});
      await running;
      expect(core.calls.any((call) => call.$1 == 'project.finish'), false);
      expect(core.cancelled, hasLength(1));
      if (leave != 'dispose') model.dispose();
      model.state.dispose();
      await core.events.close();
    });
  }
  testWidgets(
    'Embedded project manager scrolls its controls on a small screen with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final core = ProjectCore()..photos = [];
      final state = ProjectState(core)
        ..presets = [
          Preset({'id': 'a' * 64, 'displayName': '项目预设', 'fileFormat': 'NCP'}),
        ];
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: ProjectPresetsPage(state: state, embedded: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byTooltip('新建拍摄项目'), findsOneWidget);
      expect(find.text('套用默认预设'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      unawaited(core.events.close());
    },
  );
}
