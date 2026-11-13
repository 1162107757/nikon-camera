import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/album_batch.dart';
import 'package:huevia/album_operations.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/photo_grid.dart';
import 'package:huevia/photos.dart';
import 'package:huevia/theme.dart';

class _AlbumCore extends HueviaCore {
  final calls = <String>[];
  final rows = [
    for (var i = 0; i < 18; i++)
      <String, dynamic>{
        'id': '/unavailable/$i.jpg',
        'name': '$i.jpg',
        'date': 0,
        'raw': false,
      },
  ];
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add(operation);
    if (operation == 'photo.stars') return {'keys': <String>[]};
    if (operation == 'gallery.access') return {'access': 'all'};
    if (operation == 'gallery.page') {
      return {'items': rows, 'nextOffset': 18, 'hasMore': false};
    }
    throw AppFailure(operation);
  }
}

void main() {
  for (final phone in [false, true]) {
    testWidgets(
      '${phone ? 'Phone' : 'App'} selection retains the existing grid and scroll, then back only exits selection',
      (tester) async {
        tester.view.physicalSize = phone
            ? const Size(812, 375)
            : const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final core = _AlbumCore();
        final state = AppState(core)
          ..photos = core.rows
              .map(
                (r) => Photo(r['id'] as String, r['name'] as String, const {}),
              )
              .toList()
          ..uiPreferences = {
            'album': {'source': phone ? 'phone' : 'app'},
          };
        final notifications = <bool>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.light),
            home: NotificationListener<AlbumSelectionChanged>(
              onNotification: (n) {
                notifications.add(n.active);
                return true;
              },
              child: PhotosPage(state: state),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(PhotoMasonry), const Offset(0, -700));
        await tester.pumpAndSettle();
        final element = tester.element(find.byType(PhotoMasonry));
        final scrollable = tester.state<ScrollableState>(
          find
              .descendant(
                of: find.byType(PhotoMasonry),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        final offset = scrollable.position.pixels;
        expect(offset, greaterThan(0));
        await tester.tap(find.text('选择'));
        await tester.pumpAndSettle();
        expect(tester.element(find.byType(PhotoMasonry)), same(element));
        expect(scrollable.position.pixels, closeTo(offset, .1));
        expect(find.byType(AlbumSelectionPage), findsNothing);
        expect(find.text(phone ? '已选 0 张 · 手机相册' : '已选 0 张'), findsOneWidget);
        expect(find.text(phone ? '批量编辑' : '编辑'), findsOneWidget);
        expect(find.text('导出'), phone ? findsNothing : findsOneWidget);
        expect(find.text('删除'), phone ? findsNothing : findsOneWidget);
        await tester.tap(find.text('全选'));
        await tester.pump();
        expect(find.text(phone ? '已选 18 张 · 手机相册' : '已选 18 张'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(PhotosPage), findsOneWidget);
        expect(find.byType(AlbumSelectionDock), findsNothing);
        expect(tester.element(find.byType(PhotoMasonry)), same(element));
        expect(scrollable.position.pixels, closeTo(offset, .1));
        expect(notifications, [true, true, false]);
        expect(
          core.calls.where((c) => c.contains('delete') || c.contains('export')),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox());
        state.dispose();
      },
    );
  }

  testWidgets(
    'Selection uses the protected delete confirmation and an account switch invalidates selected actions',
    (tester) async {
      final core = _AlbumCore();
      final state = AppState(core)
        ..photos = [const Photo('/unavailable/0.jpg', '0.jpg', {})]
        ..session = {
          'user': {'id': 'alice'},
        };
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: PhotosPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择'));
      await tester.pump();
      await tester.tap(find.text('全选'));
      await tester.pump();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.byType(AlbumDeletePage), findsOneWidget);
      expect(core.calls.where((c) => c.contains('delete')), isEmpty);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('已选 1 张'), findsOneWidget);
      state.acceptAuthenticatedSession({
        'verified': true,
        'user': {'id': 'bob'},
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlbumSelectionDock), findsNothing);
      expect(find.text('选择'), findsOneWidget);
      expect(core.calls.where((c) => c.contains('delete')), isEmpty);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
}
