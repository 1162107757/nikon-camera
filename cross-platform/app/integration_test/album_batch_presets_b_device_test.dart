import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/album_batch_presets.dart';
import 'package:huevia/main.dart' show HomeFrame;
import 'package:huevia/photos.dart';
import 'package:huevia/theme.dart';

import '../test/album_batch_presets_b_test.dart' as batch_flows;

class _AlbumABinding extends IntegrationTestWidgetsFlutterBinding {
  @override
  bool get registerTestTextInput => true;
}

/// The UI gallery catalog is fixture data; drafts are real native, owner-scoped drafts.
class _CaptureCore extends HueviaCore {
  _CaptureCore(this.paths);
  final List<String> paths;
  List<Json> get rows => [
    for (var i = 0; i < paths.length; i++)
      {
        'id': 'album-a:$i',
        'name': '样片${i + 1}.jpg',
        'date': DateTime.now().millisecondsSinceEpoch,
        'bytes': File(paths[i]).lengthSync(),
        'modified': 1,
      },
  ];
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'gallery.access') return {'access': 'all'};
    if (operation == 'gallery.page') {
      return {
        'items': rows,
        'total': rows.length,
        'nextOffset': rows.length,
        'hasMore': false,
      };
    }
    if (operation == 'gallery.thumbnail') {
      return {
        'path': paths[int.parse((payload['id'] as String).split(':').last)],
      };
    }
    if (operation == 'gallery.import') {
      return {
        'path': paths[int.parse((payload['id'] as String).split(':').last)],
        'name': '原生批量测试.jpg',
      };
    }
    if (operation == 'photo.stars') return {'keys': <String>[]};
    return super.call(operation, payload, jobId);
  }
}

void main() {
  _AlbumABinding().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  testWidgets('Native B batch preset actions and read-only preview screenshots', (
    tester,
  ) async {
    final native = HueviaCore();
    await native.initialize();
    final session = await native.call('account.current');
    final owner = session['user']?['id'] as String? ?? '';
    final input = Directory('${native.root}/originals/album-a');
    final files =
        input
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.jpg'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(
      files.length,
      6,
      reason: 'Stage the six existing preset-showcase photos in this isolated emulator.',
    );
    final importing = AppState(native)..session = session;
    final importedPhotos = <Photo>[];
    for (final file in files) {
      importedPhotos.add(await importing.importPhoto(XFile(file.path)));
    }
    final paths = importedPhotos.map((photo) => photo.path).toList();
    importing.dispose();
    final core = _CaptureCore(paths)
      ..root = native.root
      ..platform = native.platform
      ..schema = native.schema;
    final output = Directory('${native.root}/album-b-captures');
    for (final i in [1, 2]) {
      await core.call('library.import', {
        'path': '${native.root}/originals/album-a/fixture-$i.ncp',
        'name': '测试预设$i.ncp',
      });
    }
    final library = await core.call('library.list');
    final localPresets = (library['items'] as List)
        .map((row) => Preset(object(row)))
        .toList();
    expect(localPresets, isNotEmpty);
    await output.create(recursive: true);
    final values = List<int>.filled(17, 0)..[0] = 4;
    for (var i = 0; i < paths.length; i++) {
      await core.call('draft.save', {
        'path': paths[i],
        'owner': owner,
        'recipe': i == 0 || i == 3 || i == 5
            ? {'values': values}
            : Recipe().data,
      });
    }
    final base = AppState(core)..session = session;
    base.photos = [
      for (var i = 0; i < paths.length; i++)
        Photo(paths[i], '样片${i + 1}.jpg', {
          ...importedPhotos[i].info,
          'addedAt': DateTime.now().millisecondsSinceEpoch,
          'gallerySources': [
            {
              'id': 'album-a:$i',
              'name': '样片${i + 1}.jpg',
              'bytes': files[i].lengthSync(),
              'modified': 1,
            },
          ],
        }),
    ];
    for (final variant in [
      ('portrait', const Size(390, 844), 1.0, Brightness.light),
      ('narrow-dark-large', const Size(320, 720), 1.7, Brightness.dark),
      ('landscape-large', const Size(812, 375), 1.7, Brightness.light),
      ('tablet', const Size(900, 1200), 1.0, Brightness.light),
    ]) {
      for (final phone in [false, true]) {
        tester.view.physicalSize = variant.$2;
        tester.view.devicePixelRatio = 1;
        // Each viewport is logical-pixel native rendering. Do not inherit the
        // host AVD's physical insets after replacing its pixel ratio.
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
        tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
        tester.view.viewInsets = const FakeViewPadding();
        final state = AppState(core)
          ..session = session
          ..presets = localPresets
          ..photos = List.of(base.photos)
          ..uiPreferences = {
            'album': {'source': phone ? 'phone' : 'app'},
          };
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: hueviaTheme(variant.$4, home: true),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(variant.$3),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: HomeFrame(
                location: '/photos',
                child: PhotosPage(state: state),
              ),
            ),
          ),
        );
        Future<void> settle() async {
          await tester.pumpAndSettle();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 700)),
          );
          await tester.pumpAndSettle();
        }

        Future<void> capture(String stateName) async {
          await settle();
          expect(tester.takeException(), isNull);
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '${output.path}/${variant.$1}-${phone ? 'phone' : 'app'}-$stateName.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }

        // Selection keeps the real album canvas and adaptive navigation mounted.
        await settle();
        final first = phone ? 'album-a:0' : paths.first;
        final firstTile = find.byKey(ValueKey('photo-$first'));
        await tester.ensureVisible(firstTile);
        await tester.longPressAt(
          tester.getTopLeft(firstTile) + const Offset(30, 30),
        );
        await settle();
        expect(find.text('导出'), findsOneWidget);
        expect(find.text('套用预设'), findsOneWidget);
        for (final label in ['预设', '同步', '设置']) {
          expect(find.text(label).hitTestable(), findsOneWidget);
        }
        await capture('selection');
        await tester.tap(find.text('套用预设'));
        await settle();
        final presetTile = find.byKey(
          ValueKey('album-batch-preset-local-${localPresets.first.id}'),
        );
        await tester.scrollUntilVisible(
          presetTile,
          100,
          scrollable: find
              .descendant(
                of: find.byType(AlbumBatchPresets),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await Scrollable.ensureVisible(tester.element(presetTile), alignment: .5);
        await settle();
        expect(presetTile.hitTestable(), findsOneWidget);
        await tester.tap(presetTile);
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
          final button = tester.widget<FilledButton>(
            find.byKey(const Key('album-batch-preset-run')),
          );
          if (button.onPressed != null) break;
        }
        final dynamic panel = tester.state(find.byType(AlbumBatchPresets));
        debugPrint(
          'B_PREVIEW_STATE error=${panel.preview.error} busy=${panel.preview.busy} frame=${panel.preview.frame?.path}',
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('album-batch-preset-run')),
              )
              .onPressed,
          isNotNull,
        );
        await capture('preset-picker');
        await tester.tap(find.byTooltip('关闭批量预设'));
        await settle();
        expect(find.byType(AlbumBatchPresets), findsNothing);

        await tester.pumpWidget(const SizedBox());
        state.dispose();
      }
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewPadding();
    tester.view.resetViewInsets();
    base.dispose();
    debugPrint('HUEVIA_ALBUM_B_CAPTURE_ROOT=${output.path}');
  });
  // Exercise the shared UI flows on the Android engine as well as the host.
  batch_flows.main();
}
