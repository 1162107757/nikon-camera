import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/community_state.dart';
import 'package:huevia/domain.dart';

const ownerA = '11111111-1111-4111-8111-111111111111';
const ownerB = '22222222-2222-4222-8222-222222222222';
const presetId = '33333333-3333-4333-8333-333333333333';
const firstId = '44444444-4444-4444-8444-444444444444';
const secondId = '55555555-5555-4555-8555-555555555555';
const thirdId = '66666666-6666-4666-8666-666666666666';
const fourthId = '77777777-7777-4777-8777-777777777777';
const rootId = '88888888-8888-4888-8888-888888888888';

class CommunityTestCore extends HueviaCore {
  final calls = <(String, Json)>[];
  late FutureOr<Json> Function(String, Json) handler;
  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) async {
    final snapshot = object(jsonDecode(jsonEncode(payload)));
    calls.add((operation, snapshot));
    return await handler(operation, snapshot);
  }
}

class CommunityTestState extends AppState {
  CommunityTestState(super.core) {
    session = {
      'user': {'id': ownerA},
    };
  }
  void setOwner(String id) {
    session = id.isEmpty
        ? {}
        : {
            'user': {'id': id},
          };
    notifyListeners();
  }
}

Json row(String id, {bool read = false}) => {
  'id': id,
  'read': read,
  'text': id,
  'author': {'id': ownerA, 'nickname': '甲'},
};

void main() {
  late CommunityTestCore core;
  late CommunityTestState state;
  late CommunityApi api;
  setUp(() {
    core = CommunityTestCore();
    state = CommunityTestState(core);
    api = CommunityApi(state);
  });
  tearDown(() => state.dispose());

  test('Reply recipient uses the explicit target and unavailable marker', () {
    final root = row(rootId);
    expect(communityRecipient({'parentId': rootId}, root), '甲');
    expect(communityRecipient({'parentId': firstId}, root), '原评论');
    expect(
      communityRecipient({
        'parentId': rootId,
        'replyTo': {
          'author': {'nickname': '乙'},
        },
      }, root),
      '乙',
    );
    expect(
      communityRecipient({
        'replyTo': {'available': false},
      }, root),
      '已不可用的评论',
    );
    expect(() => communityId('../comment'), throwsA(isA<AppFailure>()));
    expect(communityId(communityKey()), hasLength(36));
  });

  test('Concurrent comment confirmation sends once and cannot reuse another owner receipt', () async {
    final result = Completer<Json>();
    core.handler = (_, _) => result.future;
    final draft = CommunityCommentDraft(owner: ownerA, presetId: presetId)
      ..edit('使用感受');
    final a = draft.send(api), b = draft.send(api);
    expect(core.calls, hasLength(1));
    final payload = core.calls.single.$2;
    expect(payload['ownerId'], ownerA);
    expect(object(payload['body'])['text'], '使用感受');
    expect(
      communityId(object(payload['body'])['idempotencyKey'] as String),
      hasLength(36),
    );
    result.complete({'comment': row(firstId)});
    await Future.wait([a, b]);
    await draft.send(api);
    expect(core.calls, hasLength(1));
    state.setOwner(ownerB);
    await expectLater(draft.send(api), throwsA(isA<CommunityStale>()));
    expect(core.calls, hasLength(1));
  });

  test(
    'Failed comment retry retains its key; editing creates a new reviewed body',
    () async {
      var attempt = 0;
      core.handler = (_, _) {
        if (attempt++ == 0) throw const AppFailure('网络中断');
        return {'comment': row(firstId)};
      };
      final draft = CommunityCommentDraft(owner: ownerA, presetId: presetId)
        ..edit(' 感受 ');
      await expectLater(draft.send(api), throwsA(isA<AppFailure>()));
      final first = object(core.calls.first.$2['body']);
      await draft.send(api);
      expect(object(core.calls[1].$2['body']), first);
      draft.edit('新的感受');
      await draft.send(api);
      expect(
        object(core.calls[2].$2['body'])['idempotencyKey'],
        isNot(first['idempotencyKey']),
      );
      expect(object(core.calls[2].$2['body'])['text'], '新的感受');
    },
  );

  test('Account change rejects an in-flight comment result and invalid reply IDs never send', () async {
    final response = Completer<Json>();
    core.handler = (_, _) => response.future;
    final draft = CommunityCommentDraft(owner: ownerA, presetId: presetId)
      ..edit('旧账号');
    final result = expectLater(draft.send(api), throwsA(isA<CommunityStale>()));
    state.setOwner(ownerB);
    response.complete({'comment': row(firstId)});
    await result;
    final badReply = CommunityCommentDraft(
      owner: ownerB,
      presetId: presetId,
      parentId: rootId,
      replyToId: '../other',
    )..edit('回复');
    await expectLater(badReply.send(api), throwsA(isA<AppFailure>()));
    expect(core.calls, hasLength(1));
  });

  test('Private list switches owner without allowing an old page to replace the new request', () async {
    final a = Completer<Json>(), b = Completer<Json>();
    core.handler = (_, p) => p['ownerId'] == ownerA ? a.future : b.future;
    final list = CommunityCollection(api, CommunityCollectionKind.messages);
    addTearDown(list.dispose);
    final old = list.refresh();
    expect(core.calls.single.$2['ownerId'], ownerA);
    state.setOwner(ownerB);
    await Future<void>.delayed(Duration.zero);
    expect(core.calls.last.$2['ownerId'], ownerB);
    a.complete({
      'items': [row(firstId)],
      'total': 1,
      'unread': 1,
    });
    await old;
    expect(list.items, isEmpty);
    expect(list.busy, isTrue);
    b.complete({
      'items': [row(secondId)],
      'total': 1,
      'unread': 1,
    });
    await Future<void>.delayed(Duration.zero);
    expect(list.items.single['id'], secondId);
    expect(list.busy, isFalse);
    expect(list.error, isNull);
    state.setOwner('');
    expect(list.items, isEmpty);
    expect(list.unread, 0);
    await Future<void>.delayed(Duration.zero);
    expect(core.calls, hasLength(2));
  });

  test('Failed next page preserves rows and retries the same page with duplicate IDs merged', () async {
    var failed = false;
    core.handler = (_, p) {
      final page = Uri.parse('https://example.test${p['path']}')
          .queryParameters['page'];
      if (page == '1') {
        return {
          'items': [row(firstId)],
          'total': 3,
        };
      }
      if (!failed) {
        failed = true;
        throw const AppFailure('断网');
      }
      return {
        'items': [row(firstId), row(secondId)],
        'total': 2,
      };
    };
    final list = CommunityCollection(api, CommunityCollectionKind.submissions);
    addTearDown(list.dispose);
    await list.refresh();
    await list.load(append: true);
    expect(list.page, 1);
    expect(list.items, hasLength(1));
    expect(list.error, isNotNull);
    await list.load(append: true);
    expect(list.page, 2);
    expect(list.items.map((v) => v['id']), [firstId, secondId]);
    expect(list.hasMore, isFalse);
    expect(
      core.calls.map(
        (v) =>
            Uri.parse('https://example.test${v.$2['path']}')
                .queryParameters['page'],
      ),
      ['1', '2', '2'],
    );
  });

  test('Reply previews do not skip page one and a wrong response page never advances the cursor', () async {
    var badPage = true;
    core.handler = (_, p) {
      final path = p['path'] as String;
      if (path.contains('/presets/')) {
        return {
          'items': [
            {
              ...row(rootId),
              'replies': [row(firstId)],
              'replyCount': 3,
            },
          ],
          'total': 1,
        };
      }
      final page = Uri.parse('https://example.test$path')
          .queryParameters['page'];
      if (page == '1') {
        return {
          'items': [row(firstId), row(secondId)],
          'total': 3,
          'page': 1,
        };
      }
      if (badPage) {
        badPage = false;
        return {
          'items': [row(thirdId)],
          'total': 3,
          'page': 1,
        };
      }
      return {
        'items': [row(thirdId)],
        'total': 3,
        'page': 2,
      };
    };
    final discussion = CommunityDiscussion(api, presetId);
    addTearDown(discussion.dispose);
    await discussion.refresh();
    final root = discussion.comments.single;
    await discussion.loadReplies(root);
    expect((root['replies'] as List).length, 2);
    await discussion.loadReplies(root);
    expect((root['replies'] as List).length, 2);
    expect(discussion.error, isNotNull);
    await discussion.loadReplies(root);
    expect((root['replies'] as List).map((v) => v['id']), [
      firstId,
      secondId,
      thirdId,
    ]);
    expect(
      core.calls
          .skip(1)
          .map(
            (v) =>
                Uri.parse('https://example.test${v.$2['path']}')
                    .queryParameters['page'],
          ),
      ['1', '2', '2'],
    );
  });

  test('Read acknowledgements survive paging but cannot replace a newer unread count', () async {
    final ack = Completer<Json>();
    core.handler = (op, p) {
      if (op == 'community.write') return ack.future;
      final page = Uri.parse('https://example.test${p['path']}')
          .queryParameters['page'];
      return page == '1'
          ? {
              'items': [row(firstId), row(secondId)],
              'total': 3,
              'unread': 5,
            }
          : {
              'items': [row(thirdId)],
              'total': 3,
              'unread': 9,
            };
    };
    final list = CommunityCollection(api, CommunityCollectionKind.messages);
    addTearDown(list.dispose);
    await list.refresh();
    final reading = list.markDisplayedRead();
    expect(list.pendingReads, {firstId, secondId});
    await list.load(append: true);
    ack.complete({
      'readIds': [firstId],
      'unread': 4,
    });
    await reading;
    expect(list.items.first['read'], true);
    expect(list.items[1]['read'], false);
    expect(list.unread, 9);
    expect(list.pendingReads, isEmpty);
  });

  test(
    'Malformed read acknowledgement does not mark unrelated messages read',
    () async {
      core.handler = (op, _) => op == 'community.get'
          ? {
              'items': [row(firstId)],
              'total': 1,
              'unread': 2,
            }
          : {
              'readIds': [fourthId],
              'unread': 0,
            };
      final list = CommunityCollection(api, CommunityCollectionKind.messages);
      addTearDown(list.dispose);
      await list.refresh();
      await list.markDisplayedRead();
      expect(list.items.single['read'], false);
      expect(list.unread, 2);
      expect(list.error, contains('暂未同步'));
      expect(list.pendingReads, isEmpty);
    },
  );

  test('Read-all accepts the server acknowledgement and refreshes the real unread count', () async {
    core.handler = (op, p) => op == 'community.write'
        ? {'ok': true}
        : {
            'items': [row(firstId, read: true)],
            'total': 1,
            'unread': 2,
          };
    final list = CommunityCollection(api, CommunityCollectionKind.messages);
    addTearDown(list.dispose);
    await list.refresh();
    await list.markAllRead();
    expect(list.error, isNull);
    expect(list.items.single['read'], true);
    expect(list.unread, 2);
    expect(communityUnread(state).count, 2);
  });

  test('Single read acknowledgement refreshes the badge without assuming a returned count', () async {
    core.handler = (op, p) => op == 'community.write'
        ? {'ok': true}
        : p['path'] == '/community/messages/unread'
        ? {'unread': 3}
        : {
            'items': [row(firstId)],
            'total': 1,
            'unread': 4,
          };
    final list = CommunityCollection(api, CommunityCollectionKind.messages);
    addTearDown(list.dispose);
    await list.refresh();
    await list.acknowledgeMessage(list.items.single);
    await Future<void>.delayed(Duration.zero);
    expect(list.items.single['read'], true);
    expect(communityUnread(state).count, 3);
  });

  test('Disposed discussion ignores a pending page and never schedules another request', () async {
    final response = Completer<Json>();
    core.handler = (_, _) => response.future;
    final discussion = CommunityDiscussion(api, presetId);
    final loading = discussion.refresh();
    discussion.dispose();
    response.complete({
      'items': [row(firstId)],
      'total': 1,
    });
    await loading;
    state.setOwner(ownerB);
    await Future<void>.delayed(Duration.zero);
    expect(discussion.comments, isEmpty);
    expect(core.calls, hasLength(1));
  });
}
