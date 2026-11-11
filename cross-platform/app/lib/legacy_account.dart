part of 'profile.dart';

extension _LegacyAccount on _AccountPageState {
  Future<void> registerAccount() async {
    final session = await Navigator.push<Json>(
      context,
      MaterialPageRoute(builder: (_) => RegistrationPage(state: widget.state)),
    );
    if (!mounted || session == null) return;
    await widget.state.refreshSession();
    if (mounted) refreshAccount(password.clear);
  }

  Future<void> accountInformation(String title, String message) =>
      showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('知道了'),
            ),
          ],
        ),
      );

  Widget accountAction(String label, VoidCallback action) => SizedBox(
    height: 52,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: HuePalette.of(context).dark
              ? const [Color(0xfff0e8df), Color(0xffdad0c5)]
              : const [Color(0xff46413b), Color(0xff27241f)],
        ),
      ),
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: HuePalette.of(context).dark
              ? const Color(0xff26211c)
              : Colors.white,
          textStyle: const TextStyle(fontSize: 16),
        ),
        onPressed: busy ? null : action,
        child: Text(label),
      ),
    ),
  );

  Widget accountField(
    String label,
    String hint,
    TextEditingController controller, {
    bool secret = false,
  }) {
    final palette = HuePalette(
      dark: Theme.of(context).brightness == Brightness.dark,
      home: false,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: palette.ink,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 54,
          child: TextField(
            controller: controller,
            obscureText: secret && !passwordVisible,
            autocorrect: false,
            autofillHints: [
              secret ? AutofillHints.password : AutofillHints.username,
            ],
            textInputAction: secret
                ? TextInputAction.done
                : TextInputAction.next,
            onSubmitted: secret
                ? (_) {
                    if (!busy) unawaited(login());
                  }
                : null,
            style: TextStyle(fontSize: 16, color: palette.ink),
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: palette.card,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.outline),
              ),
              suffixIcon: secret
                  ? IconButton(
                      tooltip: passwordVisible ? '隐藏密码' : '显示密码',
                      onPressed: () => refreshAccount(
                        () => passwordVisible = !passwordVisible,
                      ),
                      icon: Icon(
                        passwordVisible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 23,
                        color: palette.secondary,
                      ),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget legacyAccount(BuildContext context) {
    final theme = hueviaTheme(Theme.of(context).brightness, home: false);
    final palette = theme.extension<HuePalette>()!;
    final welcome = !passwordLogin;
    final brand = Image.asset(
      'assets/legacy/huevia_launcher.png',
      width: welcome ? 76 : 38,
      height: welcome ? 76 : 38,
    );
    return Theme(
      data: theme,
      child: Scaffold(
        appBar: HueHeader(
          title: '账号登录',
          back: true,
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.maybePop(context),
              child: Text(
                '游客使用',
                style: TextStyle(fontSize: 14, color: palette.secondary),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, bounds) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: bounds.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (welcome) ...[
                          const SizedBox(height: 36),
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: brand,
                            ),
                          ),
                          const SizedBox(height: 17),
                          Text(
                            'Huevia',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 30,
                              height: 1.3,
                              fontWeight: FontWeight.bold,
                              color: palette.ink,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '把喜欢的色彩，带进相机',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.3,
                              color: palette.secondary,
                            ),
                          ),
                          const SizedBox(height: 44),
                          accountAction(
                            'QQ 快捷登录',
                            () => accountInformation(
                              'QQ 快捷登录',
                              '当前安装包暂不支持 QQ 授权，请使用账号密码登录。',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '使用 QQ 账号授权，首次登录自动创建账号',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              color: palette.secondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 52,
                            child: TextButton(
                              onPressed: () =>
                                  refreshAccount(() => passwordLogin = true),
                              child: Text(
                                '使用账号密码登录',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: palette.ink,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(11),
                                child: brand,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Huevia',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: palette.ink,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 30),
                          Text(
                            '账号密码登录',
                            style: TextStyle(
                              fontSize: 28,
                              height: 1.3,
                              fontWeight: FontWeight.bold,
                              color: palette.ink,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '使用你的 Huevia 账号继续。',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.3,
                              color: palette.secondary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          AutofillGroup(
                            child: Column(
                              children: [
                                accountField('用户名', '请输入用户名', username),
                                accountField(
                                  '密码',
                                  '请输入密码',
                                  password,
                                  secret: true,
                                ),
                              ],
                            ),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Text(
                                error!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          accountAction(busy ? '正在登录' : '登录', login),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 52,
                            child: TextButton(
                              onPressed: () => refreshAccount(() {
                                password.clear();
                                passwordLogin = false;
                              }),
                              child: Text(
                                '使用 QQ 快捷登录',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: palette.ink,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '还没有账号？',
                              style: TextStyle(
                                fontSize: 13,
                                color: palette.secondary,
                              ),
                            ),
                            TextButton(
                              onPressed: busy ? null : registerAccount,
                              child: Text(
                                '注册账号',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: palette.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        const SizedBox(height: 32),
                        Text(
                          '不登录，也能管理本机预设与照片',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: palette.secondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () => accountInformation(
                                'QQ 登录与隐私说明',
                                'QQ 登录为可选功能。授权成功后，使用 QQ 提供的账号身份完成登录。取消授权仍可使用账号密码登录或游客模式。',
                              ),
                              child: Text(
                                'QQ 登录与隐私说明',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: palette.secondary,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => accountInformation(
                                '登录帮助',
                                '登录需要可上网的网络。连接相机 Wi-Fi 时可能无法上网，可先切换至手机网络完成登录，再连接相机。暂时无法登录时，仍可选择游客使用。',
                              ),
                              child: Text(
                                '登录帮助',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: palette.secondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
