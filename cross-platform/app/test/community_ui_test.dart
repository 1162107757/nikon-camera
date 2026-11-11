import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/community.dart';
import 'package:huevia/community_state.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';
import 'package:huevia/widgets.dart';

import 'community_state_test.dart'
    show
        CommunityTestCore,
        CommunityTestState,
        ownerA,
        ownerB,
        presetId,
        firstId,
        row;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> showDiscussion(
    WidgetTester tester,
    CommunityTestState state,
    Size size,
    double scale,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: hueviaTheme(Brightness.light, home: false),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              child: CommunityDiscussionView(state: state, presetId: presetId),
            ),
          ),
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
      'Comment modal clears private text after account switch at $setting',
      (tester) async {
        final core = CommunityTestCore();
        final state = CommunityTestState(core);
        addTearDown(state.dispose);
        core.handler = (operation, payload) {
          if (operation == 'community.get') {
            return {
              'items': [row(firstId)],
              'total': 1,
            };
          }
          throw StateError('A stale dialog must never write');
        };
        await showDiscussion(tester, state, setting.$1, setting.$2);
        await tester.tap(find.text('发表评论'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '只属于旧账号的草稿');
        state.setOwner(ownerB);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(find.text('账号已改变，请关闭后重试。'), findsOneWidget);
        final send = find.widgetWithText(TextButton, '发送');
        expect(tester.widget<TextButton>(send).onPressed, isNull);
        expect(
          tester.getBottomRight(send).dy,
          lessThanOrEqualTo(setting.$1.height),
        );
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(core.calls.where((v) => v.$1 == 'community.write'), isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'Comment send failure preserves the reviewed text and retry key',
    (tester) async {
      final core = CommunityTestCore();
      final state = CommunityTestState(core);
      addTearDown(state.dispose);
      var writes = 0;
      core.handler = (operation, payload) {
        if (operation == 'community.get') return {'items': [], 'total': 0};
        if (writes++ == 0) throw const AppFailure('网络中断，请重试');
        return {
          'comment': {...row(firstId), 'status': 'pending'},
        };
      };
      await showDiscussion(tester, state, const Size(375, 812), 1);
      await tester.tap(find.text('发表评论'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '我的使用感受');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(find.text('网络中断，请重试'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '我的使用感受',
      );
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('评论已提交，审核后展示'), findsOneWidget);
      final requests = core.calls
          .where((v) => v.$1 == 'community.write')
          .toList();
      expect(requests, hasLength(2));
      expect(object(requests[0].$2['body']), object(requests[1].$2['body']));
      expect(requests.every((v) => v.$2['ownerId'] == ownerA), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Root message page retains read failure and never retries it in a build loop',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final core = CommunityTestCore();
      final state = CommunityTestState(core);
      addTearDown(state.dispose);
      var readCalls = 0, allRead = false;
      core.handler = (operation, payload) {
        if (operation == 'community.get') {
          return {
            'items': [
              {
                ...row(firstId, read: allRead),
                'type': 'reply',
                'text': '你好',
                'presetId': presetId,
              },
            ],
            'total': 1,
            'unread': allRead ? 0 : 1,
          };
        }
        if ((payload['path'] as String).endsWith('read-all')) {
          allRead = true;
          return {'unread': 0};
        }
        readCalls++;
        throw const AppFailure('暂时断网');
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.dark),
          home: Builder(
            builder: (context) => Scaffold(
              bottomNavigationBar: const SizedBox(
                height: 96,
                child: Text('root navigation'),
              ),
              body: Center(
                child: TextButton(
                  onPressed: () => hueRootPage<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CommunityCollectionPage(
                        state: state,
                        kind: CommunityCollectionKind.messages,
                        openSubmission: (_, _) async {},
                      ),
                    ),
                  ),
                  child: const Text('打开消息'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开消息'));
      await tester.pumpAndSettle();
      expect(readCalls, 1);
      expect(find.textContaining('已读状态暂未同步'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(readCalls, 1);
      await tester.tap(find.text('全部已读'));
      await tester.pumpAndSettle();
      expect(find.text('没有未读消息'), findsOneWidget);
      expect(readCalls, 1);
      expect(find.textContaining('已读状态暂未同步'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'Submission next page replaces rows and stops at the actual final page',
    (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final core = CommunityTestCore();
      final state = CommunityTestState(core);
      addTearDown(state.dispose);
      core.handler = (_, payload) {
        final page = Uri.parse('https://example.test${payload['path']}')
            .queryParameters['page'];
        Json item(int index) => {
          'id':
              '99999999-9999-4999-8999-${index.toRadixString(16).padLeft(12, '0')}',
          'name': '投稿$index',
          'status': 'draft',
          'updatedAt': '2026-11-12T00:00:00Z',
        };
        return {
          'items': page == '1' ? List.generate(20, item) : [item(20)],
          'total': 21,
        };
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: hueviaTheme(Brightness.light, home: false),
          home: CommunityCollectionPage(
            state: state,
            kind: CommunityCollectionKind.submissions,
            openSubmission: (_, _) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('下一页'),
        400,
        continuous: true,
        scrollable: find.byType(Scrollable).last,
        maxScrolls: 30,
      );
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('投稿20'), findsOneWidget);
      expect(find.text('投稿0'), findsNothing);
      expect(find.text('下一页'), findsNothing);
      expect(find.text('上一页'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
