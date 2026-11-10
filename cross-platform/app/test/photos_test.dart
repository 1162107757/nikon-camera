import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/photos.dart';
import 'package:huevia/theme.dart';

class PhotoCore extends HueviaCore {
  final Set<String> keys = {};
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'photo.star') {
      final key = Photo(payload['path'] as String, '', const {}).starKey;
      payload['starred'] == true ? keys.add(key) : keys.remove(key);
    } else if (operation != 'photo.stars') {
      throw AppFailure(operation);
    }
    return {'keys': keys.toList()};
  }
}

void main() {
  testWidgets(
    'Photo stars survive reload, combine with search, and keep stable editor links',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final core = PhotoCore();
      final model = AppState(core)
        ..photos = [
          const Photo('/private/originals/first.jpg', '走廊.jpg', {
            'width': 256,
            'height': 192,
          }),
          const Photo('/private/originals/second.nef', '阴天.nef', {
            'width': 512,
            'height': 384,
            'raw': true,
          }),
        ];
      final location = model.photos.first.editorLocation;
      Future<void> show() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: PhotosPage(state: model),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show();
      await tester.tap(find.byTooltip('标记星标').first);
      await tester.pumpAndSettle();
      expect(model.starredPhotos, hasLength(1));
      await tester.tap(find.text('星标').last);
      await tester.pumpAndSettle();
      expect(find.text('走廊.jpg'), findsOneWidget);
      expect(find.text('阴天.nef'), findsNothing);
      await tester.enterText(find.byType(TextField), '不存在');
      await tester.pumpAndSettle();
      expect(find.text('没有符合条件的照片'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await show();
      expect(find.byTooltip('取消星标'), findsOneWidget);
      model.photos.insert(
        0,
        const Photo('/private/originals/new.jpg', '新增.jpg', {
          'width': 1,
          'height': 1,
        }),
      );
      expect(model.photos[1].editorLocation, location);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      model.dispose();
    },
  );
}
