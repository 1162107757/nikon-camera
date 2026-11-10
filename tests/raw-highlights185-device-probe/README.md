# RAW highlights185 native regression

Local, emulator-only instrumentation against the exact installed production APK. It uses production `RawDeveloper`, `RawJpegColorMatch` and the JNI LUT application, generated original DNG fixtures, a pinned existing CC0 Nikon Z6 NEF and an existing local Z6II reference. The test photographs are packaged only in the local QA APK, copied into app-owned cache, verified by SHA and removed after each run. They are absent from the delivery APK.

`build.ps1` requires Android SDK35/build-tools35, JDK17, and the two existing local fixtures named in the script. `run.ps1` requires the installed candidate SHA to match `-CandidateApk` and `-ExpectedApkSha256`, and permits owned emulator hardware only. Pass `-Serial emulator-5584` or `emulator-5588`. Reports are written beneath `docs/validation/raw-highlights185/device/<candidate-sha-prefix>/`.

The baseline184 run must expose the controlled white-reference magenta error. Final185 checks the safe result, default H2 neutral white, full output sizes, original bytes, exact production calibration and highlight axis. The suite also records the seven unchanged native render outputs and per-file color fallback behavior for comparison in `final-results.json`.

`stageLegacyFixture` is a bounded helper for the task-local copy of the existing RAW test runner: it writes the licensed sample under a new safe run ID in the target app's own external cache. The original RAW suite then exercises and removes it. It does not modify production code or a user photo.

The user-reported NEF itself was unavailable. These tests confirm a color-fit defect and its guarded correction, not a complete diagnosis of that unseen file or physical-device behavior.
