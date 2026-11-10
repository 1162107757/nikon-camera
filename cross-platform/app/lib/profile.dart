import 'dart:async';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'widgets.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.state});
  final AppState state;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final username = TextEditingController(), password = TextEditingController();
  String? error;
  bool busy = false;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = await widget.state.core.call('account.login', {
        'username': username.text.trim(),
        'password': password.text,
      });
      if (mounted) {
        setState(() {
          widget.state.session = session;
          password.clear();
        });
      }
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.state.session['user'];
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  if (user != null) ...[
                    Text(
                      (user['nickname'] as String).isEmpty
                          ? user['username'] as String
                          : user['nickname'] as String,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text('本地预设与照片仍可离线使用。'),
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              try {
                                await widget.state.core.call('account.logout');
                                if (mounted) {
                                  setState(() => widget.state.session = {});
                                }
                              } catch (error) {
                                if (context.mounted) report(context, error);
                              }
                            },
                      child: const Text('退出登录'),
                    ),
                  ] else ...[
                    Text(
                      '欢迎回来',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text('登录后管理个人预设，参与社区交流。'),
                    const SizedBox(height: 32),
                    AutofillGroup(
                      child: Column(
                        children: [
                          TextField(
                            controller: username,
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            decoration: const InputDecoration(labelText: '用户名'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: password,
                            autofillHints: const [AutofillHints.password],
                            obscureText: true,
                            onSubmitted: (_) {
                              if (!busy) unawaited(login());
                            },
                            decoration: const InputDecoration(labelText: '密码'),
                          ),
                        ],
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : login,
                      child: Text(busy ? '正在登录' : '登录'),
                    ),
                  ],
                  const SizedBox(height: 40),
                  const Divider(),
                  const SizedBox(height: 16),
                  const Text(
                    'Huevia',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text('跨平台迁移开发版'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
