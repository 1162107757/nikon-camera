import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'domain.dart';

String communityId(String value) {
  if (!RegExp(r'^[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$')
      .hasMatch(value)) {
    throw const AppFailure('内容标识无效，请刷新后重试。');
  }
  return value;
}

String communityKey() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String communityText(Json value, String key) => value[key] is String
    ? (value[key] as String).substring(
        0,
        min(4096, (value[key] as String).length),
      )
    : '';

String communityAuthor(Json value) {
  final author = value['author'];
  final name = author is Map ? communityText(object(author), 'nickname') : '';
  return name.isEmpty ? '用户' : name;
}

String communityRecipient(Json reply, Json root) {
  final target = reply['replyTo'];
  if (target is Map) {
    return target['available'] == false
        ? '已不可用的评论'
        : communityAuthor(object(target));
  }
  return root['id'] == reply['parentId'] ? communityAuthor(root) : '原评论';
}

List<Json> communityItems(Json result) {
  final items = result['items'];
  if (items is! List || items.length > 200 || items.any((v) => v is! Map)) {
    throw const AppFailure('列表响应无效，请重试。');
  }
  return items.map((v) {
    final row = object(v);
    communityId(communityText(row, 'id'));
    if (row['replies'] != null) {
      final replies = row['replies'];
      if (replies is! List ||
          replies.length > 200 ||
          replies.any((v) => v is! Map)) {
        throw const AppFailure('评论响应无效，请重试。');
      }
      for (final reply in replies) {
        communityId(communityText(object(reply), 'id'));
      }
    }
    return row;
  }).toList();
}

List<Json> communityReplies(Json row) => row['replies'] is List
    ? (row['replies'] as List).whereType<Map>().map(object).toList()
    : [];

List<Json> communityMerge(List<Json> previous, List<Json> incoming) => {
  for (final item in previous) communityText(item, 'id'): item,
  for (final item in incoming) communityText(item, 'id'): item,
}.values.toList();

class CommunityStale implements Exception {
  const CommunityStale();
  @override
  String toString() => '账号或页面已改变，请重新打开。';
}

class CommunityApi {
  CommunityApi(this.state);
  final AppState state;
  String get owner => state.session['logoutPending'] == true
      ? ''
      : state.session['user']?['id'] as String? ?? '';

  Future<Json> read(String path, {bool login = false}) async {
    final expected = owner;
    if (login && expected.isEmpty) throw const AppFailure('请先登录账号。');
    final result = await state.core.call('community.get', {
      'path': path,
      'login': login,
      if (login) 'ownerId': expected,
    });
    if (owner != expected) throw const CommunityStale();
    return result;
  }

  Future<Json> write(
    String path,
    Json body,
    String expected, {
    String method = 'POST',
  }) async {
    if (expected.isEmpty) throw const AppFailure('请先登录账号。');
    if (owner != expected) throw const CommunityStale();
    final result = await state.core.call('community.write', {
      'path': path,
      'method': method,
      'body': body,
      'ownerId': expected,
    });
    if (owner != expected) throw const CommunityStale();
    return result;
  }
}

final _communityUnread = Expando<CommunityUnread>();
CommunityUnread communityUnread(AppState state) =>
    _communityUnread[state] ??= CommunityUnread(state);

class CommunityUnread extends ChangeNotifier {
  CommunityUnread(this.state);
  final AppState state;
  String _owner = '';
  int count = 0, _revision = 0;
  void syncOwner() {
    final owner = CommunityApi(state).owner;
    if (_owner == owner) return;
    _owner = owner;
    count = 0;
    _revision++;
    notifyListeners();
  }

  int begin() {
    syncOwner();
    return ++_revision;
  }

  void accept(int revision, Object? value) {
    if (revision != _revision ||
        _owner != CommunityApi(state).owner ||
        _owner.isEmpty ||
        value is! int ||
        value < 0) {
      return;
    }
    count = min(9999, value);
    notifyListeners();
  }

  Future<void> refresh() async {
    final revision = begin();
    if (_owner.isEmpty) return;
    try {
      final result = await CommunityApi(state)
          .read('/community/messages/unread', login: true);
      accept(revision, result['unread'] ?? result['count']);
    } catch (_) {
      /* Keep the last confirmed count until the next foreground refresh. */
    }
  }
}

/// Keeps one idempotency key for a retry of the same reviewed comment.
class CommunityCommentDraft {
  CommunityCommentDraft({
    required this.owner,
    required this.presetId,
    this.parentId = '',
    this.replyToId = '',
    this.recipient = '',
  });
  final String owner, presetId, parentId, replyToId, recipient;
  String text = '', key = communityKey();
  int revision = 0;
  Future<Json>? _inFlight;
  Json? _sent;
  bool get sending => _inFlight != null;
  void edit(String value) {
    if (value == text) return;
    text = value;
    key = communityKey();
    revision++;
    _sent = null;
  }

  void clear() => edit('');
  Future<Json> send(CommunityApi api) async {
    if (api.owner != owner || owner.isEmpty) throw const CommunityStale();
    if (_sent != null) return _sent!;
    if (_inFlight != null) return _inFlight!;
    edit(text.trim());
    if (text.isEmpty || text.runes.length > 500) {
      throw const AppFailure('请输入 1–500 字的内容。');
    }
    final snapshot = revision;
    final body = <String, dynamic>{
      'text': text,
      'idempotencyKey': key,
      if (parentId.isNotEmpty) 'parentId': communityId(parentId),
      if (parentId.isNotEmpty) 'replyToId': communityId(replyToId),
    };
    final future = api.write(
      '/community/presets/${communityId(presetId)}/comments',
      body,
      owner,
    );
    _inFlight = future;
    try {
      final result = await future;
      if (api.owner != owner) throw const CommunityStale();
      if (revision == snapshot) _sent = result;
      return result;
    } finally {
      if (identical(_inFlight, future)) _inFlight = null;
    }
  }
}

abstract class CommunityController extends ChangeNotifier {
  CommunityController(this.api) {
    _owner = api.owner;
    api.state.addListener(_accountChanged);
  }
  final CommunityApi api;
  String _owner = '';
  bool disposed = false, busy = false, loaded = false;
  String? error;
  int generation = 0;
  bool accepts(int token) => !disposed && token == generation;
  void _accountChanged() {
    if (_owner == api.owner) return;
    _owner = api.owner;
    generation++;
    busy = false;
    loaded = false;
    error = null;
    clearForAccount();
    notifyListeners();
    scheduleMicrotask(() {
      if (!disposed) unawaited(refresh());
    });
  }

  void clearForAccount();
  Future<void> refresh();
  @override
  void dispose() {
    disposed = true;
    generation++;
    api.state.removeListener(_accountChanged);
    super.dispose();
  }
}

class CommunityDiscussion extends CommunityController {
  CommunityDiscussion(super.api, this.presetId, {this.focusCommentId = ''}) {
    communityId(presetId);
    if (focusCommentId.isNotEmpty) communityId(focusCommentId);
  }
  final String presetId;
  String focusCommentId;
  List<Json> comments = [];
  final Map<String, int> _replyPages = {};
  int page = 0;
  bool hasMore = false, showingFocusedThread = false;
  @override
  void clearForAccount() {
    comments = [];
    _replyPages.clear();
    page = 0;
    hasMore = false;
  }

  @override
  Future<void> refresh() => load();
  Future<void> load({bool append = false}) async {
    if (busy || disposed) return;
    final token = ++generation, next = append ? page + 1 : 1;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await api.read(
        '/community/presets/$presetId/comments?page=$next&pageSize=20${!append && focusCommentId.isNotEmpty ? '&focusCommentId=$focusCommentId' : ''}',
      );
      if (!accepts(token)) return;
      final rows = communityItems(result);
      comments = communityMerge(append ? comments : [], rows);
      if (!append) _replyPages.clear();
      page = next;
      hasMore =
          result['hasMore'] == true ||
          (result['total'] is num &&
              comments.length < (result['total'] as num));
      if (!append) {
        showingFocusedThread =
            focusCommentId.isNotEmpty && result['focusAvailable'] != false;
        if (result['focusAvailable'] == false) {
          focusCommentId = '';
          error = '这条评论已删除或隐藏，可以重新加载查看其他交流。';
        }
      }
      loaded = true;
    } catch (failure) {
      if (accepts(token) && failure is! CommunityStale) error = '$failure';
    } finally {
      if (accepts(token)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadReplies(Json root) async {
    if (busy || disposed) return;
    final id = communityId(communityText(root, 'id'));
    final next = _replyPages[id] ?? 1, token = ++generation;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await api.read(
        '/community/comments/$id/replies?page=$next&pageSize=20',
      );
      if (!accepts(token)) return;
      final total = result['total'], responsePage = result['page'];
      if (responsePage != next || total is! int || total < 0) {
        throw const AppFailure('回复分页响应无效，请刷新评论后重试。');
      }
      final previous = (root['replies'] as List? ?? []).map(object).toList();
      final merged = communityMerge(previous, communityItems(result));
      if (merged.length > total) throw const AppFailure('回复已变化，请刷新评论后重试。');
      root['replies'] = merged;
      root['replyCount'] = total;
      _replyPages[id] = next + 1;
    } catch (failure) {
      if (accepts(token) && failure is! CommunityStale) error = '$failure';
    } finally {
      if (accepts(token)) {
        busy = false;
        notifyListeners();
      }
    }
  }
}

enum CommunityCollectionKind { messages, submissions }

class CommunityCollection extends CommunityController {
  CommunityCollection(super.api, this.kind);
  final CommunityCollectionKind kind;
  List<Json> items = [];
  int page = 0, unread = 0;
  int _readRevision = 0;
  bool hasMore = false;
  final Set<String> pendingReads = {};
  @override
  void clearForAccount() {
    items = [];
    page = 0;
    unread = 0;
    hasMore = false;
    pendingReads.clear();
    _readRevision++;
  }

  @override
  Future<void> refresh() => load();
  Future<void> load({bool append = false, int? targetPage}) async {
    if (busy || disposed || api.owner.isEmpty) return;
    final token = ++generation, next = targetPage ?? (append ? page + 1 : 1);
    if (next < 1) return;
    final readRevision = ++_readRevision;
    final unreadRevision = kind == CommunityCollectionKind.messages
        ? communityUnread(api.state).begin()
        : -1;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await api.read(
        '/community/${kind.name}?page=$next&pageSize=20',
        login: true,
      );
      if (!accepts(token)) return;
      final rows = communityItems(result);
      items = communityMerge(append ? items : [], rows);
      page = next;
      hasMore = result['total'] is num
          ? (next - 1) * 20 + rows.length < (result['total'] as num)
          : result['hasMore'] == true;
      final count = result['unread'];
      if (count is int && count >= 0 && readRevision == _readRevision) {
        unread = min(9999, count);
      }
      if (kind == CommunityCollectionKind.messages) {
        communityUnread(api.state).accept(unreadRevision, count);
      }
      loaded = true;
    } catch (failure) {
      if (accepts(token) && failure is! CommunityStale) error = '$failure';
    } finally {
      if (accepts(token)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> markDisplayedRead() async {
    if (kind != CommunityCollectionKind.messages || disposed) return;
    final owner = api.owner;
    final ids = items
        .where((v) => v['read'] != true && !pendingReads.contains(v['id']))
        .take(50)
        .map((v) => communityId(communityText(v, 'id')))
        .toList();
    if (owner.isEmpty || ids.isEmpty) return;
    final revision = ++_readRevision;
    final unreadRevision = communityUnread(api.state).begin();
    pendingReads.addAll(ids);
    try {
      final result = await api.write('/community/messages/read-batch', {
        'ids': ids,
      }, owner);
      if (disposed || api.owner != owner) return;
      final accepted = result['readIds'], count = result['unread'];
      if (accepted is! List ||
          accepted.length > 50 ||
          accepted.any((v) => v is! String || !ids.contains(v)) ||
          count is! int ||
          count < 0) {
        throw const AppFailure('已读状态暂未同步，请重新打开消息后重试。');
      }
      for (final row in items) {
        if (accepted.contains(row['id'])) row['read'] = true;
      }
      if (revision == _readRevision) unread = min(9999, count);
      communityUnread(api.state).accept(unreadRevision, count);
    } catch (failure) {
      if (!disposed && api.owner == owner && failure is! CommunityStale) {
        error = '已读状态暂未同步，请稍后重新打开消息或点击全部已读。';
      }
    } finally {
      if (!disposed && api.owner == owner) {
        pendingReads.removeAll(ids);
        notifyListeners();
      }
    }
  }

  Future<void> markAllRead() async {
    if (kind != CommunityCollectionKind.messages ||
        busy ||
        disposed ||
        api.owner.isEmpty) {
      return;
    }
    final owner = api.owner, token = ++generation;
    _readRevision++;
    final unreadRevision = communityUnread(api.state).begin();
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await api.write('/community/messages/read-all', {}, owner);
      if (!accepts(token)) return;
      final count = result['unread'];
      if (count is int && count >= 0) {
        unread = min(9999, count);
        communityUnread(api.state).accept(unreadRevision, count);
      } else if (result['ok'] != true) {
        throw const AppFailure('已读状态响应不完整，请重试。');
      }
      for (final row in items) {
        row['read'] = true;
      }
      busy = false;
      await refresh();
    } catch (failure) {
      if (accepts(token) && failure is! CommunityStale) error = '$failure';
    } finally {
      if (accepts(token)) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> acknowledgeMessage(Json item) async {
    final owner = api.owner;
    if (disposed || owner.isEmpty) throw const CommunityStale();
    final revision = ++_readRevision;
    final unreadRevision = communityUnread(api.state).begin();
    final result = await api.write(
      '/community/messages/${communityId(communityText(item, 'id'))}/read',
      {},
      owner,
    );
    if (disposed || api.owner != owner) throw const CommunityStale();
    if (result['ok'] != true &&
        (result['unread'] is! int || (result['unread'] as int) < 0)) {
      throw const AppFailure('已读状态响应不完整，请重试。');
    }
    communityUnread(api.state).accept(unreadRevision, result['unread']);
    if (result['unread'] == null) {
      unawaited(communityUnread(api.state).refresh());
    }
    if (revision == _readRevision) {
      final count = result['unread'];
      if (count is int && count >= 0) {
        unread = min(9999, count);
      } else if (item['read'] != true) {
        unread = max(0, unread - 1);
      }
    }
    item['read'] = true;
    notifyListeners();
  }
}
