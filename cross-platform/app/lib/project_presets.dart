import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'domain.dart';
import 'project_presets_model.dart';
import 'camera_live_card.dart';
import 'theme.dart';
import 'versions.dart';
import 'widgets.dart';

class ProjectPresetsPage extends StatefulWidget {
  const ProjectPresetsPage({
    super.key,
    required this.state,
    this.embedded = false,
    this.onConnect,
  });
  final AppState state;
  final bool embedded;
  final Future<void> Function()? onConnect;
  @override
  State<ProjectPresetsPage> createState() => _ProjectPresetsPageState();
}

class _ProjectPresetsPageState extends State<ProjectPresetsPage> {
  late ProjectPresetsModel model = ProjectPresetsModel(widget.state);
  String liveRevision = '';
  @override
  void initState() {
    super.initState();
    widget.state.cameraLive.addListener(liveChanged);
    unawaited(model.refresh());
  }

  @override
  void dispose() {
    widget.state.cameraLive.removeListener(liveChanged);
    model.dispose();
    super.dispose();
  }

  void liveChanged() {
    if (!mounted) return;
    final live = widget.state.cameraLive;
    final revision =
        '${live.token}:${live.completed}:${live.queued}:${live.failed}';
    if (live.projectId == model.selected &&
        revision != liveRevision &&
        !model.busy) {
      liveRevision = revision;
      unawaited(model.refresh());
    }
    setState(() {});
  }

  Future<void> name({bool rename = false}) async {
    final input = TextEditingController(
      text: rename ? (model.project?['name'] as String? ?? '') : '',
    );
    final result = await hueDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(rename ? '重命名项目' : '新建拍摄项目'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: '项目名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, input.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    input.dispose();
    if (result == null || !mounted) return;
    if (rename) {
      await model.rename(result);
    } else {
      await model.create(result);
    }
  }

  Future<void> addPhotos() async {
    final eligible = widget.state.photos
        .where(
          (photo) =>
              photo.info['raw'] != true &&
              RegExp(r'\.(jpe?g)$', caseSensitive: false).hasMatch(photo.name),
        )
        .toList();
    final chosen = await hueRootPage<List<Photo>>(
      context,
      MaterialPageRoute(builder: (_) => _ProjectPhotoPicker(photos: eligible)),
    );
    if (chosen != null && mounted) await model.addPhotos(chosen);
  }

  Widget actions() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      OutlinedButton.icon(
        onPressed:
            model.busy ||
                model.project == null ||
                model.invalid ||
                widget.state.cameraLiveActive
            ? null
            : addPhotos,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('加入 JPEG'),
      ),
      FilledButton(
        onPressed:
            widget.state.cameraLiveActive ||
                model.busy ||
                model.photos.isEmpty ||
                (model.project?['presetId'] as String? ?? '').isEmpty ||
                model.invalid
            ? null
            : () => unawaited(model.process(enqueue: true)),
        child: const Text('套用默认预设'),
      ),
      if (model.pending > 0)
        OutlinedButton(
          onPressed:
              model.busy || model.invalid || widget.state.cameraLiveActive
              ? null
              : () => unawaited(model.process()),
          child: Text('继续处理 ${model.pending} 张'),
        ),
      if (model.failed > 0)
        OutlinedButton(
          onPressed:
              model.busy || model.invalid || widget.state.cameraLiveActive
              ? null
              : () => unawaited(model.process(retry: true)),
          child: Text('重试未完成 ${model.failed} 张'),
        ),
      if (model.tasks.isNotEmpty)
        TextButton(
          onPressed: () => hueRootPage<void>(
            context,
            MaterialPageRoute(builder: (_) => _ProjectTasksPage(model: model)),
          ),
          child: const Text('处理记录'),
        ),
      if (model.busy)
        TextButton(onPressed: model.stop, child: const Text('停止处理')),
    ],
  );
  Widget controls() {
    final project = model.project, p = HuePalette.of(context);
    final presetId = project?['presetId'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.embedded)
                const Expanded(
                  child: Text(
                    '拍摄项目',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                )
              else
                const Spacer(),
              IconButton(
                tooltip: '刷新拍摄项目',
                onPressed: model.busy || model.invalid ? null : model.refresh,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: '新建拍摄项目',
                onPressed: model.busy || model.invalid ? null : name,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          if (model.invalid) ...[
            Text(model.error ?? '账号已改变，请重新打开拍摄项目。'),
            TextButton(
              onPressed: () => setState(() {
                model.dispose();
                model = ProjectPresetsModel(widget.state);
                unawaited(model.refresh());
              }),
              child: const Text('重新打开项目'),
            ),
          ] else if (model.projects.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('project-${model.selected}'),
                    initialValue: model.selected,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '拍摄项目'),
                    items: [
                      for (final row in model.projects)
                        DropdownMenuItem(
                          value: row['id'] as String,
                          child: Text(
                            row['name'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: model.busy
                        ? null
                        : (id) {
                            if (id != null) unawaited(model.select(id));
                          },
                  ),
                ),
                IconButton(
                  tooltip: '重命名拍摄项目',
                  onPressed: model.busy || project == null
                      ? null
                      : () => name(rename: true),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey('default-${model.selected}-$presetId'),
              initialValue: presetId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '项目默认预设'),
              items: [
                DropdownMenuItem(value: '', child: const Text('不使用默认预设')),
                if (presetId.isNotEmpty &&
                    !widget.state.presets.any(
                      (preset) => preset.id == presetId,
                    ))
                  DropdownMenuItem(
                    value: presetId,
                    child: Text(
                      '${project?['presetName']} · 项目快照',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                for (final preset in widget.state.presets)
                  DropdownMenuItem(
                    value: preset.id,
                    child: Text(
                      preset.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: model.busy
                  ? null
                  : (id) {
                      if (id != null) unawaited(model.setPreset(id));
                    },
            ),
            const SizedBox(height: 12),
            CameraLiveCard(
              state: widget.state,
              projectId: model.selected,
              projectName: project?['name'] as String? ?? '',
              hasPreset: presetId.isNotEmpty,
              enabled: !model.busy && !model.invalid,
              onConnect: widget.onConnect,
            ),
            const SizedBox(height: 8),
            Text(
              '原图保留在应用相册；套用默认预设会另存成品，保留照片当前编辑。',
              style: TextStyle(fontSize: 12, height: 1.5, color: p.secondary),
            ),
            const SizedBox(height: 12),
            actions(),
            const SizedBox(height: 12),
            Text(
              '项目照片 · ${model.photos.length} 张',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ] else if (!model.busy) ...[
            const SizedBox(height: 28),
            const Text('还没有拍摄项目'),
            const SizedBox(height: 8),
            Text('新建项目，整理本机照片并设置默认预设。', style: TextStyle(color: p.secondary)),
            const SizedBox(height: 16),
            FilledButton(onPressed: name, child: const Text('新建拍摄项目')),
          ],
          if (model.phase.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(model.phase),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: model.progress),
          ],
          if (model.error != null && !model.invalid) ...[
            const SizedBox(height: 12),
            Text(
              model.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (model.busy && model.phase.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = AnimatedBuilder(
      animation: model,
      builder: (context, _) => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: controls()),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              widget.embedded ? 112 + hueNavigationInset(context) : 24,
            ),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final photo = model.photos[index];
                return Semantics(
                  label: photo['name'] as String,
                  button: true,
                  child: GestureDetector(
                    onTap: () => hueRootPage<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _ProjectOriginalPage(
                          state: widget.state,
                          photo: photo,
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(
                        File(photo['path'] as String),
                        cacheWidth: 384,
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Color(0xffeeeeec),
                          child: Center(
                            child: Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }, childCount: model.photos.length),
            ),
          ),
        ],
      ),
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('拍摄项目')),
            body: SafeArea(child: body),
          );
  }
}

class _ProjectPhotoPicker extends StatefulWidget {
  const _ProjectPhotoPicker({required this.photos});
  final List<Photo> photos;
  @override
  State<_ProjectPhotoPicker> createState() => _ProjectPhotoPickerState();
}

class _ProjectPhotoPickerState extends State<_ProjectPhotoPicker> {
  final Set<String> selected = {};
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('加入 JPEG · ${selected.length} 张')),
    body: widget.photos.isEmpty
        ? const Center(child: Text('应用相册中还没有 JPEG，请先导入或从相机下载。'))
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: widget.photos.length,
            itemBuilder: (context, index) {
              final photo = widget.photos[index];
              return CheckboxListTile(
                value: selected.contains(photo.path),
                title: Text(
                  photo.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                secondary: SizedBox.square(
                  dimension: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(photo.path),
                      cacheWidth: 160,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.image_outlined),
                    ),
                  ),
                ),
                onChanged: (value) => setState(() {
                  if (value == false) {
                    selected.remove(photo.path);
                  } else if (selected.length < 100) {
                    selected.add(photo.path);
                  }
                }),
              );
            },
          ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: selected.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  widget.photos
                      .where((photo) => selected.contains(photo.path))
                      .toList(),
                ),
          child: const Text('加入项目'),
        ),
      ),
    ),
  );
}

class _ProjectTasksPage extends StatelessWidget {
  const _ProjectTasksPage({required this.model});
  final ProjectPresetsModel model;
  Future<void> open(BuildContext context, Json task) async {
    try {
      final version = await model.result(task);
      if (context.mounted) {
        await hueRootPage<void>(
          context,
          MaterialPageRoute(
            builder: (_) => VersionPreviewPage(
              core: model.state.core,
              owner: model.owner,
              version: version,
            ),
          ),
        );
      }
    } catch (failure) {
      if (context.mounted) report(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('项目处理记录')),
    body: AnimatedBuilder(
      animation: model,
      builder: (context, _) => ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: model.tasks.length,
        itemBuilder: (context, index) {
          final task = model.tasks[index], status = task['status'];
          final label =
              {
                'queued': '等待处理',
                'processing': '正在处理',
                'saved': '已保存成品',
                'error': '未完成，可重试',
              }[status] ??
              '等待处理';
          return Card(
            child: ListTile(
              title: Text(
                task['name'] as String,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${task['presetName']} · $label${status == 'error' ? '\n${task['error']}' : ''}',
              ),
              trailing: status == 'saved'
                  ? const Icon(Icons.chevron_right)
                  : null,
              onTap: status == 'saved' && !model.busy && !model.invalid
                  ? () => open(context, task)
                  : null,
            ),
          );
        },
      ),
    ),
  );
}

class _ProjectOriginalPage extends StatelessWidget {
  const _ProjectOriginalPage({required this.state, required this.photo});
  final AppState state;
  final Json photo;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('项目原图')),
    body: Column(
      children: [
        Expanded(
          child: InteractiveViewer(
            child: Center(
              child: Image.file(
                File(photo['path'] as String),
                cacheWidth: 1280,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Text('原图暂不可用，项目记录仍保留。'),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: state.photos.any((item) => item.path == photo['path'])
                  ? () => context.push<void>(
                      '/photo/${Uri.encodeComponent(state.photos.firstWhere((item) => item.path == photo['path']).id)}',
                    )
                  : null,
              child: const Text('编辑这张照片'),
            ),
          ),
        ),
      ],
    ),
  );
}
