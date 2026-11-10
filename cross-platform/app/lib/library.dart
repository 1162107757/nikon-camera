import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'domain.dart';
import 'theme.dart';
import 'widgets.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.state});
  final AppState state;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int tab = 0, page = 1, generation = 0;
  String category = '', query = '';
  String? error;
  bool busy = false, hasMore = false;
  List<Preset> online = [];
  List<String> categories = [];
  Future<void> load({bool next = false}) async {
    final request = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await widget.state.core.call('online.page', {
        'page': next ? page + 1 : 1,
        'pageSize': 24,
        'category': category,
        'fileFormat': '',
      });
      if (!mounted || request != generation) return;
      final rows = (value['items'] as List)
          .map((row) => Preset(object(row), online: true))
          .toList();
      setState(() {
        online = next ? [...online, ...rows] : rows;
        page = value['page'] as int;
        hasMore = value['hasMore'] as bool;
        categories = List<String>.from(value['categories'] as List);
      });
    } catch (failure) {
      if (mounted && request == generation) setState(() => error = '$failure');
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  Future<void> import() async {
    try {
      final selected = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: '尼康预设',
            extensions: ['ncp', 'np2', 'np3'],
            uniformTypeIdentifiers: ['public.data'],
          ),
        ],
      );
      if (selected == null) return;
      await widget.state.importPreset(selected);
      if (mounted) report(context, '预设已加入本地库');
    } catch (error) {
      if (mounted) report(context, error);
    }
  }

  Future<void> detail(Preset preset) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(sheet).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(preset.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              '${preset.format} · ${preset.category.isEmpty ? '未分类' : preset.category}${preset.author.isEmpty ? '' : ' · ${preset.author}'}',
            ),
            if (preset.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(preset.description),
              ),
            const SizedBox(height: 16),
            if (preset.online)
              FilledButton.icon(
                icon: const Icon(Icons.download_outlined),
                label: const Text('保存到我的预设'),
                onPressed: () async {
                  Navigator.pop(sheet);
                  try {
                    await widget.state.core.call('online.download', {
                      'preset': preset.data,
                    });
                    await widget.state.refreshLibrary();
                    if (mounted) report(context, '预设已保存');
                  } catch (error) {
                    if (mounted) report(context, error);
                  }
                },
              )
            else ...[
              FilledButton.icon(
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('分享预设文件'),
                onPressed: () async {
                  Navigator.pop(sheet);
                  try {
                    final file = await widget.state.core.call(
                      'library.export',
                      {'id': preset.id},
                    );
                    await SharePlus.instance.share(
                      ShareParams(
                        files: [XFile(file['path'] as String)],
                        fileNameOverrides: [file['name'] as String],
                      ),
                    );
                  } catch (error) {
                    if (mounted) report(context, error);
                  }
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  Navigator.pop(sheet);
                  await editCategory(preset);
                },
                child: const Text('编辑分类'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  Navigator.pop(sheet);
                  await remove(preset);
                },
                child: const Text('移除预设'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
  Future<void> editCategory(Preset preset) async {
    final input = TextEditingController(text: preset.category);
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('预设分类'),
        content: TextField(
          controller: input,
          maxLength: 24,
          decoration: const InputDecoration(labelText: '分类名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, input.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value == null) return;
    try {
      await widget.state.core.call('library.category', {
        'id': preset.id,
        'category': value,
      });
      await widget.state.refreshLibrary();
    } catch (error) {
      if (mounted) report(context, error);
    }
  }

  Future<void> remove(Preset preset) async {
    final value = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('移除本地预设？'),
        content: Text(preset.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (value != true) return;
    try {
      await widget.state.core.call('library.remove', {'id': preset.id});
      await widget.state.refreshLibrary();
    } catch (error) {
      if (mounted) report(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = tab == 0 ? widget.state.presets : online;
    final rows = source
        .where(
          (preset) =>
              (tab == 1 || category.isEmpty || preset.category == category) &&
              (query.isEmpty ||
                  '${preset.name} ${preset.author} ${preset.category}'
                      .toLowerCase()
                      .contains(query.toLowerCase())),
        )
        .toList();
    final allCategories = {
      ...source.map((preset) => preset.category).where((s) => s.isNotEmpty),
      ...categories,
    }.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('预设库'),
        actions: [
          IconButton(
            onPressed: import,
            tooltip: '导入预设',
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: CapsuleSwitch(
                labels: const ['我的预设', '在线预设'],
                selected: tab,
                onSelected: (value) {
                  setState(() {
                    tab = value;
                    category = '';
                  });
                  if (value == 1 && online.isEmpty) unawaited(load());
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: '搜索预设、作者或分类',
                  isDense: true,
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  for (final item in ['', ...allCategories])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(item.isEmpty ? '全部' : item),
                        selected: category == item,
                        onSelected: (_) {
                          setState(() => category = item);
                          if (tab == 1) unawaited(load());
                        },
                      ),
                    ),
                ],
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(error!),
                    TextButton(
                      onPressed: busy ? null : load,
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            if (busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    tab == 0 ? widget.state.refreshLibrary() : load(),
                child: rows.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 72),
                          Icon(
                            tab == 0
                                ? Icons.tune_rounded
                                : Icons.cloud_outlined,
                            size: 40,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: Text(
                              busy
                                  ? '正在读取预设'
                                  : tab == 0
                                  ? '把喜欢的色彩收进来'
                                  : '暂时没有符合条件的预设',
                            ),
                          ),
                          if (tab == 0)
                            Center(
                              child: TextButton(
                                onPressed: import,
                                child: const Text('导入 NCP / NP2 / NP3'),
                              ),
                            ),
                        ],
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) => GridView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: (constraints.maxWidth / 180)
                                    .floor()
                                    .clamp(2, 5),
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                mainAxisExtent:
                                    228 +
                                    (MediaQuery.textScalerOf(context)
                                                .scale(14) -
                                            14) *
                                        3,
                              ),
                          itemCount:
                              rows.length + (hasMore && tab == 1 ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == rows.length) {
                              return Center(
                                child: OutlinedButton(
                                  onPressed: busy
                                      ? null
                                      : () => load(next: true),
                                  child: const Text('加载更多'),
                                ),
                              );
                            }
                            final preset = rows[index];
                            return Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => detail(preset),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: SizedBox.expand(
                                        child: PresetImage(preset: preset),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            preset.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${preset.format} · ${preset.category.isEmpty ? '未分类' : preset.category}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
