import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'domain.dart';

Json toolsCopy(Json value) => object(jsonDecode(jsonEncode(value)));

/// Tentative PhotoLocalEditDialog gestures, preserving all unrelated binary
/// groups by committing only complete legacy mask/clone collections.
class LegacyLocalEditor extends ChangeNotifier {
  LegacyLocalEditor(Json descriptor)
    : tools = toolsCopy({
        'masks': descriptor['masks'] ?? [],
        'clones': descriptor['clones'] ?? [],
      });

  Json tools;
  final undo = <Json>[], redo = <Json>[];
  int tool = 0, parameter = 3, selectedMask = -1, selectedClone = -1;
  double brushRadius = .06, feather = .6, sourceX = .35, sourceY = .4;
  bool sourceSet = false, adding = true;
  Json? _gesture, _slider, _originalMask, _originalClone;
  int _beforeMask = -1, _beforeClone = -1, _handle = 0;
  bool _beforeAdding = true, _beforeSourceSet = false, _creating = false;
  double _beforeSourceX = .35, _beforeSourceY = .4;
  Offset _down = Offset.zero;
  Size _frame = const Size(1, 1);
  final _points = <double>[];

  List<Json> get masks => (tools['masks'] as List).map(object).toList();
  List<Json> get clones => (tools['clones'] as List).map(object).toList();
  Json? get mask => selectedMask >= 0 && selectedMask < masks.length
      ? masks[selectedMask]
      : null;
  Json? get clone => selectedClone >= 0 && selectedClone < clones.length
      ? clones[selectedClone]
      : null;
  bool get tracking => _gesture != null;
  bool get adjusting => _slider != null;
  bool get canAdd => tool == 3 ? clones.length < 64 : masks.length < 16;
  static double unit(num value) => value.toDouble().clamp(0.0, 1.0);
  static Offset bounded(Offset p) => Offset(unit(p.dx), unit(p.dy));
  static double number(Json value, String key) =>
      (value[key] as num).toDouble();
  bool same(Json a, Json b) => jsonEncode(a) == jsonEncode(b);

  void _remember(Json before) {
    if (same(before, tools)) return;
    undo.add(toolsCopy(before));
    if (undo.length > 32) undo.removeAt(0);
    redo.clear();
  }

  void _replace(Json next, {bool history = true}) {
    final before = tools;
    tools = toolsCopy(next);
    if (history) _remember(before);
    normalize();
    notifyListeners();
  }

  void _mask(Json value) {
    final list = masks;
    if (selectedMask < 0 || selectedMask >= list.length) return;
    list[selectedMask] = toolsCopy(value);
    tools['masks'] = list;
  }

  void _clone(Json value) {
    final list = clones;
    if (selectedClone < 0 || selectedClone >= list.length) return;
    list[selectedClone] = toolsCopy(value);
    tools['clones'] = list;
  }

  void normalize() {
    if (selectedMask >= masks.length) {
      selectedMask = masks.isEmpty ? -1 : masks.length - 1;
    }
    if (selectedClone >= clones.length) {
      selectedClone = clones.isEmpty ? -1 : clones.length - 1;
    }
    if (tool == 3) {
      selectedMask = -1;
    } else {
      selectedClone = -1;
      if (mask != null) {
        tool = ['brush', 'radial', 'linear'].indexOf(mask!['kind'] as String);
      }
    }
    adding = mask == null && clone == null;
    if ((tool == 3 || mask == null) && parameter < 3) parameter = 3;
    if (tool == 2 && parameter == 3) parameter = 4;
  }

  void selectTool(int value) {
    if (tracking || adjusting || value < 0 || value > 3) return;
    tool = value;
    selectedMask = selectedClone = -1;
    adding = true;
    if (tool == 3) sourceSet = false;
    normalize();
    notifyListeners();
  }

  void newSelection() {
    if (tracking || adjusting || !canAdd) return;
    adding = true;
    selectedMask = selectedClone = -1;
    if (tool == 3) sourceSet = false;
    normalize();
    notifyListeners();
  }

  void chooseMask(int index) {
    if (tracking || adjusting || index < 0 || index >= masks.length) return;
    selectedMask = index;
    selectedClone = -1;
    tool = ['brush', 'radial', 'linear'].indexOf(mask!['kind'] as String);
    normalize();
    notifyListeners();
  }

  void chooseClone(int index) {
    if (tracking || adjusting || index < 0 || index >= clones.length) return;
    selectedClone = index;
    selectedMask = -1;
    tool = 3;
    sourceX = number(clone!, 'sourceX');
    sourceY = number(clone!, 'sourceY');
    sourceSet = true;
    normalize();
    notifyListeners();
  }

  void chooseParameter(int value) {
    if (tracking || adjusting || value < 0 || value > 4) return;
    parameter = value;
    normalize();
    notifyListeners();
  }

  void history(bool forward) {
    if (tracking || adjusting) return;
    final source = forward ? redo : undo;
    if (source.isEmpty) return;
    (forward ? undo : redo).add(toolsCopy(tools));
    tools = source.removeLast();
    normalize();
    notifyListeners();
  }

  void remove() {
    if (tracking || adjusting || mask == null && clone == null) return;
    final next = toolsCopy(tools);
    (next[mask != null ? 'masks' : 'clones'] as List).removeAt(
      mask != null ? selectedMask : selectedClone,
    );
    _replace(next);
  }

  void toggleEnabled() {
    final value = mask ?? clone;
    if (tracking || adjusting || value == null) return;
    final before = toolsCopy(tools),
        next = {...value, 'enabled': value['enabled'] != true};
    if (mask != null) {
      _mask(next);
    } else {
      _clone(next);
    }
    _remember(before);
    notifyListeners();
  }

  void invert() {
    final value = mask;
    if (tracking || adjusting || value == null) return;
    final before = toolsCopy(tools);
    _mask({...value, 'inverted': value['inverted'] != true});
    _remember(before);
    notifyListeners();
  }

  void beginAdjustment() {
    if (!tracking && !adjusting) _slider = toolsCopy(tools);
  }

  void endAdjustment() {
    if (_slider == null) return;
    _remember(_slider!);
    _slider = null;
    notifyListeners();
  }

  void adjust(int value) {
    if (tracking) return;
    final before = toolsCopy(tools), m = mask, c = clone;
    if (parameter < 3 && m != null) {
      final key = ['exposure', 'temperature', 'saturation'][parameter];
      _mask({
        ...m,
        key: value.clamp(
          parameter == 0 ? -30 : -100,
          parameter == 0 ? 30 : 100,
        ),
      });
    } else if (parameter == 3 && tool != 2) {
      final size =
          value.clamp(
            1,
            m?['kind'] == 'radial'
                ? 1000
                : tool == 3
                ? 250
                : 500,
          ) /
          1000;
      brushRadius = math.min(.5, size);
      if (m != null && m['kind'] == 'radial') {
        final ratio = size / number(m, 'x1');
        _mask({
          ...m,
          'x1': size,
          'y1': (number(m, 'y1') * ratio).clamp(.001, 1.0),
        });
      } else if (m != null && m['kind'] == 'brush') {
        _mask({...m, 'radius': brushRadius});
      } else if (c != null) {
        _clone({...c, 'radius': math.min(.25, brushRadius)});
      }
    } else if (parameter == 4) {
      feather = value.clamp(0, 100) / 100;
      if (m != null) {
        _mask({...m, 'feather': feather});
      } else if (c != null) {
        _clone({...c, 'feather': feather});
      }
    }
    if (!adjusting) _remember(before);
    notifyListeners();
  }

  double distance(Offset a, Offset b) => math.sqrt(
    math.pow((a.dx - b.dx) * _frame.width, 2) +
        math.pow((a.dy - b.dy) * _frame.height, 2),
  );
  Json _newMask(String kind, Offset point) => {
    'kind': kind,
    'x0': kind == 'brush'
        ? 0
        : kind == 'linear'
        ? math.max(0, point.dx - .01)
        : point.dx,
    'y0': kind == 'brush' ? 0 : point.dy,
    'x1': kind == 'brush'
        ? 0
        : kind == 'radial'
        ? .22
        : math.min(1, point.dx + .01),
    'y1': kind == 'brush'
        ? 0
        : kind == 'radial'
        ? .22
        : point.dy,
    'radius': kind == 'brush' ? brushRadius : .08,
    'feather': kind == 'linear'
        ? .7
        : kind == 'radial'
        ? .6
        : feather,
    'inverted': false,
    'enabled': true,
    'exposure': 0,
    'temperature': 0,
    'saturation': 0,
    'points': kind == 'brush' ? [point.dx, point.dy] : [],
  };
  void begin(Offset point, Size frame) {
    if (!frame.width.isFinite ||
        !frame.height.isFinite ||
        !point.dx.isFinite ||
        !point.dy.isFinite) {
      return;
    }
    if (tracking || adjusting || frame.isEmpty || (adding && !canAdd)) return;
    _frame = frame;
    _down = bounded(point);
    _gesture = toolsCopy(tools);
    _beforeMask = selectedMask;
    _beforeClone = selectedClone;
    _beforeAdding = adding;
    _beforeSourceSet = sourceSet;
    _beforeSourceX = sourceX;
    _beforeSourceY = sourceY;
    _originalMask = mask == null ? null : toolsCopy(mask!);
    _originalClone = clone == null ? null : toolsCopy(clone!);
    _creating = adding || _originalMask == null;
    _handle = 0;
    _points.clear();
    final x = _down.dx, y = _down.dy;
    if (tool == 3) {
      if (_originalClone != null && !adding) {
        _handle =
            distance(
                  _down,
                  Offset(
                    number(_originalClone!, 'sourceX'),
                    number(_originalClone!, 'sourceY'),
                  ),
                ) <
                28
            ? 1
            : 2;
      } else if (!sourceSet) {
        sourceX = x;
        sourceY = y;
        sourceSet = true;
        _handle = 3;
      } else {
        final c = {
          'sourceX': sourceX,
          'sourceY': sourceY,
          'targetX': x,
          'targetY': y,
          'radius': math.min(.25, brushRadius),
          'feather': feather,
          'enabled': true,
        };
        final list = clones..add(c);
        tools['clones'] = list;
        selectedClone = list.length - 1;
        selectedMask = -1;
        _originalClone = toolsCopy(c);
        adding = false;
        _handle = 2;
      }
    } else if (adding || _originalMask == null) {
      final m = _newMask(['brush', 'radial', 'linear'][tool], _down);
      final list = masks..add(m);
      tools['masks'] = list;
      selectedMask = list.length - 1;
      selectedClone = -1;
      _originalMask = toolsCopy(m);
      adding = false;
      _handle = tool == 0 ? 4 : 2;
      if (tool == 0) _points.addAll([x, y]);
    } else if (tool == 1) {
      final m = _originalMask!;
      _handle =
          distance(
                _down,
                Offset(
                  math.min(1, number(m, 'x0') + number(m, 'x1')),
                  math.min(1, number(m, 'y0') + number(m, 'y1')),
                ),
              ) <
              32
          ? 2
          : 1;
    } else if (tool == 2) {
      final m = _originalMask!;
      _handle =
          distance(_down, Offset(number(m, 'x0'), number(m, 'y0'))) <
              distance(_down, Offset(number(m, 'x1'), number(m, 'y1')))
          ? 1
          : 2;
    } else {
      _handle = 1;
    }
    normalize();
    notifyListeners();
  }

  void move(Offset point) {
    if (!point.dx.isFinite || !point.dy.isFinite) return;
    if (!tracking) return;
    final p = bounded(point),
        dx = p.dx - _down.dx,
        dy = p.dy - _down.dy,
        m = _originalMask,
        c = _originalClone;
    if (tool == 3 && c != null) {
      _clone({
        ...c,
        'sourceX': _handle == 1 ? p.dx : c['sourceX'],
        'sourceY': _handle == 1 ? p.dy : c['sourceY'],
        'targetX': _handle == 2 ? p.dx : c['targetX'],
        'targetY': _handle == 2 ? p.dy : c['targetY'],
      });
    } else if (m != null) {
      if (tool == 0 && _handle == 4) {
        if (_points.length < 1024 &&
            distance(p, Offset(_points[_points.length - 2], _points.last)) >
                2) {
          _points.addAll([p.dx, p.dy]);
        }
        _mask({...m, 'points': List<double>.from(_points)});
      } else if (tool == 0) {
        final points = List<num>.from(m['points'] as List);
        for (var i = 0; i < points.length; i += 2) {
          points[i] = unit(points[i] + dx);
          points[i + 1] = unit(points[i + 1] + dy);
        }
        _mask({...m, 'points': points});
      } else if (tool == 1) {
        _mask(
          _handle == 2
              ? {
                  ...m,
                  'x1':
                      (_creating
                              ? (p.dx - number(m, 'x0')).abs()
                              : number(m, 'x1') + dx)
                          .clamp(.005, 1.0),
                  'y1':
                      (_creating
                              ? (p.dy - number(m, 'y0')).abs()
                              : number(m, 'y1') + dy)
                          .clamp(.005, 1.0),
                }
              : {
                  ...m,
                  'x0': unit(number(m, 'x0') + dx),
                  'y0': unit(number(m, 'y0') + dy),
                },
        );
      } else {
        final x0 = _handle == 1 ? p.dx : number(m, 'x0'),
            y0 = _handle == 1 ? p.dy : number(m, 'y0'),
            x1 = _handle == 2 ? p.dx : number(m, 'x1'),
            y1 = _handle == 2 ? p.dy : number(m, 'y1');
        if ((Offset(x1, y1) - Offset(x0, y0)).distance >= .001) {
          _mask({...m, 'x0': x0, 'y0': y0, 'x1': x1, 'y1': y1});
        }
      }
    }
    notifyListeners();
  }

  void end() {
    if (!tracking) return;
    _remember(_gesture!);
    _gesture = null;
    notifyListeners();
  }

  void cancel() {
    if (!tracking) return;
    tools = _gesture!;
    _gesture = null;
    selectedMask = _beforeMask;
    selectedClone = _beforeClone;
    adding = _beforeAdding;
    sourceSet = _beforeSourceSet;
    sourceX = _beforeSourceX;
    sourceY = _beforeSourceY;
    normalize();
    notifyListeners();
  }
}
