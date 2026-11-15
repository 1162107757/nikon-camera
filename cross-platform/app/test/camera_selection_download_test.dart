import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_grid.dart';
import 'package:huevia/camera_selection_download.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/sync_tools_dock.dart';
import 'package:huevia/theme.dart';

import 'camera_reconnect_226_test.dart' as fixtures;

class SelectionCameraCore extends fixtures.ReconnectCore226 {
  @override
  Json snapshot({String? session, bool? isConnected}) => {
    ...super.snapshot(session: session, isConnected: isConnected),
    'inventoryReady': true,
  };

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'camera.page') {
      calls.add((operation, Map<String, dynamic>.of(payload), jobId));
      return {
        'items': [
          for (var handle = 1; handle <= 3; handle++)
            {
              'handle': handle,
              'storage': 1,
              'name': 'DSC_000$handle.JPG',
              'bytes': 5000,
              'width': 2400,
              'height': 1600,
              'raw': false,
            },
        ],
        'nextOffset': 3,
        'hasMore': false,
      };
    }
    return super.call(operation, payload, jobId);
  }
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'Download circle paints a dark 56dp disc and white icon under conflicting ${brightness.name} button themes',
      (tester) async {
        for (final enabled in [true, false]) {
          var downloads = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: hueviaTheme(brightness).copyWith(
                iconButtonTheme: const IconButtonThemeData(
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(Colors.transparent),
                    foregroundColor: WidgetStatePropertyAll(Colors.black),
                  ),
                ),
                iconTheme: const IconThemeData(color: Colors.black, size: 14),
              ),
              home: Scaffold(
                body: Center(
                  child: CameraSelectionDownload(
                    count: 137,
                    onPressed: enabled ? () => downloads++ : null,
                  ),
                ),
              ),
            ),
          );
          final action = find.byKey(const Key('camera-selection-download'));
          expect(tester.getSize(action), const Size(56, 56));
          final surface = find.descendant(
            of: action,
            matching: find.byType(Material),
          );
          expect(surface, findsOneWidget);
          final material = tester.widget<Material>(surface);
          expect(material.color, const Color(0xff242420));
          expect(material.shape, isA<CircleBorder>());
          expect(material.clipBehavior, Clip.antiAlias);
          final physicalShape = find.descendant(
            of: surface,
            matching: find.byType(PhysicalShape),
          );
          expect(physicalShape, findsOneWidget);
          final paint = tester.renderObject<RenderPhysicalShape>(physicalShape);
          expect(paint.color, const Color(0xff242420));
          expect(paint.size, const Size(56, 56));
          final outline = paint.clipper!.getClip(paint.size);
          expect(outline.contains(const Offset(28, 28)), true);
          expect(outline.contains(const Offset(28, 2)), true);
          expect(outline.contains(const Offset(1, 1)), false);
          final icon = tester.widget<Icon>(
            find.descendant(of: action, matching: find.byType(Icon)),
          );
          expect(icon.icon, Icons.download_rounded);
          expect(icon.color, Colors.white);
          expect(icon.size, 28);
          expect(find.text('99+'), findsOneWidget);
          final gesture = await tester.startGesture(tester.getCenter(action));
          await tester.pump();
          expect(paint.color, const Color(0xff242420));
          expect(icon.color, Colors.white);
          await gesture.up();
          await tester.pump(const Duration(milliseconds: 500));
          expect(downloads, enabled ? 1 : 0);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets(
    'Long press selects camera photos in place and downloads through the approved floating circle',
    (tester) async {
      final core = SelectionCameraCore()..connected = true;
      final state = fixtures.ReconnectState226(core);
      addTearDown(() => fixtures.closeReconnect226(tester, state, core));
      await fixtures.mountCamera226(tester, state);
      await fixtures.untilReconnect(
        tester,
        () => find.text('DSC_0001.JPG').evaluate().isNotEmpty,
        'Camera photos must actually be loaded',
      );
      expect(find.byKey(const Key('camera-selection-download')), findsNothing);
      await tester.longPress(find.text('DSC_0001.JPG'));
      await tester.pump();
      expect(find.text('已选 1 张'), findsOneWidget);
      expect(find.byType(CameraPhotoViewer), findsNothing);
      await tester.tap(find.text('DSC_0002.JPG'));
      await tester.pump();
      expect(find.text('已选 2 张'), findsOneWidget);
      expect(find.textContaining('接收 2 张'), findsNothing);
      expect(core.operations('camera.download'), isEmpty);
      final action = find.byKey(const Key('camera-selection-download'));
      final circle = tester.getRect(action);
      final tools = tester.getRect(find.byKey(const Key('sync-tools-dock')));
      expect(circle.width, 56);
      expect(circle.height, circle.width);
      expect(circle.center.dx, closeTo(tools.center.dx, .01));
      expect(tools.top - circle.bottom, 12);
      await tester.tap(action);
      await fixtures.untilReconnect(
        tester,
        () => find.text('接收原文件到哪里').hitTestable().evaluate().isNotEmpty,
        'The floating action must use the real download destination flow',
      );
      expect(find.text('应用相册'), findsOneWidget);
      Navigator.of(tester.element(find.byType(Dialog))).pop();
      await tester.pumpAndSettle();
      expect(find.text('已选 2 张'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pump();
      expect(find.byKey(const Key('camera-selection-download')), findsNothing);
      expect(find.text('选择'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Selection circle fits a narrow large-text screen and yields to the expanded tools panel',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var downloads = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              floatingActionButton: SyncToolsDock(
                selectionCount: 100,
                onDownloadSelection: () => downloads++,
                onDownloads: () {},
                onRemote: () {},
                onSlots: () {},
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('camera-selection-download')));
      await tester.pump();
      expect(downloads, 1);
      await tester.tap(find.byKey(const Key('sync-tools-dock')));
      await tester.pump();
      expect(find.byKey(const Key('camera-selection-download')), findsNothing);
      expect(find.byKey(const Key('sync-tools-panel')), findsOneWidget);
      await tester.tap(find.byTooltip('收起相机工具'));
      await tester.pump();
      expect(
        find.byKey(const Key('camera-selection-download')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
