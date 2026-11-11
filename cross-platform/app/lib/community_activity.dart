import 'dart:async';

import 'package:flutter/material.dart';

import 'community_state.dart';
import 'domain.dart';

class CommunityActivity extends StatefulWidget {
  const CommunityActivity({
    super.key,
    required this.state,
    required this.child,
    this.pollInterval = const Duration(seconds: 60),
  });
  final AppState state;
  final Widget child;
  final Duration pollInterval;
  static int unreadOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_CommunityBadge>()
          ?.notifier
          ?.count ??
      0;
  @override
  State<CommunityActivity> createState() => _CommunityActivityState();
}

class _CommunityActivityState extends State<CommunityActivity>
    with WidgetsBindingObserver {
  late final unread = communityUnread(widget.state);
  Timer? timer;
  String owner = '';
  bool foreground = true;
  @override
  void initState() {
    super.initState();
    foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(sync);
    sync();
  }

  void sync({bool refresh = false}) {
    final next = CommunityApi(widget.state).owner;
    final changed = next != owner;
    owner = next;
    unread.syncOwner();
    if (!foreground || owner.isEmpty || !widget.state.ready) {
      timer?.cancel();
      timer = null;
      return;
    }
    if (timer == null || changed || refresh) unawaited(unread.refresh());
    timer ??= Timer.periodic(
      widget.pollInterval,
      (_) => unawaited(unread.refresh()),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    sync(refresh: foreground);
  }

  @override
  void dispose() {
    timer?.cancel();
    widget.state.removeListener(sync);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _CommunityBadge(notifier: unread, child: widget.child);
}

class _CommunityBadge extends InheritedNotifier<CommunityUnread> {
  const _CommunityBadge({required super.notifier, required super.child});
}
