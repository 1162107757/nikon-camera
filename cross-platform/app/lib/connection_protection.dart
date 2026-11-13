import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'domain.dart';

/// Android owns a connected-device foreground service. iOS grants finite
/// finishing time and explicitly expires it; neither platform replays a shot.
class CameraConnectionProtection extends ChangeNotifier
    with WidgetsBindingObserver {
  CameraConnectionProtection(this.core) {
    WidgetsBinding.instance.addObserver(this);
  }
  static const channel = MethodChannel('cc.huevia/connection-protection');
  static const events = EventChannel('cc.huevia/connection-protection-events');
  final HueviaCore core;
  Json status = {};
  final Set<String> actors = {};
  StreamSubscription<dynamic>? subscription;
  bool alive = true;
  bool get enabled => status['enabled'] == true;
  bool get available => status['available'] == true;
  bool get backgroundAllowed => enabled && status['backgroundAllowed'] == true;
  bool get limited => status['limited'] == true;
  String? get warning => status['warning'] as String?;
  bool get native => core.platform == 'android' || core.platform == 'ios';
  Future<Json> invoke(String method, [Json payload = const {}]) async {
    final value = await channel.invokeMethod<String>(method, payload);
    return value == null ? {} : object(jsonDecode(value));
  }

  void accept(dynamic value) {
    if (!alive) return;
    if (value is String) value = jsonDecode(value);
    if (value is Map) {
      status = object(value);
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    if (!native || !alive) return;
    subscription ??= events.receiveBroadcastStream().listen(
      accept,
      onError: (Object failure) {
        if (alive) {
          status = {
            ...status,
            'backgroundAllowed': false,
            'warning': '$failure',
          };
          notifyListeners();
        }
      },
    );
    try {
      accept(await invoke('status'));
    } catch (failure) {
      accept({
        'enabled': false,
        'available': false,
        'backgroundAllowed': false,
        'warning': '后台连接组件暂不可用：$failure',
      });
    }
  }

  Future<void> setEnabled(bool enabled) async {
    if (!native || !alive) return;
    accept(
      await invoke('set', {'enabled': enabled, 'active': actors.isNotEmpty}),
    );
  }

  Future<void> setActive(String actor, bool active) async {
    if (!alive) return;
    if (active) {
      actors.add(actor);
    } else {
      actors.remove(actor);
    }
    if (!native) return;
    try {
      accept(await invoke('set', {'active': actors.isNotEmpty}));
    } catch (failure) {
      accept({
        ...status,
        'backgroundAllowed': false,
        'warning': '连接保护未启动：$failure',
      });
    }
  }

  Future<void> openBatterySettings() async {
    if (native) await invoke('batterySettings');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (native && alive) {
      unawaited(
        invoke('foreground', {
          'foreground': state == AppLifecycleState.resumed,
        }).then(accept).catchError((Object _) {}),
      );
    }
  }

  @override
  void dispose() {
    if (native) {
      unawaited(
        invoke('set', {
          'active': false,
        }).catchError((Object _) => <String, dynamic>{}),
      );
    }
    alive = false;
    unawaited(subscription?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class ConnectionProtectionPage extends StatefulWidget {
  const ConnectionProtectionPage({super.key, required this.state});
  final AppState state;
  @override
  State<ConnectionProtectionPage> createState() =>
      _ConnectionProtectionPageState();
}

class _ConnectionProtectionPageState extends State<ConnectionProtectionPage> {
  bool busy = false;
  CameraConnectionProtection get protection =>
      widget.state.connectionProtection;
  @override
  void initState() {
    super.initState();
    unawaited(protection.initialize());
  }

  Future<void> enable(bool value) async {
    setState(() => busy = true);
    try {
      await protection.setEnabled(value);
    } catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$failure')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('后台连接与任务恢复')),
    body: AnimatedBuilder(
      animation: protection,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              widget.state.core.platform == 'ios' ? '离开应用时收尾并保留进度' : '后台接收保护',
            ),
            subtitle: Text(
              widget.state.core.platform == 'ios'
                  ? '使用系统允许的有限后台时间，到期自动暂停。回到应用后核对相机并继续。'
                  : '接收时显示持续通知并保持设备连接。可在通知中停止；系统终止后从保存的队列恢复。',
            ),
            value: protection.enabled,
            onChanged: busy || !protection.available ? null : enable,
          ),
          const SizedBox(height: 16),
          Text(
            protection.backgroundAllowed
                ? protection.limited
                      ? '系统已授予本次收尾时间'
                      : '后台连接保护正在运行'
                : '当前未执行后台接收',
          ),
          if (protection.warning != null)
            Text(
              protection.warning!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 16),
          const Text(
            '原片接收、保存位置和完成收据会写入本机。恢复时只继续未完成项；没有可信相机身份时需要手动核对。遥控快门、预设写入或删除不会在重开后自动重做。',
          ),
          if (widget.state.core.platform == 'android')
            TextButton(
              onPressed: busy ? null : protection.openBatterySettings,
              child: const Text('打开系统电池设置'),
            ),
        ],
      ),
    ),
  );
}
