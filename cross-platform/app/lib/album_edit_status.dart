import 'dart:async';

import 'package:flutter/foundation.dart';

import 'domain.dart';

/// Owner-scoped native draft status; phone aliases are matched by exact asset identity.
class AlbumEditStatus extends ChangeNotifier {
  AlbumEditStatus(this.state) {
    state.addListener(refresh);
    state.core.editRevision.addListener(refresh);
  }

  final AppState state;
  Map<String, Json> statuses = {};
  List<Photo>? _photos;
  String? _owner;
  int _revision = -1, _generation = 0;
  bool _alive = true;
  bool _logoutPending = false;
  Future<void> _loading = Future.value();
  Future<void> get ready => _loading;
  List<Json> _phoneRows = [];
  final Set<String> _identityAttempts = {};
  String get owner => state.session['user']?['id'] as String? ?? '';
  bool current(int generation, String expected) =>
      _alive &&
      generation == _generation &&
      owner == expected &&
      state.session['logoutPending'] != true;

  void refresh() {
    final nextOwner = owner, revision = state.core.editRevision.value;
    if (identical(_photos, state.photos) &&
        _owner == nextOwner &&
        _revision == revision &&
        _logoutPending == (state.session['logoutPending'] == true)) {
      return;
    }
    _logoutPending = state.session['logoutPending'] == true;
    if (_owner != nextOwner || state.session['logoutPending'] == true) {
      statuses = {};
      _identityAttempts.clear();
    }
    _photos = state.photos;
    _owner = nextOwner;
    _revision = revision;
    final generation = ++_generation;
    if (_logoutPending) return;
    _loading = _read(generation, nextOwner, List.of(state.photos));
    unawaited(_loading);
  }

  Future<void> _read(
    int generation,
    String expected,
    List<Photo> photos,
  ) async {
    final next = <String, Json>{};
    for (var start = 0; start < photos.length; start += 100) {
      if (!current(generation, expected)) return;
      final group = photos.skip(start).take(100).toList();
      try {
        final result = await state.core.call('draft.statuses', {
          'owner': expected,
          'paths': group.map((photo) => photo.path).toList(),
        });
        if (!current(generation, expected)) return;
        for (final row in (result['items'] as List? ?? const [])) {
          final value = object(row), path = value['path'];
          if (path is String && group.any((photo) => photo.path == path)) {
            next[path] = value;
          }
        }
      } catch (_) {
        // Status failure must not import originals, block browsing or invent an edited badge.
      }
    }
    if (!current(generation, expected)) return;
    statuses = next;
    notifyListeners();
    await linkPhoneRows(_phoneRows);
  }

  bool isEdited(Photo photo) {
    if (_owner != owner || state.session['logoutPending'] == true) return false;
    if (statuses[photo.path]?['edited'] == true) return true;
    if (photo.info['raw'] == true) {
      final working = state.workingPhotoFor(photo);
      return working != null && statuses[working.path]?['edited'] == true;
    }
    return false;
  }

  Set<String> editedIds(List<Json> rows, {required bool phone}) => {
    for (final row in rows)
      if (state.photos.any(
        (photo) =>
            isEdited(photo) &&
            (phone
                ? state.phonePhotoMatches(photo, row)
                : photo.path == row['id']),
      ))
        row['id'] as String,
  };

  Future<void> linkPhoneRows(List<Json> rows) async {
    _phoneRows = List.of(rows);
    final expected = owner, generation = _generation;
    // Recover old imports without filename guesses: only candidate edited names
    // request a read-only original digest; no other originals are read or copied.
    for (final row in rows) {
      if (!current(generation, expected)) return;
      final candidates = state.photos
          .where((photo) => isEdited(photo) && photo.name == row['name'])
          .toList();
      if (candidates.isEmpty ||
          candidates.any((photo) => state.phonePhotoMatches(photo, row))) {
        continue;
      }
      final key = '${row['id']}|${row['bytes']}|${row['modified']}|$expected';
      if (!_identityAttempts.add(key)) continue;
      try {
        final identity = await state.core.call('gallery.identity', {
          'id': row['id'],
        });
        if (!current(generation, expected)) return;
        final sha = identity['sourceSha'];
        if (sha is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha)) {
          continue;
        }
        final matched = candidates
            .where((photo) => statuses[photo.path]?['sourceSha'] == sha)
            .firstOrNull;
        if (matched != null) await state.linkPhonePhoto(matched, row);
      } catch (_) {
        // An unavailable local original remains unverified; opening it later can link it.
      }
    }
  }

  @override
  void dispose() {
    _alive = false;
    _generation++;
    state.removeListener(refresh);
    state.core.editRevision.removeListener(refresh);
    super.dispose();
  }
}
