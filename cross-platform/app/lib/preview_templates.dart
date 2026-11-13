import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'theme.dart';

class PreviewTemplatesPage extends StatefulWidget {
  const PreviewTemplatesPage({super.key, required this.core});
  final HueviaCore core;
  @override
  State<PreviewTemplatesPage> createState() => _PreviewTemplatesPageState();
}

class _PreviewTemplatesPageState extends State<PreviewTemplatesPage> {
  Json? info, image;
  String? error;
  bool busy = false;
  int index = 0;
  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    try {
      final value = await widget.core.call('media.templateInfo');
      final source = await widget.core.call('media.templateSource', {
        'index': index,
      });
      if (mounted) {
        setState(() {
          info = value;
          image = source;
          error = null;
        });
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    }
  }

  Future<void> change({bool reset = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (reset) {
        await widget.core.call('media.templateReset');
      } else {
        final selected = await widget.core.pickFile(preset: false);
        if (selected == null || !mounted) return;
        final path = selected['path'] as String;
        await widget.core.call('media.templateSet', {'path': path});
      }
      final previous = image?['path'];
      if (previous is String) await FileImage(File(previous)).evict();
      index = 0;
      await refresh();
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> next() async {
    if (busy || info == null) return;
    setState(() => busy = true);
    index = (index + 1) % (info!['count'] as int);
    await refresh();
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const HueHeader(title: '预览模板', back: true),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          info?['custom'] == true ? '自选模板' : '内置摄影样片 · 10 张',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text('预设主图使用这些照片生成手机模拟效果。更换模板后会重新生成主图。'),
        const SizedBox(height: 8),
        const Text('自选模板支持 20MB 以内的普通照片。'),
        const SizedBox(height: 20),
        if (image?['path'] is String) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Image.file(
              File(image!['path'] as String),
              cacheWidth: 960,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox(
                height: 160,
                child: Center(child: Text('模板图片未能打开')),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text('${image!['label']}'),
          if ((image!['credit'] as String? ?? '').isNotEmpty)
            Text(
              image!['credit'] as String,
              style: TextStyle(
                fontSize: 11,
                color: HuePalette.of(context).secondary,
              ),
            ),
        ],
        if (busy)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(error!),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : change,
          child: const Text('从手机选择模板图'),
        ),
        OutlinedButton(
          onPressed: busy || info?['custom'] != true
              ? null
              : () => change(reset: true),
          child: const Text('恢复内置摄影样片'),
        ),
        if (error != null)
          TextButton(
            onPressed: busy ? null : refresh,
            child: const Text('重新读取'),
          ),
      ],
    ),
  );
}
