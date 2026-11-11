import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

typedef Json = Map<String, dynamic>;
Json object(Object? value) => Map<String, dynamic>.from(value! as Map);

class AppFailure implements Exception {
  const AppFailure(this.message, {this.details});
  final String message;
  final Object? details;
  @override
  String toString() => message;
}

class HueviaCore {
  static const channel = MethodChannel('cc.huevia/core');
  static const events = EventChannel('cc.huevia/events');
  static final progress = events.receiveBroadcastStream();
  Stream<dynamic> get galleryChanges => progress.where(
    (event) => event is Map && event['kind'] == 'galleryChanged',
  );
  String root = '';
  Json schema = {};
  final previewRevision = ValueNotifier<int>(0);
  bool customTemplate = false;
  final List<Json> recentOperations = [];
  Future<void> initialize() async {
    final response = await _invoke('initialize', {});
    root = response['root'] as String;
    schema = object(response['schema']);
    try {
      await call('media.templateInfo');
    } catch (_) {
      /* Template preferences must not block opening the library. */
    }
  }

  Future<Json> _invoke(String method, Json arguments) async {
    try {
      final value = await channel.invokeMethod<String>(method, arguments);
      final decoded = jsonDecode(value ?? 'null');
      return decoded == null ? {} : object(decoded);
    } on PlatformException catch (error) {
      throw AppFailure(error.message ?? '操作未完成，请重试。', details: error.details);
    }
  }

  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    final started = Stopwatch()..start();
    var status = 'failed';
    try {
      final result = await _invoke('request', {
        'operation': operation,
        'payload': jsonEncode(payload),
        'jobId': ?jobId,
      });
      if ([
        'media.templateSet',
        'media.templateReset',
        'media.templateInfo',
      ].contains(operation)) {
        customTemplate = result['custom'] == true;
        previewRevision.value++;
      }
      status = 'complete';
      return result;
    } finally {
      recentOperations.add({
        'operation': RegExp(r'^[a-zA-Z][a-zA-Z0-9.]{0,63}$').hasMatch(operation)
            ? operation
            : 'invalid',
        'at': DateTime.now().toUtc().toIso8601String(),
        'elapsedMs': started.elapsedMilliseconds,
        'status': status,
      });
      if (recentOperations.length > 128) recentOperations.removeAt(0);
    }
  }

  Future<void> cancel(String jobId) =>
      channel.invokeMethod<void>('cancel', {'jobId': jobId});

  Future<Json?> pickFile({required bool preset}) async {
    final result = await _invoke('pickFile', {'preset': preset});
    if (result['cancelled'] == true) return null;
    final path = result['path'], name = result['name'], sha = result['sha256'];
    if (path is! String ||
        name is! String ||
        sha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        !p.isWithin(p.join(root, preset ? 'incoming' : 'originals'), path)) {
      throw const AppFailure('文件导入结果无效。');
    }
    return result;
  }

  Future<Json?> pickSubmission({
    required String kind,
    required String owner,
  }) async {
    if (!{'ncp', 'preview'}.contains(kind) || owner.isEmpty) {
      throw const AppFailure('投稿文件类型或账号无效。');
    }
    final result = await _invoke('pickFile', {
      'preset': kind == 'ncp',
      'submissionKind': kind,
      'owner': owner,
    });
    if (result['cancelled'] == true) return null;
    final path = result['path'], name = result['name'], sha = result['sha256'];
    if (path is! String ||
        name is! String ||
        sha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        !p.isWithin(p.join(root, 'submission-incoming', owner), path)) {
      throw const AppFailure('投稿文件导入结果无效。');
    }
    return result;
  }

  Future<Json> galleryPermission() => _invoke('galleryPermission', {});

  /// Originals stream to private storage; RAW pixels never enter the UI heap.
  Future<String> importFile(XFile selected, {required bool preset}) async {
    if (root.isEmpty) throw const AppFailure('应用尚未准备好。');
    final length = await selected.length();
    final limit = preset ? 1024 * 1024 : 1024 * 1024 * 1024;
    if (length < 1 || length > limit) throw const AppFailure('文件大小超出允许范围。');
    final extension = p.extension(selected.name).toLowerCase();
    final allowed = preset
        ? {'.ncp', '.np3'}
        : {
            '.jpg',
            '.jpeg',
            '.png',
            '.heic',
            '.heif',
            '.webp',
            '.nef',
            '.nrw',
            '.dng',
            '.arw',
            '.cr2',
            '.cr3',
            '.raf',
            '.rw2',
            '.orf',
            '.pef',
            '.srw',
          };
    if (!allowed.contains(extension)) throw const AppFailure('请选择受支持的文件格式。');
    final directory = Directory(p.join(root, preset ? 'inbox' : 'originals'));
    await directory.create(recursive: true);
    final temporary = File(
      p.join(
        directory.path,
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}.part',
      ),
    );
    final sink = temporary.openWrite();
    var received = 0;
    try {
      await for (final bytes in selected.openRead()) {
        received += bytes.length;
        if (received > limit || received > length) {
          throw const AppFailure('文件在读取时发生变化。');
        }
        sink.add(bytes);
      }
      await sink.flush();
      await sink.close();
      if (received != length) throw const AppFailure('文件读取不完整。');
      final hash = (await sha256.bind(temporary.openRead()).first).toString();
      final target = File(p.join(directory.path, '$hash$extension'));
      if (await target.exists()) {
        if ((await sha256.bind(target.openRead()).first).toString() != hash) {
          throw const AppFailure('已有文件校验失败。');
        }
        await temporary.delete();
      } else {
        await temporary.rename(target.path);
      }
      return target.path;
    } catch (_) {
      await sink.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }
}

class Preset {
  const Preset(this.data, {this.online = false});
  final Json data;
  final bool online;
  String get id => data['id'] as String;
  String get name => (data[online ? 'name' : 'displayName'] ?? '') as String;
  String get category => (data['category'] ?? '') as String;
  String get format => (data['fileFormat'] ?? 'NCP') as String;
  String get description => (data['description'] ?? '') as String;
  String get author => (data['authorName'] ?? '') as String;
  String get preview =>
      (data[online ? 'previewUrl' : 'previewUri'] ?? '') as String;
}

class Photo {
  const Photo(this.path, this.name, this.info);
  final String path, name;
  final Json info;
  String get id => p.basename(path);
  String get editorLocation => '/photo/${Uri.encodeComponent(id)}';
  String get starKey => 'f:${sha256.convert(utf8.encode(id))}';
  Json toJson() => {'path': path, 'name': name, 'info': info};
  factory Photo.fromJson(Json json) => Photo(
    json['path'] as String,
    json['name'] as String,
    object(json['info']),
  );
}

class Recipe {
  Recipe({Json? data})
    : data = data == null
          ? {
              'schema': 1,
              'presetId': '',
              'strength': 100,
              'values': List.filled(17, 0),
            }
          : object(jsonDecode(jsonEncode(data)));
  final Json data;
  List<int> get values => List<int>.from(data['values'] as List);
  Recipe clone() => Recipe(data: data);
  void setValue(int index, int value) {
    final next = values;
    next[index] = value;
    data['values'] = next;
  }
}

class AppState extends ChangeNotifier {
  AppState(this.core);
  final HueviaCore core;
  bool ready = false;
  String? failure;
  List<Preset> presets = [];
  List<Photo> photos = [];
  Set<String> starredPhotos = {};
  Json session = {};
  Json uiPreferences = {};
  String? uiPreferencesWarning;
  Future<void> _uiCommit = Future.value();
  Future<void> saveUiPreferences(Json patch) {
    // View state is optional for a standalone/test view with no private root.
    if (core.root.isEmpty) return Future.value();
    final next = _uiCommit.then((_) async {
      try {
        uiPreferences = await core.call('ui.preferences.set', patch);
        uiPreferencesWarning = null;
        notifyListeners();
      } catch (failure) {
        uiPreferencesWarning = '界面设置暂未保存，重启后可能恢复为上次设置。';
        notifyListeners();
        rethrow;
      }
    });
    _uiCommit = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _photoCommit = Future.value();
  Future<T> _serialPhotos<T>(Future<T> Function() operation) {
    final next = _photoCommit.then((_) => operation());
    _photoCommit = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

  Future<void> initialize() async {
    failure = null;
    notifyListeners();
    try {
      await core.initialize();
      try {
        uiPreferences = await core.call('ui.preferences.get');
        uiPreferencesWarning = null;
      } catch (error) {
        uiPreferencesWarning = '$error';
      }
      await refreshLibrary();
      session = await core.call('account.current');
      final index = File(p.join(core.root, 'photos-index.json'));
      if (await index.exists()) {
        final value = jsonDecode(await index.readAsString()) as List;
        photos = value
            .map((row) => restorePhoto(object(row)))
            .where(
              (photo) =>
                  p.isWithin(p.join(core.root, 'originals'), photo.path) &&
                  File(photo.path).existsSync(),
            )
            .toList();
      }
      ready = true;
    } catch (error) {
      failure = '$error';
    }
    notifyListeners();
  }

  Future<void> refreshLibrary() async {
    final value = await core.call('library.list');
    presets = (value['items'] as List)
        .map((row) => Preset(object(row)))
        .toList();
    notifyListeners();
  }

  Future<void> refreshStars() async {
    final value = await core.call('photo.stars');
    starredPhotos = Set<String>.from(value['keys'] as List);
    notifyListeners();
  }

  Future<void> starPhoto(Photo photo, bool starred) async {
    final value = await core.call('photo.star', {
      'path': photo.path,
      'starred': starred,
    });
    starredPhotos = Set<String>.from(value['keys'] as List);
    notifyListeners();
  }

  Photo restorePhoto(Json saved) {
    final row = object(saved), info = object(row['info']);
    String path(String value) {
      final restored = p.normalize(
        p.join(core.root, value.replaceAll('\\', '/')),
      );
      if (!p.isWithin(p.join(core.root, 'originals'), restored)) {
        throw const AppFailure('照片索引包含不属于原图库的路径。');
      }
      return restored;
    }

    if (row['relative'] == true) row['path'] = path(row['path'] as String);
    if (info['rawSourceRelative'] == true) {
      info['rawSource'] = path(info['rawSource'] as String);
      info.remove('rawSourceRelative');
    }
    row['info'] = info;
    return Photo.fromJson(row);
  }

  Future<void> importPreset(XFile selected) async {
    final owner = session['user']?['id'] as String? ?? '';
    final file = await core.importFile(selected, preset: true);
    await core.call('library.import', {
      'path': file,
      'name': selected.name,
      'owner': owner,
    });
    await refreshLibrary();
  }

  Future<bool> pickPreset() async {
    final owner = session['user']?['id'] as String? ?? '';
    final selected = await core.pickFile(preset: true);
    if (selected == null) return false;
    await core.call('library.import', {
      'path': selected['path'],
      'name': selected['name'],
      'owner': owner,
    });
    await refreshLibrary();
    return true;
  }

  Future<Photo?> pickPhoto() async {
    final selected = await core.pickFile(preset: false);
    if (selected == null) return null;
    final path = selected['path'] as String;
    final info = await core.call('media.info', {'path': path});
    return registerPhoto(path, selected['name'] as String, info);
  }

  Future<void> refreshSession() async {
    session = await core.call('account.current');
    notifyListeners();
    await refreshLibrary();
  }

  Future<Photo> importPhoto(XFile selected, {String? displayName}) =>
      _serialPhotos(() async {
        final name = displayName ?? p.basename(selected.name);
        if (name.trim().isEmpty ||
            name.length > 240 ||
            RegExp(r'[\x00-\x1f\x7f/\\]').hasMatch(name)) {
          throw const AppFailure('照片名称无效。');
        }
        final path = await core.importFile(selected, preset: false);
        final existing = photos.where((photo) => photo.path == path);
        if (existing.isNotEmpty) {
          final current = existing.first;
          if (displayName == null || current.name == name) return current;
          final renamed = Photo(path, name, current.info);
          final next = photos
              .map((photo) => photo.path == path ? renamed : photo)
              .toList();
          await _persistPhotos(next);
          photos = next;
          notifyListeners();
          return renamed;
        }
        final info = await core.call('media.info', {'path': path});
        final photo = Photo(path, name, {
          ...info,
          'addedAt': DateTime.now().millisecondsSinceEpoch,
        });
        final next = [photo, ...photos];
        await _persistPhotos(next);
        photos = next;
        notifyListeners();
        return photo;
      });

  Future<Photo> registerPhoto(String path, String name, Json info) =>
      _serialPhotos(() async {
        if (!p.isWithin(p.join(core.root, 'originals'), path) ||
            !await File(path).exists()) {
          throw const AppFailure('照片文件不在应用原图库中。');
        }
        final existing = photos.where((photo) => photo.path == path);
        if (existing.isNotEmpty) return existing.first;
        final photo = Photo(path, name, {
          ...info,
          'addedAt': DateTime.now().millisecondsSinceEpoch,
        });
        final next = <Photo>[photo, ...photos];
        await _persistPhotos(next);
        photos = next;
        notifyListeners();
        return photo;
      });

  Future<Photo> updatePhoto(Photo photo, Json metadata) =>
      _serialPhotos(() async {
        final index = photos.indexWhere((item) => item.path == photo.path);
        if (index < 0) throw const AppFailure('照片已不在资料库中。');
        final current = photos[index], next = List<Photo>.from(photos);
        final updated = Photo(current.path, current.name, {
          ...current.info,
          ...metadata,
        });
        next[index] = updated;
        await _persistPhotos(next);
        photos = next;
        notifyListeners();
        return updated;
      });

  Future<void> savePhotos() =>
      _serialPhotos(() => _persistPhotos(List<Photo>.from(photos)));
  Future<void> _persistPhotos(List<Photo> snapshot) async {
    final temporary = File(
      p.join(
        core.root,
        'photos-index-${DateTime.now().microsecondsSinceEpoch}.part',
      ),
    );
    try {
      final records = snapshot.map((photo) {
        if (!p.isWithin(p.join(core.root, 'originals'), photo.path)) {
          throw const AppFailure('照片文件不在应用原图库中。');
        }
        final info = {...photo.info};
        final rawSource = info['rawSource'];
        if (rawSource is String &&
            p.isWithin(p.join(core.root, 'originals'), rawSource)) {
          info['rawSource'] = p
              .relative(rawSource, from: core.root)
              .replaceAll('\\', '/');
          info['rawSourceRelative'] = true;
        }
        return {
          ...photo.toJson(),
          'path': p.relative(photo.path, from: core.root).replaceAll('\\', '/'),
          'relative': true,
          'info': info,
        };
      }).toList();
      await temporary.writeAsString(jsonEncode(records), flush: true);
      await temporary.rename(p.join(core.root, 'photos-index.json'));
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
