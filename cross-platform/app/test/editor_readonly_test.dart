import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor_details.dart';
import 'package:huevia/editor_histogram_controller.dart';

final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
);

class ReadonlyCore extends HueviaCore {
  ReadonlyCore(String directory) {
    // The real iOS bridge returns Java File.getCanonicalPath(), including
    // /private/var rather than macOS's /var temporary-directory alias.
    root = Directory(directory).resolveSymbolicLinksSync();
  }
  final calls = <(String, Json)>[];
  final cancelled = <String>[];
  Completer<Json>? held;
  bool invalidDto = false;
  bool corruptDetail = false;
  final rendered = <String>[];
  int serial = 0;
  String temporary() {
    final path =
        '$root/previews/00000000-0000-4000-8000-${(++serial).toString().padLeft(12, '0')}.png';
    File(path).writeAsBytesSync(_pixel);
    return path;
  }

  Json detail(String path) => {
    'path': path,
    'width': 1,
    'height': 1,
    'sourceSha': 'same-source',
    'temporary': true,
    'fullResolution': !invalidDto,
  };
  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    if (operation == 'source.inspect') return {'sourceSha': 'same-source'};
    if (operation == 'media.detailRender') {
      if (held != null) return held!.future;
      final output = temporary();
      rendered.add(output);
      if (corruptDetail) File(output).writeAsBytesSync([1, 2, 3]);
      return detail(output);
    }
    if (operation == 'media.reviewPreview') {
      return held?.future ?? {'path': temporary(), 'width': 1, 'height': 1};
    }
    throw AppFailure(operation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ReadonlyCore core;
  late AppState state;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('huevia-readonly-');
    Directory('${directory.path}/previews').createSync();
    core = ReadonlyCore(directory.path);
    state = AppState(core)
      ..session = {
        'user': {'id': 'alice'},
      };
  });
  tearDown(() async {
    state.dispose();
    imageCache.clear();
    imageCache.clearLiveImages();
    for (var i = 0; i < 30; i++) {
      try {
        await directory.delete(recursive: true);
        break;
      } on FileSystemException {
        if (i >= 29) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditorDetailsPage(
          state: state,
          photo: Photo('${directory.path}/original.jpg', '原照片.jpg', const {}),
          owner: 'alice',
          recipe: Recipe().data..['geometry'] = {'turns': 1},
          expectedSourceSha: 'same-source',
          isCurrent: () => true,
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();
  }

  testWidgets(
    'Detail double close during pop animation preserves its parent route',
    (tester) async {
      core.held = Completer<Json>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (root) => TextButton(
              onPressed: () => Navigator.push(
                root,
                MaterialPageRoute<void>(
                  builder: (parent) => Scaffold(
                    appBar: AppBar(title: const Text('父编辑器')),
                    body: TextButton(
                      onPressed: () => Navigator.push(
                        parent,
                        MaterialPageRoute<void>(
                          builder: (_) => EditorDetailsPage(
                            state: state,
                            photo: Photo(
                              '${directory.path}/original.jpg',
                              '照片',
                              const {},
                            ),
                            owner: 'alice',
                            recipe: Recipe().data,
                            expectedSourceSha: 'same-source',
                            isCurrent: () => true,
                          ),
                        ),
                      ),
                      child: const Text('打开细节'),
                    ),
                  ),
                ),
              ),
              child: const Text('打开父页'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开父页'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开细节'));
      await tester.pumpAndSettle();
      final close = tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == '返回照片编辑',
            ),
          )
          .onPressed!;
      await tester.tap(find.byTooltip('返回照片编辑'));
      // A queued accessibility/gesture callback still has the old closure before
      // the reverse transition has disposed the details page.
      close();
      await tester.pumpAndSettle();
      expect(find.text('父编辑器'), findsOneWidget);
      expect(find.text('打开父页'), findsNothing);
      expect(core.cancelled, isNotEmpty);
      final late = core.temporary();
      core.held!.complete(core.detail(late));
      for (var i = 0; i < 10; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(File(late).existsSync(), isFalse);

      // Owner invalidation closes data admission first; its visible back button
      // must still dismiss this route once, without dismissing the parent.
      core.held = Completer<Json>();
      await tester.tap(find.text('打开细节'));
      await tester.pumpAndSettle();
      state.session = {
        'user': {'id': 'bob'},
      };
      state.notifyListeners();
      await tester.pump();
      await tester.tap(find.byTooltip('返回照片编辑'));
      await tester.pumpAndSettle();
      expect(find.text('父编辑器'), findsOneWidget);
      final invalidLate = core.temporary();
      core.held!.complete(core.detail(invalidLate));
      for (var i = 0; i < 10; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(File(invalidLate).existsSync(), isFalse);
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'Detail decoder failure releases its cache and owned UUID before retry creates another full file',
    (tester) async {
      core.corruptDetail = true;
      await open(tester);
      for (var i = 0; i < 10; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(core.rendered, hasLength(1));
      final rejected = core.rendered.single;
      expect(File(rejected).existsSync(), isFalse);
      final status = await FileImage(File(rejected))
          .obtainCacheStatus(configuration: const ImageConfiguration());
      expect(status?.tracked, isFalse);
      expect(find.text('重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
      core.corruptDetail = false;
      await tester.tap(find.text('重试'));
      for (var i = 0; i < 12; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(core.rendered, hasLength(2));
      expect(find.textContaining('1×1 px'), findsOneWidget);
      expect(
        Directory('${directory.path}/previews')
            .listSync()
            .map((f) => f.path)
            .toList(),
        hasLength(1),
      );
      expect(File(rejected).existsSync(), isFalse);
      expect(
        core.calls.where(
          (c) =>
              c.$1 == 'media.export' ||
              c.$1.startsWith('draft.') ||
              c.$1.startsWith('version.'),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 10; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      expect(Directory('${directory.path}/previews').listSync(), isEmpty);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  testWidgets(
    'Full detail uses readonly full renderer, validates pixels and never saves a version or draft',
    (tester) async {
      await open(tester);
      expect(find.textContaining('1×1 px'), findsOneWidget);
      final request = core.calls
          .singleWhere((e) => e.$1 == 'media.detailRender')
          .$2;
      expect(request['expectedSourceSha'], 'same-source');
      expect(object(request['recipe'])['geometry'], {'turns': 1});
      expect(object(request['recipe'])['border'], isEmpty);
      await tester.tap(find.text('200%'));
      await tester.pump();
      expect(core.calls.where((e) => e.$1 == 'media.detailRender').length, 1);
      expect(
        core.calls.where(
          (e) =>
              e.$1 == 'media.export' ||
              e.$1.startsWith('draft.') ||
              e.$1.startsWith('version.') ||
              e.$1.startsWith('gallery.'),
        ),
        isEmpty,
      );
      final file = Directory('${directory.path}/previews')
          .listSync()
          .single
          .path;
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 10; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pump();
      expect(File(file).existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
  testWidgets(
    'Closing held detail cancels immediately and cleans a late native result without installation',
    (tester) async {
      core.held = Completer<Json>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => EditorDetailsPage(
                    state: state,
                    photo: Photo(
                      '${directory.path}/original.jpg',
                      '照片',
                      const {},
                    ),
                    owner: 'alice',
                    recipe: Recipe().data,
                    expectedSourceSha: 'same-source',
                    isCurrent: () => true,
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      // The native future stays unresolved; close must not wait for it.
      await tester.tap(find.byTooltip('返回照片编辑'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.byType(EditorDetailsPage), findsNothing);
      expect(core.cancelled, isNotEmpty);
      final late = core.temporary();
      core.held!.complete(core.detail(late));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pump();
      await tester.pump();
      expect(File(late).existsSync(), isFalse);
      expect(
        core.calls.where(
          (e) => e.$1 == 'media.export' || e.$1.startsWith('draft.'),
        ),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
  testWidgets(
    'Invalid full-resolution evidence is rejected and its owned temporary is removed',
    (tester) async {
      core.invalidDto = true;
      await open(tester);
      expect(find.textContaining('未取得有效的全尺寸细节文件'), findsOneWidget);
      expect(Directory('${directory.path}/previews').listSync(), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
  testWidgets(
    'Histogram geometry and warnings remain display-only and a late cancelled statistic cannot install',
    (tester) async {
      var valid = true;
      final histogram = EditorHistogramController(
        core: core,
        owner: 'alice',
        path: '${directory.path}/original.jpg',
        isCurrent: () => valid,
      );
      final recipe = Recipe().data
        ..addAll({
          'geometry': {'turns': 1},
          'border': {'template': 3},
          'localData': 'portrait-and-patches',
        });
      histogram.visible = true;
      await tester.runAsync(() => histogram.update(recipe, 'same-source'));
      expect(histogram.data?.pixelCount, 1);
      final request = core.calls
          .singleWhere((e) => e.$1 == 'media.reviewPreview')
          .$2;
      expect(object(request['recipe'])['geometry'], {'turns': 1});
      expect(object(request['recipe'])['border'], isEmpty);
      expect(recipe['border'], {'template': 3});
      expect(recipe['localData'], 'portrait-and-patches');
      await tester.runAsync(() async {
        histogram.setHighlights(true);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      expect(core.calls.length, 1);
      late String late;
      await tester.runAsync(() async {
        core.held = Completer<Json>();
        final pending = histogram.update(recipe, 'same-source');
        await Future<void>.delayed(const Duration(milliseconds: 10));
        valid = false;
        histogram.invalidate();
        late = core.temporary();
        core.held!.complete({'path': late});
        await pending;
      });
      expect(histogram.data, isNull);
      expect(histogram.warning, isNull);
      expect(File(late).existsSync(), isFalse);
      expect(core.calls.every((e) => e.$1 == 'media.reviewPreview'), isTrue);
      histogram.dispose();
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
