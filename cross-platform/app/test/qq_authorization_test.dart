import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/qq_authorization.dart';
import 'package:huevia/theme.dart';

const token = 'synthetic-provider-token-for-test';
const challengeImage =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==';

class QqTestCore extends HueviaCore {
  final calls = <(String, Json)>[];
  bool expired = false;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    if (operation == 'account.challenge') {
      return {
        'id': '00000000-0000-4000-8000-000000000001',
        'image': challengeImage,
      };
    }
    if (operation == 'account.qq') {
      if (expired) {
        throw const AppFailure(
          '验证码已过期。',
          details: {'accountCode': 'CHALLENGE_EXPIRED'},
        );
      }
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
    await tester.enterText(find.byType(TextField), '1234');
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
      await tester.tap(find.text('同意并打开 QQ'));
      await tester.pumpAndSettle();
      expect(nativeCalls, 0);
      await fill(tester);
      final sent = core.calls.singleWhere((call) => call.$1 == 'account.qq').$2;
      expect(sent['owner'], '');
      expect(sent['accessToken'], token);
      expect(sent['challengeAnswer'], '1234');
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
    'Expired proof refreshes captcha without reusing the provider token',
    (tester) async {
      messenger.setMockMethodCallHandler(
        QqAuthorization.channel,
        (_) async => {'accessToken': token},
      );
      final core = QqTestCore()..expired = true;
      final state = AppState(core);
      await page(tester, state);
      await tester.pumpAndSettle();
      await fill(tester);
      expect(core.calls.where((call) => call.$1 == 'account.qq').length, 1);
      expect(
        core.calls.where((call) => call.$1 == 'account.challenge').length,
        2,
      );
      expect(find.text('验证码已过期。'), findsOneWidget);
      state.dispose();
    },
  );
}
