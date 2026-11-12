import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'domain.dart';

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key, required this.state});
  final AppState state;
  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final form = GlobalKey<FormState>();
  final username = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController(),
      answer = TextEditingController();
  final errorFocus = FocusNode();
  final errorKey = GlobalKey();
  bool signedIn = false;
  bool busy = false, loading = false;
  String proof = '';
  String? error;
  Uint8List? image;
  int epoch = 0;
  @override
  void initState() {
    super.initState();
    unawaited(challenge());
  }

  @override
  void dispose() {
    epoch++;
    for (final input in [username, password, confirm, answer]) {
      input.dispose();
    }
    errorFocus.dispose();
    super.dispose();
  }

  Future<void> challenge() async {
    final request = ++epoch;
    setState(() {
      loading = true;
      proof = '';
      image = null;
      answer.clear();
    });
    try {
      final result = await widget.state.core.call('account.challenge');
      final encoded = result['image'];
      if (encoded is! String ||
          encoded.length > 60000 ||
          !encoded.startsWith('data:image/png;base64,')) {
        throw const AppFailure('验证码图片无效。');
      }
      final bytes = base64Decode(encoded.substring(22));
      if (bytes.length < 24 ||
          bytes[0] != 137 ||
          bytes[1] != 80 ||
          bytes[2] != 78 ||
          bytes[3] != 71) {
        throw const AppFailure('验证码图片无效。');
      }
      final data = ByteData.sublistView(bytes);
      final width = data.getUint32(16), height = data.getUint32(20);
      if (width < 1 || width > 1024 || height < 1 || height > 512) {
        throw const AppFailure('验证码图片尺寸无效。');
      }
      final id = result['id'];
      if (id is! String ||
          !RegExp(r'^[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$')
              .hasMatch(id)) {
        throw const AppFailure('验证码响应无效。');
      }
      if (mounted && request == epoch) {
        setState(() {
          proof = id;
          image = bytes;
        });
      }
    } catch (failure) {
      if (mounted && request == epoch) setState(() => error = '$failure');
    } finally {
      if (mounted && request == epoch) setState(() => loading = false);
    }
  }

  Future<void> submit() async {
    if (busy || loading || signedIn || !form.currentState!.validate()) return;
    if (proof.isEmpty) {
      setState(() => error = '请先获取验证码。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = await widget.state.core.call('account.register', {
        'username': username.text.trim(),
        'password': password.text,
        'challengeId': proof,
        'challengeAnswer': answer.text.trim(),
      });
      widget.state.acceptAuthenticatedSession(session);
      unawaited(widget.state.refreshLibrary().catchError((Object _) {}));
      if (mounted) {
        signedIn = true;
        if (Navigator.canPop(context)) {
          Navigator.pop(context, session);
        } else {
          setState(() {});
        }
      }
    } catch (failure) {
      if (mounted) {
        final details = failure is AppFailure ? failure.details : null;
        final code = details is Map ? details['accountCode'] : null;
        var message = '$failure';
        if (code == 'CHALLENGE_INVALID' ||
            code == 'CHALLENGE_EXPIRED' ||
            code == 'CHALLENGE_REQUIRED') {
          await challenge();
          if (!mounted) return;
          message += proof.isEmpty
              ? '\n获取新验证码失败，请点击刷新后重试。'
              : '\n已更换验证码，请重新填写后注册。';
        }
        setState(() => error = message);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          FocusManager.instance.primaryFocus?.unfocus();
          errorFocus.requestFocus();
          final target = errorKey.currentContext;
          if (target != null) {
            unawaited(
              Scrollable.ensureVisible(
                target,
                duration: const Duration(milliseconds: 180),
                alignment: .5,
              ),
            );
          }
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('注册账号')),
    body: signedIn
        ? const Center(child: Text('注册成功，已登录'))
        : SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Form(
                    key: form,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '建立你的预设收藏',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: username,
                            enabled: !busy,
                            autofillHints: const [AutofillHints.newUsername],
                            autocorrect: false,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '用户名',
                              helperText: '3–32 位，字母开头，可含数字与下划线',
                            ),
                            validator: (value) =>
                                RegExp(r'^[A-Za-z][A-Za-z0-9_]{2,31}$')
                                    .hasMatch(value?.trim() ?? '')
                                ? null
                                : '请输入有效用户名。',
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: password,
                            enabled: !busy,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '密码',
                              helperText: '8–128 个字符',
                            ),
                            validator: (value) =>
                                value != null &&
                                    value.length >= 8 &&
                                    value.length <= 128
                                ? null
                                : '密码需为 8–128 个字符。',
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: confirm,
                            enabled: !busy,
                            obscureText: true,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: '确认密码',
                            ),
                            validator: (value) =>
                                value == password.text ? null : '两次输入的密码不同。',
                          ),
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 80,
                                  child: image != null
                                      ? Image.memory(
                                          image!,
                                          fit: BoxFit.contain,
                                          semanticLabel: '注册图片验证码',
                                          errorBuilder: (_, _, _) =>
                                              const Center(
                                                child: Text('验证码无法显示，请刷新。'),
                                              ),
                                        )
                                      : Center(
                                          child: loading
                                              ? const CircularProgressIndicator()
                                              : const Text('点击刷新获取验证码'),
                                        ),
                                ),
                              ),
                              IconButton(
                                tooltip: '刷新验证码',
                                onPressed: busy || loading ? null : challenge,
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: answer,
                            enabled: !busy,
                            autocorrect: false,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: '图片验证码',
                            ),
                            validator: (value) =>
                                RegExp(r'^[A-Za-z0-9]{4,8}$')
                                    .hasMatch(value?.trim() ?? '')
                                ? null
                                : '请输入图片中的验证码。',
                            onFieldSubmitted: (_) {
                              if (!busy && !loading) unawaited(submit());
                            },
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Focus(
                                key: errorKey,
                                focusNode: errorFocus,
                                child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    error!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: busy || loading ? null : submit,
                            child: Text(busy ? '正在注册' : '注册并登录'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
  );
}
