import 'dart:async';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'original_files.dart';
import 'original_save.dart';

/// Original format and destination are explicit; no rendered JPEG is substituted for RAW.
class OriginalTargetsPage extends StatefulWidget {
  const OriginalTargetsPage({
    super.key,
    required this.state,
    required this.source,
    required this.sourceSha,
    required this.filename,
  });
  final AppState state;
  final String source, sourceSha, filename;
  @override
  State<OriginalTargetsPage> createState() => _OriginalTargetsPageState();
}

class _OriginalTargetsPageState extends State<OriginalTargetsPage> {
  late final String owner;
  Json? inspected, folder;
  OriginalSave? save;
  String target = 'app';
  String? error;
  bool busy = false, keptInApp = false;
  @override
  void initState() {
    super.initState();
    widget.state.addListener(changed);
    owner = widget.state.session['user']?['id'] as String? ?? '';
    unawaited(inspect());
  }

  bool get current =>
      mounted &&
      widget.state.session['logoutPending'] != true &&
      (widget.state.session['user']?['id'] as String? ?? '') == owner;
  Future<void> inspect() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final checked = await widget.state.core.call('source.inspect', {
        'owner': owner,
        'path': widget.source,
        'expectedSourceSha': widget.sourceSha,
      });
      if (current) setState(() => inspected = checked);
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseFolder() async {
    if (busy || save?.busy == true) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final selected = await OriginalFiles.chooseTarget(owner);
      if (current && selected != null) {
        save?.removeListener(changed);
        save?.dispose();
        save = null;
        setState(() {
          folder = selected;
          target = 'files';
          keptInApp = false;
        });
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> publish() async {
    if (!current || inspected == null || busy || save?.busy == true) return;
    if (target == 'app') {
      await inspect();
      if (current && error == null) setState(() => keptInApp = true);
      return;
    }
    if (target == 'files' && folder == null) {
      await chooseFolder();
      return;
    }
    save ??= OriginalSave(
      widget.state,
      owner,
      widget.source,
      widget.sourceSha,
      widget.filename,
      targetId: target == 'files' ? folder!['id'] as String : null,
    )..addListener(changed);
    await save!.run();
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void choose(String selected) {
    if (save?.busy == true) return;
    save?.removeListener(changed);
    save?.dispose();
    save = null;
    setState(() {
      target = selected;
      keptInApp = false;
    });
  }

  @override
  void dispose() {
    widget.state.removeListener(changed);
    save?.removeListener(changed);
    save?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locked = busy || save?.busy == true || !current;
    final format = inspected?['format'] ?? '原始格式';
    return Scaffold(
      appBar: AppBar(title: const Text('保存原始文件')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.filename,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('$format · ${inspected?['bytes'] ?? '正在核对'} 字节'),
            const SizedBox(height: 12),
            if (!current) const Text('账号已变化，请返回相册重新选择原文件。'),
            const Text('完整保留原文件字节、EXIF 与拍摄信息，不应用编辑、边框或导出画质设置。NEF 不转换成 JPEG。'),
            const SizedBox(height: 20),
            Text('选择保存位置', style: Theme.of(context).textTheme.titleMedium),
            RadioGroup<String>(
              groupValue: target,
              onChanged: (value) {
                if (!locked && value != null) choose(value);
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    value: 'app',
                    enabled: !locked,
                    title: const Text('应用相册'),
                    subtitle: const Text('原文件已在应用中保留，重新核对内容即可'),
                  ),
                  RadioListTile<String>(
                    value: 'gallery',
                    enabled: !locked,
                    title: const Text('手机系统相册'),
                    subtitle: Text(
                      format == 'NEF'
                          ? '以 NEF 原字节保存；系统不支持时可选择 Files'
                          : '保留 JPEG 原文件及其已有信息',
                    ),
                  ),
                  RadioListTile<String>(
                    value: 'files',
                    enabled: !locked,
                    title: const Text('Files / 文件夹'),
                    subtitle: Text(
                      folder?['name'] as String? ?? '选择并授权文件夹，保存后读回核对 SHA-256',
                    ),
                  ),
                ],
              ),
            ),
            if (target == 'files')
              TextButton.icon(
                onPressed: locked ? null : chooseFolder,
                icon: const Icon(Icons.folder_open),
                label: Text(folder == null ? '选择文件夹' : '更换文件夹'),
              ),
            if (locked) const LinearProgressIndicator(),
            if (error != null || save?.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error ?? save!.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ),
            if (keptInApp || save?.done == true)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('原始文件已保存并保留完整格式。'),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  locked || inspected == null || save?.done == true || keptInApp
                  ? null
                  : publish,
              icon: const Icon(Icons.save_alt),
              label: Text(
                save?.error != null
                    ? '重试此保存任务'
                    : target == 'app'
                    ? '保留并核对应用原文件'
                    : '确认保存 $format 原文件',
              ),
            ),
            if (save?.busy == true)
              TextButton(onPressed: save!.cancel, child: const Text('停止保存')),
          ],
        ),
      ),
    );
  }
}
