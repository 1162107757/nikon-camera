# Actual export preview native probe

This standalone instrumentation compiles against Android only and reflects the installed app. No production classes are included in the probe APK.

Build with `build.ps1`. The root agent exclusively installs the frozen candidate separately, then runs:

```powershell
pwsh -NoProfile -File tests/export-preview-device-probe/run.ps1 -CandidateApk <absolute-final-apk> -ExpectedApkSha256 <sha256> -Serial emulator-5586
```

The runner verifies the installed APK bytes, uses one ordinary-font emulator configuration, temporarily enables airplane mode, and restores its settings. It does not clear, install or uninstall the main app. It uninstalls its own probe and cleans its private generated JPEG fixture. Evidence is kept in a new `docs/validation/photo-export-preview/<APK-prefix>/<run-id>/` directory.

Checks cover an actual JPEG and its lossless pre-encoder reference from the installed renderer: JPEG compression differences, actual dimensions/quality/file bytes/hash, native 100% tile pixels versus a whole-file decode, 200% zoom and a real pan gesture, EXIF orientation 6, crop and external border, owner invalidation, closing pending work, worker termination and private temporary-file removal. Four screenshots are captured. The generated neutral fixture does not certify all colour algorithms, a real RAW decoder, phone performance or gallery publication.

This child task only built the probe; it did not operate ADB. Actual native results must come from the root's final APK run.
