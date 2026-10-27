# Real large-update DownloadManager probe

This separate instrumentation uses Android API35 only. It tests a **real published APK**, above 4MiB and at most 32MiB, through the canonical release endpoint's zero-body HTTPS307 and private-storage redirect. No HTTP or DownloadManager replacement is linked.

The runner binds the local candidate, installed target, test sources, probe APK and report. Downloaded bytes must match the candidate length and SHA256; Android's archive parser must confirm its package, version and the installed target's signing certificate. The downloaded APK is never installed. No account/editor action or device setting is performed.

Only an explicitly named emulator/AVD is allowed. The probe owns a UUID directory and a single DownloadManager ID. `finally` removes that ID, payload and empty directory and records cleanup failures. The report records only public canonical URL, storage host/path, HTTP status and native progress; provider signed URLs and tokens are never saved.

Build:

```powershell
pwsh -NoProfile -File tests/update-large-download-device-probe/build.ps1
```

Run after installing the exact frozen candidate separately and publishing the real release:

```powershell
pwsh -NoProfile -File tests/update-large-download-device-probe/run.ps1 -CandidateApk D:/dev/ai-project/nikon/dist/huevia-0.22.1-beta-debug.apk -ExpectedApkSha256 5f42f3a9733e86bc472ce56cae0e669609828d1a2027e050db39934e27ae0fe8 -Serial emulator-5586 -CanonicalUrl https://huevia.cc/preset-library/releases/REPLACE-WITH-REAL-RELEASE-ID/file
```

The native download wait is bounded to 120 seconds and uses native status/reason/received/total columns. This is emulator transport and artifact verification, not physical-device or PackageInstaller certification.
