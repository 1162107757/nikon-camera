import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huevia/camera_grid.dart';
import 'package:huevia/camera_previews.dart';
import 'package:huevia/camera_transfer.dart';
import 'package:huevia/domain.dart';
import 'package:huevia/theme.dart';

import 'camera_test.dart' as camera;

void main() {
  for (final scale in [1.6, 2.0]) {
    testWidgets(
      'Camera viewer receiving card fits 568x320 landscape at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(568, 320);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final core = await camera.fixture(), state = AppState(core);
        final previews = CameraPreviews(core)..setSession('z6-fixture');
        final photo = <String, dynamic>{
          'handle': 1,
          'name': 'DSC_6522.NEF',
          'bytes': 27000000,
          'raw': true,
        };
        final transfer = CameraTransfer(state)
          ..photo = photo
          ..phase = CameraTransferPhase.receiving
          ..received = 13500000
          ..total = 27000000
          ..busy = true;
        await tester.pumpWidget(
          MaterialApp(
            theme: hueviaTheme(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: CameraPhotoViewer(
              photo: photo,
              previews: previews,
              transfer: transfer,
              onDownload: () async =>
                  fail('Layout inspection must not download'),
            ),
          ),
        );
        await camera.settleImages(tester);
        await tester.ensureVisible(find.text('停止下载'));
        await tester.pumpAndSettle();
        final exception = tester.takeException();
        final stopVisible = find
            .text('停止下载')
            .hitTestable()
            .evaluate()
            .isNotEmpty;
        final progressVisible = find
            .textContaining('50%')
            .evaluate()
            .isNotEmpty;
        await tester.pumpWidget(const SizedBox());
        tester.binding.imageCache.clear();
        tester.binding.imageCache.clearLiveImages();
        transfer.busy = false;
        transfer.dispose();
        previews.dispose();
        state.dispose();
        expect(
          exception,
          isNull,
          reason: 'Receiving progress must fit the landscape viewport',
        );
        expect(progressVisible, isTrue);
        expect(
          stopVisible,
          isTrue,
          reason: 'Stopping a receive must remain reachable',
        );
      },
    );
  }
}
