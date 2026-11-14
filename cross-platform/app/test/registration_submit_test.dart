import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/profile.dart';
import 'package:huevia/registration.dart';
import 'package:huevia/theme.dart';

const _owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==';
Json _challenge(int index) => {
  'id': '00000000-0000-0000-0000-${index.toString().padLeft(12, '0')}',
  'image': _png,
};
Json _session() => {
  'user': {'id': _owner},
  'verified': true,
};

class _AuthCore extends HueviaCore {
  final calls = <(String, Json)>[];
  int challenges = 0;
  Future<Json> Function(Json)? register;
  Future<Json> Function(Json)? login;
  Future<Json> Function(int)? challenge;
  Future<Json> Function()? current, library;

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    switch (operation) {
      case 'account.challenge':
        final index = ++challenges;
        return challenge == null ? _challenge(index) : await challenge!(index);
      case 'account.register':
        return register == null ? _session() : await register!(payload);
      case 'account.login':
        return login == null ? _session() : await login!(payload);
      case 'account.current':
        return current == null ? {} : await current!();
      case 'library.list':
        return library == null ? {'items': []} : await library!();
      default:
        return {};
    }
  }
}

Future<void> _page(WidgetTester tester, AppState state, {Key? key}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.light),
      home: RegistrationPage(key: key, state: state),
    ),
  );
  await tester.pump();
}

Future<void> _fill(WidgetTester tester, String password) async {
  final fields = find.byType(TextFormField);
  for (final field in [
    (0, 'example_user'),
    (1, password),
    (2, password),
    (3, 'ABCD'),
  ]) {
    await tester.enterText(fields.at(field.$1), field.$2);
  }
}

Future<void> _submit(WidgetTester tester) async {
  await tester.ensureVisible(find.text('注册并登录'));
  await tester.tap(find.text('注册并登录'));
  await tester.pump();
}

String _text(WidgetTester tester, int field) => tester
    .widget<TextFormField>(find.byType(TextFormField).at(field))
    .controller!
    .text;

void main() {
  for (final scenario in [
    ('digits', '12345678'),
    ('letters', 'abcdefgh'),
    ('whitespace', ' abcdefg '),
  ]) {
    final password = scenario.$2;
    testWidgets(
      'Registration accepts a simple password unchanged: ${scenario.$1}',
      (tester) async {
        final core = _AuthCore();
        final actual = AppState(core);
        await _page(tester, actual);
        await tester.pumpAndSettle();
        await _fill(tester, password);
        await _submit(tester);
        await tester.pumpAndSettle();
        final request = core.calls.singleWhere(
          (call) => call.$1 == 'account.register',
        );
        expect(request.$2['password'], password);
        expect(actual.session['user']['id'], _owner);
        expect(find.text('注册成功，已登录'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'A short password gives a visible error without submitting or clearing fields',
    (tester) async {
      final core = _AuthCore();
      await _page(tester, AppState(core));
      await tester.pumpAndSettle();
      await _fill(tester, '1234567');
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('密码需为 8–128 个字符。'), findsOneWidget);
      expect(
        core.calls.where((call) => call.$1 == 'account.register'),
        isEmpty,
      );
      expect(_text(tester, 0), 'example_user');
      expect(_text(tester, 1), '1234567');
    },
  );

  for (final empty in [false, true]) {
    testWidgets(
      'Registration ${empty ? 'empty response' : 'network failure'} retains every field and displays the error',
      (tester) async {
        final core = _AuthCore()
          ..register = (_) async {
            if (empty) return {};
            throw const AppFailure('当前网络无法连接账号服务。');
          };
        final state = AppState(core);
        await _page(tester, state);
        await tester.pumpAndSettle();
        await _fill(tester, '12345678');
        await _submit(tester);
        await tester.pumpAndSettle();
        expect(_text(tester, 0), 'example_user');
        expect(_text(tester, 1), '12345678');
        expect(_text(tester, 2), '12345678');
        expect(_text(tester, 3), 'ABCD');
        expect(
          find.text(empty ? '未取得有效登录状态，请重试登录。' : '当前网络无法连接账号服务。'),
          findsOneWidget,
        );
        expect(state.session, isEmpty);
        expect(core.challenges, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Expired captcha reports the failure before a slow replacement and retains credentials',
    (tester) async {
      final replacement = Completer<Json>();
      final core = _AuthCore()
        ..register = (_) async {
          throw const AppFailure(
            '验证码已过期。',
            details: {'accountCode': 'CHALLENGE_EXPIRED'},
          );
        }
        ..challenge = (index) async =>
            index == 1 ? _challenge(index) : await replacement.future;
      await _page(tester, AppState(core));
      await tester.pumpAndSettle();
      await _fill(tester, '12345678');
      await _submit(tester);
      await tester.pump();
      expect(find.textContaining('验证码已过期。'), findsOneWidget);
      expect(find.textContaining('账号和密码已保留'), findsOneWidget);
      expect(_text(tester, 0), 'example_user');
      expect(_text(tester, 1), '12345678');
      expect(_text(tester, 2), '12345678');
      expect(_text(tester, 3), isEmpty);
      replacement.complete(_challenge(2));
      await tester.pumpAndSettle();
      expect(find.textContaining('已更换验证码'), findsOneWidget);
      expect(_text(tester, 0), 'example_user');
      expect(_text(tester, 1), '12345678');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Leaving registration discards a late successful response', (
    tester,
  ) async {
    final response = Completer<Json>();
    final core = _AuthCore()..register = (_) => response.future;
    final state = AppState(core);
    await _page(tester, state);
    await tester.pumpAndSettle();
    await _fill(tester, '12345678');
    await _submit(tester);
    await tester.pumpWidget(const MaterialApp(home: Text('left registration')));
    response.complete(_session());
    await tester.pumpAndSettle();
    expect(state.session, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'A late captcha from an old page cannot clear a new registration form',
    (tester) async {
      final oldCaptcha = Completer<Json>();
      final core = _AuthCore()
        ..challenge = (index) async =>
            index == 1 ? await oldCaptcha.future : _challenge(index);
      final state = AppState(core);
      await _page(tester, state, key: const ValueKey('old'));
      await _page(tester, state, key: const ValueKey('new'));
      await tester.pumpAndSettle();
      await _fill(tester, '12345678');
      oldCaptcha.complete(_challenge(1));
      await tester.pumpAndSettle();
      expect(_text(tester, 0), 'example_user');
      expect(_text(tester, 1), '12345678');
      expect(_text(tester, 3), 'ABCD');
      await _submit(tester);
      await tester.pumpAndSettle();
      final request = core.calls.singleWhere(
        (call) => call.$1 == 'account.register',
      );
      expect(request.$2['challengeId'], _challenge(2)['id']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Failed password login preserves credentials and does not silently install an account refresh',
    (tester) async {
      final core = _AuthCore()
        ..login = (_) async => throw const AppFailure('用户名或密码不正确。');
      final state = AppState(core);
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: AccountPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('使用账号密码登录'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'example_user');
      await tester.enterText(fields.at(1), '12345678');
      await tester.ensureVisible(find.text('登录'));
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(fields.at(0)).controller!.text,
        'example_user',
      );
      expect(
        tester.widget<TextField>(fields.at(1)).controller!.text,
        '12345678',
      );
      expect(find.text('用户名或密码不正确。'), findsOneWidget);
      expect(core.calls.where((call) => call.$1 == 'account.current'), isEmpty);
      expect(state.session, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'A late anonymous refresh cannot replace a successfully installed session',
    () async {
      final response = Completer<Json>();
      final core = _AuthCore()..current = () => response.future;
      final state = AppState(core);
      final refresh = state.refreshSession();
      state.acceptAuthenticatedSession(_session());
      response.complete({});
      await refresh;
      expect(state.session['user']['id'], _owner);
      expect(core.calls.where((call) => call.$1 == 'library.list'), isEmpty);
    },
  );

  test(
    'An old library snapshot cannot install another owners presets after login',
    () async {
      final response = Completer<Json>();
      final core = _AuthCore()..library = () => response.future;
      final state = AppState(core);
      final refresh = state.refreshLibrary();
      state.acceptAuthenticatedSession(_session());
      response.complete({
        'items': [
          {'id': 'old-guest-preset', 'name': 'old guest'},
        ],
      });
      await refresh;
      expect(state.presets, isEmpty);
      expect(state.session['user']['id'], _owner);
    },
  );
}
