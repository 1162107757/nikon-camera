import 'package:flutter/material.dart';

import 'domain.dart';
import 'split_compare.dart';
import 'widgets.dart';

/// A gallery cover and a generated original may show different subjects.
/// Always compare the paired showcase renders from the same template.
class PresetShowcaseCompare extends StatefulWidget {
  const PresetShowcaseCompare({
    super.key,
    required this.core,
    required this.preset,
    required this.owner,
  });

  final HueviaCore core;
  final Preset preset;
  final String owner;

  @override
  State<PresetShowcaseCompare> createState() => _PresetShowcaseCompareState();
}

class _PresetShowcaseCompareState extends State<PresetShowcaseCompare> {
  late Future<({String effect, String? original})?> preview;

  @override
  void initState() {
    super.initState();
    widget.core.previewRevision.addListener(reload);
    preview = load();
  }

  @override
  void didUpdateWidget(covariant PresetShowcaseCompare oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.core != widget.core) {
      oldWidget.core.previewRevision.removeListener(reload);
      widget.core.previewRevision.addListener(reload);
    }
    if (oldWidget.core != widget.core ||
        oldWidget.preset.id != widget.preset.id ||
        oldWidget.preset.category != widget.preset.category ||
        oldWidget.owner != widget.owner) {
      preview = load();
    }
  }

  @override
  void dispose() {
    widget.core.previewRevision.removeListener(reload);
    super.dispose();
  }

  void reload() {
    final next = load();
    setState(() {
      preview = next;
    });
  }

  Future<({String effect, String? original})?> load() async {
    final core = widget.core, preset = widget.preset, owner = widget.owner;
    final revision = core.previewRevision.value;
    final id = preset.online ? preset.data['sha256'] : preset.id;
    if (id is! String || id.isEmpty) return null;
    final request = {
      'id': id,
      if (preset.online) 'preset': preset.data,
      'owner': owner,
      'category': preset.category,
      'edge': 960,
    };
    Json effect;
    try {
      effect = await core.call('media.showcase', {
        ...request,
        'original': false,
      });
    } catch (_) {
      return null;
    }
    final path = effect['path'] as String?;
    if (path == null || path.isEmpty) return null;
    if (!mounted ||
        widget.owner != owner ||
        core.previewRevision.value != revision) {
      return null;
    }
    try {
      final original = await core.call('media.showcase', {
        ...request,
        'original': true,
      });
      if (effect['scene'] != null && original['scene'] == effect['scene']) {
        final before = original['path'] as String?;
        if (before != null && before.isNotEmpty && before != path) {
          return (effect: path, original: before);
        }
      }
    } catch (_) {
      // This effect is still usable if the paired original could not be created.
    }
    return (effect: path, original: null);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    key: ValueKey(preview),
    future: preview,
    builder: (context, snapshot) {
      final pair = snapshot.data;
      if (pair != null) {
        return SplitCompare(
          effect: pair.effect,
          original: pair.original,
          enabled: pair.original != null,
          photoFit: BoxFit.cover,
          effectLabel: '预设效果',
          fitPreview: true,
          onRetry: reload,
        );
      }
      final pending = snapshot.connectionState != ConnectionState.done;
      if (widget.preset.online && widget.preset.preview.isNotEmpty) {
        return Stack(
          fit: StackFit.expand,
          children: [
            PresetImage(
              preset: widget.preset,
              core: widget.core,
              owner: widget.owner,
              detail: true,
            ),
            if (!pending)
              const Positioned(
                right: 12,
                bottom: 12,
                child: Chip(label: Text('原图对比暂不可用')),
              ),
          ],
        );
      }
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainer,
        child: Center(
          child: pending
              ? const CircularProgressIndicator()
              : TextButton(onPressed: reload, child: const Text('重试预览')),
        ),
      );
    },
  );
}
