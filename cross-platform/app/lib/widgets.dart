import 'dart:io';

import 'package:flutter/material.dart';

import 'domain.dart';

Future<T?> hueRootPage<T>(BuildContext context, Route<T> route) =>
    Navigator.of(context, rootNavigator: true).push<T>(route);

// A popped dialog can still build during its exit animation. Its caller may
// release temporary text controllers only after the route has left the overlay.
Future<T?> hueDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? barrierColor,
}) async {
  final route = DialogRoute<T>(
    context: context,
    builder: builder,
    barrierColor: barrierColor ?? const Color(0x8a000000),
    themes: InheritedTheme.capture(
      from: context,
      to: Navigator.of(context, rootNavigator: true).context,
    ),
  );
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  return result;
}

Future<T?> hueBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color barrierColor = const Color.fromRGBO(0, 0, 0, .35),
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = ModalBottomSheetRoute<T>(
    builder: (sheet) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheet).bottom > 0
            ? MediaQuery.viewInsetsOf(sheet).bottom
            : MediaQuery.viewPaddingOf(sheet).bottom,
      ),
      child: Material(
        color: const Color(0xff242321),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(22)),
        ),
        child: MediaQuery.removePadding(
          context: sheet,
          removeBottom: true,
          child: Builder(builder: builder),
        ),
      ),
    ),
    capturedThemes: InheritedTheme.capture(
      from: context,
      to: navigator.context,
    ),
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    modalBarrierColor: barrierColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(22)),
    ),
  );
  final result = await navigator.push(route);
  await route.completed;
  return result;
}

Rect? shareAnchor(BuildContext context) {
  final box = context.findRenderObject();
  return box is RenderBox && box.hasSize && !box.size.isEmpty
      ? box.localToGlobal(Offset.zero) & box.size
      : null;
}

void report(BuildContext context, Object error) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$error'), behavior: SnackBarBehavior.floating),
    );
  }
}

class PresetImage extends StatelessWidget {
  const PresetImage({
    super.key,
    required this.preset,
    this.core,
    this.owner = '',
    this.original = false,
    this.showBadge = false,
    this.detail = false,
  });
  final Preset preset;
  final HueviaCore? core;
  final String owner;
  final bool original, showBadge, detail;
  @override
  Widget build(BuildContext context) {
    if (!preset.online && core != null) {
      return _LocalPresetImage(
        preset: preset,
        core: core!,
        owner: owner,
        original: original,
        showBadge: showBadge,
        detail: detail,
      );
    }
    Widget fallback() => ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Center(
        child: Text(
          preset.format,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
    final uri = Uri.tryParse(preset.preview);
    if (uri == null) return fallback();
    if (uri.scheme == 'https' && uri.userInfo.isEmpty) {
      return Image.network(
        preset.preview,
        fit: BoxFit.cover,
        cacheWidth: 480,
        errorBuilder: (_, _, _) => fallback(),
        excludeFromSemantics: true,
      );
    }
    if (uri.scheme == 'file') {
      return Image.file(
        File.fromUri(uri),
        fit: BoxFit.cover,
        cacheWidth: 480,
        errorBuilder: (_, _, _) => fallback(),
        excludeFromSemantics: true,
      );
    }
    return fallback();
  }
}

Future<void> _presetPreviewQueue = Future.value();

class _LocalPresetImage extends StatefulWidget {
  const _LocalPresetImage({
    required this.preset,
    required this.core,
    required this.owner,
    required this.original,
    required this.showBadge,
    required this.detail,
  });
  final Preset preset;
  final HueviaCore core;
  final String owner;
  final bool original, showBadge, detail;
  @override
  State<_LocalPresetImage> createState() => _LocalPresetImageState();
}

class _LocalPresetImageState extends State<_LocalPresetImage> {
  late Future<String?> image = load();
  @override
  void initState() {
    super.initState();
    widget.core.previewRevision.addListener(templateChanged);
  }

  void templateChanged() {
    if (mounted) setState(() => image = load());
  }

  @override
  void dispose() {
    widget.core.previewRevision.removeListener(templateChanged);
    super.dispose();
  }

  Future<String?> load() {
    final id = widget.preset.id,
        category = widget.preset.category,
        owner = widget.owner;
    final core = widget.core,
        original = widget.original,
        detail = widget.detail;
    final pending = _presetPreviewQueue.then((_) async {
      if (!mounted ||
          widget.preset.id != id ||
          widget.owner != owner ||
          widget.original != original ||
          widget.detail != detail) {
        return null;
      }
      try {
        final value = await core.call('media.showcase', {
          'id': id,
          'category': category,
          'owner': owner,
          'original': original,
          'edge': detail ? 960 : 480,
        });
        return value['path'] as String;
      } catch (_) {
        return null;
      }
    });
    _presetPreviewQueue = pending.then<void>((_) {});
    return pending;
  }

  @override
  void didUpdateWidget(covariant _LocalPresetImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.core != widget.core) {
      oldWidget.core.previewRevision.removeListener(templateChanged);
      widget.core.previewRevision.addListener(templateChanged);
      image = load();
    }
    if (oldWidget.preset.id != widget.preset.id ||
        oldWidget.preset.category != widget.preset.category ||
        oldWidget.owner != widget.owner ||
        oldWidget.original != widget.original ||
        oldWidget.detail != widget.detail) {
      image = load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    key: ValueKey(
      '${widget.owner}/${widget.preset.id}/${widget.preset.category}/${widget.original}/${widget.detail}',
    ),
    future: image,
    builder: (_, value) {
      final pending = value.connectionState != ConnectionState.done;
      final photo = value.data == null
          ? ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    pending ? '正在生成效果…' : '效果暂不可用\n点按查看详情',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            )
          : Image.file(
              File(value.data!),
              fit: BoxFit.cover,
              cacheWidth: widget.detail ? 960 : 480,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainer,
              ),
            );
      if (!widget.showBadge) return photo;
      return Stack(
        fit: StackFit.expand,
        children: [
          photo,
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xaa000000),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                pending
                    ? '生成中'
                    : value.data == null
                    ? '效果未生成'
                    : '模板模拟',
                style: const TextStyle(fontSize: 10, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    },
  );
}
