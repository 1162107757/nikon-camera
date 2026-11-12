import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/library.dart';
import 'package:huevia/registration.dart';
import 'package:huevia/theme.dart';

class TestCore extends HueviaCore {
  int challenges = 0;
  bool registerSuccess = false;
  bool expiredChallenge = false;
  final List<(String, Json)> calls = [];
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    calls.add((operation, payload));
    switch (operation) {
      case 'account.challenge':
        challenges++;
        return {
          'id':
              '00000000-0000-0000-0000-${challenges.toString().padLeft(12, '0')}',
          'image': 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP48OHDfwAJdAPQXHvArAAAAABJRU5ErkJggg==',
        };
      case 'account.register':
        if (registerSuccess) {
          return {
            'user': {'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'},
            'verified': true,
          };
        }
        if (expiredChallenge) {
          throw const AppFailure(
            '验证码不正确或已过期，请换一张后重试。',
            details: {'accountCode': 'CHALLENGE_EXPIRED'},
          );
        }
        throw const AppFailure('验证码已过期，请刷新后重试。');
      case 'online.page':
        return {
          'items': [
            {'id': 'first', 'name': '第一页预设', 'fileFormat': 'NCP'},
          ],
          'page': 1,
          'hasMore': true,
          'categories': [],
        };
      case 'online.search':
        return {
          'items': [
            {'id': 'beyond', 'name': '远处的蓝', 'fileFormat': 'NP3'},
          ],
          'available': true,
          'fromCache': false,
          'message': '',
          'categories': [],
        };
      default:
        throw AppFailure('Unexpected request $operation');
    }
  }
}

void main() {
  testWidgets(
    'Registration failures retain credentials and refresh only the challenge answer',
    (tester) async {
      final core = TestCore();
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: RegistrationPage(state: AppState(core)),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'example_user');
      await tester.enterText(fields.at(1), 'example-password');
      await tester.enterText(fields.at(2), 'example-password');
      await tester.enterText(fields.at(3), 'ABCD');
      await tester.ensureVisible(find.text('注册并登录'));
      await tester.tap(find.text('注册并登录'));
      await tester.pumpAndSettle();
      expect(find.text('验证码已过期，请刷新后重试。'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(fields.at(0)).controller!.text,
        'example_user',
      );
      expect(
        tester.widget<TextFormField>(fields.at(1)).controller!.text,
        'example-password',
      );
      await tester.ensureVisible(find.byTooltip('刷新验证码'));
      await tester.tap(find.byTooltip('刷新验证码'));
      await tester.pumpAndSettle();
      expect(core.challenges, 2);
      expect(
        tester.widget<TextFormField>(fields.at(3)).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextFormField>(fields.at(1)).controller!.text,
        'example-password',
      );
      expect(
        core.calls
            .where((call) => call.$1 == 'account.register')
            .single
            .$2['challengeId'],
        '00000000-0000-0000-0000-000000000001',
      );
    },
  );
  testWidgets(
    'Registration commits login even if refreshing the preset library fails',
    (tester) async {
      final core = TestCore()..registerSuccess = true;
      final state = AppState(core);
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light),
          home: RegistrationPage(state: state),
        ),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      for (final entry in [
        (0, 'example_user'),
        (1, 'example-password'),
        (2, 'example-password'),
        (3, 'ABCD'),
      ]) {
        await tester.enterText(fields.at(entry.$1), entry.$2);
      }
      await tester.ensureVisible(find.text('注册并登录'));
      await tester.tap(find.text('注册并登录'));
      await tester.pumpAndSettle();
      expect(state.session['verified'], isTrue);
      expect(
        state.session['user']['id'],
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      );
      expect(find.text('注册成功，已登录'), findsOneWidget);
      expect(core.challenges, 1);
      expect(
        core.calls.where((call) => call.$1 == 'account.register'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'An expired challenge refreshes the proof and visibly retains the failure',
    (tester) async {
      final core = TestCore()..expiredChallenge = true;
      await tester.pumpWidget(
        MaterialApp(home: RegistrationPage(state: AppState(core))),
      );
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      for (final entry in [
        (0, 'example_user'),
        (1, 'example-password'),
        (2, 'example-password'),
        (3, 'ABCD'),
      ]) {
        await tester.enterText(fields.at(entry.$1), entry.$2);
      }
      await tester.ensureVisible(find.text('注册并登录'));
      await tester.tap(find.text('注册并登录'));
      await tester.pumpAndSettle();
      expect(core.challenges, 2);
      expect(find.textContaining('已更换验证码，请重新填写后注册。'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(fields.at(3)).controller!.text,
        isEmpty,
      );
      expect(
        tester.widget<TextFormField>(fields.at(1)).controller!.text,
        'example-password',
      );
    },
  );
  testWidgets('Online search can display a match beyond the loaded feed page', (
    tester,
  ) async {
    final core = TestCore();
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.light),
        home: LibraryPage(state: AppState(core)),
      ),
    );
    await tester.tap(find.text('在线预设'));
    await tester.pumpAndSettle();
    expect(find.text('第一页预设'), findsOneWidget);
    await tester.tap(find.byTooltip('搜索预设'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '远处');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('远处的蓝'), findsOneWidget);
    expect(find.text('第一页预设'), findsNothing);
    final search = core.calls.lastWhere((call) => call.$1 == 'online.search');
    expect(search.$2['query'], '远处');
    expect(tester.takeException(), isNull);
  });
}
