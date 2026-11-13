import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'domain.dart';
import 'theme.dart';

class IosRelease {
  IosRelease(Json value, {required this.manifest, required String bundleId})
    : data = value {
    final uri = Uri.tryParse(value['downloadUrl'] as String? ?? '');
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
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value['sha256'] as String? ?? '') ||
        value['notes'] is! String ||
        (value['notes'] as String).length > 12000 ||
        uri == null ||
        !trustedDownload(uri)) {
      throw const AppFailure('iOS 发布资料校验失败，未下载安装包。');
    }
  }
  final Json data;
  final Uri manifest;
  String get hash => data['sha256'] as String;
  int get bytes => data['byteLength'] as int;
  int get code => data['versionCode'] as int;
  Uri get download => Uri.parse(data['downloadUrl'] as String);
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
  bool trustedRedirect(Uri value) =>
      trustedDownload(value) ||
      validHttps(value) &&
          ([
                'release-assets.githubusercontent.com',
                'objects.githubusercontent.com',
              ].contains(value.host) ||
              value.host == 'download.huevia.cc' &&
                  value.path.startsWith(
                    '/huevia-updates/mobile-releases/ios/',
                  ));
}

class IosUpdatesPage extends StatefulWidget {
  const IosUpdatesPage({super.key, required this.root});
  final String root;
  @override
  State<IosUpdatesPage> createState() => _IosUpdatesPageState();
}

class _IosUpdatesPageState extends State<IosUpdatesPage> {
  static const channel = MethodChannel('cc.huevia/distribution');
  Json installed = {};
  IosRelease? release;
  String error = '', status = '', verifiedPath = '';
  bool busy = false;
  double? progress;
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

  Future<HttpClientResponse> request(Uri uri, {IosRelease? artifact}) async {
    var current = uri;
    for (var redirects = 0; redirects < 5; redirects++) {
      if (!IosRelease.validHttps(current) ||
          (artifact != null && !artifact.trustedRedirect(current))) {
        throw const AppFailure('分发地址不可信，已停止下载。');
      }
      final query = await client!
          .getUrl(current)
          .timeout(const Duration(seconds: 20));
      query.followRedirects = false;
      query.headers.set(
        'Accept',
        artifact == null ? 'application/json' : 'application/octet-stream',
      );
      final response = await query.close().timeout(const Duration(seconds: 25));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value('location');
        if (location == null || artifact == null) {
          throw const AppFailure('发布资料地址发生重定向，请联系分发者。');
        }
        current = current.resolve(location);
        await response.timeout(const Duration(seconds: 25)).drain<void>();
        continue;
      }
      if (response.statusCode != 200) {
        throw const AppFailure('暂时无法读取分发文件；私有或草稿发布需要在原分发入口登录后取得文件。');
      }
      return response;
    }
    throw const AppFailure('分发地址跳转过多，已停止下载。');
  }

  Future<void> check() async {
    if (busy) return;
    final attempt = ++generation;
    setState(() {
      busy = true;
      error = '';
      status = '正在检查 iOS 发布版本…';
      verifiedPath = '';
      release = null;
    });
    client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      installed = object(
        await channel.invokeMapMethod<String, dynamic>('information'),
      );
      final configured = installed['manifestUrl'] as String? ?? '';
      if (configured.isEmpty) {
        throw const AppFailure('尚未提供 iOS 发布清单。当前渠道交付未签名 IPA，请从交付聊天取得文件并自行签名。');
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
            status = '新的未签名 IPA 已可下载';
          } else {
            status = '已是当前分发版本';
          }
        });
      }
    } catch (failure) {
      if (mounted && attempt == generation) {
        setState(() {
          error = failure is AppFailure ? '$failure' : '无法检查 iOS 更新，请稍后重试。';
          status = '检查未完成';
        });
      }
    } finally {
      client?.close(force: true);
      client = null;
      if (mounted && attempt == generation) setState(() => busy = false);
    }
  }

  Future<void> download() async {
    final selected = release;
    if (busy || selected == null) return;
    final attempt = ++generation;
    setState(() {
      busy = true;
      error = '';
      status = '正在下载未签名 IPA…';
      progress = 0;
      verifiedPath = '';
    });
    final directory = Directory(p.join(widget.root, 'app-updates-ios'));
    File? partial;
    client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      await directory.create(recursive: true);
      if (await FileSystemEntity.isLink(directory.path)) {
        throw const AppFailure('更新目录无效。');
      }
      partial = File(p.join(directory.path, '${selected.hash}.part'));
      if (await FileSystemEntity.isLink(partial.path)) {
        throw const AppFailure('更新文件路径无效。');
      }
      final output = partial.openWrite();
      var received = 0;
      try {
        final response = await request(selected.download, artifact: selected);
        if (response.contentLength >= 0 &&
            response.contentLength != selected.bytes) {
          throw const AppFailure('IPA 文件大小与发布清单不符。');
        }
        await for (final block in response.timeout(
          const Duration(seconds: 30),
        )) {
          if (attempt != generation) throw const AppFailure('下载已取消。');
          received += block.length;
          if (received > selected.bytes) {
            throw const AppFailure('IPA 超过清单声明大小，已停止下载。');
          }
          output.add(block);
          if (mounted) setState(() => progress = received / selected.bytes);
        }
        await output.flush();
      } finally {
        await output.close();
      }
      if (received != selected.bytes ||
          (await sha256.bind(partial.openRead()).first).toString() !=
              selected.hash) {
        throw const AppFailure('IPA 的大小或 SHA-256 校验失败，未保留此下载。');
      }
      if (mounted) {
        setState(() {
          status = '正在核对 IPA 应用身份与版本…';
          progress = null;
        });
      }
      await channel.invokeMethod<void>('verifyIpa', {
        'path': partial.path,
        'bundleId': installed['bundleId'],
        'versionName': selected.data['versionName'],
        'versionCode': '${selected.code}',
      });
      final target = File(
        p.join(
          directory.path,
          'Huevia-${selected.data['versionName']}-${selected.code}.ipa',
        ),
      );
      if (await FileSystemEntity.isLink(target.path)) {
        throw const AppFailure('更新输出路径无效。');
      }
      await partial.rename(target.path);
      partial = null;
      if (mounted && attempt == generation) {
        setState(() {
          verifiedPath = target.path;
          status = 'IPA 文件校验通过，请导出后自行签名安装';
        });
      }
    } catch (failure) {
      if (mounted && attempt == generation) {
        setState(
          () => error = failure is AppFailure
              ? '$failure'
              : 'IPA 下载或包身份校验未完成，请重试。',
        );
      }
    } finally {
      client?.close(force: true);
      client = null;
      if (partial != null && await partial.exists()) await partial.delete();
      if (mounted && attempt == generation) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  Future<void> shareVerified() async {
    if (verifiedPath.isEmpty || busy) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(verifiedPath)],
          subject: 'Huevia 未签名 IPA',
          sharePositionOrigin: Rect.fromLTWH(
            24,
            MediaQuery.sizeOf(context).height / 2,
            1,
            1,
          ),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => error = '无法打开 IPA 导出菜单，请稍后重试。');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const HueHeader(title: 'iOS 应用更新', back: true),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '当前版本 ${installed['versionName'] ?? '正在读取…'}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          const Text('分发渠道：未签名 IPA · 自行签名'),
          const SizedBox(height: 16),
          Text(status),
          if (busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: LinearProgressIndicator(value: progress),
            ),
          if (release != null) ...[
            const SizedBox(height: 24),
            Text(
              '新版本 ${release!.data['versionName']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('IPA ${(release!.bytes / 1048576).toStringAsFixed(1)} MiB'),
            const SizedBox(height: 12),
            Text(release!.data['notes'] as String),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy
                  ? null
                  : verifiedPath.isEmpty
                  ? download
                  : shareVerified,
              child: Text(verifiedPath.isEmpty ? '下载并校验 IPA' : '导出 IPA 进行签名'),
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
          if (busy && progress != null)
            TextButton(
              onPressed: () {
                client?.close(force: true);
              },
              child: const Text('取消下载'),
            ),
          const SizedBox(height: 16),
          const Text(
            '文件通过 SHA-256、应用标识、版本和真机平台校验后才可导出。IPA 未签名，不能在应用内直接安装；请使用自己的签名工具、证书和设备许可。更换签名团队或 Bundle ID 可能形成独立安装，更新前请先导出资料。',
          ),
        ],
      ),
    ),
  );
}
