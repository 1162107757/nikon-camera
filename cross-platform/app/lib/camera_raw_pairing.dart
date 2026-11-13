import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'camera_transfer.dart';
import 'domain.dart';
import 'original_targets.dart';

class CameraRawPairingPage extends StatefulWidget {
  const CameraRawPairingPage({
    super.key,
    required this.state,
    required this.session,
    required this.jpegHandle,
  });
  final AppState state;
  final String session;
  final int jpegHandle;
  @override
  State<CameraRawPairingPage> createState() => _CameraRawPairingPageState();
}

class _CameraRawPairingPageState extends State<CameraRawPairingPage> {
  late final CameraTransfer transfer;
  Json data = {};
  Json? receivedPair, receivedSource;
  List<Json> rows = [];
  int? selected;
  bool busy = false;
  bool linked = false, linkFailed = false;
  String? error, job;
  @override
  void initState() {
    super.initState();
    transfer = CameraTransfer(widget.state)..addListener(changed);
    unawaited(load());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  Future<void> load({bool more = false}) async {
    if (busy || transfer.busy) return;
    if (widget.state.cameraDownloadsActive ||
        widget.state.cameraManualTransferActive) {
      setState(() => error = '请先停止相机接收队列，再核对 RAW 原文件。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    job = 'raw-pair-${DateTime.now().microsecondsSinceEpoch}';
    try {
      final result = await widget.state.core.call(
        more ? 'camera.raw.page' : 'camera.raw.pair',
        {
          'session': widget.session,
          if (more) ...{
            'pairId': data['pairId'],
            'offset': data['nextOffset'],
            'limit': 60,
          } else
            'handle': widget.jpegHandle,
        },
        job,
      );
      if (!mounted) return;
      final incoming = (result['items'] as List).map(object).toList();
      if (!more) {
        rows = [];
        selected = (result['matchedHandle'] as num? ?? 0).toInt();
        if (selected == 0) selected = null;
        if (result['matched'] is Map) {
          incoming.insert(0, object(result['matched']));
        }
      }
      final known = rows.map((item) => item['handle']).toSet();
      for (final item in incoming) {
        if (known.add(item['handle'])) rows.add(item);
      }
      setState(() => data = result);
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      job = null;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> receive() async {
    if (selected == null || busy || transfer.busy) return;
    if (widget.state.cameraDownloadsActive ||
        widget.state.cameraManualTransferActive) {
      setState(() => error = '请先停止相机接收队列，再手动接收 RAW 原文件。');
      return;
    }
    final row = rows.firstWhere((item) => item['handle'] == selected);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('接收 ${row['name']}？'),
        content: Text(
          '原始 NEF · ${row['bytes']} 字节\n存储卡 ${row['storage']} · ${row['capturedAt']}\n\n请确认这是所需 RAW。应用按原字节接收，并核对相机描述符、长度、NEF 结构和 SHA-256。若应用中存在同一相机来源的唯一 JPEG，接收后会更新它的 RAW 关联。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认接收此 RAW'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (widget.state.cameraDownloadsActive ||
        widget.state.cameraManualTransferActive) {
      setState(() => error = '相机接收队列已开始，请停止队列后重新确认。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      linked = false;
      linkFailed = false;
    });
    try {
      await widget.state.core.call('camera.raw.select', {
        'session': widget.session,
        'pairId': data['pairId'],
        'handle': selected,
        'confirmed': true,
      });
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
      return;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    receivedPair = Map<String, dynamic>.from(data);
    receivedSource = Map<String, dynamic>.from(row);
    await transfer.start(widget.session, row, raw: true);
    if (mounted && transfer.done) await linkOriginal();
  }

  Future<void> linkOriginal() async {
    final raw = transfer.importedPhoto;
    final proof = receivedPair, selectedRaw = receivedSource;
    if (raw == null ||
        proof == null ||
        selectedRaw == null ||
        proof['cameraId'] is! String ||
        proof['jpegDescriptor'] is! String) {
      return;
    }
    final sha = p.basenameWithoutExtension(raw.path);
    final matches = widget.state.photos.where((photo) {
      final source = photo.info['cameraSource'];
      return source is Map &&
          source['cameraId'] == proof['cameraId'] &&
          source['descriptor'] == proof['jpegDescriptor'];
    }).toList();
    if (matches.length != 1 || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) return;
    setState(() => busy = true);
    try {
      final jpeg = matches.single;
      await widget.state.updatePhoto(jpeg, {
        ...jpeg.info,
        'rawSource': raw.path,
        'rawSourceSha': sha,
        'rawPairing': {
          'cameraId': proof['cameraId'],
          'jpegDescriptor': proof['jpegDescriptor'],
          'rawDescriptor': selectedRaw['descriptor'],
          'explicitSelection': true,
          'matchedByInventory': proof['matchedHandle'] == selectedRaw['handle'],
          'sha256': sha,
        },
      });
      if (mounted) {
        setState(() {
          linked = true;
          linkFailed = false;
        });
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = 'NEF 已保存，JPEG 关联尚未保存：$failure';
          linkFailed = true;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> destinations() async {
    final photo = transfer.importedPhoto;
    if (photo == null) return;
    final sha = p.basenameWithoutExtension(photo.path);
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OriginalTargetsPage(
          state: widget.state,
          source: photo.path,
          sourceSha: sha,
          filename: photo.name,
        ),
      ),
    );
  }

  @override
  void dispose() {
    final active = job;
    if (active != null) unawaited(widget.state.core.cancel(active));
    transfer.removeListener(changed);
    transfer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('核对相机 RAW 原文件')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('先核对相机完整库存，再明确选择要接收的 NEF。浏览此列表只读取元数据，不下载 RAW 原文件。'),
          const SizedBox(height: 12),
          if (data['reason'] is String) Text(data['reason'] as String),
          if (data['objects'] is num)
            Text('本次核对 ${data['objects']} 个对象，列出 ${data['rawCount']} 个 NEF'),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          RadioGroup<int>(
            groupValue: selected,
            onChanged: (value) {
              if (!busy && !transfer.busy) setState(() => selected = value);
            },
            child: Column(
              children: [
                for (final row in rows)
                  RadioListTile<int>(
                    value: row['handle'] as int,
                    enabled: !busy && !transfer.busy,
                    title: Text(row['name'] as String),
                    subtitle: Text(
                      '存储卡 ${row['storage']} · ${row['capturedAt']}\n${row['bytes']} 字节 · 序列 ${row['sequence']}',
                    ),
                  ),
              ],
            ),
          ),
          if (data['hasMore'] == true)
            TextButton(
              onPressed: busy || transfer.busy ? null : () => load(more: true),
              child: const Text('继续读取 RAW 列表'),
            ),
          if (rows.isEmpty && !busy && data.isNotEmpty)
            const Text('本次库存未列出 NEF。请在相机确认存储卡和 RAW 设置后刷新。'),
          CameraTransferCard(transfer: transfer),
          if (linked) const Text('已为应用中有同一相机描述符的 JPEG 保存原始 NEF 关联。'),
          if (transfer.done && !linked && !linkFailed)
            const Text('NEF 已独立保存在应用相册；未把缺少相机来源证据的旧 JPEG 按文件名自动绑定。'),
          if (linkFailed)
            TextButton(
              onPressed: linkOriginal,
              child: const Text('重试 JPEG 与 NEF 关联'),
            ),
          FilledButton.icon(
            onPressed: selected == null || busy || transfer.busy
                ? null
                : receive,
            icon: const Icon(Icons.download),
            label: const Text('接收所选 NEF 原文件'),
          ),
          if (transfer.done && transfer.importedPhoto != null)
            OutlinedButton.icon(
              onPressed: destinations,
              icon: const Icon(Icons.save_alt),
              label: const Text('选择原文件保存位置'),
            ),
          TextButton(
            onPressed: busy || transfer.busy ? null : load,
            child: const Text('重新核对相机库存'),
          ),
        ],
      ),
    ),
  );
}
