import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/domain.dart';

/// Matches the owned synthetic NCP in tests/java/.../NcpCompatibilityFixtures.
/// This is a generated test recipe, with no downloaded or user preset data.
Uint8List _projectNcpFixture() {
  final bytes = Uint8List(638), curve = Uint8List(578);
  bytes.setRange(0, 3, ascii.encode('NCP'));
  bytes[7] = 1;
  bytes[11] = 36;
  bytes.setRange(12, 16, ascii.encode('0100'));
  bytes.setRange(16, 24, ascii.encode('HOST NCP'));
  bytes[36] = 0x03;
  bytes[37] = 0xc2;
  bytes[39] = 0xff;
  bytes[40] = 0x82;
  bytes[41] = bytes[42] = 1;
  bytes[43] = 0x7f;
  bytes[44] = 0x83;
  bytes[45] = bytes[46] = bytes[47] = 0xff;
  bytes[51] = bytes[54] = 2;
  bytes[55] = 0x42;
  curve[0] = 0x49;
  curve[1] = 0x30;
  curve[3] = curve[5] = 0xff;
  curve[6] = 1;
  curve[8] = 2;
  curve[11] = curve[12] = 0xff;
  for (var i = 0; i <= 256; i++) {
    final value = (i * 128).clamp(0, 32767);
    curve[64 + i * 2] = value >> 8;
    curve[65 + i * 2] = value & 255;
  }
  bytes.setRange(56, 634, curve);
  return bytes;
}

Future<String> _hashFile(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// One real native project render. The caller supplies its own small PNG.
Future<void> verifyNativeProjects(HueviaCore core, String sourcePath) async {
  final source = File(sourcePath),
      sourceSha = await _hashFile(File(sourcePath));
  final account = await core.call('account.current');
  final owner = account['logoutPending'] == true
      ? ''
      : account['user']?['id'] as String? ?? '';
  Future<Json> call(String operation, [Json payload = const {}]) =>
      core.call(operation, {'owner': owner, ...payload});

  // A read-only native render creates a JPEG without adding a version of the
  // caller's PNG or changing its draft. Normal import retains the exact bytes.
  final plain = await call('media.reviewPreview', {
    'path': sourcePath,
    'recipe': Recipe().data,
    'maxEdge': 256,
  });
  final plainFile = File(plain['path'] as String);
  final plainSha = await _hashFile(plainFile);
  final jpegPath = await core.importFile(XFile(plainFile.path), preset: false);
  final jpeg = File(jpegPath), jpegSha = await _hashFile(File(jpegPath));
  expect(
    jpegSha,
    plainSha,
    reason: 'Project import must keep native JPEG bytes',
  );
  final info = await call('media.info', {'path': jpegPath});
  expect(info['raw'], false);
  expect((info['width'] as num).toInt(), greaterThan(0));

  final nonce = DateTime.now().microsecondsSinceEpoch;
  final incoming = Directory('${core.root}/integration-project-$nonce');
  await incoming.create();
  final presetFile = File('${incoming.path}/project-fixture.ncp');
  final presetBytes = _projectNcpFixture();
  await presetFile.writeAsBytes(presetBytes, flush: true);
  final imported = await call('library.import', {
    'path': presetFile.path,
    'name': 'Project native fixture.ncp',
  });
  final preset = object(imported['record']);
  expect(preset['id'], sha256.convert(presetBytes).toString());
  var removeFixturePreset = imported['added'] == true;

  try {
    final created = await call('project.create', {
      'name': 'Native project $nonce',
    });
    final projectId = created['id'] as String;
    Future<Json> project(String operation, [Json payload = const {}]) =>
        call(operation, {'projectId': projectId, ...payload});
    await project('project.add', {
      'path': jpegPath,
      'name': 'Project-$nonce.JPG',
    });
    final addedAgain = await project('project.add', {
      'path': jpegPath,
      'name': 'Project-$nonce.JPG',
    });
    expect(addedAgain['photoCount'], 1);
    await project('project.setPreset', {'presetId': preset['id']});
    // Remove only a record introduced by this test. The project must already
    // have a native, checksummed copy of the default recipe at this boundary.
    if (removeFixturePreset) {
      await call('library.remove', {'id': preset['id']});
      removeFixturePreset = false;
    }
    final queued = await project('project.enqueue');
    final task = object((queued['tasks'] as List).single);
    expect(task['status'], 'queued');
    expect(task['presetId'], preset['id']);
    final existing = await call('version.list', {'path': jpegPath});
    final beforeIds = (existing['items'] as List)
        .map((row) => object(row)['id'])
        .toSet();

    final frozen = await project('project.begin', {'key': task['key']});
    expect(frozen['sourceSha'], jpegSha);
    expect(object(frozen['recipe'])['presetId'], preset['id']);
    final rendered = await call('media.export', {
      'path': frozen['path'],
      'recipe': frozen['recipe'],
      'size': 'full',
      'snapshot': true,
      'expectedSourceSha': frozen['sourceSha'],
    });
    final completion = {
      'key': task['key'],
      'lease': frozen['lease'],
      'versionId': rendered['id'],
    };
    final finished = await project('project.finish', completion);
    expect(object((finished['tasks'] as List).single)['status'], 'saved');
    await project(
      'project.finish',
      completion,
    ); // Same lost reply, same receipt.
    final saved = await project('project.result', {'key': task['key']});
    expect(saved['id'], rendered['id']);
    expect(saved['sourceSha'], jpegSha);
    final encoded = File(saved['path'] as String);
    expect(await encoded.exists(), true);
    expect(await _hashFile(encoded), saved['sha256']);
    final encodedSha = await _hashFile(encoded);
    final codec = await ui.instantiateImageCodec(await encoded.readAsBytes());
    try {
      final frame = await codec.getNextFrame();
      expect(frame.image.width, saved['width']);
      expect(frame.image.height, saved['height']);
      frame.image.dispose();
    } finally {
      codec.dispose();
    }

    final replay = await project('project.begin', {'key': task['key']});
    expect(
      replay['done'],
      true,
      reason: 'Saved tasks must not start a new render',
    );
    expect(replay.containsKey('lease'), false);
    final duplicate = await project('project.enqueue');
    expect((duplicate['tasks'] as List), hasLength(1));
    expect(object((duplicate['tasks'] as List).single)['status'], 'saved');
    final retry = await project('project.retry');
    expect(object((retry['tasks'] as List).single)['status'], 'saved');
    final after = await call('version.list', {'path': jpegPath});
    final afterIds = (after['items'] as List)
        .map((row) => object(row)['id'])
        .toSet();
    expect(afterIds, {...beforeIds, saved['id']});
    expect(await _hashFile(encoded), encodedSha);
    expect(await _hashFile(jpeg), jpegSha);
    expect(await _hashFile(source), sourceSha);
  } finally {
    if (removeFixturePreset) {
      try {
        await call('library.remove', {'id': preset['id']});
      } catch (_) {
        // Keep the original test failure; never remove a preexisting record.
      }
    }
    // Preserve the rendered fixtures and durable project receipts for inspection;
    // only this helper's uniquely owned staging file is disposable.
    if (await presetFile.exists()) await presetFile.delete();
    if (await incoming.exists()) await incoming.delete();
  }
}
