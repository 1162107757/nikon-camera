import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import 'domain.dart';
import 'theme.dart';
import 'widgets.dart';
import 'app_stability.dart';

const hueviaVersion = '0.31.0-dev';
const hueviaBuild = 215;

Future<Json> diagnosticSnapshot(AppState state) async {
  final core = state.core;
  Future<Json> read(String operation) async {
    try {
      return await core.call(operation).timeout(const Duration(seconds: 20));
    } catch (_) {
      return {'unavailable': true};
    }
  }

  final values = await Future.wait([
    read('gallery.access'),
    read('camera.diagnostics'),
    AppStability.snapshot(),
  ]);
  final gallery = values[0], camera = values[1];
  // Both producers are bounded. Keep a strict token alphabet as a second
  // boundary: filenames, endpoint addresses and exception text are excluded.
  final trace = (camera['trace'] as String? ?? '')
      .split('\n')
      .where(
        (line) =>
            line.length <= 512 &&
            RegExp(
              r'^wall_ms=[0-9]+ mono_ms=[0-9]+ event=[A-Z][A-Z0-9_]*(?: [a-z_]+=(?:[A-Z_]+|[0-9]+|0x[0-9a-f]+))*$',
            ).hasMatch(line),
      )
      .take(256)
      .toList();
  return {
    'schema': 1,
    'createdAt': DateTime.now().toUtc().toIso8601String(),
    'application': {
      'version': hueviaVersion,
      'build': hueviaBuild,
      'platform': Platform.operatingSystem,
      'systemVersion': Platform.operatingSystemVersion,
    },
    'library': {
      'presets': state.presets.length,
      'photos': state.photos.length,
      'rawPhotos': state.photos
          .where((photo) => photo.info['raw'] == true)
          .length,
    },
    'state': {
      'ready': state.ready,
      'signedIn': state.session['user'] != null,
      'viewSettingsWarning': state.uiPreferencesWarning != null,
      'accountStorageWarning':
          (state.session['storageWarning'] as String? ?? '').isNotEmpty,
    },
    'gallery': {
      'access': ['full', 'limited', 'none'].contains(gallery['access'])
          ? gallery['access']
          : 'unavailable',
      'canAsk': gallery['canAsk'] == true,
      'alternateBasis':
          ['added', 'modified'].contains(gallery['alternateBasis'])
          ? gallery['alternateBasis']
          : 'unknown',
    },
    'camera': {
      'available': camera['unavailable'] != true,
      'connected': camera['connected'] == true,
      'totalHandles': camera['totalHandles'] is int
          ? camera['totalHandles']
          : 0,
      'observedObjects': camera['observedObjects'] is int
          ? camera['observedObjects']
          : 0,
      'trace': trace,
    },
    'appStability': values[2],
    'operations': core.recentOperations
        .take(128)
        .map(
          (row) => {
            'operation': row['operation'],
            'at': row['at'],
            'elapsedMs': row['elapsedMs'],
            'status': row['status'],
          },
        )
        .toList(),
  };
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const HueHeader(title: '使用帮助', back: true),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _HelpCard(
          '预设与在线库',
          '在「预设」添加 NCP、NP3，或切换「在线预设」浏览已发布内容。在线预设下载后可离线编辑；在我的预设中长按卡片或打开详情，可置顶多个预设，最近置顶的排在前面。筛选中的风格、格式和下载状态会分别记住。',
        ),
        _HelpCard(
          '手机照片与权限',
          '在「相册 → 手机相册」允许照片访问。iOS 选择部分照片时，可点「管理可访问的照片」增减范围。也可以使用「选择指定照片」导入文件。',
        ),
        _HelpCard(
          'RAW 显影',
          '原文件保留在应用相册。RAW 先按相机白平衡和高光保护显影，再用 JPEG 工作副本编辑。若刚打开就出现高光偏色，请保留原始 RAW，并记录格式、设备和操作步骤。',
        ),
        _HelpCard(
          '批量编辑与导出',
          '点相册右上方「选择」，可逐张、按日期分组或全选，最多 100 张。可以依次编辑，保留各自编辑或统一选择预设，再保存到应用或系统相册。停止后已完成的成品保留，继续只处理未完成项。删除时可分别选择应用原图、成品版本及已核对的系统副本。',
        ),
        _HelpCard(
          '成品与分享',
          '成品版本保留生成时的配方，可在编辑器查看、恢复和分享。批量导出完成后使用系统分享，选择接收应用或保存位置。',
        ),
        _HelpCard(
          'USB 有线传输',
          '在「设置 → USB 数据线连接」检测并选择尼康相机，允许系统访问后浏览 JPEG 或 NEF。点开照片可查看相邻照片并明确选择对应 NEF；多选下载可保存到应用、系统相册或文件夹。Android 需支持 OTG；iPhone 需 USB-C 数据线或兼容的相机转接器。断线后从下载队列继续未完成项。',
        ),
        _HelpCard(
          '无线相机',
          '先让手机连接相机 Wi-Fi，再到「设置 → Wi-Fi 无线连接」连接。同步页可浏览原片、打开遥控拍摄及相机预设槽位。功能按机身实际能力开放；快门和预设写入结果不明时，先核对机身，避免重复执行。',
        ),
        _HelpCard(
          '后台连接与恢复',
          '在设置中开启后台接收保护。Android 接收期间显示持续通知，可从通知停止；iOS 提供有限收尾时间，到期暂停，持续接收请保持应用前台。重开应用后到下载队列核对原相机，继续未完成项。',
        ),
        _HelpCard(
          '人像与修补',
          '编辑器的人像工具支持选择人脸、皮肤与五官调整；识别不准时可手动调整范围。修补工具支持涂抹选择、撤销、重做，确认后才写入当前编辑配方。原始照片始终保留。',
        ),
        _HelpCard(
          '更新与旧版资料',
          '在设置中检查更新，Android 下载核对后打开系统安装；iOS 下载未签名 IPA 后自行签名安装。旧 Android 先安装同签名维护版导出资料包，iOS 可从文件中的旧版资料导入。迁入前可检查清单，旧账号需重新登录。',
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => hueRootPage<void>(
            context,
            MaterialPageRoute(builder: (_) => DiagnosticsPage(state: state)),
          ),
          child: const Text('导出诊断报告'),
        ),
      ],
    ),
  );
}

class _HelpCard extends StatelessWidget {
  const _HelpCard(this.title, this.text);
  final String title, text;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: HuePalette.of(context).card,
      borderRadius: BorderRadius.circular(17),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(text, style: const TextStyle(fontSize: 13, height: 1.6)),
      ],
    ),
  );
}

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key, required this.state});
  final AppState state;
  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  Json? snapshot;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await diagnosticSnapshot(widget.state);
      if (mounted) setState(() => snapshot = value);
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> share() async {
    if (snapshot == null || busy) return;
    setState(() => busy = true);
    try {
      final root = await Directory(widget.state.core.root)
          .resolveSymbolicLinks();
      final directory = Directory(p.join(root, 'diagnostics'));
      if (await FileSystemEntity.isLink(directory.path)) {
        throw const AppFailure('诊断目录不可用。');
      }
      await directory.create();
      if (!p.isWithin(root, await directory.resolveSymbolicLinks())) {
        throw const AppFailure('诊断目录不可用。');
      }
      final target = File(
        p.join(
          directory.path,
          'huevia-diagnostics-${DateTime.now().microsecondsSinceEpoch}.json',
        ),
      );
      final encoded = const JsonEncoder.withIndent('  ').convert(snapshot);
      if (utf8.encode(encoded).length > 128 * 1024) {
        throw const AppFailure('诊断报告过大。');
      }
      await target.writeAsString(encoded, flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          sharePositionOrigin: shareAnchor(context),
          files: [XFile(target.path, mimeType: 'application/json')],
        ),
      );
    } catch (failure) {
      if (mounted) report(context, failure);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const HueHeader(title: '诊断报告', back: true),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '报告包含应用和系统版本、资料数量、相册授权、操作耗时、相机协议阶段，以及本机可取得的异常类型、调用位置和系统退出摘要。不会包含照片、账号凭据、相机地址、异常消息或个人文件路径。',
        ),
        const SizedBox(height: 16),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (snapshot != null) ...[
          const SizedBox(height: 16),
          SelectableText(
            const JsonEncoder.withIndent('  ').convert(snapshot),
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ],
      ],
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : refresh,
                child: const Text('刷新'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: busy || snapshot == null ? null : share,
                child: const Text('导出 JSON'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const HueHeader(title: '关于 Huevia', back: true),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Huevia',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        const Text('$hueviaVersion · $hueviaBuild'),
        const SizedBox(height: 24),
        const _HelpCard('摄影与色彩', '预设浏览、本地管理、照片编辑和相机原片接收。手机预设模拟效果与相机实拍可能存在差异。'),
        const _HelpCard(
          '开源组件',
          'Flutter 与 Dart · LibRaw 0.22.3 · J2ObjC 3.1。Flutter 依赖的许可见「开源许可」；原生组件许可随项目保留。',
        ),
        const _HelpCard(
          '摄影样片',
          '内置样片来自 Pexels。样片已随安装包提供，具体来源保留在项目摄影资源清单；自选模板由你提供。',
        ),
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: 'Huevia',
            applicationVersion: hueviaVersion,
          ),
          child: const Text('开源许可'),
        ),
      ],
    ),
  );
}
