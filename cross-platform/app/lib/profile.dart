import 'dart:async';

import 'package:flutter/material.dart';

import 'domain.dart';
import 'widgets.dart';
import 'registration.dart';
import 'account_profile.dart';
import 'theme.dart';

part 'legacy_account.dart';

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
  bool passwordLogin = false, passwordVisible = false;
  String _owner = '';
  @override
  void initState() {
    super.initState();
    _owner = profileOwner(widget.state);
    widget.state.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!mounted) return;
    final next = profileOwner(widget.state);
    if (next != _owner) {
      _owner = next;
      username.clear();
      password.clear();
      passwordVisible = false;
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(AccountPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      oldWidget.state.removeListener(_sessionChanged);
      widget.state.addListener(_sessionChanged);
      _owner = profileOwner(widget.state);
      username.clear();
      password.clear();
    }
  }

  void refreshAccount(VoidCallback mutation) => setState(mutation);
  @override
  void dispose() {
    widget.state.removeListener(_sessionChanged);
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (busy) return;
    final owner = profileOwner(widget.state);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.state.core.call('account.login', {
        'username': username.text.trim(),
        'password': password.text,
        'owner': owner,
      });
      await widget.state.refreshSession();
      if (mounted) {
        setState(() {
          password.clear();
        });
      }
    } catch (failure) {
      try {
        await widget.state.refreshSession();
      } catch (_) {}
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> logout([String? expectedOwner]) async {
    if (busy) return;
    final owner = expectedOwner ?? profileOwner(widget.state);
    if (owner.isNotEmpty && profileOwner(widget.state) != owner) return;
    setState(() => busy = true);
    Object? failure;
    try {
      await widget.state.core.call('account.logout', {
        if (owner.isNotEmpty) 'owner': owner,
      });
    } catch (error) {
      failure = error;
    }
    try {
      await widget.state.refreshSession();
    } catch (error) {
      failure ??= error;
    }
    if (mounted) {
      setState(() => busy = false);
      if (failure != null) report(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state.session['user'] == null) return legacyAccount(context);
    return AccountProfileView(
      key: ValueKey(profileOwner(widget.state)),
      state: widget.state,
      onLogout: (owner) => logout(owner),
      onPrivacy: () => accountInformation(
        'QQ 登录与隐私说明',
        'QQ 登录为可选功能。授权成功后，使用 QQ 提供的账号身份完成登录。取消授权仍可使用账号密码登录或游客模式。',
      ),
    );
  }
}
