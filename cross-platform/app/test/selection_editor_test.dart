import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/selection_editor.dart';
import 'package:huevia/selection_mask.dart';

Json seed({List<Json> strokes = const [], List<Json> shapes = const []}) => {
  'id': 'fixed-region',
  'name': '区域 1',
  'strokes': strokes,
  'shapes': shapes,
  'inverted': false,
  'enabled': true,
  'amount': 1,
  'adjustments': {'values': List.filled(17, 0)},
  'hasPortrait': true,
};
Json dot() => {
  'points': [.5, .5],
  'radius': .04,
  'feather': .2,
  'erase': false,
};
Json box() => {
  'kind': 'rectangle',
  'left': .2,
  'top': .2,
  'right': .6,
  'bottom': .6,
  'feather': .2,
  'subtract': false,
  'strokeIndex': 0,
};
SelectionEditor model(Json value) =>
    SelectionEditor(value, sourceSize: const Size(1200, 800));

void main() {
  test('Original replace mode clears once for brush and explicit rearming clears again', () {
    final original = seed();
    final editor = model(original);
    editor.begin(const Offset(.1, .2));
    editor.move(const Offset(.3, .4));
    editor.end();
    expect(editor.strokes, hasLength(1));
    editor.begin(const Offset(.4, .5));
    editor.end();
    expect(editor.strokes, hasLength(2));
    editor.chooseOperation(0);
    editor.begin(const Offset(.8, .8));
    editor.end();
    expect(editor.strokes, hasLength(1));
    editor.history(false);
    expect(editor.strokes, hasLength(2));
    editor.history(true);
    expect(editor.strokes, hasLength(1));
    expect(original['strokes'], isEmpty);
    expect(editor.region['id'], original['id']);
    expect(editor.region['adjustments'], original['adjustments']);
    editor.dispose();
  });
  test('Add and subtract are inverted with the visible selection as in the original', () {
    final editor = model(seed(strokes: [dot()]));
    editor.toggleInverted();
    editor.chooseOperation(1);
    editor.begin(const Offset(.1, .1));
    editor.end();
    expect(editor.strokes.last['erase'], true);
    editor.chooseOperation(2);
    editor.begin(const Offset(.9, .9));
    editor.end();
    expect(editor.strokes.last['erase'], false);
    final coverage = SelectionCoverage(editor.region, 1200, 800);
    expect(coverage.weight(.1, .1), closeTo(1, 1e-12));
    expect(coverage.weight(.9, .9), closeTo(0, 1e-12));
    editor.dispose();
  });
  test('Pointer cancellation for pinch restores the selection, history and replace state', () {
    final editor = model(seed(strokes: [dot()]));
    editor.chooseOperation(0);
    final before = jsonEncode(editor.region);
    editor.begin(const Offset(.1, .1));
    editor.move(const Offset(.8, .8));
    expect(editor.displayRegion['strokes'], hasLength(1));
    editor.cancel();
    expect(jsonEncode(editor.region), before);
    expect(editor.undo, isEmpty);
    expect(editor.replaceArmed, true);
    expect(editor.tracking, false);
    editor.dispose();
  });
  test('Shape corners flip around their opposite corner and movement remains in frame', () {
    final editor = model(seed(shapes: [box()]));
    editor.chooseTool(2);
    editor.chooseOperation(0);
    editor.begin(const Offset(.2, .2), shapeIndex: 0, handle: 0);
    editor.move(const Offset(.1, .15));
    editor.end();
    expect(editor.shapes.single['left'], .1);
    expect(editor.shapes.single['top'], .15);
    expect(editor.shapes.single['right'], .6);
    expect(editor.shapes.single['bottom'], .6);
    editor.begin(const Offset(.3, .3), shapeIndex: 0, handle: 4);
    editor.move(const Offset(2, 2));
    editor.end();
    expect(editor.shapes.single['left'], closeTo(.5, 1e-12));
    expect(editor.shapes.single['top'], closeTo(.55, 1e-12));
    expect(editor.shapes.single['right'], 1);
    expect(editor.shapes.single['bottom'], 1);
    expect(editor.shapes.single['strokeIndex'], 0);
    editor.dispose();
  });
  test('An empty shape tap preserves the original; new shapes keep stroke ordering', () {
    final editor = model(seed(strokes: [dot()]));
    final before = jsonEncode(editor.region);
    editor.chooseTool(1);
    editor.chooseOperation(0);
    editor.begin(const Offset(.1, .1));
    editor.end();
    expect(jsonEncode(editor.region), before);
    expect(editor.undo, isEmpty);
    editor.chooseOperation(1);
    editor.begin(const Offset(.2, .3));
    editor.move(const Offset(.7, .8));
    editor.end();
    expect(editor.shapes.single['kind'], 'ellipse');
    expect(editor.shapes.single['strokeIndex'], 1);
    expect(editor.strokes, hasLength(1));
    editor.dispose();
  });
  test('Feather changes only the active shape and one slider gesture records one undo', () {
    final editor = model(
      seed(
        strokes: [dot()],
        shapes: [
          {...box(), 'strokeIndex': 1},
        ],
      ),
    );
    editor.chooseTool(2);
    editor.beginSlider();
    editor.setFeather(.4);
    editor.setFeather(.8);
    editor.endSlider();
    expect(editor.shapes.single['feather'], .8);
    expect(editor.strokes.single['feather'], .2);
    expect(editor.undo, hasLength(1));
    editor.history(false);
    expect(editor.shapes.single['feather'], .2);
    editor.chooseTool(0);
    editor.beginSlider();
    editor.setRadius(.08);
    editor.setFeather(.6);
    editor.endSlider();
    expect(editor.strokes.single['radius'], .04);
    expect(editor.strokes.single['feather'], .2);
    expect(editor.undo, isEmpty);
    editor.dispose();
  });
  test('Original point and history limits remain bounded and overflow preserves prior data', () {
    final editor = model(seed());
    editor.begin(Offset.zero);
    for (var i = 1; i <= 1000; i++) {
      editor.move(Offset(i / 1000, .5));
    }
    editor.end();
    expect(editor.strokes.single['points'], hasLength(1024));
    final full = model(seed(strokes: List.generate(64, (_) => dot())));
    final before = jsonEncode(full.region);
    full.chooseOperation(1);
    full.begin(const Offset(.1, .1));
    full.end();
    expect(jsonEncode(full.region), before);
    expect(full.error, contains('已达上限'));
    expect(full.undo, isEmpty);
    for (var i = 0; i < 40; i++) {
      editor.toggleInverted();
    }
    expect(editor.undo, hasLength(32));
    editor.dispose();
    full.dispose();
  });
  test('Clearing an existing region remains confirmable while an empty new region does not', () {
    final editor = model(seed(strokes: [dot()]));
    editor.clear();
    expect(editor.canComplete(false), true);
    expect(selectionHasContent(editor.region), false);
    expect(editor.region['hasPortrait'], true);
    expect(editor.region['adjustments'], editor.original['adjustments']);
    final empty = model(seed());
    expect(empty.canComplete(false), false);
    editor.history(false);
    expect(editor.strokes, hasLength(1));
    editor.begin(const Offset(.2, .2));
    expect(editor.canComplete(true), false);
    editor.cancel();
    editor.dispose();
    empty.dispose();
  });
}
