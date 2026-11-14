import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/editing_viewport.dart';

void pointClose(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, 1e-8));
  expect(actual.dy, closeTo(expected.dy, 1e-8));
}

void main() {
  test('A cropped fit view keeps its sampled source center and density in a full-frame tool', () {
    final shared = EditingViewportState();
    final transform = TransformationController();
    final binding = EditingViewportBinding(
      shared: shared,
      transform: transform,
    );
    final cropped = EditingViewportPlane.fromRecipe({
      'geometry': {'left': 500000},
    }, sourceSize: const Size(4000, 3000));
    const viewport = Size(400, 600);
    binding.layout(
      viewport: viewport,
      imageRect: const Rect.fromLTWH(0, 0, 400, 600),
      plane: cropped,
    );
    pointClose(shared.focus, const Offset(.75, .5));
    expect(transform.value.getMaxScaleOnAxis(), 1);
    binding.layout(
      viewport: viewport,
      imageRect: const Rect.fromLTWH(0, 150, 400, 300),
    );
    final fullPoint = transform.toScene(viewport.center(Offset.zero));
    pointClose(
      Offset(fullPoint.dx / 400, (fullPoint.dy - 150) / 300),
      const Offset(.75, .5),
    );
    expect(transform.value.getMaxScaleOnAxis(), closeTo(2, 1e-8));
    binding.layout(
      viewport: viewport,
      imageRect: const Rect.fromLTWH(0, 0, 400, 600),
      plane: cropped,
    );
    expect(transform.value, Matrix4.identity());
    pointClose(shared.focus, const Offset(.75, .5));
    binding.dispose();
    transform.dispose();
  });
  test('Tool planes match actual native rotation, mirror, straighten, perspective and crop', () {
    final golden = jsonDecode(
      File('test/fixtures/viewport_geometry.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final plane = EditingViewportPlane.fromRecipe({
      'geometry': golden['geometry'],
    }, sourceSize: const Size(4000, 3000));
    for (final row in golden['points'] as List) {
      final source = row['source'] as List, image = row['image'] as List;
      final point = Offset(
        (source[0] as num).toDouble(),
        (source[1] as num).toDouble(),
      );
      final mapped = Offset(
        (image[0] as num).toDouble(),
        (image[1] as num).toDouble(),
      );
      pointClose(plane.fromSource(point), mapped);
      pointClose(plane.toSource(mapped), point);
    }
  });

  test('Crop and border planes identify the same source detail', () {
    final plane = EditingViewportPlane.fromRecipe(
      {
        'geometry': {
          'turns': 1,
          'mirrored': true,
          'left': 100000,
          'top': 100000,
          'right': 900000,
          'bottom': 900000,
        },
      },
      sourceSize: const Size(4000, 3000),
      contentRect: const Rect.fromLTWH(.1, .2, .8, .6),
    );
    pointClose(plane.fromSource(const Offset(.2, .3)), const Offset(.3, .275));
    pointClose(plane.toSource(const Offset(.3, .275)), const Offset(.2, .3));
  });

  test('Different panel heights retain the source pixel at its screen position and magnification', () {
    final shared = EditingViewportState();
    final first = TransformationController();
    final binding = EditingViewportBinding(shared: shared, transform: first);
    binding.layout(
      viewport: const Size(600, 500),
      imageRect: const Rect.fromLTWH(0, 50, 600, 400),
    );
    first.value = Matrix4.identity()
      ..setEntry(0, 0, 4)
      ..setEntry(1, 1, 4)
      ..setEntry(0, 3, -1620)
      ..setEntry(1, 3, -590);
    pointClose(shared.focus, const Offset(.8, .4));
    final oldDensity = first.value.getMaxScaleOnAxis() * 600;
    binding.layout(
      viewport: const Size(600, 350),
      imageRect: const Rect.fromLTWH(37.5, 0, 525, 350),
    );
    // The panel has changed height, so retain the original on-screen anchor
    // instead of recentering the source pixel in the new photograph bounds.
    final center = first.toScene(const Offset(300, 250));
    pointClose(
      Offset((center.dx - 37.5) / 525, center.dy / 350),
      const Offset(.8, .4),
    );
    expect(first.value.getMaxScaleOnAxis() * 525, closeTo(oldDensity, 1e-8));
    binding.dispose();
    first.dispose();
  });

  test('Returning from a rotated cropped tool restores the source location without a fit', () {
    final shared = EditingViewportState();
    final transform = TransformationController();
    final binding = EditingViewportBinding(
      shared: shared,
      transform: transform,
    );
    const viewport = Size(600, 400), image = Rect.fromLTWH(0, 0, 600, 400);
    binding.layout(viewport: viewport, imageRect: image);
    transform.value = Matrix4.identity()
      ..setEntry(0, 0, 3)
      ..setEntry(1, 1, 3)
      ..setEntry(0, 3, -960)
      ..setEntry(1, 3, -280);
    final focus = shared.focus;
    final plane = EditingViewportPlane.fromRecipe({
      'geometry': {'turns': 1, 'left': 100000, 'right': 900000},
    }, sourceSize: const Size(600, 400));
    binding.layout(viewport: viewport, imageRect: image, plane: plane);
    final point = transform.toScene(viewport.center(Offset.zero));
    pointClose(plane.toSource(Offset(point.dx / 600, point.dy / 400)), focus);
    expect(transform.value.getMaxScaleOnAxis(), greaterThan(1));
    binding.layout(viewport: viewport, imageRect: image);
    pointClose(
      transform.toScene(viewport.center(Offset.zero)),
      Offset(focus.dx * 600, focus.dy * 400),
    );
    expect(transform.value.getMaxScaleOnAxis(), closeTo(3, 1e-8));
    binding.dispose();
    transform.dispose();
  });

  test('A replacement canvas owns sampling before the previous canvas is disposed', () {
    final shared = EditingViewportState();
    final oldTransform = TransformationController();
    final nextTransform = TransformationController();
    final oldHost = EditingViewportBinding(
      shared: shared,
      transform: oldTransform,
    );
    final nextHost = EditingViewportBinding(
      shared: shared,
      transform: nextTransform,
    );
    oldHost.layout(
      viewport: const Size(400, 588),
      imageRect: const Rect.fromLTWH(0, 94, 400, 400),
    );
    oldTransform.value = Matrix4.identity()
      ..setEntry(0, 0, 3)
      ..setEntry(1, 1, 3)
      ..setEntry(0, 3, -544)
      ..setEntry(1, 3, -480);
    final focus = shared.focus, revision = shared.revision;
    nextHost.layout(
      viewport: const Size(400, 404),
      imageRect: const Rect.fromLTWH(0, 2, 400, 400),
    );
    // During a tool switch both widget states briefly listen to the controller.
    // A notification interpreted with the retired dimensions must be ignored.
    oldTransform.value = Matrix4.copy(nextTransform.value);
    pointClose(shared.focus, focus);
    expect(shared.revision, revision);
    nextTransform.value = Matrix4.copy(nextTransform.value)
      ..translateByDouble(10, 15, 0, 1);
    expect(shared.focus, isNot(focus));
    oldHost.dispose();
    nextHost.dispose();
    oldTransform.dispose();
    nextTransform.dispose();
  });

  test('Hidden hosts cannot overwrite the active tool viewport; explicit fit resets it', () {
    final shared = EditingViewportState();
    final a = TransformationController(), b = TransformationController();
    final first = EditingViewportBinding(shared: shared, transform: a);
    final second = EditingViewportBinding(shared: shared, transform: b);
    const viewport = Size(400, 400), image = Rect.fromLTWH(0, 0, 400, 400);
    first.layout(viewport: viewport, imageRect: image);
    a.value = Matrix4.identity()
      ..setEntry(0, 0, 4)
      ..setEntry(1, 1, 4)
      ..setEntry(0, 3, -1080)
      ..setEntry(1, 3, -920);
    final focus = shared.focus, revision = shared.revision;
    first.layout(viewport: viewport, imageRect: image, active: false);
    a.value = Matrix4.identity();
    expect(shared.revision, revision);
    second.layout(viewport: viewport, imageRect: image);
    pointClose(
      b.toScene(viewport.center(Offset.zero)),
      Offset(focus.dx * 400, focus.dy * 400),
    );
    b.value = Matrix4.identity();
    expect(shared.zoom, 1);
    first.layout(viewport: viewport, imageRect: image);
    expect(a.value, Matrix4.identity());
    first.dispose();
    second.dispose();
    a.dispose();
    b.dispose();
  });
}
