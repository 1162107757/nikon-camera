import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'nikon_location_protocol.dart';
import 'theme.dart';

typedef _Camera = ({String id, String name});

class CameraLocationPage extends StatefulWidget {
  const CameraLocationPage({super.key});

  @override
  State<CameraLocationPage> createState() => _CameraLocationPageState();
}

class _CameraLocationPageState extends State<CameraLocationPage>
    with WidgetsBindingObserver {
  static const _native = MethodChannel('cc.huevia/camera-location');
  static const _events = EventChannel('cc.huevia/camera-location/events');
  static const _pairingKey = 'nikonLocationPairing.v1';
  static const _identityKey = 'nikonLocationPhone.v1';
  final _preferences = SharedPreferencesAsync();
  StreamSubscription<dynamic>? _subscription;
  List<_Camera> _cameras = [];
  String? _device, _problem;
  String _status = '等待连接';
  bool _busy = false, _connected = false;
  bool _foreground = true, _disposed = false;
  int _generation = 0;
  int? _pendingStage;
  Completer<Uint8List?>? _pendingPair;
  Completer<void>? _readySignal;
  Timer? _nextFix;
  DateTime? _lastSent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.paused && _connected) {
      unawaited(_stop('已暂停，请返回后重新连接'));
    }
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) throw const _OperationEnded();
  }

  void _event(dynamic event) {
    if (_disposed || event is! Map) return;
    final bytes = event['bytes'];
    if (event['type'] == 'disconnected' && (_connected || _busy)) {
      unawaited(_stop('相机蓝牙已断开'));
    } else if (bytes is Uint8List) {
      if (event['type'] == 'ready' &&
          bytes.length == 2 &&
          bytes[0] == 1 &&
          bytes[1] == 0) {
        final signal = _readySignal;
        if (signal != null && !signal.isCompleted) signal.complete();
      } else if (event['type'] == 'pair' &&
          bytes.isNotEmpty &&
          bytes.first == _pendingStage) {
        final waiting = _pendingPair;
        if (waiting != null && !waiting.isCompleted) waiting.complete(bytes);
      }
    }
  }

  Future<void> _write(String type, Uint8List bytes) =>
      _native.invokeMethod<void>('write', {'type': type, 'bytes': bytes});

  Future<Uint8List> _pairStep(int stage, Uint8List request) async {
    final pending = Completer<Uint8List?>();
    _pendingPair = pending;
    _pendingStage = stage;
    try {
      await _write('pair', request);
      final response = await pending.future.timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw const FormatException('相机配对等待超时。'),
      );
      if (response == null) throw const _OperationEnded();
      return response;
    } finally {
      if (identical(_pendingPair, pending)) {
        _pendingPair = null;
        _pendingStage = null;
      }
    }
  }

  Future<List<_Camera>> _discover() async {
    final results = await _native.invokeListMethod<Map<dynamic, dynamic>>(
      'scan',
    );
    return [
      for (final item in results ?? const [])
        if (item['id'] is String && item['name'] is String)
          (id: item['id'] as String, name: item['name'] as String),
    ];
  }

  Future<void> _scan() async {
    if (_busy || _connected) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _problem = null;
      _status = '正在搜索附近的尼康相机…';
      _cameras = [];
    });
    try {
      final found = await _discover();
      _check(generation);
      setState(() {
        _cameras = found;
        _status = found.isEmpty ? '没有找到相机' : '请选择你的相机';
        _busy = false;
      });
    } catch (error) {
      await _fail(generation, error);
    }
  }

  Future<String> _handshake(
    String id,
    Uint8List identity,
    int generation, {
    String? expectedSerial,
  }) async {
    final ready = Completer<void>();
    _readySignal = ready;
    await _native.invokeMethod<void>('connect', {'id': id});
    _check(generation);
    final nonce = NikonLocationProtocol.randomBytes();
    final challenge = await _pairStep(
      2,
      NikonLocationProtocol.hello(identity, nonce),
    );
    final response = await NikonLocationProtocol.respond(nonce, challenge, (
      block,
    ) async {
      _check(generation);
      final encrypted = await _native.invokeMethod<Uint8List>('encrypt', {
        'bytes': block,
      });
      if (encrypted == null) throw const FormatException('无法校验相机配对。');
      return encrypted;
    });
    _check(generation);
    final reply = await _pairStep(4, response);
    final serial = NikonLocationProtocol.confirm(reply);
    _check(generation);
    if (expectedSerial != null && expectedSerial != serial) {
      throw const FormatException('这不是之前确认的相机，请重新选择。');
    }
    await ready.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    _check(generation);
    await _write('name', NikonLocationProtocol.clientName());
    _check(generation);
    return serial;
  }

  Future<void> _connect(_Camera camera) async {
    if (_busy || _connected) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _problem = null;
      _device = camera.name;
      _status = '正在连接相机…';
      _lastSent = null;
    });
    try {
      _subscription ??= _events.receiveBroadcastStream().listen(
        _event,
        onError: (Object error) => unawaited(_fail(_generation, error)),
      );
      final savedIdentity = await _preferences.getString(_identityKey);
      final savedPairing = await _preferences.getString(_pairingKey);
      final identity = savedIdentity == null
          ? NikonLocationProtocol.createIdentity()
          : base64Decode(savedIdentity);
      if (savedIdentity == null) {
        await _preferences.setString(_identityKey, base64Encode(identity));
      }
      final saved = savedPairing == null ? null : jsonDecode(savedPairing);
      final serial =
          savedIdentity != null &&
              saved is Map &&
              saved['name'] == camera.name &&
              saved['serial'] is String
          ? saved['serial'] as String
          : null;
      _check(generation);
      final confirmed = await _handshake(
        camera.id,
        identity,
        generation,
        expectedSerial: serial,
      );
      if (serial == null) {
        setState(() => _status = '请在手机和相机上确认配对');
        await _native.invokeMethod<void>('pairClassic', {'name': camera.name});
        _check(generation);
        setState(() => _status = '正在重新连接已配对的相机…');
        final found = await _discover();
        _check(generation);
        final sameId = found.where((item) => item.id == camera.id).firstOrNull;
        final sameName = found
            .where((item) => item.name == camera.name)
            .toList();
        final paired =
            sameId ?? (sameName.length == 1 ? sameName.single : null);
        if (paired == null) {
          throw const FormatException('没有重新找到已配对的相机，请保持相机开机后重试。');
        }
        await _handshake(
          paired.id,
          identity,
          generation,
          expectedSerial: confirmed,
        );
        await _preferences.setString(
          _pairingKey,
          jsonEncode({'name': camera.name, 'serial': confirmed}),
        );
      }
      _check(generation);
      setState(() {
        _busy = false;
        _connected = true;
        _status = '相机已连接，正在获取手机定位…';
      });
      await _sync(generation);
    } catch (error) {
      await _fail(generation, error);
    }
  }

  Future<void> _sync(int generation) async {
    try {
      _check(generation);
      if (!_foreground) {
        _scheduleFix(generation);
        return;
      }
      final fix = await _native.invokeMapMethod<String, dynamic>('locate');
      _check(generation);
      if (!_foreground) {
        _scheduleFix(generation);
        return;
      }
      final accuracy = (fix?['accuracy'] as num?)?.toDouble();
      final timestamp = fix?['time'] as int?;
      final time = timestamp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true);
      if (accuracy == null ||
          !accuracy.isFinite ||
          accuracy < 0 ||
          accuracy > 100 ||
          time == null ||
          DateTime.now().toUtc().difference(time).abs() >
              const Duration(seconds: 30)) {
        setState(() => _status = '等待有效的手机定位…');
      } else {
        await _write(
          'location',
          NikonLocationProtocol.location(
            latitude: (fix!['latitude'] as num).toDouble(),
            longitude: (fix['longitude'] as num).toDouble(),
            altitude: (fix['altitude'] as num?)?.toDouble(),
            time: time,
          ),
        );
        _check(generation);
        setState(() {
          _lastSent = DateTime.now();
          _status = '位置已发送给相机';
        });
      }
      _scheduleFix(generation);
    } on PlatformException catch (error) {
      if (error.code == 'LOCATION_UNAVAILABLE' &&
          mounted &&
          generation == _generation) {
        setState(() => _status = error.message ?? '等待手机定位…');
        _scheduleFix(generation);
      } else {
        await _fail(generation, error);
      }
    } catch (error) {
      await _fail(generation, error);
    }
  }

  void _scheduleFix(int generation) {
    if (_disposed || generation != _generation) return;
    _nextFix = Timer(
      const Duration(seconds: 10),
      () => unawaited(_sync(generation)),
    );
  }

  Future<void> _fail(int generation, Object error) async {
    if (_disposed || generation != _generation || error is _OperationEnded) {
      return;
    }
    final message = switch (error) {
      PlatformException() => error.message ?? '连接未完成，请重试。',
      FormatException() => error.message,
      MissingPluginException() => '当前设备无法使用蓝牙定位同步。',
      _ => '定位同步未完成，请重试。',
    };
    await _stop('连接未完成', problem: message);
  }

  Future<void> _stop(String status, {String? problem}) async {
    final generation = ++_generation;
    _nextFix?.cancel();
    final pending = _pendingPair;
    if (pending != null && !pending.isCompleted) pending.complete(null);
    final signal = _readySignal;
    if (signal != null && !signal.isCompleted) signal.complete();
    if (!_disposed) {
      setState(() {
        _busy = true;
        _connected = false;
        _status = status;
        _problem = problem;
      });
    }
    try {
      await _native
          .invokeMethod<void>('stop')
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Native teardown also invalidates outstanding operations.
    }
    if (!_disposed && generation == _generation) {
      setState(() => _busy = false);
    }
  }

  Future<void> _forgetPairing() async {
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      await _preferences.remove(_pairingKey);
      _check(generation);
      setState(() {
        _problem = null;
        _device = null;
        _cameras = [];
        _status = '请在相机上重新开始配对，再搜索相机';
        _busy = false;
      });
    } catch (error) {
      await _fail(generation, error);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    unawaited(_stop('已断开'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sent = _lastSent;
    return Scaffold(
      appBar: const HueHeader(title: '蓝牙定位同步', back: true),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bluetooth_rounded),
              title: Text(_device ?? '尼康相机'),
              subtitle: Semantics(
                liveRegion: true,
                child: Text(_problem ?? _status),
              ),
              trailing: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
            ),
            if (_connected && sent != null)
              Text('上次发送 ${TimeOfDay.fromDateTime(sent).format(context)}'),
            if (!_connected && !_busy) ...[
              const SizedBox(height: 12),
              const Text(
                '首次连接时，在相机上打开「连接至智能设备 → 蓝牙配对 → 开始配对」。保持此页面打开，手机会把定位发给相机。',
              ),
            ],
            const SizedBox(height: 20),
            if (!_connected && !_busy)
              FilledButton(onPressed: _scan, child: const Text('搜索蓝牙相机')),
            if (!_connected && !_busy && _problem != null)
              TextButton(onPressed: _forgetPairing, child: const Text('重新配对')),
            if (_connected || _busy)
              OutlinedButton(
                onPressed: () => unawaited(_stop('已断开')),
                child: const Text('停止同步'),
              ),
            if (!_busy && !_connected)
              for (final camera in _cameras)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(camera.name),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => unawaited(_connect(camera)),
                ),
          ],
        ),
      ),
    );
  }
}

class _OperationEnded implements Exception {
  const _OperationEnded();
}
