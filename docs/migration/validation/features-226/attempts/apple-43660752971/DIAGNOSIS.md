# 61423d6 full Mac run: two confirmation-wait fixture failures

Run `43660752971`, frozen source `61423d6b144229e3113edd54da6597177efc0555`, completed with failure. The native parity/preparation step completed successfully; the failure is inside the later `Build and test the unsigned device app` step. All network operations for diagnosis were GET-only; no test, build, workflow dispatch, source edit or acceptance change was performed.

The original Flutter log finishes with **695 passed / 2 failed**. Its only failed tests are the two live-panel tests that previously could not complete on the Windows native host:

1. `A central start keeps the same preview bounds and freezes the mutually exclusive format`: `camera_live_panel_226_test.dart:172`, `pumpAndSettle timed out`.
2. `A committed photograph keeps the preview frame and never carries a large action over its pixels`: `camera_live_panel_226_test.dart:225`, `pumpAndSettle timed out`.

Both failing waits occur directly after tapping the real initial Start button and before tapping the confirmation dialog's `开始拍摄`. `CameraLivePanel.start()` sets `checking=true`, awaits `available()`, opens the real confirmation dialog, and deliberately awaits the dialog future before clearing `checking` in `finally`. The initial action displays an animated checking spinner while this transaction is pending. Waiting for the entire widget tree to stop animating while the confirmation itself awaits user input therefore has no valid completion condition. The tests should wait for the **real confirmation button to become hit-testable**, then make the existing user confirmation. This is a fixture synchronization issue, not evidence that active reception, decoded photo rendering or format/bounds assertions passed: those later assertions were not reached in these two cases.

Minimal suggested correction: change only those two post-Start `pumpAndSettle()` calls to the existing bounded `until(...)` helper with the actual `FilledButton` labeled `开始拍摄` and a `hitTestable()` finder. Keep all RAW confirmation text, exclusive format selection, native/controller start, frozen format, stable preview bounds, external Stop, actual decoded image and retained-session assertions unchanged. Do not invoke private callbacks, remove assertions, increase the global settle timeout, skip the tests or change product spinner/state semantics. A new exact source must subsequently pass the full Mac gate.

The raw evidence also records:

- `device-build.log`: actual unsigned `Runner.app` built, Xcode build 145 seconds.
- `analyze.log`: `No issues found`.
- `core-ios/parity.json`: Objective-C runtime parity `pass=true`, golden boundary count 1865.
- `mobile-apple/public-internet/result.json`: schema2, source614, compile/execution exit0 and six source digests. These are observed individual receipts, not independent final IPA acceptance.
- No successful UIKit/native integration result or accepted IPA is available in this failed-run artifact. The existence of a built `.app` does not bypass Flutter failure.

Original preserved downloads:

- `workflow-logs.zip`: 27,376B, SHA256 `a53f6b69239b74ac565ce8df2056eb7ecb3e663c3b1ade573913472ce3416e9b`.
- `diagnostic-artifact.zip`: 36,984B, SHA256 `5c625d887cf26d41c54d0f03e9b92a9d9d004cfe9ee0c66413b1d52453c701e0`, matching the GitHub artifact digest.
- `diagnostic-artifact/mobile-apple/flutter-tests.log`: 164,524B, SHA256 `1277fa1892bc1ed2f65307832557a599504804894067aa9c1681b8b82d76e9bc`.
- Complete API/source/run provenance and the other raw logs are listed in `diagnostic-download.json` and `diagnostic-artifact-receipt.json`.

The full run remains failed, the two UI tests remain unaccepted, and no IPA was promoted.
