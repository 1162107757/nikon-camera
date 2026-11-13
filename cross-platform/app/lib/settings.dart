import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'domain.dart';
import 'theme.dart';
import 'appearance.dart';
import 'legacy_dialog.dart';
import 'camera.dart';
import 'widgets.dart';
import 'help.dart';
import 'preview_templates.dart';
import 'community.dart';
import 'community_state.dart';
import 'submission_editor.dart';
import 'community_activity.dart';
import 'updates.dart';
import 'legacy_migration.dart';
import 'connection_protection.dart';
import 'camera_downloads.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});
  final AppState state;
  Future<void> appearance(BuildContext context) async {
    final selected = await hueChoice<ThemeMode>(
      context: context,
      title: '外观',
      selected: appearanceMode.value,
      choices: const [
        (ThemeMode.system, '跟随系统'),
        (ThemeMode.light, '浅色'),
        (ThemeMode.dark, '深色'),
      ],
    );
    if (selected != null) await setAppearance(state.core.root, selected);
  }

  void explain(BuildContext context, String title, String text) {
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = HuePalette.of(context), user = state.session['user'];
    final pendingLogout = state.session['logoutPending'] == true;
    final identity = user is Map ? object(user) : <String, dynamic>{};
    final nickname = identity['nickname'] as String? ?? '';
    final username = identity['username'] as String? ?? '';
    final accountName = identity['provider'] == 'qq'
        ? 'QQ 账号'
        : username.isEmpty
        ? '账号已登录'
        : '@$username';
    final accountTitle = pendingLogout
        ? '退出未完成'
        : user == null
        ? '未登录'
        : nickname.isEmpty
        ? username
        : nickname;
    final accountSubtitle = pendingLogout
        ? '本机登录信息尚未清除，请重试退出登录'
        : user == null
        ? '登录或注册，也可继续以游客使用'
        : '$accountName${state.session['verified'] == true ? ' · 登录状态已验证' : ' · 已保存登录信息，待联网核验'}';
    Widget heading(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 9),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, height: 1.17, color: p.secondary),
      ),
    );
    Widget row(
      HueIconKind icon,
      String title,
      VoidCallback onTap, {
      String note = '',
      String value = '',
      int unread = 0,
    }) => Material(
      color: p.card,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: Center(child: HueIcon(icon, size: 18, color: p.ink)),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.17,
                        color: p.ink,
                      ),
                    ),
                    if (note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          note,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.17,
                            color: p.secondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (unread > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 22,
                      minHeight: 20,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: p.dark ? p.surface : Colors.white,
                      ),
                    ),
                  ),
                ),
              if (value.isNotEmpty)
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.17,
                    color: p.secondary,
                  ),
                ),
              if (value.isEmpty)
                HueIcon(HueIconKind.chevron, size: 14, color: p.secondary),
            ],
          ),
        ),
      ),
    );
    Widget group(List<Widget> children) => ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: p.card,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i != 0)
                Padding(
                  padding: const EdgeInsets.only(left: 49),
                  child: Divider(height: 1, thickness: 1, color: p.outline),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
    void connect() => hueRootPage<void>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraPage(state: state, configuration: true),
      ),
    );
    return Scaffold(
      appBar: const HueHeader(title: '设置'),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          appearanceMode,
          state.core.previewRevision,
        ]),
        builder: (context, _) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            96 + hueNavigationInset(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => context.push('/account'),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 80),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: p.container,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: HueIcon(HueIconKind.person, color: p.secondary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              accountTitle,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: p.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              accountSubtitle,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.2,
                                color: p.secondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      HueIcon(
                        HueIconKind.chevron,
                        size: 15,
                        color: p.secondary,
                      ),
                    ],
                  ),
                ),
              ),
              heading('相机与传输'),
              group([
                row(HueIconKind.wifi, 'Wi-Fi 无线连接', connect, note: '尼康相机 / 富士'),
                row(
                  HueIconKind.usb,
                  'USB 数据线连接',
                  connect,
                  note: '接收 JPEG / NEF 照片',
                ),
                row(
                  HueIconKind.wifi,
                  '后台连接保护',
                  () => hueRootPage<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConnectionProtectionPage(state: state),
                    ),
                  ),
                  note: '接收任务与中断恢复',
                ),
              ]),
              heading('账号与社区'),
              group([
                row(
                  HueIconKind.presets,
                  '我的投稿',
                  () => hueRootPage<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CommunityCollectionPage(
                        state: state,
                        kind: CommunityCollectionKind.submissions,
                        openSubmission: (context, id) =>
                            openSubmissionEditor(context, state, id),
                      ),
                    ),
                  ),
                ),
                row(
                  HueIconKind.info,
                  '消息',
                  () => hueRootPage<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CommunityCollectionPage(
                        state: state,
                        kind: CommunityCollectionKind.messages,
                        openSubmission: (context, id) =>
                            openSubmissionEditor(context, state, id),
                      ),
                    ),
                  ),
                  unread: CommunityActivity.unreadOf(context),
                ),
              ]),
              heading('应用'),
              group([
                row(
                  HueIconKind.download,
                  '相机下载队列',
                  () => hueRootPage<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CameraDownloadsPage(state: state),
                    ),
                  ),
                ),
                row(
                  HueIconKind.adjust,
                  '外观',
                  () => appearance(context),
                  value: switch (appearanceMode.value) {
                    ThemeMode.system => '跟随系统',
                    ThemeMode.light => '浅色',
                    ThemeMode.dark => '深色',
                  },
                ),
                row(
                  HueIconKind.album,
                  '预览模板',
                  () => hueRootPage<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PreviewTemplatesPage(core: state.core),
                    ),
                  ),
                  value: state.core.customTemplate ? '自选模板' : '摄影样片 · 10 张',
                ),
                row(
                  HueIconKind.help,
                  '使用帮助',
                  () => hueRootPage<void>(
                    context,
                    MaterialPageRoute(builder: (_) => HelpPage(state: state)),
                  ),
                ),
                row(
                  HueIconKind.download,
                  '检查更新',
                  () => hueRootPage<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UpdatesPage(state: state),
                    ),
                  ),
                ),
                row(
                  HueIconKind.download,
                  '旧版资料迁入',
                  () => hueRootPage<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LegacyMigrationPage(state: state),
                    ),
                  ),
                ),
                row(
                  HueIconKind.info,
                  '关于',
                  () => hueRootPage<void>(
                    context,
                    MaterialPageRoute(builder: (_) => const AboutPage()),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
