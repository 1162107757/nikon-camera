import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/account_profile.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';

import 'community_state_test.dart'
    show CommunityTestCore, CommunityTestState, ownerA, ownerB, firstId;

const profileFirst = '2026-01-01T00:00:00.000Z',
    profileSecond = '2026-01-02T00:00:00.000Z';
Json profileSession({String owner = ownerA, String updatedAt = profileFirst}) =>
    {
      'user': {
        'id': owner,
        'username': 'alice',
        'nickname': '资料甲',
        'provider': 'password',
        'avatarUrl': '',
        'avatarSource': 'default',
        'createdAt': profileFirst,
        'lastLoginAt': profileFirst,
        'updatedAt': updatedAt,
      },
      'verified': true,
    };
Json avatarReceipt() => {
  'receipt': firstId,
  'path': '/fake/profile-pending/$ownerA/$firstId.jpg',
  'owner': ownerA,
  'updatedAt': profileFirst,
  'sha256': 'a' * 64,
  'bytes': 128,
};

class ProfileTestCore extends CommunityTestCore {
  Future<Json?> Function(String owner, String updatedAt)? picker;
  @override
  Future<Json?> pickAvatar({
    required String owner,
    required String updatedAt,
  }) => picker!(owner, updatedAt);
}

class ProfileTestState extends CommunityTestState {
  ProfileTestState(super.core) {
    session = profileSession();
  }
  @override
  Future<void> refreshSession() async {
    session = await core.call('account.current');
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Avatar uploads only after review and ignores a second concurrent confirmation', () async {
    final core = ProfileTestCore(), ack = Completer<Json>();
    final state = ProfileTestState(core), current = profileSession();
    var uploads = 0;
    core.picker = (_, _) async => avatarReceipt();
    core.handler = (op, p) {
      if (op == 'account.avatarCommit') {
        uploads++;
        return ack.future;
      }
      if (op == 'account.current') return current;
      return {};
    };
    final model = AccountProfileModel(state);
    expect(await model.pick(), true);
    expect(uploads, 0);
    final first = model.commit();
    expect(await model.commit(), false);
    current['user'] = profileSession(updatedAt: profileSecond)['user'];
    ack.complete({});
    expect(await first, true);
    expect(uploads, 1);
    expect(model.draft, isNull);
    model.dispose();
    state.dispose();
  });

  test(
    'Late avatar selection from another account is discarded without a write',
    () async {
      final core = ProfileTestCore(), selected = Completer<Json?>();
      final state = ProfileTestState(core);
      core.picker = (_, _) => selected.future;
      core.handler = (_, _) => {};
      final model = AccountProfileModel(state);
      final picking = model.pick();
      await Future<void>.delayed(Duration.zero);
      state.setOwner(ownerB);
      selected.complete(avatarReceipt());
      expect(await picking, false);
      expect(model.stale, true);
      expect(model.draft, isNull);
      expect(core.calls.where((c) => c.$1 == 'account.avatarCommit'), isEmpty);
      expect(
        core.calls
            .where((c) => c.$1 == 'account.avatarDiscard')
            .single
            .$2['owner'],
        ownerA,
      );
      model.dispose();
      state.dispose();
    },
  );

  test(
    'Failed avatar upload preserves the reviewed receipt for an explicit retry',
    () async {
      final core = ProfileTestCore(),
          state = ProfileTestState(ProfileTestCore());
      final actual = ProfileTestState(core);
      var current = profileSession(), uploads = 0;
      core.picker = (_, _) async => avatarReceipt();
      core.handler = (op, p) {
        if (op == 'account.current') return current;
        if (op == 'account.avatarCommit') {
          uploads++;
          if (uploads == 1) throw const AppFailure('网络中断');
          current = profileSession(updatedAt: profileSecond);
        }
        return {};
      };
      final model = AccountProfileModel(actual);
      await model.pick();
      expect(await model.commit(), false);
      expect(model.draft!['receipt'], firstId);
      expect(model.error, contains('网络中断'));
      expect(await model.commit(), true);
      final writes = core.calls
          .where((c) => c.$1 == 'account.avatarCommit')
          .toList();
      expect(writes.length, 2);
      expect(writes[0].$2, writes[1].$2);
      model.dispose();
      actual.dispose();
      state.dispose();
    },
  );

  Future<void> showProfile(
    WidgetTester tester,
    ProfileTestState state,
    Size size,
    double scale,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(scale == 2 ? Brightness.dark : Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: AccountProfileView(
          state: state,
          onLogout: (_) async {},
          onPrivacy: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final setting in [
    (const Size(375, 812), 1.0),
    (const Size(812, 375), 2.0),
  ]) {
    testWidgets(
      'Profile and avatar preview purge old account details at $setting',
      (tester) async {
        final core = ProfileTestCore(),
            state = ProfileTestState(ProfileTestCore());
        final actual = ProfileTestState(core);
        core.picker = (_, _) async => avatarReceipt();
        core.handler = (_, _) => {};
        await showProfile(tester, actual, setting.$1, setting.$2);
        expect(
          Theme.of(tester.element(find.byType(Scaffold)))
              .extension<HuePalette>()!
              .home,
          false,
        );
        expect(find.text('注册时间'), findsOneWidget);
        expect(find.text('最近登录'), findsOneWidget);
        await tester.tap(find.text('修改头像'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('从相册选择'));
        await tester.pumpAndSettle();
        expect(find.text('确认新头像'), findsOneWidget);
        expect(find.bySemanticsLabel('新头像预览'), findsOneWidget);
        actual.setOwner(ownerB);
        await tester.pump();
        expect(find.bySemanticsLabel('新头像预览'), findsNothing);
        expect(find.text('资料甲'), findsNothing);
        final save = tester.widget<TextButton>(
          find.widgetWithText(TextButton, '保存头像'),
        );
        expect(save.onPressed, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        actual.dispose();
        state.dispose();
      },
    );
  }

  testWidgets(
    'Logout confirmation cannot log out an account selected after the dialog opened',
    (tester) async {
      final core = ProfileTestCore(),
          state = ProfileTestState(ProfileTestCore());
      final actual = ProfileTestState(core);
      var logouts = 0;
      core.handler = (_, _) => {};
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light, home: false),
          home: AccountProfileView(
            state: actual,
            onLogout: (_) async {
              logouts++;
            },
            onPrivacy: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      final logout = find.widgetWithText(FilledButton, '退出登录');
      await tester.ensureVisible(logout);
      await tester.tap(logout);
      await tester.pumpAndSettle();
      actual.setOwner(ownerB);
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('退出登录'),
        ),
      );
      await tester.pumpAndSettle();
      expect(logouts, 0);
      await tester.pumpWidget(const SizedBox());
      actual.dispose();
      state.dispose();
    },
  );
}
