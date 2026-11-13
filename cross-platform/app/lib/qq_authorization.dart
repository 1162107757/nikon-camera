import 'dart:async';

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
  String error = '';
  bool consent = false, busy = false;
  int generation = 0;
  String get owner => widget.state.session['user']?['id'] as String? ?? '';

  @override
  void dispose() {
    generation++;
    unawaited(authorization.cancel());
    super.dispose();
  }

  Future<void> login() async {
    if (busy) return;
    if (!consent) {
      setState(() => error = '请阅读并同意 QQ 登录说明。');
      return;
    }
    final expectedOwner = owner, attempt = ++generation;
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
      });
      if (!mounted || generation != attempt) return;
      if (owner != expectedOwner) throw const AppFailure('账号已改变，请重新登录。');
      widget.state.acceptAuthenticatedSession(session);
      unawaited(widget.state.refreshLibrary().catchError((Object _) {}));
      if (mounted) Navigator.pop(context, session);
    } catch (failure) {
      if (!mounted || generation != attempt) return;
      final details = failure is AppFailure ? failure.details : null;
      final code = details is Map ? details['accountCode'] : null;
      if ([
        'CHALLENGE_REQUIRED',
        'CHALLENGE_INVALID',
        'CHALLENGE_EXPIRED',
      ].contains(code)) {
        setState(() => error = 'QQ 登录服务尚未更新，请稍后重试或使用账号密码登录。');
        return;
      }
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted && generation == attempt) setState(() => busy = false);
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
            onPressed: busy ? null : login,
            child: Text(busy ? '正在完成 QQ 登录…' : '同意并打开 QQ'),
          ),
        ],
      ),
    ),
  );
}
