import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/phone_album_categories.dart';
import 'package:huevia/photos.dart';
import 'package:huevia/theme.dart';

class CategoryCore extends HueviaCore {
  final calls = <(String, Json)>[];
  final pending = <String, Completer<Json>>{};
  bool defer = false;
  final rows = <Json>[
    {
      'id': 'image',
      'name': '图片.jpg',
      'raw': false,
      'mediaType': 'image',
      'date': 0,
    },
    {
      'id': 'raw',
      'name': '相机.NEF',
      'raw': true,
      'mediaType': 'image',
      'date': 0,
    },
    {
      'id': 'live',
      'name': '实况.jpg',
      'raw': false,
      'live': true,
      'mediaType': 'image',
      'date': 0,
    },
  ];

  Json page(String category, [String album = '']) {
    final result = rows
        .where(
          (r) => switch (category) {
            'raw' => r['raw'] == true,
            'live' => r['live'] == true,
            'video' => r['mediaType'] == 'video',
            'image' => r['mediaType'] == 'image' && r['raw'] != true,
            _ => true,
          },
        )
        .where(
          (r) =>
              album.isEmpty ||
              (album == 'camera' ? r['raw'] == true : r['raw'] != true),
        )
        .toList();
    return {
      'items': result,
      'total': result.length,
      'hasMore': false,
      'nextOffset': result.length,
      'albums': [
        {'id': '', 'name': '全部相册', 'count': rows.length, 'cover': 'image'},
        {'id': 'camera', 'name': '相机', 'count': 1, 'cover': 'raw'},
        {'id': 'downloads', 'name': '下载', 'count': 3, 'cover': 'image'},
      ],
    };
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, Map.of(payload)));
    if (operation == 'photo.stars') return {'keys': <String>[]};
    if (operation == 'gallery.access') {
      return {'access': 'full', 'videoAccess': 'full'};
    }
    if (operation == 'ui.preferences.set') return payload;
    if (operation == 'gallery.preview') return {'opened': true};
    if (operation == 'gallery.page') {
      final category = payload['category'] as String;
      if (defer) return (pending[category] = Completer<Json>()).future;
      return page(category, payload['album'] as String? ?? '');
    }
    throw AppFailure(operation);
  }
}

Future<AppState> showGallery(
  WidgetTester tester,
  CategoryCore core, {
  bool phone = true,
  double scale = 1,
}) async {
  final state = AppState(core)
    ..uiPreferences = {
      'album': {'source': phone ? 'phone' : 'app'},
    };
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.light),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: PhotosPage(state: state),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(state.dispose);
  return state;
}

void main() {
  testWidgets(
    'prototype album menu changes the native folder and closes outside',
    (tester) async {
      final core = CategoryCore();
      await showGallery(tester, core);
      await tester.tap(find.byKey(const ValueKey('phone-album-picker')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phone-album-menu')), findsOneWidget);
      expect(find.text('相机'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('phone-folder-camera')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phone-album-menu')), findsNothing);
      final request = core.calls
          .lastWhere((call) => call.$1 == 'gallery.page')
          .$2;
      expect(request, containsPair('album', 'camera'));
      expect(request, containsPair('offset', 0));
      expect(request, containsPair('refresh', true));
      expect(find.byKey(const ValueKey('photo-raw')), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-image')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('phone-album-picker')));
      await tester.pumpAndSettle();
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      await tester.tapAt(Offset(screen.width - 8, screen.height - 32));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phone-album-menu')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('phone-album-picker')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('phone-album-menu')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('prototype pills are compact inside a full height touch target', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.light),
        home: Scaffold(
          body: PhoneAlbumCategories(
            selected: PhoneAlbumCategory.all,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pill = find.byKey(const ValueKey('category-pill-all'));
    expect(tester.getSize(pill).height, lessThan(36));
    expect(
      tester
          .getSize(
            find.ancestor(of: pill, matching: find.byType(InkWell)).first,
          )
          .height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets(
    'album name stays readable and batch action aligns with the right inset',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final variant in [(390.0, 1.0), (360.0, 1.3)]) {
        tester.view.physicalSize = Size(variant.$1, 844);
        await showGallery(tester, CategoryCore(), scale: variant.$2);
        final name = tester.renderObject<RenderParagraph>(find.text('全部相册'));
        expect(name.didExceedMaxLines, isFalse);
        final batch = find
            .ancestor(of: find.text('批量修图'), matching: find.byType(TextButton))
            .first;
        expect(tester.getRect(batch).right, closeTo(variant.$1 - 20, .1));
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  for (final initialCategory in ['all', 'raw']) {
    testWidgets(
      'empty search recovery clears query and reloads all from $initialCategory',
      (tester) async {
        final core = CategoryCore();
        await showGallery(tester, core);
        if (initialCategory == 'raw') {
          await tester.tap(find.text('RAW'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip('搜索照片'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '不存在的照片');
        await tester.tap(find.text('搜索'));
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的照片'), findsOneWidget);
        await tester.tap(find.text('查看全部'));
        await tester.pumpAndSettle();
        final page = core.calls
            .lastWhere((call) => call.$1 == 'gallery.page')
            .$2;
        expect(page, containsPair('category', 'all'));
        expect(page, containsPair('query', ''));
        expect(page, containsPair('offset', 0));
        expect(page, containsPair('refresh', true));
        expect(find.byKey(const ValueKey('photo-image')), findsOneWidget);
      },
    );
  }
  testWidgets(
    'A filters appear only in phone album; RAW is a native query with fresh paging',
    (tester) async {
      final core = CategoryCore();
      await showGallery(tester, core, phone: false);
      expect(find.byType(PhoneAlbumCategories), findsNothing);
      await tester.tap(find.text('手机相册'));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneAlbumCategories), findsOneWidget);
      await tester.tap(find.text('RAW'));
      await tester.pumpAndSettle();
      expect(
        core.calls.lastWhere((c) => c.$1 == 'gallery.page').$2,
        containsPair('category', 'raw'),
      );
      expect(
        core.calls.lastWhere((c) => c.$1 == 'gallery.page').$2,
        containsPair('offset', 0),
      );
      expect(find.byKey(const ValueKey('photo-raw')), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-image')), findsNothing);
      await tester.tap(find.text('应用相册'));
      await tester.pumpAndSettle();
      expect(find.byType(PhoneAlbumCategories), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late RAW response cannot replace a newly selected image category',
    (tester) async {
      final core = CategoryCore();
      await showGallery(tester, core);
      core.defer = true;
      await tester.tap(find.text('RAW'));
      await tester.pump();
      await tester.tap(find.text('图片'));
      await tester.pump();
      core.pending['image']!.complete(core.page('image'));
      await tester.pumpAndSettle();
      core.pending['raw']!.complete(core.page('raw'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo-image')), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-raw')), findsNothing);
    },
  );

  test(
    'gallery excludes video and restores an obsolete video preference to all',
    () {
      expect(PhoneAlbumCategory.values.map((category) => category.id), [
        'all',
        'image',
        'live',
        'raw',
      ]);
      expect(PhoneAlbumCategory.restored('video'), PhoneAlbumCategory.all);
    },
  );

  for (final width in [320.0, 390.0, 800.0]) {
    testWidgets(
      'category bar works at width $width with large text and dark mode',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        PhoneAlbumCategory selected = PhoneAlbumCategory.all;
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.dark),
            home: MediaQuery(
              data: MediaQueryData(
                size: Size(width, 850),
                textScaler: const TextScaler.linear(2),
              ),
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) => PhoneAlbumCategories(
                    selected: selected,
                    onSelected: (value) => setState(() => selected = value),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const ValueKey('phone-album-categories')),
          const Offset(-600, 0),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('RAW'));
        await tester.pumpAndSettle();
        expect(selected, PhoneAlbumCategory.raw);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
