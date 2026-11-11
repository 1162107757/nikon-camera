import 'dart:async';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'widgets.dart';

class RecipesPage extends StatefulWidget {
  const RecipesPage({
    super.key,
    required this.core,
    required this.owner,
    required this.path,
    required this.current,
  });
  final HueviaCore core;
  final String owner, path;
  final Json current;
  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
  List<Json> items = [];
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(run('recipe.list'));
  }

  Future<void> run(String operation, [Json extras = const {}]) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.core.call(operation, {
        ...extras,
        'owner': widget.owner,
        'path': widget.path,
        if (operation == 'recipe.create' || operation == 'recipe.apply')
          'recipe': widget.current,
      });
      if (!mounted) return;
      if (operation == 'recipe.apply') {
        setState(() => busy = false);
        Navigator.pop(context, object(result['recipe']));
        return;
      }
      final listing = operation == 'recipe.list'
          ? result
          : await widget.core.call('recipe.list', {'owner': widget.owner});
      if (mounted) {
        setState(() => items = (listing['items'] as List).map(object).toList());
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> nameRecipe([Json? item]) async {
    var enteredName = item?['name'] as String? ?? '';
    final name = await hueDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(item == null ? '保存当前配方' : '重命名配方'),
        content: TextFormField(
          initialValue: enteredName,
          onChanged: (value) => enteredName = value,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: '配方名称'),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(dialog, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (enteredName.trim().isNotEmpty) {
                Navigator.pop(dialog, enteredName.trim());
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) return;
    await run(item == null ? 'recipe.create' : 'recipe.rename', {
      'name': name,
      if (item != null) 'id': item['id'],
    });
  }

  Future<void> remove(Json item) async {
    final confirmed = await hueDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('删除配方？'),
        content: Text('删除“${item['name']}”后，照片当前的编辑设置会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await run('recipe.delete', {'id': item['id']});
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('我的配方')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('保存滤镜与色彩调节，应用到其他照片。'),
            const SizedBox(height: 8),
            const Text('构图、边框和局部编辑保持当前照片的设置。'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy ? null : nameRecipe,
              icon: const Icon(Icons.add_rounded),
              label: const Text('保存当前配方'),
            ),
            if (busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: busy ? null : () => run('recipe.list'),
                child: const Text('重新读取'),
              ),
            ],
            const SizedBox(height: 20),
            if (!busy && items.isEmpty && error == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Text('还没有配方。将喜欢的调色保存下来，下次继续使用。'),
              ),
            for (final item in items)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
                  title: Text(item['name'] as String),
                  subtitle: Text(item['summary'] as String),
                  onTap: busy
                      ? null
                      : () => run('recipe.apply', {'id': item['id']}),
                  trailing: PopupMenuButton<String>(
                    enabled: !busy,
                    tooltip: '管理配方',
                    onSelected: (value) =>
                        value == 'rename' ? nameRecipe(item) : remove(item),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
