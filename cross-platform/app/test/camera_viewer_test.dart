import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_grid.dart';
import 'package:huevia/camera_previews.dart';
import 'package:huevia/camera_transfer.dart';
import 'package:huevia/domain.dart';

class ViewerCore extends HueviaCore {
  ViewerCore() {
    root = '/private/viewer-fixture';
  }
  final calls = <(String, Json)>[];
  @override
  Future<Json> call(String op, [Json payload = const {}, String? job]) async {
    calls.add((op, Map<String, dynamic>.of(payload)));
    if (op == 'camera.thumbnail') throw const AppFailure('缩略图暂不可用');
    throw AppFailure('Viewer must not initiate $op while browsing');
  }
}

class ViewerTransfer extends CameraTransfer {
  ViewerTransfer(super.state);
  void block(bool value) {
    busy = value;
    notifyListeners();
  }
}

Json photo(int handle) => {
  'handle': handle,
  'name': 'DSC_$handle.JPG',
  'bytes': 12345,
  'raw': false,
};
Future<void> open(
  WidgetTester tester,
  CameraPreviews previews,
  ViewerTransfer transfer, {
  required Json selected,
  required List<Json> photos,
  Future<void> Function(Json)? download,
  Future<void> Function()? original,
  Future<List<Json>> Function()? more,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CameraPhotoViewer(
        photo: selected,
        photos: photos,
        previews: previews,
        transfer: transfer,
        onDownload: original ?? () async {},
        onDownloadPhoto: download,
        onMore: more,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

IconButton arrow(WidgetTester tester, String label) =>
    tester.widget<IconButton>(find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == label));
FilledButton downloadButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, '接收原文件'));

void main() {
  (ViewerCore, CameraPreviews, ViewerTransfer) fixture() {
    final core = ViewerCore(), state = AppState(ViewerCore());
    final previews = CameraPreviews(core)..setSession('session-one');
    final transfer = ViewerTransfer(state);
    addTearDown(() {
      transfer.dispose();
      previews.dispose();
      state.dispose();
    });
    return (core, previews, transfer);
  }

  testWidgets(
    'next photo receives the current immutable row and prefetches thumbnails only',
    (tester) async {
      final (core, previews, transfer) = fixture();
      final received = <Json>[];
      final rows = [photo(1), photo(2), photo(3), photo(4)];
      await open(
        tester,
        previews,
        transfer,
        selected: rows[1],
        photos: rows,
        download: (row) async {
          received.add(row);
        },
      );
      expect(core.calls.map((c) => c.$2['handle']), [2, 1, 3]);
      expect(core.calls.every((c) => c.$1 == 'camera.thumbnail'), true);
      await tester.tap(find.byTooltip('下一张'));
      await tester.pumpAndSettle();
      expect(find.text('DSC_3.JPG'), findsOneWidget);
      expect(find.text('3 / 4'), findsOneWidget);
      await tester.tap(find.text('接收原文件'));
      await tester.pumpAndSettle();
      expect(received.single['handle'], 3);
      expect(() => received.single['handle'] = 1, throwsUnsupportedError);
      expect(core.calls.map((c) => c.$2['handle']).toList(), [2, 1, 3, 4]);
      expect(core.calls.any((c) => c.$1 == 'camera.download'), false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('old session and same-session reset disable all camera actions', (
    tester,
  ) async {
    final (core, previews, transfer) = fixture();
    var received = 0;
    await open(
      tester,
      previews,
      transfer,
      selected: photo(1),
      photos: [photo(1), photo(2)],
      download: (_) async {
        received++;
      },
    );
    final before = core.calls.length;
    previews.reset('session-one');
    await tester.pump();
    await tester.pump();
    expect(find.text('相机会话已变化，请返回并刷新照片。'), findsOneWidget);
    expect(arrow(tester, '下一张').onPressed, isNull);
    expect(downloadButton(tester).onPressed, isNull);
    final raw = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '核对并接收对应 RAW'),
    );
    expect(raw.onPressed, isNull);
    previews.setSession('session-two');
    await tester.pump();
    await tester.pump();
    expect(downloadButton(tester).onPressed, isNull);
    expect(received, 0);
    expect(core.calls.length, before);
  });
  testWidgets(
    'pagination deduplicates handles and does not switch while a transfer begins',
    (tester) async {
      final (core, previews, transfer) = fixture();
      final page = Completer<List<Json>>();
      var pages = 0;
      await open(
        tester,
        previews,
        transfer,
        selected: photo(2),
        photos: [photo(1), photo(1), photo(2)],
        download: (_) async {},
        more: () {
          pages++;
          return page.future;
        },
      );
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.tap(find.byTooltip('下一张'));
      await tester.pump();
      expect(find.text('正在读取下一页'), findsOneWidget);
      expect(arrow(tester, '上一张').onPressed, isNull);
      expect(downloadButton(tester).onPressed, isNull);
      transfer.block(true);
      page.complete([photo(2), photo(3), photo(3)]);
      await tester.pumpAndSettle();
      expect(find.text('DSC_2.JPG'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      expect(core.calls.any((c) => c.$2['handle'] == 3), false);
      transfer.block(false);
      await tester.pump();
      await tester.tap(find.byTooltip('下一张'));
      await tester.pumpAndSettle();
      expect(find.text('DSC_3.JPG'), findsOneWidget);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(pages, 1);
      expect(core.calls.where((c) => c.$2['handle'] == 3).length, 1);
      expect(core.calls.every((c) => c.$1 == 'camera.thumbnail'), true);
    },
  );
  testWidgets(
    'download callback blocks navigation before transfer publishes busy state',
    (tester) async {
      final (_, previews, transfer) = fixture();
      final pending = Completer<void>();
      var received = 0;
      await open(
        tester,
        previews,
        transfer,
        selected: photo(1),
        photos: [photo(1), photo(2)],
        download: (row) {
          received++;
          return pending.future;
        },
      );
      await tester.tap(find.text('接收原文件'));
      await tester.pump();
      expect(transfer.busy, false);
      expect(downloadButton(tester).onPressed, isNull);
      expect(arrow(tester, '下一张').onPressed, isNull);
      pending.complete();
      await tester.pumpAndSettle();
      expect(received, 1);
      expect(arrow(tester, '下一张').onPressed, isNotNull);
      expect(find.text('DSC_1.JPG'), findsOneWidget);
    },
  );
  testWidgets(
    'legacy download closure cannot receive a different navigated photo',
    (tester) async {
      final (_, previews, transfer) = fixture();
      var received = 0;
      await open(
        tester,
        previews,
        transfer,
        selected: photo(1),
        photos: [photo(1), photo(2)],
        original: () async {
          received++;
        },
      );
      await tester.tap(find.byTooltip('下一张'));
      await tester.pumpAndSettle();
      expect(downloadButton(tester).onPressed, isNull);
      await tester.tap(find.byTooltip('上一张'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('接收原文件'));
      await tester.pumpAndSettle();
      expect(received, 1);
    },
  );
  testWidgets(
    'pagination failure retains the current photo and can be retried',
    (tester) async {
      final (_, previews, transfer) = fixture();
      var attempt = 0;
      await open(
        tester,
        previews,
        transfer,
        selected: photo(1),
        photos: [photo(1)],
        download: (_) async {},
        more: () async {
          if (++attempt == 1) throw const AppFailure('下一页读取失败');
          return [photo(1), photo(2)];
        },
      );
      await tester.tap(find.byTooltip('下一张'));
      await tester.pumpAndSettle();
      expect(find.textContaining('下一页读取失败'), findsOneWidget);
      expect(find.text('DSC_1.JPG'), findsOneWidget);
      await tester.tap(find.byTooltip('下一张'));
      await tester.pumpAndSettle();
      expect(find.text('DSC_2.JPG'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(attempt, 2);
    },
  );
}
