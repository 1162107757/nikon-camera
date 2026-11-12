import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef StabilityJson = Map<String, dynamic>;

/// Local evidence only. Existing Flutter error handling and termination remain
/// in charge; recording never marks a failed operation successful.
class AppStability {
  static const channel = MethodChannel('cc.huevia/stability');
  static bool _installed = false, _sending = false;
  static int _lastWriteAttempt = 0;
  static StabilityJson? _pending, _last;

  static void install() {
    if (_installed) return;
    _installed = true;
    final framework = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exception, details.stack ?? StackTrace.empty, 'framework');
      framework?.call(details);
    };
    final asynchronous = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, 'unhandled');
      return asynchronous?.call(error, stack) ?? false;
    };
  }

  static void record(Object error, StackTrace stack, String kind) {
    try {
      _last = _pending = flutterRecord(error, stack, kind);
      unawaited(_flush());
    } catch (_) {
      // Optional evidence cannot replace the failure being handled.
    }
  }

  static Future<void> _flush({bool force = false}) async {
    if (_sending || _pending == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _lastWriteAttempt < 1000) return;
    _lastWriteAttempt = now;
    _sending = true;
    final value = _pending!;
    _pending = null;
    try {
      await channel.invokeMethod<void>('recordFlutter', value);
    } catch (_) {
      // Keep one bounded entry for the next diagnostics request or error.
      _pending ??= value;
    } finally {
      _sending = false;
    }
  }

  static Future<StabilityJson> snapshot() async {
    await _flush(force: true)
        .timeout(const Duration(seconds: 3), onTimeout: () {});
    Object? native;
    try {
      final value = await channel
          .invokeMethod<String>('snapshot')
          .timeout(const Duration(seconds: 6));
      if (value != null && value.length <= 512 * 1024) {
        native = jsonDecode(value);
      }
    } catch (_) {
      // Other platforms and an unavailable native collector stay usable.
    }
    final result = redactSnapshot(native);
    if (_last != null) result['lastFlutterError'] = _last;
    return result;
  }

  static StabilityJson flutterRecord(
    Object error,
    StackTrace stack,
    String kind,
  ) => {
    'recordedAtEpochMillis': DateTime.now().millisecondsSinceEpoch,
    'kind': kind == 'framework' ? 'framework' : 'unhandled',
    'type': _type(error.runtimeType.toString()) ?? 'Error',
    'frames': safeFrames(stack.toString().split('\n')),
  };

  /// A second boundary at export time. Exception messages, local paths, system
  /// descriptions, binary traces, addresses, account data and unknown fields are
  /// never copied into the shareable report.
  static StabilityJson redactSnapshot(Object? value) {
    final native = value is Map ? value : const {};
    final platform = native['platform'];
    final result = <String, dynamic>{
      'schema': 1,
      'available': platform == 'android' || platform == 'ios',
      'platform': platform == 'android' || platform == 'ios'
          ? platform
          : 'unavailable',
    };
    if (platform == 'android') {
      for (final key in ['sdk', 'manufacturer', 'model', 'currentAppVersion']) {
        final value = native[key];
        if (value is int && value >= 0 && value <= 10000) result[key] = value;
        if (value is String &&
            RegExp(r'^[A-Za-z0-9 ._()+-]{1,100}$').hasMatch(value)) {
          result[key] = value;
        }
      }
      result['processExitHistoryAvailable'] =
          native['processExitHistoryAvailable'] == true;
      final raw = native['lastJavaCrash'];
      if (raw is String && raw.isNotEmpty) {
        final lines = raw.substring(0, raw.length.clamp(0, 65536)).split('\n');
        final record = <String, dynamic>{'frames': safeFrames(lines)};
        for (final line in lines) {
          final header = RegExp(
            r'^(recordedAtEpochMillis|heapMax|heapUsed)=([0-9]{1,18})$',
          ).firstMatch(line);
          if (header != null) {
            final number = int.tryParse(header[2]!);
            if (number != null && number <= 9007199254740991) {
              record[header[1]!] = number;
            }
          }
          final type = RegExp(
            r'^(?:Caused by: )?([A-Za-z_$][A-Za-z0-9_$.]*(?:Exception|Error))(?::|$)',
          ).firstMatch(line);
          if (type != null && _type(type[1]) != null) {
            record.putIfAbsent('type', () => type[1]!);
          }
        }
        result['lastJavaCrash'] = record;
      }
      final exits = native['processExitHistory'];
      result['processExitHistory'] = [
        if (exits is List)
          for (final row in exits.take(4))
            if (row is Map)
              _numbers(row, [
                'reason',
                'status',
                'timestamp',
                'pssKb',
                'rssKb',
              ]),
      ];
    }
    if (platform == 'ios') {
      result['uncaughtExceptionHandlerInstalled'] =
          native['uncaughtExceptionHandlerInstalled'] == true;
      result['metricKitRegistered'] = native['metricKitRegistered'] == true;
      result['metricKitDelivery'] = 'system-managed';
      final exception = native['lastNativeException'];
      if (exception is Map) {
        result['lastNativeException'] = {
          ..._numbers(exception, ['recordedAtEpochMillis']),
          if (_type(exception['type']) != null)
            'type': _type(exception['type']),
          'frames': safeFrames(
            exception['frames'] is List ? exception['frames'] as List : [],
          ),
        };
      }
      final crashes = native['metricKitCrashes'];
      result['metricKitCrashes'] = [
        if (crashes is List)
          for (final row in crashes.take(4))
            if (row is Map)
              _numbers(row, [
                'recordedAtEpochMillis',
                'windowStartedAt',
                'windowEndedAt',
                'signal',
                'exceptionType',
              ]),
      ];
      final exits = native['metricKitExits'];
      if (exits is Map) {
        result['metricKitExits'] = {
          ..._numbers(exits, [
            'recordedAtEpochMillis',
            'windowStartedAt',
            'windowEndedAt',
            'foregroundMemoryLimit',
            'backgroundMemoryLimit',
            'backgroundMemoryPressure',
            'foregroundWatchdog',
            'backgroundWatchdog',
            'backgroundCPUResourceLimit',
          ]),
          'countsForReportingWindow': true,
          'includesMultipleAppVersions':
              exits['includesMultipleAppVersions'] == true,
          if (exits['latestAppVersion'] is String &&
              RegExp(r'^[0-9A-Za-z._+-]{1,80}$')
                  .hasMatch(exits['latestAppVersion'] as String))
            'latestAppVersion': exits['latestAppVersion'],
        };
      }
    }
    final flutter = native['lastFlutterError'];
    if (flutter is Map) {
      result['lastFlutterError'] = {
        ..._numbers(flutter, ['recordedAtEpochMillis']),
        'kind': flutter['kind'] == 'framework' ? 'framework' : 'unhandled',
        if (_type(flutter['type']) != null) 'type': _type(flutter['type']),
        'frames': safeFrames(
          flutter['frames'] is List ? flutter['frames'] as List : [],
        ),
      };
    }
    return result;
  }

  static String? _type(Object? value) =>
      value is String &&
          RegExp(r'^[A-Za-z_$][A-Za-z0-9_$.<>]{0,95}$').hasMatch(value)
      ? value
      : null;
  static StabilityJson _numbers(Map source, List<String> keys) => {
    for (final key in keys)
      if (source[key] is int &&
          (source[key] as int) >= 0 &&
          (source[key] as int) <= 9007199254740991)
        key: source[key],
  };

  static List<String> safeFrames(Iterable<dynamic> lines) {
    final output = <String>[];
    for (final value in lines.take(256)) {
      if (value is! String || value.length > 1024) continue;
      final line = value.trim();
      final java = RegExp(
        r'^at ([A-Za-z0-9_$<>.]+)\(([A-Za-z0-9_$.-]+\.java:[0-9]+|Native Method|Unknown Source)\)$',
      ).firstMatch(line);
      final dart = RegExp(
        r'^(?:#[0-9]+\s+)?([A-Za-z0-9_$<>.]+) \(((?:package:|dart:)[A-Za-z0-9_./:$-]+)\)$',
      ).firstMatch(line);
      final objc = RegExp(r'^[+-]\[[A-Za-z_][A-Za-z0-9_$.]* [A-Za-z0-9_$:]+\]$')
          .hasMatch(line);
      final frame = java != null
          ? 'at ${java[1]}(${java[2]})'
          : dart != null
          ? '${dart[1]} (${dart[2]})'
          : objc
          ? line
          : null;
      if (frame != null && frame.length <= 200) output.add(frame);
      if (output.length == 48) break;
    }
    return output;
  }
}
