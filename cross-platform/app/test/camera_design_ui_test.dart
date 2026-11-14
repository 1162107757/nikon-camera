import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera.dart';
import 'package:huevia/camera_downloads.dart';
import 'package:huevia/camera_photo_sort.dart';
import 'package:huevia/camera_photo_toolbar.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/legacy_glass_sheet.dart';
import 'package:huevia/sync_tools_dock.dart';
import 'package:huevia/theme.dart';

import 'camera_intent_test.dart' as intent;

class _EmptyDownloadsCore extends HueviaCore {
  @override
  Stream<dynamic> get operationProgress => const Stream<dynamic>.empty();
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'downloads.list') return {'items': [], 'issues': []};
    throw StateError('Unexpected operation in empty queue UI: $operation');
  }
}

void main() {
  testWidgets(
    'Approved compact photo header fits 375dp and large text; its controls remain independent',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(375, 812);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var raw = false, selecting = false;
      var order = CameraPhotoSort.newest;
      var rawChanges = 0;
      for (final scale in [1.0, 1.8]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.light),
            home: StatefulBuilder(
              builder: (context, change) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: CameraPhotoToolbar(
                      count: 128,
                      hasMore: true,
                      inventoryReady: true,
                      raw: raw,
                      selecting: selecting,
                      order: order,
                      onRawChanged: (value) => change(() {
                        raw = value;
                        rawChanges++;
                      }),
                      onOrderChanged: (value) => change(() => order = value),
                      onSelection: () => change(() => selecting = !selecting),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const Key('camera-raw-switch')));
      await tester.pumpAndSettle();
      expect(raw, isTrue);
      expect(rawChanges, 1);
      await tester.tap(find.byKey(const Key('camera-photo-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('名称 · 降序'));
      await tester.pumpAndSettle();
      expect(order, CameraPhotoSort.nameDescending);
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      expect(selecting, isTrue);
      expect(find.text('取消'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'B entry is a single 52dp circle and opens exactly the three camera tools',
    (tester) async {
      var remoteOpened = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: SyncToolsDock(
                onDownloads: () {},
                onRemote: () => remoteOpened++,
                onSlots: () {},
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const Key('sync-tools-dock'))),
        const Size(52, 52),
      );
      expect(find.text('相机工具'), findsNothing);
      expect(find.text('0'), findsNothing);
      await tester.tap(find.byTooltip('相机工具'));
      await tester.pumpAndSettle();
      expect(find.text('下载队列'), findsOneWidget);
      expect(find.text('遥控拍照'), findsOneWidget);
      expect(find.text('相机预设槽位'), findsOneWidget);
      await tester.tap(find.text('遥控拍照'));
      await tester.pumpAndSettle();
      expect(remoteOpened, 1);
      expect(
        tester.getSize(find.byKey(const Key('sync-tools-dock'))),
        const Size(52, 52),
      );
    },
  );

  testWidgets('Empty floating download queue uses its content height', (
    tester,
  ) async {
    final state = AppState(_EmptyDownloadsCore());
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 351,
              child: LegacyGlassSheet(
                child: CameraDownloadsPage(
                  state: state,
                  embedded: true,
                  compact: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂无下载任务'), findsOneWidget);
    expect(
      tester.getSize(find.byType(CameraDownloadsPage)).height,
      lessThan(200),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  testWidgets(
    'Connection from Sync returns without reading photos until explicit browsing',
    (tester) async {
      final core = intent.IntentCameraCore();
      final state = AppState(core)..cameraVisible.value = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: CameraPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '连接相机'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('camera-connect')));
      await tester.pumpAndSettle();
      expect(core.photoCalls, isEmpty);
      await tester.tap(find.text('浏览相机照片'));
      await tester.pumpAndSettle();
      expect(
        core.calls.where((call) => call.$1 == 'camera.page'),
        hasLength(1),
      );
      expect(core.cancelled, isEmpty);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
