import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'community.dart';
import 'community_state.dart';
import 'domain.dart';
import 'theme.dart';
import 'widgets.dart';

class _SubmissionLength extends TextInputFormatter {
  const _SubmissionLength(this.maximum);
  final int maximum;
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length <= maximum) return newValue;
    var end = maximum;
    final last = newValue.text.codeUnitAt(end - 1);
    if (last >= 0xd800 && last <= 0xdbff) end--;
    return newValue.copyWith(
      text: newValue.text.substring(0, end),
      selection: TextSelection(
        baseOffset: newValue.selection.baseOffset.clamp(0, end),
        extentOffset: newValue.selection.extentOffset.clamp(0, end),
      ),
      composing: TextRange.empty,
    );
  }
}

class SubmissionModel extends ChangeNotifier {
  SubmissionModel(this.state, {String? id})
    : owner = CommunityApi(state).owner,
      slot = id ?? 'new' {
    communityId(owner);
    if (slot != 'new') communityId(slot);
    state.addListener(_accountChanged);
  }
  final AppState state;
  final String owner;
  String slot;
  Json draft = {};
  String? error, warning;
  bool busy = false, loaded = false, stale = false, disposed = false;
  int _editRevision = 0;
  int documentRevision = 0;
  Timer? _timer;
  Future<void> _commits = Future.value();
  bool get uncertain =>
      draft['savePending'] == true || draft['submitPending'] == true;
  bool get locked => ['pending', 'pending_review'].contains(draft['status']);
  bool get editable => loaded && !busy && !stale && !uncertain && !locked;
  void _notify() {
    if (!disposed) notifyListeners();
  }

  void _check() {
    if (stale || CommunityApi(state).owner != owner) {
      throw const CommunityStale();
    }
  }

  void _accountChanged() {
    if (CommunityApi(state).owner == owner || stale) return;
    stale = true;
    _timer?.cancel();
    draft = {};
    documentRevision++;
    error = '账号已改变，请关闭此页后重新打开。';
    _notify();
  }

  Future<Json> _call(String operation, [Json payload = const {}]) async {
    _check();
    final result = await state.core.call(operation, {
      'owner': owner,
      'slot': slot,
      ...payload,
    });
    _check();
    return result;
  }

  void _accept(Json result, {bool syncFields = true}) {
    slot = communityText(result, 'slot');
    if (slot != 'new') communityId(slot);
    draft = object(result['draft']);
    warning = communityText(result, 'warning');
    loaded = true;
    if (syncFields) documentRevision++;
  }

  Future<void> load() async {
    if (busy || stale) return;
    busy = true;
    error = null;
    _notify();
    try {
      _accept(await _call('submission.load'));
    } catch (failure) {
      if (!stale) error = '$failure';
    } finally {
      busy = false;
      _notify();
    }
  }

  void edit(Json patch) {
    if (!editable) return;
    draft = {...draft, ...patch};
    _editRevision++;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), () {
      unawaited(flush().catchError((Object _) {}));
    });
    _notify();
  }

  Future<void> flush() {
    _timer?.cancel();
    if (!loaded || stale || uncertain || locked) return _commits;
    final snapshot = Map<String, dynamic>.from(draft), revision = _editRevision;
    final next = _commits.then((_) async {
      final result = await _call('submission.persist', {'draft': snapshot});
      if (revision == _editRevision) _accept(result, syncFields: false);
      error = null;
    });
    _commits = next.then<void>(
      (_) {
        _notify();
      },
      onError: (Object failure, StackTrace _) {
        if (!stale) error = '本机草稿暂未保存：$failure';
        _notify();
      },
    );
    return next;
  }

  Future<bool> _run(Future<void> Function() action) async {
    if (busy || stale || disposed) return false;
    busy = true;
    error = null;
    _notify();
    try {
      await flush();
      await action();
      return true;
    } catch (failure) {
      if (!stale) {
        error = '$failure';
        // Native checkpoints may have advanced even if the HTTP response was lost.
        try {
          _accept(await _call('submission.load'));
        } catch (_) {}
      }
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> pick(String kind) => _run(() async {
    final picked = await state.core.pickSubmission(kind: kind, owner: owner);
    _check();
    if (picked == null) return;
    _accept(
      await _call('submission.attach', {
        'kind': kind,
        'path': picked['path'],
        'name': picked['name'],
      }),
    );
  });
  Future<bool> removePreview() => _run(() async {
    _accept(
      await _call('submission.attach', {'kind': 'preview', 'remove': true}),
    );
  });
  Future<bool> save({required bool submit}) => _run(() async {
    _accept(await _call('submission.save', {'draft': draft, 'submit': submit}));
  });
  Future<bool> reloadServer() => _run(() async {
    _accept(await _call('submission.reload', {'discardLocal': true}));
  });
  @override
  void dispose() {
    _timer?.cancel();
    // Finish an already authorized local draft write when leaving the editor.
    if (!stale && loaded && editable) {
      unawaited(flush().catchError((Object _) {}));
    }
    disposed = true;
    state.removeListener(_accountChanged);
    super.dispose();
  }
}

Future<void> openSubmissionEditor(
  BuildContext context,
  AppState state,
  String? id,
) async {
  if (!await communityLogin(context, state, null) || !context.mounted) return;
  await hueRootPage<void>(
    context,
    MaterialPageRoute(
      builder: (_) => SubmissionEditor(state: state, id: id),
    ),
  );
}

class SubmissionEditor extends StatefulWidget {
  const SubmissionEditor({super.key, required this.state, this.id});
  final AppState state;
  final String? id;
  @override
  State<SubmissionEditor> createState() => _SubmissionEditorState();
}

class _SubmissionEditorState extends State<SubmissionEditor> {
  late final model = SubmissionModel(widget.state, id: widget.id);
  final controllers = <String, TextEditingController>{
    for (final key in ['name', 'description', 'category', 'models'])
      key: TextEditingController(),
  };
  bool syncing = false;
  int documentRevision = -1;
  @override
  void initState() {
    super.initState();
    model.addListener(sync);
    unawaited(model.load());
  }

  void sync() {
    if (documentRevision == model.documentRevision) return;
    documentRevision = model.documentRevision;
    syncing = true;
    final values = {
      for (final key in ['name', 'description', 'category'])
        key: communityText(model.draft, key),
      'models': model.draft['compatibleModels'] is List
          ? (model.draft['compatibleModels'] as List).whereType<String>().join(
              '，',
            )
          : '',
    };
    for (final entry in controllers.entries) {
      final value = values[entry.key]!;
      if (entry.value.text != value) {
        entry.value.value = TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length),
        );
      }
    }
    syncing = false;
  }

  @override
  void dispose() {
    model.removeListener(sync);
    model.dispose();
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save(bool submit) async {
    if (await model.save(submit: submit) && mounted) {
      report(context, submit ? '投稿已提交审核' : '投稿草稿已保存');
    }
  }

  String fileLabel(String prefix) {
    final local = communityText(model.draft, '${prefix}Name');
    if (local.isNotEmpty) return local;
    final asset = model.draft[prefix];
    return asset is Map ? communityText(object(asset), 'originalName') : '';
  }

  Future<void> reload() async {
    final accepted = await hueDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('读取服务器版本'),
        content: const Text('本机尚未保存到服务器的修改会被替换。是否继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('读取'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) await model.reloadServer();
  }

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context);
    return AnimatedBuilder(
      animation: model,
      builder: (context, _) {
        Widget field(
          String key,
          String label,
          String hint,
          int limit, {
          bool multiline = false,
        }) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextField(
              key: ValueKey('submission-$key'),
              controller: controllers[key],
              enabled: model.editable,
              maxLines: multiline ? null : 1,
              style: const TextStyle(fontSize: 16),
              inputFormatters: [_SubmissionLength(limit)],
              decoration: InputDecoration(
                hintText: hint,
                constraints: const BoxConstraints(minHeight: 52),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                filled: true,
                fillColor: p.container,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                if (!syncing) {
                  model.edit(
                    key == 'models'
                        ? {
                            'compatibleModels': value
                                .split(RegExp('[,，]'))
                                .map((v) => v.trim())
                                .where((v) => v.isNotEmpty)
                                .toList(),
                          }
                        : {key: value},
                  );
                }
              },
            ),
          ],
        );
        final reason = communityText(model.draft, 'reviewReason').isEmpty
            ? communityText(model.draft, 'reason')
            : communityText(model.draft, 'reviewReason');
        return Scaffold(
          appBar: HueHeader(
            title: widget.id == null ? '发布预设' : '编辑投稿',
            back: true,
          ),
          body: SafeArea(
            top: false,
            child: !model.loaded && model.busy
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      24 + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (model.error != null) ...[
                          Text(model.error!, style: TextStyle(color: p.ink)),
                          const SizedBox(height: 12),
                          if (model.loaded &&
                              !model.stale &&
                              !model.uncertain &&
                              communityText(model.draft, 'id').isNotEmpty)
                            communityAction(
                              context,
                              '读取服务器版本',
                              model.busy ? null : reload,
                            ),
                          if (!model.loaded && !model.stale)
                            communityAction(
                              context,
                              '重试',
                              model.busy ? null : model.load,
                            ),
                        ],
                        if (model.warning?.isNotEmpty == true) ...[
                          Text(model.warning!),
                          const SizedBox(height: 12),
                        ],
                        if (model.loaded) ...[
                          Text(
                            '状态：${communitySubmissionStatus(communityText(model.draft, 'status'))}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          if (reason.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: SelectableText(reason),
                            ),
                          if (model.locked)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('投稿正在审核，暂时不能修改。'),
                            ),
                          if (model.uncertain)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text('上次操作的结果尚未确认。草稿已保留，请重试以恢复结果。'),
                            ),
                          const SizedBox(height: 20),
                          field('name', '预设名称', '让大家认识这份色彩', 160),
                          field(
                            'description',
                            '简介',
                            '适合什么场景、有什么特点',
                            2000,
                            multiline: true,
                          ),
                          field('category', '分类', '如人像、风景、胶片', 24),
                          field('models', '适用相机（选填）', '多个机型用逗号分隔', 256),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              communityAction(
                                context,
                                fileLabel('file').isEmpty
                                    ? '选择 NCP 文件'
                                    : '重新选择 NCP 文件',
                                model.editable ? () => model.pick('ncp') : null,
                              ),
                              communityAction(
                                context,
                                fileLabel('preview').isEmpty
                                    ? '添加效果图（可选）'
                                    : '更换效果图',
                                model.editable
                                    ? () => model.pick('preview')
                                    : null,
                              ),
                              if (communityText(
                                    model.draft,
                                    'previewPath',
                                  ).isNotEmpty ||
                                  communityText(
                                    model.draft,
                                    'previewAssetId',
                                  ).isNotEmpty)
                                communityAction(
                                  context,
                                  '移除效果图',
                                  model.editable ? model.removePreview : null,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'NCP：${fileLabel('file').isEmpty ? '未选择' : fileLabel('file')}',
                          ),
                          if (fileLabel('preview').isNotEmpty)
                            Text('效果图：${fileLabel('preview')}'),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              '仅支持 NCP 0100（不超过 1 MB）。效果图不超过 4 MB；没有效果图时展示模板示意。',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text(
                              '我确认拥有预设和效果图的公开分享权利。',
                              style: TextStyle(fontSize: 14),
                            ),
                            value: model.draft['rightsConfirmed'] == true,
                            onChanged: model.editable
                                ? (value) => model.edit({
                                    'rightsConfirmed': value == true,
                                  })
                                : null,
                          ),
                          const SizedBox(height: 16),
                          if (!model.locked || model.uncertain)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (model.draft['submitPending'] != true &&
                                    !(model.draft['savePending'] == true &&
                                        model.draft['saveIntentSubmit'] ==
                                            true))
                                  communityAction(
                                    context,
                                    model.uncertain ? '重试保存' : '保存草稿',
                                    model.busy || model.stale
                                        ? null
                                        : () => save(false),
                                  ),
                                if (!model.uncertain ||
                                    model.draft['submitPending'] == true ||
                                    model.draft['saveIntentSubmit'] == true)
                                  communityAction(
                                    context,
                                    model.uncertain ? '重试提交' : '提交审核',
                                    model.busy || model.stale
                                        ? null
                                        : () => save(true),
                                    primary: true,
                                  ),
                              ],
                            ),
                          if (model.busy)
                            const Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: LinearProgressIndicator(),
                            ),
                        ],
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }
}
