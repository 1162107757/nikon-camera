import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'domain.dart';

Json selectionCopy(Json value) => object(jsonDecode(jsonEncode(value)));
List<Json> selectionItems(Json value, String key) =>
    (value[key] as List? ?? const []).map(object).toList();
bool selectionHasContent(Json value) =>
    selectionItems(value, 'strokes').any((s) => s['erase'] != true) ||
    selectionItems(value, 'shapes').any((s) => s['subtract'] != true);

/// Tentative PhotoBrushDialog behavior. Only explicit completion reaches the
/// shared binary adapter; pointer cancellation and pinch navigation roll back.
class SelectionEditor extends ChangeNotifier {
  SelectionEditor(Json seed, {required this.sourceSize})
    : original = selectionCopy(seed),
      region = selectionCopy(seed) {
    operation = selectionHasContent(seed) ? 1 : 0;
    replaceArmed = operation == 0;
  }
  final Size sourceSize;
  final Json original;
  Json region;
  final undo = <Json>[], redo = <Json>[];
  int tool = 0, operation = 0, activeShape = -1;
  bool replaceArmed = true,
      showSelection = true,
      tracking = false,
      adjusting = false;
  double radius = .04, feather = .2;
  String? error;
  Json? _gesture, _shapeStart, _sliderStart;
  bool _gestureReplace = true;
  Offset _down = Offset.zero;
  int _shapeIndex = -1, _handle = -1;
  final _path = <double>[];

  bool get changed => jsonEncode(region) != jsonEncode(original);
  bool canComplete(bool hasCoverage) =>
      !tracking &&
      !adjusting &&
      (hasCoverage || selectionHasContent(original) && changed);
  bool get inverted => region['inverted'] == true;
  List<Json> get strokes => selectionItems(region, 'strokes');
  List<Json> get shapes => selectionItems(region, 'shapes');
  Json get displayRegion => tracking && tool == 0 && _path.isNotEmpty
      ? {
          ...region,
          'strokes': [...strokes, _liveStroke()],
        }
      : region;
  int get selectedShapeIndex {
    if (tool == 0) return -1;
    final values = shapes, kind = tool == 1 ? 'ellipse' : 'rectangle';
    if (activeShape >= 0 &&
        activeShape < values.length &&
        values[activeShape]['kind'] == kind) {
      return activeShape;
    }
    return values.lastIndexWhere((shape) => shape['kind'] == kind);
  }

  Json? get selectedShape {
    final index = selectedShapeIndex;
    return index < 0 ? null : shapes[index];
  }

  void chooseTool(int value) {
    cancel();
    tool = value.clamp(0, 2);
    showSelection = true;
    final shape = selectedShape;
    if (shape != null) feather = (shape['feather'] as num).toDouble();
    notifyListeners();
  }

  void chooseOperation(int value) {
    cancel();
    operation = value.clamp(0, 2);
    replaceArmed = operation == 0;
    notifyListeners();
  }

  void toggleOverlay() {
    showSelection = !showSelection;
    notifyListeners();
  }

  void toggleInverted() {
    cancel();
    if (!selectionHasContent(region)) return;
    final before = selectionCopy(region);
    region = {...region, 'inverted': !inverted};
    _remember(before);
    showSelection = true;
    notifyListeners();
  }

  void clear() {
    cancel();
    final before = selectionCopy(region);
    _clearSelection();
    _remember(before);
    error = null;
    notifyListeners();
  }

  void _clearSelection() {
    region = {
      ...region,
      'strokes': <Json>[],
      'shapes': <Json>[],
      'inverted': false,
    };
    activeShape = -1;
  }

  void _remember(Json before) {
    if (jsonEncode(before) == jsonEncode(region)) return;
    undo.add(before);
    if (undo.length > 32) undo.removeAt(0);
    redo.clear();
  }

  void history(bool forward) {
    cancel();
    final from = forward ? redo : undo, to = forward ? undo : redo;
    if (from.isEmpty) return;
    to.add(selectionCopy(region));
    if (to.length > 32) to.removeAt(0);
    region = from.removeLast();
    showSelection = true;
    error = null;
    final shape = selectedShape;
    if (shape != null) feather = (shape['feather'] as num).toDouble();
    notifyListeners();
  }

  void beginSlider() {
    cancel();
    _sliderStart = selectionCopy(region);
    adjusting = true;
    notifyListeners();
  }

  void setRadius(double value) {
    radius = value.clamp(.001, .12);
    notifyListeners();
  }

  void setFeather(double value) {
    feather = value.clamp(0.0, 1.0);
    final index = selectedShapeIndex;
    if (tool > 0 && index >= 0) {
      final values = shapes;
      values[index] = {...values[index], 'feather': feather};
      region = {...region, 'shapes': values};
    }
    notifyListeners();
  }

  void endSlider() {
    final before = _sliderStart;
    _sliderStart = null;
    adjusting = false;
    if (before != null) _remember(before);
    notifyListeners();
  }

  Offset _point(Offset p) => Offset(p.dx.clamp(0.0, 1.0), p.dy.clamp(0.0, 1.0));
  void begin(Offset point, {int shapeIndex = -1, int handle = -1}) {
    if (adjusting) return;
    cancel();
    _gesture = selectionCopy(region);
    _gestureReplace = replaceArmed;
    _down = _point(point);
    tracking = true;
    showSelection = true;
    error = null;
    if (tool > 0 &&
        operation == 0 &&
        shapeIndex >= 0 &&
        shapeIndex < shapes.length &&
        handle >= 0) {
      _shapeIndex = activeShape = shapeIndex;
      _handle = handle;
      _shapeStart = selectionCopy(shapes[shapeIndex]);
    } else {
      if (operation == 0 && (tool > 0 || replaceArmed)) {
        _clearSelection();
        replaceArmed = false;
      }
      if (tool == 0) _path.addAll([_down.dx, _down.dy]);
    }
    notifyListeners();
  }

  Json _liveStroke() => {
    'points': List<double>.of(_path),
    'radius': radius,
    'feather': feather,
    'erase': (operation == 2) != inverted,
  };
  void move(Offset point) {
    if (!tracking) return;
    final p = _point(point);
    if (tool == 0) {
      final n = _path.length;
      if (n >= 2 && n < 1024) {
        final dx = (p.dx - _path[n - 2]) * sourceSize.width,
            dy = (p.dy - _path[n - 1]) * sourceSize.height;
        if (math.sqrt(dx * dx + dy * dy) > .001 * sourceSize.shortestSide) {
          _path.addAll([p.dx, p.dy]);
        }
      }
    } else {
      _moveShape(p);
    }
    notifyListeners();
  }

  void _moveShape(Offset p) {
    var left = 0.0, top = 0.0, right = 0.0, bottom = 0.0;
    final start = _shapeStart;
    if (_handle == 4 && start != null) {
      final l = (start['left'] as num).toDouble(),
          t = (start['top'] as num).toDouble(),
          r = (start['right'] as num).toDouble(),
          b = (start['bottom'] as num).toDouble();
      final dx = (p.dx - _down.dx).clamp(-l, 1 - r),
          dy = (p.dy - _down.dy).clamp(-t, 1 - b);
      left = l + dx;
      right = r + dx;
      top = t + dy;
      bottom = b + dy;
    } else {
      final ax = _handle < 0 || start == null
              ? _down.dx
              : (start[_handle.isEven ? 'right' : 'left'] as num).toDouble(),
          ay = _handle < 0 || start == null
              ? _down.dy
              : (start[_handle < 2 ? 'bottom' : 'top'] as num).toDouble();
      left = math.min(ax, p.dx);
      right = math.max(ax, p.dx);
      top = math.min(ay, p.dy);
      bottom = math.max(ay, p.dy);
    }
    if (right - left < .0001 || bottom - top < .0001) return;
    final values = shapes;
    if (_shapeIndex < 0) {
      values.add({
        'kind': tool == 1 ? 'ellipse' : 'rectangle',
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
        'feather': feather,
        'subtract': (operation == 2) != inverted,
        'strokeIndex': strokes.length,
      });
    } else {
      values[_shapeIndex] = {
        ...values[_shapeIndex],
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
      };
    }
    final next = {...region, 'shapes': values};
    if (!_withinLimits(next)) {
      error = '选区元素已达上限，请撤销或清空后重试。';
      return;
    }
    region = next;
    if (_shapeIndex < 0) _shapeIndex = activeShape = values.length - 1;
  }

  bool _withinLimits(Json value) {
    final a = selectionItems(value, 'strokes'),
        b = selectionItems(value, 'shapes');
    return a.length + b.length <= 64 &&
        a.fold<int>(0, (n, s) => n + (s['points'] as List).length ~/ 2) <= 8192;
  }

  void end({Offset? point}) {
    if (!tracking) return;
    if (point != null) move(point);
    final before = _gesture!;
    if (tool == 0) {
      final next = {
        ...region,
        'strokes': [...strokes, _liveStroke()],
      };
      if (_withinLimits(next)) {
        region = next;
      } else {
        region = before;
        error = '选区元素已达上限，请撤销或清空后重试。';
      }
    } else if (_shapeIndex < 0) {
      region = before;
    }
    tracking = false;
    _gesture = null;
    _path.clear();
    _shapeIndex = _handle = -1;
    _shapeStart = null;
    _remember(before);
    notifyListeners();
  }

  void cancel() {
    if (_gesture != null) {
      region = _gesture!;
      replaceArmed = _gestureReplace;
    }
    final wasTracking = tracking;
    tracking = false;
    _gesture = null;
    _shapeStart = null;
    _shapeIndex = _handle = -1;
    _path.clear();
    if (wasTracking) notifyListeners();
  }
}
