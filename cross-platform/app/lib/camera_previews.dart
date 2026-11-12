import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'domain.dart';
import 'theme.dart';

class CameraPreview {
  const CameraPreview({this.path, this.error});
  final String? path;
  final String? error;
}

class _PreviewRequest {
  _PreviewRequest(this.session, this.handle, this.generation, this.refresh);
  final String session;
  final int handle, generation;
  final bool refresh;
  final result = Completer<CameraPreview>();
}

/// One camera read at a time, including across visible rows. Scrolling never
/// cancels an in-flight PTP operation, which would close the Wi-Fi session.
class CameraPreviews {
  CameraPreviews(this.core);
  final HueviaCore core;
  String _session = '';
  int _generation = 0, _sequence = 0;
  bool _running = false, _disposed = false, _paused = false;
  final _pending = <_PreviewRequest>[];
  final _futures = <String, Future<CameraPreview>>{};

  void reset(String session) {
    _session = session;
    _generation++;
    _futures.clear();
    for (final request in _pending) {
      request.result.complete(const CameraPreview());
    }
    _pending.clear();
  }

  void setSession(String session) {
    if (_session != session) reset(session);
  }

  void pause() => _paused = true;
  void resume() {
    _paused = false;
    if (!_disposed) unawaited(_drain());
  }

  Future<CameraPreview> load(Json photo, {bool refresh = false}) {
    final handle = photo['handle'];
    if (_disposed || _session.isEmpty || handle is! int || handle < 1) {
      return Future.value(const CameraPreview());
    }
    final key = jsonEncode([
      _session,
      handle,
      photo['name'],
      photo['bytes'],
      photo['capturedAt'],
    ]);
    if (!refresh && _futures.containsKey(key)) return _futures[key]!;
    final request = _PreviewRequest(_session, handle, _generation, refresh);
    _pending.add(request);
    _futures[key] = request.result.future;
    if (_futures.length > 128) _futures.remove(_futures.keys.first);
    unawaited(_drain());
    return request.result.future;
  }

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (!_disposed && !_paused && _pending.isNotEmpty) {
        final request = _pending.removeAt(0);
        CameraPreview preview;
        try {
          final result = await core.call(
            'camera.thumbnail',
            {
              'session': request.session,
              'handle': request.handle,
              'refresh': request.refresh,
            },
            'camera-thumbnail-${DateTime.now().microsecondsSinceEpoch}-${_sequence++}',
          );
          final path = result['path'];
          if (result['session'] != request.session ||
              result['handle'] != request.handle ||
              path is! String ||
              core.root.isEmpty ||
              !p.isWithin(p.join(core.root, 'camera-previews'), path)) {
            throw const AppFailure('缩略图已失效，请重新读取。');
          }
          preview = CameraPreview(path: path);
        } catch (failure) {
          preview = CameraPreview(error: '$failure');
        }
        request.result.complete(
          !_disposed && request.generation == _generation
              ? preview
              : const CameraPreview(),
        );
      }
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    reset('');
  }
}

class CameraThumbnail extends StatefulWidget {
  const CameraThumbnail({
    super.key,
    required this.previews,
    required this.photo,
  });
  final CameraPreviews previews;
  final Json photo;
  @override
  State<CameraThumbnail> createState() => _CameraThumbnailState();
}

class _CameraThumbnailState extends State<CameraThumbnail> {
  late Future<CameraPreview> future;
  @override
  void initState() {
    super.initState();
    future = widget.previews.load(widget.photo);
  }

  @override
  void didUpdateWidget(CameraThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previews != widget.previews ||
        oldWidget.photo != widget.photo) {
      future = widget.previews.load(widget.photo);
    }
  }

  void retry() => setState(() {
    future = widget.previews.load(widget.photo, refresh: true);
  });

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: SizedBox.square(
      dimension: 64,
      child: ColoredBox(
        color: HuePalette.of(context).container,
        child: FutureBuilder<CameraPreview>(
          future: future,
          builder: (context, snapshot) {
            final path = snapshot.data?.path;
            if (path != null) {
              return Image(
                image: ResizeImage(
                  FileImage(File(path)),
                  width: 256,
                  height: 256,
                  policy: ResizeImagePolicy.fit,
                ),
                fit: BoxFit.cover,
                semanticLabel: '${widget.photo['name']} 缩略图',
                errorBuilder: (_, _, _) => _retry('缩略图无法显示，轻点重试'),
              );
            }
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            return _retry(snapshot.data?.error ?? '轻点读取缩略图');
          },
        ),
      ),
    ),
  );

  Widget _retry(String message) => Tooltip(
    message: message,
    child: InkWell(
      onTap: retry,
      child: Semantics(
        button: true,
        label: '${widget.photo['name']} 缩略图读取失败，轻点重试',
        child: const Center(child: Icon(Icons.image_not_supported_outlined)),
      ),
    ),
  );
}
