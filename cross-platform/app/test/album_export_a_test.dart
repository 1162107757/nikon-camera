import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/album_batch.dart';
import 'package:huevia/album_export_action.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/main.dart';
import 'package:huevia/photos.dart';
import 'package:huevia/theme.dart';

class _AlbumACore extends HueviaCore {
  final calls = <String>[];
  List<Json> get rows => [
    for (var i = 0; i < 8; i++)
      {
        'id': '/unavailable/$i.jpg',
        'name': '$i.jpg',
        'date': 0,
        'bytes': 10,
        'modified': 12,
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
      return {'items': rows, 'nextOffset': 8, 'hasMore': false};
    }
    if (operation == 'draft.statuses') {
      return {
        'items': [
          for (final path in payload['paths'] as List)
            {
              'path': path,
              'sourceSha': 'a' * 64,
              'edited': path.toString().endsWith('0.jpg'),
            },
        ],
      };
    }
    throw AppFailure(operation);
  }
}

void main() {
  for (final phone in [false, true]) {
    for (final config in [
      (const Size(375, 812), 1.0, Brightness.light),
      (const Size(320, 640), 2.0, Brightness.dark),
      (const Size(812, 375), 2.0, Brightness.light),
    ]) {
      testWidgets(
        '${phone ? 'Phone' : 'App'} A: long press, badge, circle and persistent navigation at $config',
        (tester) async {
          tester.view.physicalSize = config.$1;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final core = _AlbumACore();
          final state = AppState(core)
            ..uiPreferences = {
              'album': {'source': phone ? 'phone' : 'app'},
            }
            ..photos = [
              for (final row in core.rows)
                Photo(row['id'] as String, row['name'] as String, {
                  if (phone)
                    'gallerySources': [
                      {
                        'id': row['id'],
                        'name': row['name'],
                        'bytes': row['bytes'],
                        'modified': row['modified'],
                      },
                    ],
                }),
            ];
          await tester.pumpWidget(
            MaterialApp(
              theme: hueviaTheme(config.$3),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(config.$2)),
                child: child!,
              ),
              home: HomeFrame(
                location: '/photos',
                child: PhotosPage(state: state),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('已编辑'), findsOneWidget);
          final firstPhoto = find.byKey(
            const ValueKey('photo-/unavailable/0.jpg'),
          );
          await tester.ensureVisible(firstPhoto);
          await tester.longPressAt(
            tester.getTopLeft(firstPhoto) + const Offset(30, 30),
          );
          await tester.pumpAndSettle();
          expect(find.byType(AlbumExportAction), findsOneWidget);
          expect(
            tester
                .renderObject<RenderParagraph>(find.textContaining('已选 1 张'))
                .didExceedMaxLines,
            isFalse,
          );
          for (final label in ['预设', '同步', '设置']) {
            expect(find.text(label).hitTestable(), findsOneWidget);
          }
          final circle = find.byKey(const ValueKey('album-export-circle'));
          expect(tester.getSize(circle), const Size(56, 56));
          final actionRect = tester.getRect(find.byType(AlbumExportAction));
          final navigationRect = tester.getRect(find.text('设置').last);
          if (config.$1.width >= 600) {
            expect(actionRect.left, greaterThan(navigationRect.right));
          } else {
            expect(actionRect.bottom, lessThan(navigationRect.top));
          }
          expect(circle.hitTestable(), findsOneWidget);
          expect(
            core.calls.where(
              (call) => call.contains('export') || call.contains('delete'),
            ),
            isEmpty,
          );
          await tester.tap(circle);
          await tester.pumpAndSettle();
          final page = tester.widget<BatchExportPage>(
            find.byType(BatchExportPage),
          );
          expect(page.currentEffects, isTrue);
          expect(page.saveToGallery, isTrue);
          expect(find.text('导出照片'), findsOneWidget);
          expect(find.text('统一预设'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          state.dispose();
        },
      );
    }
  }
}
