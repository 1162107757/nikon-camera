import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/export_settings_model.dart';

class ExportFormCore extends HueviaCore {
  final calls = <(String, Json, String?)>[];
  final cancelled = <String>[];
  String source = 'a' * 64, savedSource = 'a' * 64;
  Object? listError;
  Completer<Json>? pendingRecipe;
  Json savedRecipe = {
    'schema': 1,
    'presetId': 'saved',
    'values': List.filled(17, 0),
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
    calls.add((operation, exportCopy(payload), jobId));
    switch (operation) {
      case 'media.info':
        return {'width': 1200, 'height': 800, 'orientation': 1};
      case 'version.list':
        if (listError != null) throw listError!;
        return {
          'items': [
            {'id': 'one', 'name': '保存的胶片'},
            {'id': 'broken', 'error': 'unreadable'},
          ],
        };
      case 'version.recipe':
        if (pendingRecipe != null) return pendingRecipe!.future;
        return {'sourceSha': savedSource, 'recipe': savedRecipe};
      case 'export.describe':
        final hasBorder =
            object(object(payload['recipe'])['border'] ?? {})['template'] == 3;
        return {
          'sourceSha': source,
          'fullWidth': 1200,
          'fullHeight': hasBorder ? 934 : 800,
          'customEnabled': true,
          'minimumEdge': 640,
          'maximumEdge': 1200,
          'qualities': [
            for (final (edge, quality) in [
              (1280, 80),
              (2048, 85),
              (4096, 92),
              (0, 95),
            ])
              {
                'size': edge == 0 ? 'full' : 'custom',
                'longEdge': edge,
                'quality': quality,
                'width': 1200,
                'height': hasBorder ? 934 : 800,
                'model': 'frozen-$quality',
              },
          ],
        };
      default:
        throw StateError(
          'Unexpected write or unsupported operation $operation',
        );
    }
  }
}

class ExportFormState extends AppState {
  ExportFormState(super.core);
  void switchOwner() {
    session = {
      'user': {'id': 'another'},
    };
    notifyListeners();
  }
}

void main() {
  Future<void> tick() => Future<void>.delayed(Duration.zero);
  (ExportFormCore, ExportFormState, ExportSettings) fixture({Json? recipe}) {
    final core = ExportFormCore();
    final actualState = ExportFormState(core);
    final form = ExportSettings(
      state: actualState,
      photo: const Photo('/own/photo.png', 'own.png', {}),
      owner: '',
      recipe: recipe ?? Recipe().data,
      isCurrent: () => true,
    );
    addTearDown(() {
      form.dispose();
      actualState.dispose();
    });
    return (core, actualState, form);
  }

  test('inspection freezes the current recipe, lists original/saved versions and never writes a draft or export', () async {
    final recipe = Recipe().data;
    recipe['border'] = {'template': 3};
    final (core, _, form) = fixture(recipe: recipe);
    (recipe['border'] as Json)['template'] = 0;
    await form.load();
    expect(form.error, isNull);
    expect(form.variants.map((v) => v.label), ['当前编辑', '原图', '保存的胶片']);
    expect(form.variants.first.description['fullHeight'], 934);
    expect(form.variants[1].description['fullHeight'], 800);
    expect(
      core.calls.map((c) => c.$1),
      everyElement(
        isNot(anyOf('draft.save', 'media.export', 'media.exportPreview')),
      ),
    );
    expect(core.calls.map((c) => c.$3).toSet().length, core.calls.length);
  });

  test('multiple chosen versions retain independent frozen recipes and the original compact quality ceiling', () async {
    final (core, _, form) = fixture();
    await form.load();
    form.select('saved:one', true);
    form.chooseQuality(0);
    final items = await form.freezeSelected();
    expect(items.map((i) => i.id), ['current', 'saved:one']);
    expect(items.last.recipe['presetId'], 'saved');
    expect(
      items.every(
        (i) => i.options['longEdge'] == 1280 && i.options['quality'] == 80,
      ),
      isTrue,
    );
    core.savedRecipe['presetId'] = 'later';
    form.chooseQuality(3);
    expect(items.last.recipe['presetId'], 'saved');
    expect(items.last.options['quality'], 80);
  });

  test('a recipe being resolved pins selection and quality until the complete export snapshot is ready', () async {
    final (core, _, form) = fixture();
    await form.load();
    form.select('saved:one', true);
    core.pendingRecipe = Completer<Json>();
    final frozen = form.freezeSelected();
    await tick();
    expect(core.calls.last.$1, 'version.recipe');
    form.chooseQuality(0);
    form.select('current', false);
    expect(form.quality, 3);
    expect(form.selected, {'current', 'saved:one'});
    core.pendingRecipe!.complete({
      'sourceSha': core.source,
      'recipe': core.savedRecipe,
    });
    final items = await frozen;
    expect(items, hasLength(2));
    expect(
      items.every(
        (i) => i.options['size'] == 'full' && i.options['quality'] == 95,
      ),
      isTrue,
    );
  });

  test('account switch redacts all recipes and a late saved-version reply cannot revive the old form', () async {
    final (core, state, form) = fixture();
    await form.load();
    form.select('saved:one', true);
    core.pendingRecipe = Completer<Json>();
    final outcome = expectLater(
      form.freezeSelected(),
      throwsA(isA<AppFailure>()),
    );
    await tick();
    state.switchOwner();
    expect(form.variants, isEmpty);
    expect(form.selected, isEmpty);
    expect(form.sourceSha, isNull);
    core.pendingRecipe!.complete({
      'sourceSha': core.source,
      'recipe': core.savedRecipe,
    });
    await outcome;
    expect(form.variants, isEmpty);
    expect(form.current, isFalse);
    expect(core.cancelled, hasLength(1));
    expect(core.calls.last.$1, 'version.recipe');
  });

  test('a saved recipe from another source is rejected without silently exporting the current image', () async {
    final (core, _, form) = fixture();
    await form.load();
    form.select('saved:one', true);
    core.savedSource = 'b' * 64;
    await expectLater(form.freezeSelected(), throwsA(isA<AppFailure>()));
    expect(core.calls.last.$1, 'version.recipe');
    expect(form.error, contains('不匹配'));
  });

  test('history loading can retry, while a changed source invalidates the existing frozen form', () async {
    final (core, _, form) = fixture();
    core.listError = const AppFailure('history unavailable');
    await form.load();
    expect(form.error, contains('history unavailable'));
    expect((await form.freezeSelected()), hasLength(1));
    core.listError = null;
    await form.load();
    expect(form.error, isNull);
    core.source = 'c' * 64;
    await form.load();
    expect(form.error, contains('原图已变化'));
    await expectLater(form.freezeSelected(), throwsA(isA<AppFailure>()));
  });
}
