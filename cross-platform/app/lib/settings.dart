import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'domain.dart';
import 'theme.dart';
import 'appearance.dart';
import 'legacy_dialog.dart';
import 'camera.dart';
import 'widgets.dart';

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
        listenable: appearanceMode,
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
                              user == null
                                  ? '未登录'
                                  : (user['nickname'] as String?) ??
                                        user['username'] as String,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                                color: p.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user == null ? '登录或注册，也可继续以游客使用' : '管理账号与个人预设',
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
                  () => explain(
                    context,
                    'USB 数据线连接',
                    '此安装包暂不支持 USB 相机连接。可在 Wi-Fi 无线连接中连接相机。',
                  ),
                  note: '导入预设',
                ),
                row(
                  HueIconKind.wifi,
                  '后台连接保护',
                  () => explain(
                    context,
                    '后台连接保护',
                    '传输时请保持应用在前台运行，并保持相机 Wi-Fi 连接。',
                  ),
                  value: '省电受限',
                ),
              ]),
              heading('账号与社区'),
              group([
                row(
                  HueIconKind.presets,
                  '我的投稿',
                  () => context.push('/account'),
                ),
                row(HueIconKind.info, '消息', () => context.push('/account')),
              ]),
              heading('应用'),
              group([
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
                  () => explain(
                    context,
                    '预览模板',
                    '预设使用 10 张内置摄影样片生成手机模拟效果。展示样片与相机实拍可能存在差异。',
                  ),
                  value: '摄影样片 · 10 张',
                ),
                row(
                  HueIconKind.help,
                  '使用帮助',
                  () => explain(
                    context,
                    '使用帮助',
                    '添加 NCP、NP3 预设后，在相册选择照片进行编辑。相机连接位于「设置」；同步页用于浏览和接收相机照片。RAW 原文件会保留，显影后继续编辑。',
                  ),
                ),
                row(
                  HueIconKind.download,
                  '检查更新',
                  () => explain(context, '应用更新', '当前版本：0.31.0-dev。'),
                  value: '0.31.0-dev',
                ),
                row(
                  HueIconKind.info,
                  '关于',
                  () => explain(
                    context,
                    'Huevia',
                    '管理本地预设、模拟色调、连接相机、浏览和下载照片。\n\n0.31.0-dev',
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
