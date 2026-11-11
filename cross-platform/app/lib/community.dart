import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'community_state.dart';
import 'domain.dart';
import 'legacy_preset_details.dart';
import 'theme.dart';
import 'widgets.dart';

String communityDate(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return '';
  return '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String communitySubmissionStatus(String value) => switch (value) {
  'pending' || 'pending_review' => '待审核',
  'approved' || 'published' => '已发布',
  'rejected' => '审核未通过',
  'unpublished' || 'withdrawn' => '已下架',
  _ => '草稿',
};

Widget communityAction(
  BuildContext context,
  String text,
  VoidCallback? action, {
  bool primary = false,
}) {
  final p = HuePalette.of(context);
  return FilledButton(
    onPressed: action,
    style: FilledButton.styleFrom(
      backgroundColor: primary ? p.action : p.container,
      foregroundColor: primary ? p.onAction : p.ink,
      minimumSize: const Size(0, 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
    ),
    child: Text(text),
  );
}

Future<bool> communityLogin(
  BuildContext context,
  AppState state,
  Future<void> Function()? login,
) async {
  if (CommunityApi(state).owner.isNotEmpty) return true;
  if (login != null) {
    await login();
  } else {
    await context.push<void>('/account');
  }
  return context.mounted && CommunityApi(state).owner.isNotEmpty;
}

class _CommunityFailure extends StatelessWidget {
  const _CommunityFailure(this.message, this.retry);
  final String message;
  final VoidCallback? retry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          style: TextStyle(color: HuePalette.of(context).secondary),
        ),
        if (retry != null)
          Align(
            alignment: Alignment.centerLeft,
            child: communityAction(context, '重试', retry),
          ),
      ],
    ),
  );
}

class _CommunityEmpty extends StatelessWidget {
  const _CommunityEmpty(this.title, this.body);
  final String title, body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: HuePalette.of(context).secondary,
          ),
        ),
      ],
    ),
  );
}

class _CommunityAvatar extends StatelessWidget {
  const _CommunityAvatar(this.person, this.name, this.size);
  final Json person;
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(communityText(person, 'avatarUrl'));
    final fallback = ColoredBox(
      color: HuePalette.of(context).container,
      child: Center(child: HueIcon(HueIconKind.person, size: size * .55)),
    );
    return Semantics(
      label: '$name的头像',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child:
              uri != null &&
                  uri.scheme == 'https' &&
                  uri.host.isNotEmpty &&
                  uri.userInfo.isEmpty
              ? Image.network(
                  uri.toString(),
                  fit: BoxFit.cover,
                  cacheWidth: 160,
                  excludeFromSemantics: true,
                  errorBuilder: (_, _, _) => fallback,
                )
              : fallback,
        ),
      ),
    );
  }
}

/// The preset detail owns its existing footer; discussion is part of its scroll.
class PresetDiscussion extends StatefulWidget {
  const PresetDiscussion({
    super.key,
    required this.state,
    required this.preset,
    this.focusCommentId = '',
    this.onLogin,
  });
  final AppState state;
  final Preset preset;
  final String focusCommentId;
  final Future<void> Function()? onLogin;
  @override
  State<PresetDiscussion> createState() => _PresetDiscussionState();
}

class _PresetDiscussionState extends State<PresetDiscussion> {
  String? discussionId, error;
  bool loading = false, missing = false;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    unawaited(resolve());
  }

  @override
  void didUpdateWidget(PresetDiscussion old) {
    super.didUpdateWidget(old);
    if (old.preset.id != widget.preset.id ||
        old.preset.online != widget.preset.online) {
      unawaited(resolve());
    }
  }

  Future<void> resolve() async {
    final serial = ++generation,
        api = CommunityApi(widget.state),
        owner = CommunityApi(widget.state).owner;
    setState(() {
      loading = true;
      error = null;
      missing = false;
      discussionId = null;
    });
    try {
      var id = widget.preset.online
          ? widget.preset.id
          : communityText(widget.preset.data, 'discussionId');
      if (id.isEmpty) {
        final result = await widget.state.core.call('community.discussion', {
          'id': widget.preset.id,
          'owner': owner,
        });
        if (!mounted || generation != serial || api.owner != owner) return;
        if (result['status'] != 'linked') {
          setState(() {
            missing = true;
            error = communityText(result, 'message');
          });
          return;
        }
        id = communityText(result, 'id');
      }
      communityId(id);
      if (widget.focusCommentId.isNotEmpty) communityId(widget.focusCommentId);
      if (mounted && generation == serial && api.owner == owner) {
        setState(() => discussionId = id);
      }
    } catch (failure) {
      if (mounted && generation == serial) setState(() => error = '$failure');
    } finally {
      if (mounted && generation == serial) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (discussionId != null) {
      return CommunityDiscussionView(
        key: ValueKey(discussionId),
        state: widget.state,
        presetId: discussionId!,
        focusCommentId: widget.focusCommentId,
        onLogin: widget.onLogin,
      );
    }
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (missing && widget.preset.data['source'] != 'online') {
      return const SizedBox();
    }
    return _CommunityFailure(error ?? '暂时无法加载评论。', () => unawaited(resolve()));
  }
}

class CommunityDiscussionView extends StatefulWidget {
  const CommunityDiscussionView({
    super.key,
    required this.state,
    required this.presetId,
    this.focusCommentId = '',
    this.onLogin,
  });
  final AppState state;
  final String presetId, focusCommentId;
  final Future<void> Function()? onLogin;
  @override
  State<CommunityDiscussionView> createState() =>
      _CommunityDiscussionViewState();
}

class _CommunityDiscussionViewState extends State<CommunityDiscussionView> {
  late final api = CommunityApi(widget.state);
  late final model = CommunityDiscussion(
    api,
    widget.presetId,
    focusCommentId: widget.focusCommentId,
  );
  CommunityCommentDraft? draft;
  String owner = '';
  bool writing = false;
  int mutationGeneration = 0;
  final focusKey = GlobalKey();
  bool focused = false;
  @override
  void initState() {
    super.initState();
    owner = api.owner;
    widget.state.addListener(accountChanged);
    unawaited(model.refresh());
  }

  void accountChanged() {
    if (owner == api.owner) return;
    owner = api.owner;
    mutationGeneration++;
    draft?.clear();
    draft = null;
    if (mounted) setState(() => writing = false);
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    model.dispose();
    super.dispose();
  }

  Future<void> compose({Json? root, Json? reply}) async {
    if (writing ||
        !await communityLogin(context, widget.state, widget.onLogin) ||
        !mounted) {
      return;
    }
    final expected = api.owner;
    final parent = root == null ? '' : communityText(root, 'id');
    final target = reply == null ? parent : communityText(reply, 'id');
    if (draft == null ||
        draft!.owner != expected ||
        draft!.parentId != parent ||
        draft!.replyToId != target) {
      draft = CommunityCommentDraft(
        owner: expected,
        presetId: widget.presetId,
        parentId: parent,
        replyToId: target,
        recipient: reply == null ? '' : communityAuthor(reply),
      );
    }
    final current = draft!, input = TextEditingController(text: draft!.text);
    StateSetter? refresh;
    BuildContext? modal;
    String? failure;
    void changed() {
      if (api.owner != expected) {
        current.clear();
        input.clear();
        if (modal?.mounted == true) refresh?.call(() {});
      }
    }

    widget.state.addListener(changed);
    try {
      final sent = await hueDialog<Json>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, update) {
            refresh = update;
            modal = dialog;
            final stale = api.owner != expected;
            return AlertDialog(
              title: Text(
                parent.isEmpty
                    ? '发表评论'
                    : '回复 ${current.recipient.isEmpty ? '这条评论' : current.recipient}',
              ),
              scrollable: true,
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: input,
                    autofocus: true,
                    enabled: !current.sending && !stale,
                    maxLength: 500,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: '内容',
                      counterText: '',
                      hintText: parent.isEmpty
                          ? '分享使用感受'
                          : '回复 ${current.recipient}',
                    ),
                    onChanged: current.edit,
                  ),
                  if (stale || failure != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(stale ? '账号已改变，请关闭后重试。' : failure!),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: current.sending
                      ? null
                      : () => Navigator.pop(dialog),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: current.sending || stale
                      ? null
                      : () async {
                          current.edit(input.text);
                          update(() => failure = null);
                          try {
                            final request = current.send(api);
                            update(() {});
                            final result = await request;
                            if (dialog.mounted && api.owner == expected) {
                              Navigator.pop(dialog, result);
                            }
                          } catch (error) {
                            if (dialog.mounted) {
                              update(() => failure = '$error');
                            }
                          }
                        },
                  child: Text(current.sending ? '发送中…' : '发送'),
                ),
              ],
            );
          },
        ),
      );
      if (sent != null && mounted && api.owner == expected) {
        draft = null;
        final comment = sent['comment'];
        report(
          context,
          comment is Map && comment['status'] == 'pending'
              ? '评论已提交，审核后展示'
              : '评论已发送',
        );
        await model.refresh();
      }
    } finally {
      widget.state.removeListener(changed);
      input.dispose();
    }
  }

  Future<void> remove(Json row) async {
    final expected = api.owner;
    final confirmed = await hueDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('删除这条评论？'),
        content: const Text('删除后其他用户将无法查看这条内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || expected != api.owner) return;
    await mutate(
      () => api.write(
        '/community/comments/${communityId(communityText(row, 'id'))}',
        {},
        expected,
        method: 'DELETE',
      ),
    );
  }

  Future<void> flag(Json row) async {
    if (!await communityLogin(context, widget.state, widget.onLogin) ||
        !mounted) {
      return;
    }
    final expected = api.owner;
    final reason = await hueDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('举报原因'),
        children: [
          for (final text in ['广告或垃圾信息', '辱骂或骚扰', '涉嫌侵权', '其他不当内容'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, text),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(text),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (reason == null || !mounted || expected != api.owner) return;
    await mutate(
      () => api.write(
        '/community/comments/${communityId(communityText(row, 'id'))}/report',
        {'reason': reason, 'idempotencyKey': communityKey()},
        expected,
      ),
      notice: '举报已收到，管理员会进行核查。',
    );
  }

  Future<void> mutate(Future<Json> Function() action, {String? notice}) async {
    if (writing) return;
    final expected = api.owner, serial = ++mutationGeneration;
    setState(() => writing = true);
    try {
      await action();
      if (!mounted || serial != mutationGeneration || api.owner != expected) {
        return;
      }
      if (notice != null) {
        report(context, notice);
      } else {
        await model.refresh();
      }
    } catch (failure) {
      if (mounted && failure is! CommunityStale) report(context, failure);
    } finally {
      if (mounted && serial == mutationGeneration) {
        setState(() => writing = false);
      }
    }
  }

  Widget comment(Json value, Json? root) {
    final p = HuePalette.of(context), name = communityAuthor(value);
    final person = value['author'] is Map
        ? object(value['author'])
        : <String, dynamic>{};
    final own = api.owner.isNotEmpty && person['id'] == api.owner;
    final id = communityText(value, 'id');
    final focus =
        !focused &&
        widget.focusCommentId.isNotEmpty &&
        id == widget.focusCommentId;
    if (focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && focusKey.currentContext != null && !focused) {
          focused = true;
          unawaited(
            Scrollable.ensureVisible(
              focusKey.currentContext!,
              duration: const Duration(milliseconds: 250),
              alignment: .2,
            ),
          );
        }
      });
    }
    return Container(
      key: focus ? focusKey : null,
      padding: EdgeInsets.fromLTRB(root == null ? 0 : 20, 16, 0, 12),
      decoration: BoxDecoration(
        color: focus ? p.primaryContainer : null,
        border: Border(bottom: BorderSide(color: p.outline, width: .5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CommunityAvatar(person, name, root == null ? 36 : 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: name,
                        children: root == null
                            ? []
                            : [
                                TextSpan(
                                  text: ' 回复 ',
                                  style: TextStyle(
                                    color: p.secondary,
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                                TextSpan(text: communityRecipient(value, root)),
                              ],
                      ),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      communityDate(communityText(value, 'createdAt')),
                      style: TextStyle(fontSize: 12, color: p.secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: SelectableText(
              value['status'] == 'deleted'
                  ? '评论已删除'
                  : communityText(value, 'text'),
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ),
          if (value['status'] != 'deleted')
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                communityAction(
                  context,
                  '回复',
                  writing
                      ? null
                      : () => unawaited(
                          compose(root: root ?? value, reply: value),
                        ),
                ),
                communityAction(
                  context,
                  own ? '删除' : '举报',
                  writing
                      ? null
                      : () => unawaited(own ? remove(value) : flag(value)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: const Text(
                  '评论',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            communityAction(
              context,
              '发表评论',
              writing ? null : () => unawaited(compose()),
            ),
          ],
        ),
        if (model.busy) const LinearProgressIndicator(minHeight: 2),
        if (model.error != null)
          _CommunityFailure(
            model.error!,
            model.busy ? null : () => unawaited(model.refresh()),
          ),
        if (model.loaded &&
            model.comments.isEmpty &&
            !model.busy &&
            model.error == null)
          const _CommunityEmpty('还没有评论', '说说你的使用感受，交流拍摄场景、相机适配和预设效果。'),
        for (final row in model.comments) ...[
          comment(row, null),
          for (final reply in communityReplies(row)) comment(reply, row),
          if ((row['replyCount'] is num ? row['replyCount'] as num : 0) >
              communityReplies(row).length)
            Align(
              alignment: Alignment.centerLeft,
              child: communityAction(
                context,
                '查看更多回复',
                model.busy ? null : () => unawaited(model.loadReplies(row)),
              ),
            ),
        ],
        if (model.hasMore)
          communityAction(
            context,
            '更多评论',
            model.busy ? null : () => unawaited(model.load(append: true)),
          ),
        if (model.showingFocusedThread)
          communityAction(
            context,
            '查看全部评论',
            model.busy
                ? null
                : () {
                    model.focusCommentId = '';
                    unawaited(model.refresh());
                  },
          ),
      ],
    ),
  );
}

class CommunityCollectionPage extends StatefulWidget {
  const CommunityCollectionPage({
    super.key,
    required this.state,
    required this.kind,
    required this.openSubmission,
    this.onLogin,
  });
  final AppState state;
  final CommunityCollectionKind kind;
  final Future<void> Function(BuildContext context, String? id) openSubmission;
  final Future<void> Function()? onLogin;
  @override
  State<CommunityCollectionPage> createState() =>
      _CommunityCollectionPageState();
}

class _CommunityCollectionPageState extends State<CommunityCollectionPage>
    with WidgetsBindingObserver {
  late final api = CommunityApi(widget.state);
  late final model = CommunityCollection(api, widget.kind);
  int autoReadGeneration = -1;
  bool opening = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(model.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() => autoReadGeneration = -1);
    }
  }

  void scheduleReads() {
    if (widget.kind != CommunityCollectionKind.messages ||
        !model.loaded ||
        model.busy ||
        model.generation == autoReadGeneration ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    autoReadGeneration = model.generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent != false) {
        unawaited(model.markDisplayedRead());
      } else {
        autoReadGeneration = -1;
      }
    });
  }

  Future<void> edit(String? id) async {
    if (!await communityLogin(context, widget.state, widget.onLogin) ||
        !mounted) {
      return;
    }
    await widget.openSubmission(context, id);
    if (mounted) await model.load(targetPage: model.page == 0 ? 1 : model.page);
  }

  Future<void> openMessage(Json item) async {
    if (opening) return;
    final expected = api.owner;
    setState(() => opening = true);
    try {
      await model.acknowledgeMessage(item);
      if (!mounted || expected != api.owner) return;
      if (item['available'] == false) {
        report(context, '这条消息关联的内容已删除、隐藏或下架。');
        return;
      }
      final submission = communityText(item, 'submissionId');
      if (communityText(item, 'type') != 'reply' && submission.isNotEmpty) {
        await edit(communityId(submission));
      } else {
        final selected = communityId(communityText(item, 'presetId'));
        final result = await api.read('/community/presets/$selected');
        if (!mounted || expected != api.owner) return;
        final preset = Preset(object(result['preset']), online: true);
        final focus = communityText(item, 'commentId');
        if (focus.isNotEmpty) communityId(focus);
        await hueRootPage<void>(
          context,
          MaterialPageRoute(
            builder: (_) => LegacyPresetDetails(
              state: widget.state,
              preset: preset,
              focusCommentId: focus,
              onShare: () {},
              onCategory: () {},
              onRemove: () {},
              onDownload: () async {
                try {
                  await widget.state.core.call('online.download', {
                    'preset': preset.data,
                    'owner': expected,
                  });
                  if (api.owner != expected) return;
                  await widget.state.refreshLibrary();
                  if (mounted) report(context, '预设已下载');
                } catch (failure) {
                  if (mounted) report(context, failure);
                }
              },
            ),
          ),
        );
      }
    } catch (failure) {
      if (mounted && failure is! CommunityStale) report(context, failure);
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Widget message(Json value) {
    final p = HuePalette.of(context), type = communityText(value, 'type');
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: value['read'] == true ? Colors.transparent : p.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            type == 'reply'
                ? '${communityAuthor(value)} 回复了你'
                : type.contains('reject')
                ? '投稿审核未通过'
                : '投稿审核通知',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              communityText(value, 'text'),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Text(
            communityDate(communityText(value, 'createdAt')),
            style: TextStyle(fontSize: 12, color: p.secondary),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: communityAction(
              context,
              value['available'] == false ? '内容已不可用' : '查看详情',
              opening ? null : () => unawaited(openMessage(value)),
            ),
          ),
        ],
      ),
    );
  }

  Widget submission(Json value) {
    final p = HuePalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            communityText(value, 'name'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${communitySubmissionStatus(communityText(value, 'status'))} · ${communityDate(communityText(value, 'updatedAt'))}',
              style: TextStyle(fontSize: 13, color: p.secondary),
            ),
          ),
          if (communityText(value, 'reason').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '审核说明：${communityText(value, 'reason')}',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: communityAction(
              context,
              '查看与编辑',
              model.busy
                  ? null
                  : () => unawaited(
                      edit(communityId(communityText(value, 'id'))),
                    ),
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: hueviaTheme(Theme.of(context).brightness, home: false),
    child: Builder(
      builder: (context) => Scaffold(
        appBar: HueHeader(
          title: widget.kind == CommunityCollectionKind.messages
              ? '消息'
              : '我的投稿',
          back: true,
          actions: [
            ListenableBuilder(
              listenable: model,
              builder: (context, _) => HueIconButton(
                kind: HueIconKind.refresh,
                label: '刷新',
                onPressed: model.busy ? null : () => unawaited(model.refresh()),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: ListenableBuilder(
            listenable: model,
            builder: (context, _) {
              scheduleReads();
              if (api.owner.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _CommunityEmpty('登录后查看', '投稿和消息只对当前账号显示。'),
                      communityAction(
                        context,
                        '登录账号',
                        () => unawaited(
                          communityLogin(context, widget.state, widget.onLogin),
                        ),
                        primary: true,
                      ),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: model.refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (widget.kind == CommunityCollectionKind.submissions)
                      communityAction(
                        context,
                        '发布新预设',
                        model.busy ? null : () => unawaited(edit(null)),
                        primary: true,
                      )
                    else
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        children: [
                          Text(
                            model.loaded
                                ? (model.unread > 0
                                      ? '${model.unread} 条未读'
                                      : '没有未读消息')
                                : (model.busy ? '正在加载消息' : '消息'),
                            style: TextStyle(
                              color: HuePalette.of(context).secondary,
                            ),
                          ),
                          communityAction(
                            context,
                            '全部已读',
                            model.busy
                                ? null
                                : () => unawaited(model.markAllRead()),
                          ),
                        ],
                      ),
                    if (model.busy || opening)
                      const LinearProgressIndicator(minHeight: 2),
                    if (model.error != null)
                      _CommunityFailure(
                        model.error!,
                        model.busy ? null : () => unawaited(model.refresh()),
                      ),
                    if (model.loaded &&
                        model.items.isEmpty &&
                        !model.busy &&
                        model.error == null)
                      widget.kind == CommunityCollectionKind.messages
                          ? const _CommunityEmpty(
                              '消息会保存在这里',
                              '有人回复你的评论、或投稿审核完成时，你会在这里收到消息。',
                            )
                          : const _CommunityEmpty(
                              '把喜欢的色彩分享出来',
                              '投稿会先交给管理员审核，审核结果会发送到消息列表。',
                            ),
                    for (final item in model.items)
                      widget.kind == CommunityCollectionKind.messages
                          ? message(item)
                          : submission(item),
                    if (model.hasMore)
                      communityAction(
                        context,
                        widget.kind == CommunityCollectionKind.messages
                            ? '更多消息'
                            : '下一页',
                        model.busy
                            ? null
                            : () => unawaited(
                                model.load(
                                  append:
                                      widget.kind ==
                                      CommunityCollectionKind.messages,
                                  targetPage:
                                      widget.kind ==
                                          CommunityCollectionKind.submissions
                                      ? model.page + 1
                                      : null,
                                ),
                              ),
                      ),
                    if (widget.kind == CommunityCollectionKind.submissions &&
                        model.page > 1)
                      communityAction(
                        context,
                        '上一页',
                        model.busy
                            ? null
                            : () => unawaited(
                                model.load(targetPage: model.page - 1),
                              ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
