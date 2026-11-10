# Album and expandable search regression

Run only on a task-owned emulator. Builds against the app's current manual classes; uses the same debug signer. Does not clear app data. Inserts 42 run-specific MediaStore JPEGs and deletes only their returned URIs in `finally`; temporary appearance and image permission are restored.

```powershell
./tests/album-search165-device-probe/build.ps1
./tests/album-search165-device-probe/run.ps1 -CandidateApk ./dist/huevia-0.30.11-beta-debug.apk -Serial emulator-5592
```

The full run limits the in-memory thumbnail LRU to 2 MiB and observes attached tile identity and bitmap-to-placeholder regressions for 6.5 seconds. This intentionally forces cache pressure; it is not a Samsung hardware benchmark. It then checks scrolling, inline search focus, live query, clear, cursor, cancel and app back. `-VisualOnly -Appearance dark` captures collapsed / IME / submitted search at the emulator's current display and font configuration. A system dialog over the app invalidates the capture. The runner verifies the installed APK SHA-256 and writes evidence under `docs/validation/album-search165/<RunId>`.

Compare 164 and 165 at the same display, font, permissions and cache cap; use a fresh run ID. Reset any task-specific `wm size`, `wm density`, `font_scale`, and system night overrides after the run. No connected physical S24+ is available in this environment.
