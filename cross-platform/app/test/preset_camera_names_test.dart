import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/preset_display_name.dart';
import 'package:huevia/settings.dart';
import 'package:huevia/theme.dart';

class _Core extends HueviaCore {
  _Core() {
    root = 'preset-name-test';
  }

  final calls = <(String, Json)>[];
  Json preferences = {};

  @override
  Future<Json> call(String op, [Json payload = const {}, String? jobId]) async {
    calls.add((op, Map.of(payload)));
    switch (op) {
      case 'ui.preferences.set':
        return preferences = {...preferences, ...payload};
      case 'library.cameraName':
        return {'cameraName': payload['id'] == 'legacy' ? 'Camera Legacy' : ''};
      case 'online.cameraName':
        return {'cameraName': 'ZR_CINEMATIC_TEAL'};
      default:
        throw StateError(op);
    }
  }
}

void main() {
  testWidgets(
    'Original-name setting uses the normal row with a trailing switch',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppState(_Core());
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: SettingsPage(state: app),
        ),
      );

      final title = find.text('显示预设原名');
      final appearance = find.text('外观');
      final toggle = find.byType(Switch);
      await tester.ensureVisible(title);
      await tester.pumpAndSettle();
      final row = find.ancestor(of: title, matching: find.byType(InkWell));
      final appearanceRow = find.ancestor(
        of: appearance,
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(row).height, tester.getSize(appearanceRow).height);
      expect(tester.getTopLeft(title).dx, tester.getTopLeft(appearance).dx);
      expect(
        tester.getCenter(toggle).dx,
        greaterThan(tester.getCenter(title).dx),
      );

      await tester.tap(title);
      await tester.pumpAndSettle();
      expect(app.showPresetCameraNames, isTrue);
      expect(tester.widget<Switch>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(app.showPresetCameraNames, isFalse);
      expect(tester.widget<Switch>(toggle).value, isFalse);
    },
  );

  testWidgets(
    'One preference reveals real camera names across preset surfaces',
    (tester) async {
      final core = _Core();
      final app = AppState(core);
      addTearDown(app.dispose);
      const local = Preset({
        'id': 'legacy',
        'displayName': '我保存的旧预设',
        'originalFileName': 'local-copy.NCP',
      });
      const online = Preset({
        'id': 'catalog-row',
        'sha256': 'file-identity',
        'name': '青橙分色电影',
      }, online: true);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PresetDisplayName(state: app, preset: local),
                PresetDisplayName(state: app, preset: online),
                PresetDisplayName(state: app, preset: online),
                PresetDisplayName(
                  state: app,
                  title: '旧修图草稿',
                  cameraName: 'Snapshot Name',
                ),
              ],
            ),
          ),
        ),
      );
      expect(core.calls, isEmpty);
      expect(find.text('Camera Legacy'), findsNothing);
      expect(find.text('青橙分色电影'), findsNWidgets(2));

      await app.saveUiPreferences({'showPresetCameraNames': true});
      await tester.pumpAndSettle();
      expect(find.text('Camera Legacy'), findsOneWidget);
      expect(find.text('ZR_CINEMATIC_TEAL'), findsNWidgets(2));
      expect(find.text('Snapshot Name'), findsOneWidget);
      expect(find.text('local-copy.NCP'), findsNothing);
      expect(
        core.calls.where((call) => call.$1 == 'online.cameraName'),
        hasLength(1),
      );
      expect(
        core.calls.singleWhere((call) => call.$1 == 'library.cameraName').$2,
        {'owner': '', 'id': 'legacy'},
      );

      await app.saveUiPreferences({'showPresetCameraNames': false});
      await tester.pumpAndSettle();
      expect(find.text('Camera Legacy'), findsNothing);
      expect(find.text('ZR_CINEMATIC_TEAL'), findsNothing);
      expect(find.text('Snapshot Name'), findsNothing);
      expect(find.text('我保存的旧预设'), findsOneWidget);
    },
  );

  testWidgets('An unavailable embedded name does not show the file name', (
    tester,
  ) async {
    final app = AppState(_Core())
      ..uiPreferences = {'showPresetCameraNames': true};
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PresetDisplayName(
          state: app,
          preset: const Preset({
            'id': 'unavailable',
            'displayName': '预设标题',
            'originalFileName': 'download.NP3',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('预设标题'), findsOneWidget);
    expect(find.textContaining('download'), findsNothing);
  });
}
