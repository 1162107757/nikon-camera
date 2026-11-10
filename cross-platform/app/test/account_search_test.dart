import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/library.dart';
import 'package:huevia/registration.dart';
import 'package:huevia/theme.dart';

class TestCore extends HueviaCore {
  int challenges = 0;
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
          'image': 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO3R9v8AAAAASUVORK5CYII=',
        };
      case 'account.register':
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
    await tester.enterText(find.byType(TextField), '远处');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('远处的蓝'), findsOneWidget);
    expect(find.text('第一页预设'), findsNothing);
    expect(core.calls.last.$1, 'online.search');
    expect(core.calls.last.$2['query'], '远处');
    expect(tester.takeException(), isNull);
  });
}
