import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'domain.dart';
import 'theme.dart';

/// Provider credentials are confined to one attempt and exchanged immediately.
class QqAuthorization {
  static const channel = MethodChannel('cc.huevia/qq');
  int _generation = 0;
  bool _active = false;

  Future<Json?> authorize() async {
    if (_active) throw const AppFailure('请先完成当前 QQ 授权。');
    _active = true;
    final attempt = ++_generation;
    try {
      final value = await channel.invokeMapMethod<String, dynamic>(
        'authorize',
        {'consent': true},
      );
      if (attempt != _generation || value?['cancelled'] == true) return null;
      final token = value?['accessToken'];
      if (token is! String ||
          token.length < 16 ||
          token.length > 2048 ||
          !RegExp(r'^[\x21-\x7e]+$').hasMatch(token)) {
        throw const AppFailure('QQ 授权结果无效，请重新登录。');
      }
      return {'accessToken': token};
    } on MissingPluginException {
      throw const AppFailure('此安装包缺少 QQ 授权组件，请安装完整版本。');
    } on PlatformException catch (failure) {
      throw AppFailure(failure.message ?? 'QQ 授权未完成，请重试。');
    } finally {
      if (attempt == _generation) _active = false;
    }
  }

  Future<void> cancel() async {
    _generation++;
    _active = false;
    try {
      await channel.invokeMethod<void>('cancel');
    } on PlatformException catch (_) {
      // Disposal must not expose or retain provider results.
    } on MissingPluginException catch (_) {}
  }
}

class QqLoginPage extends StatefulWidget {
  const QqLoginPage({super.key, required this.state});
  final AppState state;
  @override
  State<QqLoginPage> createState() => _QqLoginPageState();
}

class _QqLoginPageState extends State<QqLoginPage> {
  final authorization = QqAuthorization();
  final answer = TextEditingController();
  Uint8List? image;
  String proof = '', error = '';
  bool consent = false, busy = false, loading = false;
  int generation = 0;
  String get owner => widget.state.session['user']?['id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(challenge());
  }

  @override
  void dispose() {
    generation++;
    unawaited(authorization.cancel());
    answer.dispose();
    super.dispose();
  }

  Future<void> challenge() async {
    final attempt = ++generation;
    setState(() {
      loading = true;
      proof = '';
      image = null;
      answer.clear();
    });
    try {
      final result = await widget.state.core.call('account.challenge');
      final value = result['image'], id = result['id'];
      if (value is! String ||
          value.length > 60000 ||
          !value.startsWith('data:image/png;base64,') ||
          id is! String ||
          !RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(id)) {
        throw const AppFailure('验证码响应无效，请刷新重试。');
      }
      final bytes = base64Decode(value.substring(22));
      if (bytes.length < 24 ||
          bytes[0] != 137 ||
          bytes[1] != 80 ||
          bytes[2] != 78 ||
          bytes[3] != 71) {
        throw const AppFailure('验证码图片无效。');
      }
      final data = ByteData.sublistView(bytes);
      if (data.getUint32(16) < 1 ||
          data.getUint32(16) > 1024 ||
          data.getUint32(20) < 1 ||
          data.getUint32(20) > 512) {
        throw const AppFailure('验证码图片尺寸无效。');
      }
      if (mounted && attempt == generation) {
        setState(() {
          proof = id;
          image = bytes;
        });
      }
    } catch (failure) {
      if (mounted && attempt == generation) setState(() => error = '$failure');
    } finally {
      if (mounted && attempt == generation) setState(() => loading = false);
    }
  }

  Future<void> login() async {
    if (busy || loading) return;
    if (!consent || proof.isEmpty || answer.text.trim().isEmpty) {
      setState(() => error = '请填写验证码，并阅读同意 QQ 登录说明。');
      return;
    }
    final expectedOwner = owner, attempt = generation;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final credentials = await authorization.authorize();
      if (credentials == null || !mounted || generation != attempt) return;
      if (owner != expectedOwner) throw const AppFailure('账号已改变，请重新登录。');
      final session = await widget.state.core.call('account.qq', {
        ...credentials,
        'owner': expectedOwner,
        'challengeId': proof,
        'challengeAnswer': answer.text.trim(),
      });
      if (!mounted || generation != attempt) return;
      widget.state.acceptAuthenticatedSession(session);
      unawaited(widget.state.refreshLibrary().catchError((Object _) {}));
      if (mounted) Navigator.pop(context, session);
    } catch (failure) {
      if (!mounted) return;
      final details = failure is AppFailure ? failure.details : null;
      final code = details is Map ? details['accountCode'] : null;
      if ([
        'CHALLENGE_REQUIRED',
        'CHALLENGE_INVALID',
        'CHALLENGE_EXPIRED',
      ].contains(code)) {
        await challenge();
      }
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const HueHeader(title: 'QQ 快捷登录', back: true),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('使用 QQ 账号继续', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          const Text(
            '授权时将打开 QQ。腾讯提供的账号身份、昵称和头像用于创建或登录 Huevia 账号。授权凭据仅用于服务端核验，不保存为本机登录密码。取消授权后仍可使用游客功能。',
          ),
          const SizedBox(height: 24),
          if (image != null)
            Image.memory(image!, height: 80, semanticLabel: '图形验证码'),
          TextButton(
            onPressed: busy || loading ? null : challenge,
            child: Text(loading ? '正在获取验证码…' : '刷新验证码'),
          ),
          TextField(
            controller: answer,
            enabled: !busy,
            decoration: const InputDecoration(labelText: '验证码'),
            autocorrect: false,
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: consent,
            onChanged: busy
                ? null
                : (value) => setState(() => consent = value == true),
            title: const Text('我已阅读并同意以上 QQ 登录说明'),
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton(
            onPressed: busy || loading ? null : login,
            child: Text(busy ? '正在完成 QQ 登录…' : '同意并打开 QQ'),
          ),
        ],
      ),
    ),
  );
}
