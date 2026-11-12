import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/legacy_local_editor.dart';

void main() {
  const frame = Size(800, 600);
  LegacyLocalEditor editor() => LegacyLocalEditor({'masks': [], 'clones': []});

  test('legacy brush uses original 2dp sampling, source-relative radius and one gesture history', () {
    final e = editor();
    e.begin(const Offset(.2, .3), frame);
    e.move(const Offset(.201, .3));
    e.move(const Offset(.3, .4));
    e.end();
    expect(e.mask!['points'], [.2, .3, .3, .4]);
    expect(e.mask!['radius'], .06);
    expect(e.mask!['feather'], .6);
    expect(e.undo, hasLength(1));
    e.begin(const Offset(.2, .3), frame);
    e.move(const Offset(1, 1));
    e.end();
    expect(e.mask!['points'], [1.0, 1.0, 1.0, 1.0]);
    e.history(false);
    expect(e.mask!['points'], [.2, .3, .3, .4]);
    e.dispose();
  });

  test('multi-touch cancellation restores selection and clone source without adding history', () {
    final e = editor();
    e.begin(const Offset(.2, .3), frame);
    e.move(const Offset(.4, .5));
    e.cancel();
    expect(e.masks, isEmpty);
    expect(e.selectedMask, -1);
    expect(e.adding, isTrue);
    expect(e.undo, isEmpty);
    e.selectTool(3);
    e.begin(const Offset(.2, .3), frame);
    expect(e.sourceSet, isTrue);
    e.cancel();
    expect(e.sourceSet, isFalse);
    expect((e.sourceX, e.sourceY), (.35, .4));
    e.begin(const Offset(.2, .3), frame);
    e.end();
    expect(e.undo, isEmpty);
    e.begin(const Offset(.8, .7), frame);
    e.move(const Offset(.9, .9));
    e.cancel();
    expect(e.clones, isEmpty);
    expect((e.sourceX, e.sourceY), (.2, .3));
    expect(e.sourceSet, isTrue);
    e.dispose();
  });

  test('radial resizing preserves aspect ratio and repeated move events stay anchored', () {
    final e = editor()..selectTool(1);
    e.begin(const Offset(.5, .5), const Size(1000, 1000));
    e.move(const Offset(.7, .6));
    e.end();
    expect(e.mask!['x1'], closeTo(.2, 1e-12));
    expect(e.mask!['y1'], closeTo(.1, 1e-12));
    e.beginAdjustment();
    e.adjust(300);
    e.adjust(400);
    e.endAdjustment();
    expect(e.mask!['x1'], .4);
    expect(e.mask!['y1'], closeTo(.2, 1e-12));
    expect(e.undo, hasLength(2));
    e.begin(const Offset(.5, .5), const Size(1000, 1000));
    e.move(const Offset(.7, .9));
    e.move(const Offset(.8, .95));
    e.end();
    expect(e.mask!['x0'], closeTo(.8, 1e-12));
    expect(e.mask!['y0'], closeTo(.95, 1e-12));
    expect(e.mask!['x1'], .4);
    e.dispose();
  });

  test('linear endpoint protection and parameter selection follow the original editor', () {
    final e = editor()..selectTool(2);
    expect(e.parameter, 4);
    e.begin(const Offset(.2, .3), frame);
    e.move(const Offset(.8, .7));
    e.end();
    expect(e.mask!['x0'], closeTo(.19, 1e-12));
    expect(e.mask!['x1'], .8);
    e.chooseParameter(0);
    e.adjust(12);
    expect(e.mask!['exposure'], 12);
    e.chooseParameter(3);
    expect(e.parameter, 4);
    e.begin(const Offset(.8, .7), frame);
    e.move(const Offset(.19, .3));
    e.end();
    expect(e.mask!['x1'], .8);
    expect(e.mask!['y1'], .7);
    e.dispose();
  });

  test(
    'clone requires a sample point and moves each endpoint independently',
    () {
      final e = editor()..selectTool(3);
      e.begin(const Offset(.2, .3), frame);
      e.end();
      expect(e.clones, isEmpty);
      e.begin(const Offset(.8, .7), frame);
      e.end();
      expect(e.clones, hasLength(1));
      expect(e.undo, hasLength(1));
      e.begin(const Offset(.2, .3), frame);
      e.move(const Offset(.4, .5));
      e.end();
      expect(e.clone!['sourceX'], .4);
      expect(e.clone!['sourceY'], .5);
      expect(e.clone!['targetX'], .8);
      e.begin(const Offset(.9, .9), frame);
      e.move(const Offset(.1, .1));
      e.end();
      expect(e.clone!['sourceX'], .4);
      expect(e.clone!['targetX'], .1);
      e.chooseParameter(3);
      e.adjust(1000);
      expect(e.clone!['radius'], .25);
      e.newSelection();
      expect(e.sourceSet, isFalse);
      e.dispose();
    },
  );

  test('original brush and collection limits remain bounded', () {
    final e = editor();
    e.begin(const Offset(.1, .1), frame);
    for (var i = 0; i < 700; i++) {
      e.move(Offset((i % 97) / 100, (i % 89) / 100));
    }
    e.end();
    expect(e.mask!['points'] as List, hasLength(1024));
    for (var i = 1; i < 16; i++) {
      e.newSelection();
      e.begin(const Offset(.5, .5), frame);
      e.end();
    }
    expect(e.canAdd, isFalse);
    e.newSelection();
    expect(e.masks, hasLength(16));
    e.selectTool(3);
    for (var i = 0; i < 64; i++) {
      e.newSelection();
      e.begin(const Offset(.2, .2), frame);
      e.end();
      e.begin(const Offset(.7, .7), frame);
      e.end();
    }
    expect(e.clones, hasLength(64));
    expect(e.canAdd, isFalse);
    e.dispose();
  });

  test('undo stays bounded and a new edit clears redo without erasing selection metadata', () {
    final e = editor();
    e.begin(const Offset(.2, .3), frame);
    e.end();
    e.chooseParameter(0);
    for (var i = 0; i < 45; i++) {
      e.adjust(i % 31);
    }
    expect(e.undo, hasLength(32));
    e.history(false);
    expect(e.redo, hasLength(1));
    e.adjust(17);
    expect(e.redo, isEmpty);
    e.invert();
    e.toggleEnabled();
    expect(e.mask!['inverted'], isTrue);
    expect(e.mask!['enabled'], isFalse);
    expect(e.mask!['points'], [.2, .3]);
    e.remove();
    expect(e.masks, isEmpty);
    e.history(false);
    expect(e.masks.single['inverted'], isTrue);
    expect(e.masks.single['enabled'], isFalse);
    e.dispose();
  });

  test(
    'invalid viewport or pointer data never starts or corrupts a gesture',
    () {
      final e = editor();
      e.begin(const Offset(.2, .3), const Size(double.nan, 1));
      expect(e.tracking, isFalse);
      e.begin(const Offset(double.nan, .3), frame);
      expect(e.tracking, isFalse);
      e.begin(const Offset(.2, .3), frame);
      e.move(const Offset(double.infinity, .5));
      e.end();
      expect(e.mask!['points'], [.2, .3]);
      e.dispose();
    },
  );
}
