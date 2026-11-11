import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'community_state.dart';
import 'domain.dart';
import 'theme.dart';
import 'widgets.dart';

String profileOwner(AppState state) => CommunityApi(state).owner;
String profileText(Json value, String key) =>
    value[key] is String ? value[key] as String : '';
Json profileUser(AppState state) =>
    state.session['user'] is Map ? object(state.session['user']) : {};
String profileDate(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return '暂无记录';
  return '${date.year}年${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class AccountProfileModel extends ChangeNotifier {
  AccountProfileModel(this.state) : owner = profileOwner(state) {
    communityId(owner);
    state.addListener(_stateChanged);
  }
  final AppState state;
  final String owner;
  Json? draft;
  bool busy = false, stale = false, disposed = false;
  String? error;
  int _generation = 0;
  bool _accepts(int token) =>
      !disposed &&
      !stale &&
      token == _generation &&
      profileOwner(state) == owner;
  void _notify() {
    if (!disposed) notifyListeners();
  }

  void _stateChanged() {
    if (profileOwner(state) != owner) {
      stale = true;
      _generation++;
      error = '账号已改变，请重新打开账号资料。';
      unawaited(discard());
    } else if (draft != null &&
        profileText(profileUser(state), 'updatedAt') != draft!['updatedAt']) {
      unawaited(discard());
    }
    _notify();
  }

  Future<void> _discard(Json value) async {
    await _evictPreview(value);
    try {
      await state.core.call('account.avatarDiscard', {
        'owner': owner,
        'receipt': value['receipt'],
      });
    } catch (_) {}
  }

  Future<void> _evictPreview(Json value) async {
    final path = value['path'];
    if (path is! String) return;
    try {
      await ResizeImage.resizeIfNeeded(
        512,
        null,
        FileImage(File(path)),
      ).evict();
    } catch (_) {}
  }

  Future<void> discard() async {
    final previous = draft;
    draft = null;
    _notify();
    if (previous != null) await _discard(previous);
  }

  Future<bool> pick() async {
    if (busy || stale || disposed) return false;
    final token = _generation,
        updatedAt = profileText(profileUser(state), 'updatedAt');
    busy = true;
    error = null;
    _notify();
    try {
      await discard();
      if (!_accepts(token)) return false;
      final result = await state.core.pickAvatar(
        owner: owner,
        updatedAt: updatedAt,
      );
      if (result == null) return false;
      if (!_accepts(token) ||
          profileText(profileUser(state), 'updatedAt') != updatedAt) {
        await _discard(result);
        return false;
      }
      draft = result;
      return true;
    } catch (failure) {
      if (_accepts(token)) error = '$failure';
      return false;
    } finally {
      if (_accepts(token)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<bool> _run(String operation, Json payload) async {
    if (busy || stale || disposed) return false;
    final token = _generation;
    busy = true;
    error = null;
    _notify();
    try {
      await state.core.call(operation, {'owner': owner, ...payload});
      await state.refreshSession();
      return _accepts(token);
    } catch (failure) {
      try {
        await state.refreshSession();
      } catch (_) {}
      if (_accepts(token)) error = '$failure';
      return false;
    } finally {
      if (_accepts(token)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<bool> commit() async {
    final reviewed = draft;
    if (reviewed == null ||
        reviewed['updatedAt'] != profileText(profileUser(state), 'updatedAt')) {
      return false;
    }
    final result = await _run('account.avatarCommit', {
      'receipt': reviewed['receipt'],
      'sha256': reviewed['sha256'],
    });
    if (result) {
      draft = null;
      await _evictPreview(reviewed);
      _notify();
    }
    return result;
  }

  Future<bool> reset() => _run('account.avatarReset', {
    'updatedAt': profileText(profileUser(state), 'updatedAt'),
  });
  Future<bool> refresh() => _run('account.refresh', {});
  Future<void> logoutWith(Future<void> Function(String owner) action) async {
    if (busy || stale || disposed) return;
    busy = true;
    _notify();
    try {
      await action(owner);
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    final previous = draft;
    draft = null;
    disposed = true;
    _generation++;
    state.removeListener(_stateChanged);
    if (previous != null) unawaited(_discard(previous));
    super.dispose();
  }
}

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.user,
    this.size = 72,
    this.preview,
  });
  final Json user;
  final double size;
  final String? preview;
  @override
  Widget build(BuildContext context) {
    final palette = HuePalette.of(context);
    final fallback = ColoredBox(
      color: palette.container,
      child: Center(
        child: HueIcon(
          HueIconKind.person,
          size: size * .55,
          color: palette.secondary,
        ),
      ),
    );
    final uri = Uri.tryParse(profileText(user, 'avatarUrl'));
    return SizedBox.square(
      dimension: size,
      child: ClipOval(
        child: preview != null
            ? Image.file(
                File(preview!),
                fit: BoxFit.cover,
                cacheWidth: 512,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => fallback,
              )
            : uri != null &&
                  uri.scheme == 'https' &&
                  uri.host.isNotEmpty &&
                  uri.userInfo.isEmpty &&
                  !uri.hasFragment
            ? Image.network(
                uri.toString(),
                fit: BoxFit.cover,
                cacheWidth: 512,
                excludeFromSemantics: true,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}

class AccountProfileView extends StatelessWidget {
  const AccountProfileView({
    super.key,
    required this.state,
    required this.onLogout,
    required this.onPrivacy,
  });
  final AppState state;
  final Future<void> Function(String owner) onLogout;
  final Future<void> Function() onPrivacy;
  @override
  Widget build(BuildContext context) => Theme(
    data: hueviaTheme(Theme.of(context).brightness, home: false),
    child: _AccountProfileBody(
      key: ObjectKey(state),
      state: state,
      onLogout: onLogout,
      onPrivacy: onPrivacy,
    ),
  );
}

class _AccountProfileBody extends StatefulWidget {
  const _AccountProfileBody({
    super.key,
    required this.state,
    required this.onLogout,
    required this.onPrivacy,
  });
  final AppState state;
  final Future<void> Function(String owner) onLogout;
  final Future<void> Function() onPrivacy;
  @override
  State<_AccountProfileBody> createState() => _AccountProfileViewState();
}

class _AccountProfileViewState extends State<_AccountProfileBody> {
  late final model = AccountProfileModel(widget.state);
  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  bool get ready => mounted && !model.busy && !model.stale;
  Future<void> avatarActions() async {
    if (!ready) return;
    final qq = profileText(profileUser(widget.state), 'provider') == 'qq';
    final choice = await hueDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('修改头像'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const HueIcon(HueIconKind.album),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(dialog, 'pick'),
            ),
            ListTile(
              leading: const HueIcon(HueIconKind.refresh),
              title: Text(qq ? '恢复 QQ 头像' : '恢复默认头像'),
              onTap: () => Navigator.pop(dialog, 'reset'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || !ready) return;
    if (choice == 'pick') {
      await pickAvatar();
    } else if (choice == 'reset') {
      final confirmed = await hueDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(qq ? '恢复 QQ 头像？' : '恢复默认头像？'),
          content: Text(qq ? '将使用最近一次 QQ 登录时验证的头像。' : '将使用统一的默认用户头像。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('恢复'),
            ),
          ],
        ),
      );
      if (confirmed == true && ready && await model.reset() && mounted) {
        report(context, '头像已恢复');
      }
    }
  }

  Future<void> pickAvatar() async {
    if (!await model.pick() || !mounted || model.draft == null) return;
    final reviewed = Map<String, dynamic>.from(model.draft!);
    await hueDialog<void>(
      context: context,
      builder: (dialog) => ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          final valid =
              !model.stale && model.draft?['receipt'] == reviewed['receipt'];
          return AlertDialog(
            title: const Text('确认新头像'),
            scrollable: true,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (valid)
                  Semantics(
                    label: '新头像预览',
                    image: true,
                    child: AccountAvatar(
                      user: const {},
                      size: 160,
                      preview: reviewed['path'] as String,
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  valid ? '照片已居中裁为正方形，确认后用于账号与社区展示。' : '头像预览已失效，请重新选择。',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
                if (model.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      model.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (model.busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: model.busy ? null : () => Navigator.pop(dialog),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: !valid || model.busy
                    ? null
                    : () async {
                        if (await model.commit() && dialog.mounted) {
                          Navigator.pop(dialog);
                          if (mounted) report(this.context, '头像已保存');
                        }
                      },
                child: const Text('保存头像'),
              ),
            ],
          );
        },
      ),
    );
    await model.discard();
  }

  Future<void> logout() async {
    if (!ready) return;
    final confirmed = await hueDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('退出当前账号？'),
        content: const Text('手机中的预设、照片和拍摄项目会保留，您可以继续以游客使用。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed == true && ready) await model.logoutWith(widget.onLogout);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (context, _) {
      final p = HuePalette.of(context), user = profileUser(widget.state);
      final name = profileText(user, 'nickname').isEmpty
          ? profileText(user, 'username')
          : profileText(user, 'nickname');
      Widget action(
        String title,
        VoidCallback? callback, {
        bool danger = false,
      }) => FilledButton(
        onPressed: callback,
        style: FilledButton.styleFrom(
          backgroundColor: p.container,
          foregroundColor: danger ? Theme.of(context).colorScheme.error : p.ink,
          minimumSize: const Size.fromHeight(52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15),
        ),
        child: Text(title),
      );
      Widget detail(String title, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: TextStyle(fontSize: 12, color: p.secondary)),
            const SizedBox(height: 4),
            SelectableText(value, style: TextStyle(fontSize: 15, color: p.ink)),
          ],
        ),
      );
      return Scaffold(
        appBar: const HueHeader(title: '我的账号', back: true),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (model.stale)
                  const Text('账号已改变，请重新打开账号资料。')
                else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 20,
                    ),
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Semantics(
                              button: true,
                              label: '修改头像',
                              child: InkWell(
                                onTap: ready ? avatarActions : null,
                                customBorder: const CircleBorder(),
                                child: AccountAvatar(user: user),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name.isEmpty ? '用户' : name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    profileText(user, 'provider') == 'qq'
                                        ? 'QQ 账号'
                                        : profileText(user, 'username').isEmpty
                                        ? '账号已登录'
                                        : '@${profileText(user, 'username')}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: p.secondary,
                                    ),
                                  ),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      minimumSize: const Size(0, 48),
                                      padding: const EdgeInsets.only(right: 12),
                                    ),
                                    onPressed: ready ? avatarActions : null,
                                    child: const Text(
                                      '修改头像',
                                      style: TextStyle(fontSize: 15),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.state.session['verified'] == true
                              ? '已登录 · 状态已验证'
                              : '已保存登录信息 · 待联网核验',
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.state.session['verified'] == true
                                ? Color(p.dark ? 0xff9ac8ae : 0xff42735b)
                                : p.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (profileText(user, 'username').isNotEmpty)
                          detail('用户名', profileText(user, 'username')),
                        detail(
                          '登录方式',
                          profileText(user, 'provider') == 'qq' ? 'QQ' : '账号密码',
                        ),
                        detail(
                          '注册时间',
                          profileDate(profileText(user, 'createdAt')),
                        ),
                        detail(
                          '最近登录',
                          profileDate(profileText(user, 'lastLoginAt')),
                        ),
                      ],
                    ),
                  ),
                  if (model.error != null ||
                      profileText(
                        widget.state.session,
                        'storageWarning',
                      ).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                      child: Text(
                        model.error ??
                            profileText(widget.state.session, 'storageWarning'),
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  action('刷新账号资料', ready ? () => model.refresh() : null),
                  const SizedBox(height: 10),
                  action('退出登录', ready ? logout : null, danger: true),
                  if (model.busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
                    child: Text(
                      '账号退出后，手机中的预设、照片和拍摄项目仍会保留。',
                      style: TextStyle(fontSize: 12, color: p.secondary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: widget.onPrivacy,
                    child: const Text(
                      'QQ 登录与隐私说明',
                      style: TextStyle(fontSize: 13),
                    ),
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
