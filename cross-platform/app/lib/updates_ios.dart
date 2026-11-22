import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'domain.dart';
import 'theme.dart';

String updateVersionLabel(Object? name, Object? code) {
  final build = int.tryParse('$code');
  if (build == null || build < 1) return name?.toString() ?? '正在读取…';
  return name == null ? '构建 $build' : '$name · 构建 $build';
}

Future<bool> openIosReleaseDownload(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

class IosRelease {
  IosRelease(Json value, {required this.manifest, required String bundleId})
    : data = Map.unmodifiable(value) {
    final url = value['downloadUrl'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (value['schema'] != 1 ||
        value['platform'] != 'ios' ||
        value['distribution'] != 'unsigned-ipa' ||
        value['bundleId'] != bundleId ||
        value['minimumIOS'] is! String ||
        !RegExp(r'^\d{1,2}\.\d{1,2}(?:\.\d{1,2})?$')
            .hasMatch(value['minimumIOS'] as String) ||
        value['versionCode'] is! int ||
        (value['versionCode'] as int) < 1 ||
        value['versionName'] is! String ||
        !RegExp(r'^[0-9A-Za-z][0-9A-Za-z._+-]{0,99}$')
            .hasMatch(value['versionName'] as String) ||
        value['byteLength'] is! int ||
        (value['byteLength'] as int) < 1024 ||
        (value['byteLength'] as int) > 128 * 1024 * 1024 ||
        value['sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String) ||
        value['notes'] is! String ||
        (value['notes'] as String).length > 12000 ||
        uri == null ||
        !trustedDownload(uri)) {
      throw const AppFailure('iOS 发布资料校验失败，未下载安装包。');
    }
  }
  final Json data;
  final Uri manifest;
  static const _officialHosts = {
    'huevia.cc',
    'nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com',
  };
  static final _releaseFile = RegExp(
    r'^/preset-library/ios/releases/[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}/file$',
  );
  int get bytes => data['byteLength'] as int;
  int get code => data['versionCode'] as int;
  Uri get download => Uri.parse(data['downloadUrl'] as String);

  Uri get browserDownload {
    final uri = download;
    return _officialHosts.contains(manifest.host) &&
            _officialHosts.contains(uri.host) &&
            _releaseFile.hasMatch(uri.path)
        ? Uri.https('huevia.cc', uri.path)
        : uri;
  }

  bool supportsOs(String version) {
    final current = version.split('.').map(int.tryParse).toList();
    final minimum = (data['minimumIOS'] as String)
        .split('.')
        .map(int.parse)
        .toList();
    if (current.isEmpty || current.any((part) => part == null)) return false;
    for (var i = 0; i < 3; i++) {
      final actual = i < current.length ? current[i]! : 0;
      final required = i < minimum.length ? minimum[i] : 0;
      if (actual != required) return actual > required;
    }
    return true;
  }

  bool trustedDownload(Uri value) {
    if (!validHttps(value)) return false;
    if (_officialHosts.contains(manifest.host) &&
        _officialHosts.contains(value.host)) {
      return !value.hasQuery &&
          _releaseFile.hasMatch(value.path) &&
          (data['id'] == null || data['id'] == value.pathSegments[3]);
    }
    if (!value.path.toLowerCase().endsWith('.ipa')) return false;
    if (value.host == manifest.host &&
        value.path.startsWith('${p.posix.dirname(manifest.path)}/')) {
      return true;
    }
    return value.host == 'github.com' &&
        value.path.startsWith('/1162107757/nikon-camera/releases/download/');
  }

  static bool validHttps(Uri value) =>
      value.scheme == 'https' &&
      value.host.isNotEmpty &&
      value.userInfo.isEmpty &&
      value.fragment.isEmpty &&
      value.pathSegments.every(
        (part) =>
            part != '..' &&
            part != '.' &&
            !part.contains('/') &&
            !part.contains('\\'),
      ) &&
      (!value.hasPort || value.port == 443);
}

class IosUpdatesPage extends StatefulWidget {
  const IosUpdatesPage({super.key});
  @override
  State<IosUpdatesPage> createState() => _IosUpdatesPageState();
}

class _IosUpdatesPageState extends State<IosUpdatesPage> {
  static const channel = MethodChannel('cc.huevia/distribution');
  Json installed = {};
  IosRelease? release;
  String error = '', status = '';
  bool busy = false;
  HttpClient? client;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(check());
  }

  @override
  void dispose() {
    generation++;
    client?.close(force: true);
    super.dispose();
  }

  Future<HttpClientResponse> request(Uri uri) async {
    final query = await client!
        .getUrl(uri)
        .timeout(const Duration(seconds: 20));
    query.followRedirects = false;
    query.headers.set('Accept', 'application/json');
    final response = await query.close().timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw const AppFailure('暂时无法读取 iOS 更新信息，请稍后重试。');
    }
    return response;
  }

  Future<void> check() async {
    if (busy) return;
    final attempt = ++generation;
    setState(() {
      busy = true;
      error = '';
      status = '正在检查 iOS 发布版本…';
      release = null;
    });
    client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      installed = object(
        await channel.invokeMapMethod<String, dynamic>('information'),
      );
      final configured = installed['manifestUrl'] as String? ?? '';
      if (configured.isEmpty) {
        throw const AppFailure('此安装包暂未配置 iOS 更新地址。');
      }
      final uri = Uri.tryParse(configured);
      if (uri == null || !IosRelease.validHttps(uri)) {
        throw const AppFailure('iOS 分发清单地址无效。');
      }
      final response = await request(uri);
      final bytes = <int>[];
      await for (final block in response.timeout(const Duration(seconds: 25))) {
        bytes.addAll(block);
        if (bytes.length > 64 * 1024) throw const AppFailure('iOS 发布清单过大。');
      }
      final responseValue = object(jsonDecode(utf8.decode(bytes)));
      if (responseValue.containsKey('release') &&
          responseValue['release'] == null) {
        if (mounted && attempt == generation) {
          setState(
            () => status = responseValue['reason'] == 'withdrawn'
                ? '此渠道的最近发布已撤回，暂时没有可下载版本'
                : '此渠道尚未发布 iOS 安装包',
          );
        }
        return;
      }
      final next = IosRelease(
        responseValue['release'] is Map
            ? object(responseValue['release'])
            : responseValue,
        manifest: uri,
        bundleId: installed['bundleId'] as String? ?? '',
      );
      if (mounted && attempt == generation) {
        setState(() {
          if (!next.supportsOs(installed['osVersion'] as String? ?? '')) {
            status = '新版本需要 iOS ${next.data['minimumIOS']} 或更高版本';
          } else if (next.code >
              (int.tryParse('${installed['versionCode']}') ?? 0)) {
            release = next;
            status = '发现可下载的更新';
          } else {
            status = '已是当前分发版本';
          }
        });
      }
    } catch (failure) {
      if (mounted && attempt == generation) {
        setState(() {
          error = failure is AppFailure
              ? '$failure'
              : failure is SocketException || failure is TimeoutException
              ? '暂时无法连接更新服务。连接相机 Wi-Fi 时，请同时开启移动数据后重试，无需断开相机。'
              : failure is HandshakeException
              ? '无法与更新服务建立安全连接，请稍后重试。'
              : '无法检查 iOS 更新，请稍后重试。';
          status = '检查未完成';
        });
      }
    } finally {
      client?.close(force: true);
      client = null;
      if (mounted && attempt == generation) setState(() => busy = false);
    }
  }

  Future<void> openDownload() async {
    final selected = release;
    if (busy || selected == null) return;
    setState(() {
      busy = true;
      error = '';
    });
    final opened = await openIosReleaseDownload(selected.browserDownload);
    if (!mounted) return;
    setState(() {
      busy = false;
      if (opened) {
        status = '已在浏览器打开 IPA 下载地址';
      } else {
        error = '无法打开浏览器，请稍后重试。';
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const HueHeader(title: 'iOS 应用更新', back: true),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '当前版本 ${updateVersionLabel(installed['versionName'], installed['versionCode'])}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          const Text('分发渠道：未签名 IPA · 自行签名'),
          const SizedBox(height: 16),
          Text(status),
          if (busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: const LinearProgressIndicator(),
            ),
          if (release != null) ...[
            const SizedBox(height: 24),
            Text(
              '新版本 ${updateVersionLabel(release!.data['versionName'], release!.code)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('IPA ${(release!.bytes / 1048576).toStringAsFixed(1)} MiB'),
            const SizedBox(height: 12),
            Text(release!.data['notes'] as String),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : openDownload,
              child: const Text('在浏览器下载 IPA'),
            ),
          ],
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextButton(onPressed: busy ? null : check, child: const Text('重新检查')),
          const SizedBox(height: 16),
          const Text('浏览器会打开 IPA 安装包下载地址。下载后需自行签名安装。'),
        ],
      ),
    ),
  );
}
