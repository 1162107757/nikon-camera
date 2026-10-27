# Update prompt component probe

This is a narrow instrumentation test of the actual candidate APK's `UpdatePanel` and Android dialogs. It does not test the production update endpoint, DownloadManager, APK verification, unknown-source permission, package installer, or real device behavior.

The instrumentation substitutes its own `android.app.Activity` when Android resolves the target app's launcher Activity. `MainActivity.onCreate` never runs. The test Activity receives the target app Context and constructs the production `UpdatePanel` and `UiPalette`. It seeds validated production `Release` objects and calls the production manager's real listener. A guard executor rejects unexpected manager worker tasks, so no metadata HTTP, downloads, APK installation, camera connection, or account operation can occur.

Run only after the root task explicitly grants exclusive ownership of its disposable `emulator-5586`; never use another serial or a phone. The run script checks emulator hardware, candidate APK identity against the installed production base APK, and production version code. It installs/uninstalls only this test package. Update preferences are backed up, cleared before manager construction, and restored in `finally`; font scaling is local to the test Activity, not a system setting.

Use PowerShell 7 (`pwsh`) as the project build does.

```powershell
./tests/update-prompt-device-probe/build.ps1
./tests/update-prompt-device-probe/run.ps1 -CandidateApk '.tooling/.../<sha256>.apk' -FontScale 1.0
./tests/update-prompt-device-probe/run.ps1 -CandidateApk '.tooling/.../<sha256>.apk' -FontScale 1.3
```

The root task owns full production builds. This harness build compiles only its own source against existing candidate production classes. Source/API/negative safety checks are recorded in the report and must not be presented as whole-app or network/install integration coverage.
