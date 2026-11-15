import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:huevia/border_panel.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/light_workspace.dart';
import 'package:huevia/photo_collage.dart';
import 'package:huevia/theme.dart';

import '../test/camera_intent_test.dart' as camera;
import '../test/camera_live_test.dart' as live;
import '../test/editor_more_test.dart' as menu;
import '../test/album_inline_selection_test.dart' as selection;
import '../test/border_panel_test.dart' as border;
import '../test/light_workspace_test.dart' as light;
import '../test/photo_collage_test.dart' as collage;

class FeaturesBinding extends IntegrationTestWidgetsFlutterBinding {
  @override
  bool get registerTestTextInput => true;
}

class PausedCollageCore extends HueviaCore {
  PausedCollageCore(this.delegate) {
    root = delegate.root;
    schema = delegate.schema;
  }
  final HueviaCore delegate;
  final release = Completer<void>();
  final cancelled = <String>{};
  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
    await delegate.cancel(jobId);
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    if (operation == 'media.reviewPreview') {
      await release.future;
      if (cancelled.contains(jobId)) throw const AppFailure('受控预览已取消');
    }
    return delegate.call(operation, payload, jobId);
  }
}

void main() {
  FeaturesBinding().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  collage.main();
  light.main();
  border.main();
  menu.main();
  selection.main();
  camera.main();
  live.main();
  testWidgets(
    'Native collage, light and lens export with phone/tablet captures',
    (tester) async {
      final core = HueviaCore();
      await core.initialize();
      final state = AppState(core);
      await state.initialize();
      final owner = state.session['user']?['id'] as String? ?? '';
      final output = Directory('${core.root}/features-six-validation');
      await output.create(recursive: true);
      final created = <Photo>[];
      final nonce = DateTime.now().microsecondsSinceEpoch;
      for (var i = 0; i < 2; i++) {
        final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 600, 400),
          Paint()
            ..shader = ui.Gradient.linear(
              Offset.zero,
              const Offset(600, 400),
              i == 0
                  ? const [Color(0xff243f4b), Color(0xffe7d1a6)]
                  : const [Color(0xff60564b), Color(0xff91a39b)],
            ),
        );
        for (var x = 0; x < 12; x++) {
          canvas.drawRect(
            Rect.fromLTWH(40 + x * 40, 80 + x * 12, 12, 200),
            Paint()..color = const Color(0x604a2415),
          );
        }
        canvas.drawRect(
          Rect.fromLTWH(0, 0, (nonce % 37 + i).toDouble() + 1, 1),
          Paint()..color = Colors.white,
        );
        final picture = recorder.endRecording(),
            image = await picture.toImage(600, 400),
            bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('${output.path}/source-$nonce-$i.png');
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
        created.add(await state.importPhoto(XFile(file.path)));
      }
      final initialDrafts = [
        for (final photo in created)
          await core.call('draft.load', {'path': photo.path, 'owner': owner}),
      ];
      Future<void> settle() async {
        for (var i = 0; i < 45; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      }

      Future<void> capture(
        String name,
        Widget surface,
        Size size, {
        bool dark = false,
        Future<void> Function()? beforeCapture,
      }) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              theme: hueviaTheme(
                dark ? Brightness.dark : Brightness.light,
                home: !dark,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.3),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: surface,
            ),
          ),
        );
        await settle();
        if (beforeCapture != null) {
          await beforeCapture();
          await settle();
        }
        expect(tester.takeException(), isNull);
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1),
            png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('${output.path}/$name.png')
            .writeAsBytes(png!.buffer.asUint8List(), flush: true);
        image.dispose();
      }

      final rows = [
        for (final photo in created)
          {'id': photo.path, 'name': photo.name, 'raw': false},
      ];
      final held = PausedCollageCore(core);
      final paused = AppState(held)
        ..session = state.session
        ..photos = List.from(state.photos);
      await capture(
        'collage-busy-phone',
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PhotoCollagePage(state: paused, rows: rows),
                ),
              ),
              child: const Text('返回相册'),
            ),
          ),
        ),
        const Size(375, 812),
        beforeCapture: () async {
          await tester.tap(find.text('返回相册'));
        },
      );
      expect(find.byKey(const Key('cancel-collage')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('返回相册'), findsOneWidget);
      expect(held.cancelled, isNotEmpty);
      held.release.complete();
      await tester.pump();
      paused.dispose();
      for (final target in [
        ('phone', const Size(375, 812)),
        ('tablet', const Size(1000, 800)),
      ]) {
        await capture(
          'collage-${target.$1}',
          PhotoCollagePage(state: state, rows: rows),
          target.$2,
        );
        expect(find.byKey(const Key('save-collage')), findsOneWidget);
        final save = tester.widget<TextButton>(
          find.byKey(const Key('save-collage')),
        );
        expect(save.onPressed, isNotNull);
        if (target.$1 == 'phone') {
          final originals = state.photos.length;
          await tester.tap(find.byKey(const Key('save-collage')));
          for (var i = 0; i < 240 && state.photos.length == originals; i++) {
            await tester.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          expect(state.photos.length, originals + 1);
          final result = state.photos.first;
          expect(result.name, startsWith('拼接_'));
          final info = await core.call('media.info', {'path': result.path});
          expect(info['width'], greaterThan(2000));
          expect(File(result.path).existsSync(), true);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        final base = await core.call('local.describe', {'localData': ''});
        final frame = await core.call('media.localPreview', {
          'path': created.first.path,
          'owner': owner,
          'recipe': Recipe().data,
          'maxEdge': 1280,
        });
        Json? applied;
        await capture(
          'light-${target.$1}',
          LightWorkspace(
            state: state,
            photo: created.first,
            owner: owner,
            recipe: Recipe().data,
            localState: base,
            frame: frame,
            isCurrent: () => true,
            onFinished: (value) => applied = value,
            onBackReady: (_) {},
            layoutBuilder: (context, photo, panel) => Scaffold(
              body: Column(
                children: [
                  Expanded(flex: 3, child: photo),
                  Expanded(flex: 2, child: panel),
                ],
              ),
            ),
          ),
          target.$2,
          dark: true,
          beforeCapture: () async {
            await tester.tap(find.widgetWithText(ChoiceChip, '侧光'));
          },
        );
        await tester.tap(find.widgetWithText(ChoiceChip, '侧光'));
        await settle();
        await tester.tap(find.byKey(const Key('apply-light')));
        await tester.pump();
        expect(applied, isNotNull);
        expect(applied!['localData'], isNotEmpty);
        final recipe = <String, dynamic>{
          ...Recipe().data,
          'localData': applied!['localData'],
          'border': {
            'template': 3,
            'showLens': true,
            'lens': 'NIKKOR Z 24-70mm f/4 S',
          },
        };
        final exported = await core.call('media.export', {
          'path': created.first.path,
          'owner': owner,
          'recipe': recipe,
          'size': 'full',
        });
        expect(File(exported['path'] as String).existsSync(), true);
        final saved = await core.call('draft.load', {
          'path': created.first.path,
          'owner': owner,
        });
        expect(object(object(saved['recipe'])['border'])['showLens'], true);
        expect(
          object(object(saved['recipe'])['border'])['lens'],
          'NIKKOR Z 24-70mm f/4 S',
        );
        await capture(
          'lens-${target.$1}',
          Scaffold(
            body: Column(
              children: [
                Expanded(child: Image.file(File(exported['path'] as String))),
                SizedBox(
                  height: 280,
                  child: BorderPanel(
                    state: state,
                    photo: created.first,
                    owner: owner,
                    recipe: recipe,
                    enabled: true,
                    onChanged: (_, _) {},
                    onDragStart: () {},
                    onUndo: () {},
                    onRedo: () {},
                    canUndo: false,
                    canRedo: false,
                  ),
                ),
              ],
            ),
          ),
          target.$2,
          dark: true,
          beforeCapture: () async {
            final scroll = find
                .descendant(
                  of: find.byKey(const Key('border-information-list')),
                  matching: find.byType(Scrollable),
                )
                .first;
            final position = tester.state<ScrollableState>(scroll).position;
            position.jumpTo(position.maxScrollExtent);
            await tester.pump();
            expect(find.byKey(const Key('border-show-lens')), findsOneWidget);
          },
        );
        final offRecipe = <String, dynamic>{
          ...recipe,
          'border': {
            ...object(recipe['border']),
            'showLens': false,
            'lens': 'NIKKOR Z 24-70mm f/4 S / NIKKOR Z 85mm f/1.8 S (manual)',
          },
        };
        final off = await core.call('media.export', {
          'path': created.first.path,
          'owner': owner,
          'recipe': offRecipe,
          'size': 'full',
        });
        await capture(
          'lens-off-${target.$1}',
          Scaffold(
            body: Column(
              children: [
                Expanded(child: Image.file(File(off['path'] as String))),
                SizedBox(
                  height: 280,
                  child: BorderPanel(
                    state: state,
                    photo: created.first,
                    owner: owner,
                    recipe: offRecipe,
                    enabled: true,
                    onChanged: (_, _) {},
                    onDragStart: () {},
                    onUndo: () {},
                    onRedo: () {},
                    canUndo: false,
                    canRedo: false,
                  ),
                ),
              ],
            ),
          ),
          target.$2,
          dark: true,
          beforeCapture: () async {
            final scroll = find
                .descendant(
                  of: find.byKey(const Key('border-information-list')),
                  matching: find.byType(Scrollable),
                )
                .first;
            final position = tester.state<ScrollableState>(scroll).position;
            position.jumpTo(position.maxScrollExtent);
            await tester.pump();
            expect(find.byKey(const Key('border-show-lens')), findsOneWidget);
          },
        );
      }
      // Collage source reads are read-only; only the deliberate light export above changes this source draft.
      expect(
        initialDrafts.last,
        await core.call('draft.load', {
          'path': created.last.path,
          'owner': owner,
        }),
      );
      await File('${output.path}/complete.json').writeAsString(
        '{"nativePhotoPipeline":true,"captures":9,"busyBackCancelled":true}',
      );
      await tester.pumpWidget(const SizedBox());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      state.dispose();
    },
  );
}
