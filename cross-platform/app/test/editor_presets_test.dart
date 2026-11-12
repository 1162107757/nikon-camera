import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/editor_presets.dart';
import 'package:huevia/widgets.dart';

class FilterCore extends HueviaCore {
  FilterCore() {
    root = '/private';
  }
  final calls = <(String, Json)>[];
  Completer<Json>? catalogReply, preparedReply, thumbnailReply;
  String? showcasePath;
  final cancelled = <String>[];
  @override
  Future<void> cancel(String jobId) async {
    cancelled.add(jobId);
  }

  @override
  Future<Json> call(String op, [Json payload = const {}, String? jobId]) async {
    calls.add((op, payload));
    if (op == 'media.showcase') return {'path': showcasePath};
    if (op == 'editor.catalog') {
      return catalogReply?.future ??
          {
            'status': 'ok',
            'items': [onlineFilter.data, onlineFilter.data],
            'message': '',
          };
    }
    if (op == 'editor.prepare') {
      return preparedReply?.future ?? {'id': 'b' * 64};
    }
    if (op == 'media.reviewPreview') {
      return thumbnailReply?.future ?? {'path': '/private/previews/filter.jpg'};
    }
    throw AppFailure(op);
  }
}

final onlineFilter = Preset({
  'id': 'catalog-id',
  'sha256': 'b' * 64,
  'name': '在线人像',
  'category': '人像',
  'previewUrl': '',
  'fileFormat': 'NCP',
}, online: true);
EditorPresets filterModel(FilterCore core) => EditorPresets(
  AppState(core),
  Photo('/private/originals/source.jpg', '照片', const {}),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Fresh editor loads online recipes and uses SHA identity without a personal-library import', () async {
    final core = FilterCore();
    final actual = filterModel(core);
    await actual.load();
    expect(actual.online, hasLength(1));
    expect(actual.state.presets, isEmpty);
    core.preparedReply = Completer<Json>();
    final first = actual.prepare(onlineFilter),
        duplicate = actual.prepare(onlineFilter);
    expect(
      core.calls.where((call) => call.$1 == 'editor.prepare'),
      hasLength(1),
    );
    core.preparedReply!.complete({'id': 'b' * 64});
    expect(await first, 'b' * 64);
    expect(await duplicate, 'b' * 64);
    expect(core.calls.any((call) => call.$1 == 'online.download'), false);
    actual.dispose();
    actual.state.dispose();
  });
  test('Filter thumbnails preserve adjustments, use tentative small renders and never save the draft', () async {
    final core = FilterCore();
    final model = filterModel(core);
    final recipe = {
      'presetId': 'previous',
      'strength': 70,
      'values': [1, 2, 3],
      'geometry': {'turns': 1},
    };
    final first = model.thumbnail(onlineFilter, recipe);
    final duplicate = model.thumbnail(onlineFilter, recipe);
    expect(await first, '/private/previews/filter.jpg');
    expect(await duplicate, '/private/previews/filter.jpg');
    final render = core.calls
        .singleWhere((call) => call.$1 == 'media.reviewPreview')
        .$2;
    expect(render['maxEdge'], 160);
    expect(render['recipe']['presetId'], 'b' * 64);
    expect(render['recipe']['values'], [1, 2, 3]);
    expect(recipe['presetId'], 'previous');
    expect(
      core.calls.any(
        (call) => call.$1 == 'draft.save' || call.$1 == 'media.preview',
      ),
      false,
    );
    model.dispose();
    model.state.dispose();
  });
  test('Offline catalog failure is retryable and late owner replies are suppressed', () async {
    final core = FilterCore();
    final model = filterModel(core);
    core.catalogReply = Completer<Json>();
    final loading = model.load();
    core.catalogReply!.complete({'status': 'network_error', 'message': '离线'});
    await loading;
    expect(model.error, contains('离线'));
    core.catalogReply = null;
    await model.load();
    expect(model.error, isNull);
    expect(model.online, hasLength(1));
    core.preparedReply = Completer<Json>();
    final pending = model.prepare(onlineFilter);
    final rejected = expectLater(pending, throwsA(isA<AppFailure>()));
    model.state.session = {
      'user': {'id': 'another'},
    };
    core.preparedReply!.complete({'id': 'b' * 64});
    await rejected;
    model.dispose();
    model.state.dispose();
  });
  testWidgets(
    'Online cards without preview URLs generate the checked recipe showcase',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync('huevia-showcase-');
      final source = File('${directory.path}/scene.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
          ),
        );
      final core = FilterCore()..showcasePath = source.path;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 100,
            height: 100,
            child: PresetImage(preset: onlineFilter, core: core),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final request = core.calls
          .singleWhere((call) => call.$1 == 'media.showcase')
          .$2;
      expect(request['id'], 'b' * 64);
      expect(request['preset']['id'], 'catalog-id');
      expect(request['edge'], 480);
      expect(find.byType(Image), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      tester.binding.imageCache.clear();
      tester.binding.imageCache.clearLiveImages();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        try {
          directory.deleteSync(recursive: true);
        } on FileSystemException {
          if (!Platform.isWindows) rethrow;
        }
      });
      expect(tester.takeException(), isNull);
    },
  );
}
