import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/qq_authorization.dart';
import 'package:huevia/theme.dart';

const token = 'synthetic-provider-token-for-test';

class QqTestCore extends HueviaCore {
  final calls = <(String, Json)>[];
  bool legacyChallenge = false;
  Completer<Json>? exchange;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    if (operation == 'account.qq') {
      if (legacyChallenge) {
        throw const AppFailure(
          '请填写图片验证码后继续。',
          details: {'accountCode': 'CHALLENGE_REQUIRED'},
        );
      }
      if (exchange != null) return exchange!.future;
      return {
        'user': {'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'},
        'verified': true,
      };
    }
    if (operation == 'library.list') return {'items': <Json>[]};
    throw StateError('Unexpected operation $operation');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(QqAuthorization.channel, null),
  );

  test('Native consent and bounded provider token are required', () async {
    Json? arguments;
    messenger.setMockMethodCallHandler(QqAuthorization.channel, (call) async {
      arguments = object(call.arguments);
      return {'accessToken': token};
    });
    final result = await QqAuthorization().authorize();
    expect(arguments, {'consent': true});
    expect(result, {'accessToken': token});
    messenger.setMockMethodCallHandler(
      QqAuthorization.channel,
      (_) async => {'accessToken': 'short'},
    );
    await expectLater(
      QqAuthorization().authorize(),
      throwsA(isA<AppFailure>()),
    );
  });

  test(
    'Cancel discards a late token and duplicate authorization stays single',
    () async {
      final outcome = Completer<Object?>();
      final methods = <String>[];
      messenger.setMockMethodCallHandler(QqAuthorization.channel, (call) async {
        methods.add(call.method);
        return call.method == 'authorize' ? outcome.future : null;
      });
      final authorization = QqAuthorization();
      final first = authorization.authorize();
      await expectLater(authorization.authorize(), throwsA(isA<AppFailure>()));
      await authorization.cancel();
      outcome.complete({'accessToken': token});
      expect(await first, isNull);
      expect(methods, ['authorize', 'cancel']);
    },
  );

  Future<void> fill(WidgetTester tester) async {
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('同意并打开 QQ'));
    await tester.pumpAndSettle();
  }

  Future<void> page(WidgetTester tester, AppState state) => tester.pumpWidget(
    MaterialApp(
      theme: hueviaTheme(Brightness.light, home: false),
      home: QqLoginPage(state: state),
    ),
  );

  testWidgets('Provider cancellation never creates an app session', (
    tester,
  ) async {
    final core = QqTestCore();
    final actualState = AppState(core);
    messenger.setMockMethodCallHandler(
      QqAuthorization.channel,
      (call) async => {'cancelled': true},
    );
    await page(tester, actualState);
    await tester.pumpAndSettle();
    await fill(tester);
    expect(core.calls.where((call) => call.$1 == 'account.qq'), isEmpty);
    expect(actualState.session['user'], isNull);
    actualState.dispose();
  });

  testWidgets(
    'Consent precedes SDK launch and success commits verified app session',
    (tester) async {
      var nativeCalls = 0;
      messenger.setMockMethodCallHandler(QqAuthorization.channel, (call) async {
        if (call.method == 'authorize') nativeCalls++;
        return {'accessToken': token};
      });
      final core = QqTestCore();
      final actualState = AppState(core);
      await page(tester, actualState);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('刷新验证码'), findsNothing);
      expect(
        core.calls.where((call) => call.$1 == 'account.challenge'),
        isEmpty,
      );
      await tester.tap(find.text('同意并打开 QQ'));
      await tester.pumpAndSettle();
      expect(nativeCalls, 0);
      await fill(tester);
      final sent = core.calls.singleWhere((call) => call.$1 == 'account.qq').$2;
      expect(sent['owner'], '');
      expect(sent['accessToken'], token);
      expect(sent.keys.toSet(), {'owner', 'accessToken'});
      expect(
        core.calls.where((call) => call.$1 == 'account.challenge'),
        isEmpty,
      );
      expect(actualState.session['verified'], true);
      expect(nativeCalls, 1);
      actualState.dispose();
    },
  );

  testWidgets('Owner change while QQ is open prevents exchange', (
    tester,
  ) async {
    final result = Completer<Object?>();
    messenger.setMockMethodCallHandler(
      QqAuthorization.channel,
      (call) async => call.method == 'authorize' ? result.future : null,
    );
    final core = QqTestCore();
    final actualState = AppState(core);
    await page(tester, actualState);
    await tester.pumpAndSettle();
    await fill(tester);
    actualState.acceptAuthenticatedSession({
      'user': {'id': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'},
      'verified': true,
    });
    result.complete({'accessToken': token});
    await tester.pumpAndSettle();
    expect(core.calls.where((call) => call.$1 == 'account.qq'), isEmpty);
    expect(find.text('账号已改变，请重新登录。'), findsOneWidget);
    actualState.dispose();
  });

  testWidgets(
    'An older server that still requires QQ captcha is reported without fetching a hidden challenge',
    (tester) async {
      messenger.setMockMethodCallHandler(
        QqAuthorization.channel,
        (_) async => {'accessToken': token},
      );
      final core = QqTestCore()..legacyChallenge = true;
      final state = AppState(core);
      await page(tester, state);
      await tester.pumpAndSettle();
      await fill(tester);
      expect(core.calls.where((call) => call.$1 == 'account.qq').length, 1);
      expect(
        core.calls.where((call) => call.$1 == 'account.challenge').length,
        0,
      );
      expect(find.text('QQ 登录服务尚未更新，请稍后重试或使用账号密码登录。'), findsOneWidget);
      expect(state.session['user'], isNull);
      state.dispose();
    },
  );

  testWidgets(
    'Owner change during QQ session exchange prevents a late app session from replacing the new account',
    (tester) async {
      messenger.setMockMethodCallHandler(
        QqAuthorization.channel,
        (_) async => {'accessToken': token},
      );
      final core = QqTestCore()..exchange = Completer<Json>();
      final state = AppState(core);
      await page(tester, state);
      await tester.pumpAndSettle();
      await fill(tester);
      state.acceptAuthenticatedSession({
        'user': {'id': 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'},
        'verified': true,
      });
      core.exchange!.complete({
        'user': {'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'},
        'verified': true,
      });
      await tester.pumpAndSettle();
      expect(
        state.session['user']['id'],
        'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      );
      expect(find.text('账号已改变，请重新登录。'), findsOneWidget);
      expect(
        core.calls.where((call) => call.$1 == 'account.challenge'),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  testWidgets(
    'Leaving the QQ page discards a late native credential without a challenge or exchange',
    (tester) async {
      final result = Completer<Object?>();
      messenger.setMockMethodCallHandler(
        QqAuthorization.channel,
        (call) async => call.method == 'authorize' ? result.future : null,
      );
      final core = QqTestCore();
      final state = AppState(core);
      await page(tester, state);
      await tester.pumpAndSettle();
      await fill(tester);
      await tester.pumpWidget(const SizedBox());
      result.complete({'accessToken': token});
      await tester.pumpAndSettle();
      expect(core.calls, isEmpty);
      expect(state.session['user'], isNull);
      state.dispose();
    },
  );
}
