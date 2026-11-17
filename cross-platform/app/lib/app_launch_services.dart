import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'updates.dart';
import 'updates_ios.dart';

/// A new gate belongs to each cold launch. Dismissals never survive that launch.
class LaunchUpdateGate {
  LaunchUpdateGate({double? draw})
    : draw = draw ?? Random.secure().nextDouble();
  final double draw;
  bool shown = false;

  bool eligible({required bool mandatory, required double probability}) =>
      mandatory ||
      (!shown && probability.isFinite && draw < probability.clamp(0, 1));
}

/// Mandatory updates are independent of optional anonymous usage reporting.
Future<void> coordinateLaunchChecks({
  required Future<void> usage,
  required Future<void> update,
  required bool Function() mandatory,
  required VoidCallback notify,
}) async {
  final optionalUsage = usage.catchError((Object _) {});
  await update;
  if (mandatory()) {
    notify();
    unawaited(optionalUsage);
    return;
  }
  await optionalUsage;
  notify();
}

String newUsageId() {
  final random = Random.secure(), bytes = List<int>.generate(16, (_) => 0);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = random.nextInt(256);
  }
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class AppLaunchServices with WidgetsBindingObserver {
  AppLaunchServices({
    required this.state,
    required this.navigatorKey,
    required this.canPrompt,
  });
  final AppState state;
  final GlobalKey<NavigatorState> navigatorKey;
  final bool Function() canPrompt;
  static final endpoint = Uri.parse(
    'https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com/preset-library/app/usage',
  );
  static const android = MethodChannel('cc.huevia/updates');
  static const ios = MethodChannel('cc.huevia/distribution');
  final gate = LaunchUpdateGate();
  final launchId = newUsageId();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  Json metadata = {};
  String installationId = '';
  bool started = false,
      disposed = false,
      reporting = false,
      launchRecorded = false,
      prompting = false,
      foreground = true;
  bool? lastLogin;
  double probability = .5;
  int retryCount = 0;
  Timer? heartbeat, retry, pendingPrompt, stateDebounce;
  Json? available;

  bool get loggedIn =>
      state.session['user'] is Map && state.session['logoutPending'] != true;

  void attach() {
    state.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
    changed();
  }

  void changed() {
    if (!started &&
        state.ready &&
        state.core.root.isNotEmpty &&
        (Platform.isAndroid || Platform.isIOS)) {
      started = true;
      lastLogin = loggedIn;
      unawaited(initialize());
    } else if (started && lastLogin != loggedIn) {
      lastLogin = loggedIn;
      stateDebounce?.cancel();
      stateDebounce = Timer(
        const Duration(seconds: 1),
        () => unawaited(report()),
      );
    }
  }

  Future<void> initialize() async {
    try {
      metadata = object(
        await (Platform.isAndroid
            ? android.invokeMapMethod<String, dynamic>('snapshot')
            : ios.invokeMapMethod<String, dynamic>('information')),
      );
      final file = File(p.join(state.core.root, 'anonymous-usage.json'));
      try {
        if (await file.exists() && await file.length() < 4096) {
          final saved = object(jsonDecode(await file.readAsString()));
          installationId = saved['installationId'] as String? ?? '';
          final savedProbability = saved['promptProbability'];
          if (savedProbability is num &&
              savedProbability.isFinite &&
              savedProbability >= 0 &&
              savedProbability <= 1) {
            probability = savedProbability.toDouble();
          }
        }
      } catch (_) {
        /* A damaged local preference does not disable anonymous reporting. */
      }
      if (!RegExp(r'^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$')
          .hasMatch(installationId)) {
        installationId = newUsageId();
      }
      await saveIdentity();
      if (disposed) return;
      heartbeat = Timer.periodic(const Duration(minutes: 15), (_) {
        if (foreground) unawaited(report());
      });
      await coordinateLaunchChecks(
        usage: report(),
        update: checkUpdate(),
        mandatory: () => available?['mandatory'] == true,
        notify: schedulePrompt,
      );
    } catch (_) {
      /* Optional services never prevent opening the app or editing offline. */
    }
  }

  Future<void> saveIdentity() async {
    final file = File(p.join(state.core.root, 'anonymous-usage.json'));
    await file.writeAsString(
      jsonEncode({
        'installationId': installationId,
        'promptProbability': probability,
      }),
      flush: true,
    );
  }

  Future<Json> request(Uri uri, {Json? body, int maxBytes = 8192}) async {
    if (disposed || uri.scheme != 'https') throw const AppFailure('服务不可用。');
    final request =
        await (body == null ? client.getUrl(uri) : client.postUrl(uri)).timeout(
          const Duration(seconds: 8),
        );
    request.followRedirects = false;
    request.headers.set('Accept', 'application/json');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 10));
    final bytes = <int>[];
    await for (final part in response.timeout(const Duration(seconds: 10))) {
      bytes.addAll(part);
      if (bytes.length > maxBytes) throw const AppFailure('服务返回内容过大。');
    }
    if (response.statusCode != 200) throw const AppFailure('服务暂不可用。');
    return object(jsonDecode(utf8.decode(bytes)));
  }

  Future<void> report() async {
    if (disposed || reporting || metadata.isEmpty || installationId.isEmpty) {
      return;
    }
    reporting = true;
    final login = loggedIn;
    try {
      final result = await request(
        endpoint,
        body: {
          'installationId': installationId,
          'launchId': launchId,
          'platform': Platform.isAndroid ? 'android' : 'ios',
          'packageName': metadata['packageName'] ?? metadata['bundleId'],
          'versionCode': int.tryParse('${metadata['versionCode']}'),
          'versionName': metadata['versionName'],
          'loggedIn': login,
          'event': launchRecorded ? 'heartbeat' : 'launch',
        },
      );
      launchRecorded = result['recorded'] == true;
      retryCount = 0;
      final value = result['promptProbability'];
      if (value is num && value.isFinite && value >= 0 && value <= 1) {
        probability = value.toDouble();
        await saveIdentity();
      }
    } catch (_) {
      if (!disposed && retryCount < 3) {
        retry?.cancel();
        retry = Timer(
          Duration(seconds: [5, 30, 120][retryCount++]),
          () => unawaited(report()),
        );
      }
    } finally {
      reporting = false;
      if (!disposed && login != loggedIn) unawaited(report());
    }
  }

  Future<void> checkUpdate() async {
    if (disposed) return;
    try {
      if (Platform.isAndroid) {
        var status = object(
          await android.invokeMapMethod<String, dynamic>('check'),
        );
        for (
          var i = 0;
          status['checking'] == true && i < 80 && !disposed;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          status = object(
            await android.invokeMapMethod<String, dynamic>('snapshot'),
          );
        }
        if (status['release'] is Map &&
            (status['release']['versionCode'] as num? ?? 0) >
                (status['versionCode'] as num? ?? 0)) {
          available = {
            ...object(status['release']),
            'mandatory': status['mandatory'] == true,
          };
        } else {
          available = null;
        }
      } else {
        final uri = Uri.tryParse(metadata['manifestUrl'] as String? ?? '');
        if (uri == null || !IosRelease.validHttps(uri)) return;
        final value = await request(uri, maxBytes: 64 * 1024);
        if (value['release'] == null && value.containsKey('release')) return;
        final release = IosRelease(
          value['release'] is Map ? object(value['release']) : value,
          manifest: uri,
          bundleId: metadata['bundleId'] as String,
        );
        if (release.code > (int.tryParse('${metadata['versionCode']}') ?? 0) &&
            release.supportsOs(metadata['osVersion'] as String)) {
          available = {...release.data, 'mandatory': false};
        }
      }
    } catch (_) {
      /* A transient failure keeps the manual update page available. */
    }
  }

  void schedulePrompt() {
    if (disposed ||
        available == null ||
        !gate.eligible(
          mandatory: available!['mandatory'] == true,
          probability: probability,
        )) {
      return;
    }
    pendingPrompt?.cancel();
    pendingPrompt = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (disposed || gate.shown && available!['mandatory'] != true) {
        timer.cancel();
        return;
      }
      if (foreground &&
          !state.cameraDownloadsActive &&
          canPrompt() &&
          navigatorKey.currentState?.overlay != null &&
          !prompting) {
        timer.cancel();
        unawaited(showPrompt());
      }
    });
  }

  Future<void> showPrompt() async {
    final context = navigatorKey.currentState?.overlay?.context;
    if (context == null || available == null || disposed || prompting) return;
    prompting = true;
    gate.shown = true;
    final release = available!, required = release['mandatory'] == true;
    try {
      final update = await showDialog<bool>(
        context: context,
        barrierDismissible: !required,
        builder: (dialog) => PopScope(
          canPop: !required,
          child: AlertDialog(
            title: Text(required ? '需要更新' : '发现新版本 ${release['versionName']}'),
            content: SingleChildScrollView(
              child: Text(release['notes'] as String? ?? '新版本已发布，可前往应用更新查看。'),
            ),
            actions: [
              if (!required)
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: const Text('暂不更新'),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('查看更新'),
              ),
            ],
          ),
        ),
      );
      if (update == true && !disposed) {
        await navigatorKey.currentState?.push<void>(
          MaterialPageRoute(builder: (_) => UpdatesPage(state: state)),
        );
        if (required && !disposed) {
          await checkUpdate();
          schedulePrompt();
        }
      }
    } finally {
      prompting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground && started) {
      unawaited(report());
      schedulePrompt();
    }
  }

  void dispose() {
    disposed = true;
    state.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    heartbeat?.cancel();
    retry?.cancel();
    pendingPrompt?.cancel();
    stateDebounce?.cancel();
    client.close(force: true);
  }
}
