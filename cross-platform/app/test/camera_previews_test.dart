import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_previews.dart';
import 'package:huevia/domain.dart';
import 'package:path/path.dart' as p;

class PreviewCore extends HueviaCore {
  PreviewCore() {
    root = p.join(p.current, 'camera-fixture');
  }
  final calls = <Json>[];
  final replies = <Completer<Json>>[];
  int cancellations = 0;
  @override
  Future<void> cancel(String id) async {
    cancellations++;
  }

  @override
  Future<Json> call(
    String operation, [
    Json payload = const {},
    String? jobId,
  ]) {
    expect(operation, 'camera.thumbnail');
    calls.add(payload);
    final reply = Completer<Json>();
    replies.add(reply);
    return reply.future;
  }

  Json response(int i) => {
    'session': calls[i]['session'],
    'handle': calls[i]['handle'],
    'path': p.join(root, 'camera-previews', '${calls[i]['handle']}.jpg'),
  };
}

const previewPhoto = <String, dynamic>{
  'handle': 1,
  'name': 'DSC_6522.NEF',
  'bytes': 27000000,
};

void main() {
  test('Visible thumbnails share one serialized camera read and one future per object', () async {
    final core = PreviewCore();
    final loader = CameraPreviews(core)..setSession('session');
    final first = loader.load(previewPhoto);
    expect(identical(first, loader.load(previewPhoto)), isTrue);
    final second = loader.load({...previewPhoto, 'handle': 2});
    expect(core.calls, hasLength(1));
    core.replies[0].complete(core.response(0));
    expect((await first).path, isNotNull);
    expect(core.calls, hasLength(2));
    core.replies[1].complete(core.response(1));
    expect((await second).path, isNotNull);
    expect(core.cancellations, 0);
    loader.dispose();
  });
  test(
    'A changed session retires queued reads and discards an old active reply',
    () async {
      final core = PreviewCore();
      final previews = CameraPreviews(core)..setSession('old');
      final active = previews.load(previewPhoto);
      final queued = previews.load({...previewPhoto, 'handle': 2});
      previews.setSession('new');
      expect((await queued).path, isNull);
      final next = previews.load(previewPhoto);
      core.replies[0].complete(core.response(0));
      expect((await active).path, isNull);
      expect(core.calls.last['session'], 'new');
      core.replies[1].complete(core.response(1));
      expect((await next).path, isNotNull);
      expect(core.cancellations, 0);
      previews.dispose();
    },
  );
  test('Wrong-session and external preview paths are rejected and explicit retry refreshes', () async {
    final core = PreviewCore();
    final previews = CameraPreviews(core)..setSession('session');
    final first = previews.load(previewPhoto);
    core.replies[0].complete({...core.response(0), 'session': 'old'});
    expect((await first).error, isNotNull);
    final outside = previews.load(previewPhoto, refresh: true);
    expect(core.calls.last['refresh'], isTrue);
    core.replies[1].complete({
      ...core.response(1),
      'path': p.join(core.root, 'originals', 'source.nef'),
    });
    expect((await outside).path, isNull);
    final retry = previews.load(previewPhoto, refresh: true);
    core.replies[2].complete(core.response(2));
    expect((await retry).path, isNotNull);
    previews.dispose();
  });
  test('Disposing a thumbnail list drains its active read without disconnecting the camera', () async {
    final core = PreviewCore();
    final previews = CameraPreviews(core)..setSession('session');
    final first = previews.load(previewPhoto);
    final queued = previews.load({...previewPhoto, 'handle': 2});
    previews.dispose();
    expect((await queued).path, isNull);
    core.replies[0].complete(core.response(0));
    expect((await first).path, isNull);
    expect(core.calls, hasLength(1));
    expect(core.cancellations, 0);
  });
  test('A failed preview is retained until explicit retry instead of flooding the camera', () async {
    final core = PreviewCore();
    final previews = CameraPreviews(core)..setSession('session');
    final first = previews.load(previewPhoto);
    core.replies[0].completeError(const AppFailure('相机缩略图读取失败'));
    expect((await first).error, contains('读取失败'));
    expect(identical(first, previews.load(previewPhoto)), isTrue);
    expect(core.calls, hasLength(1));
    previews.dispose();
  });
}
