# Loading / update UI probe (105)

Run only against the task-owned `emulator-5588` with the exact local 105 APK installed.

```powershell
./tests/update-loading-device-probe/build.ps1
./tests/update-loading-device-probe/run.ps1 -CandidateApk D:/dev/ai-project/nikon/dist/huevia-0.21.6-beta-debug.apk -FontScale 1.0 -Theme light -Motion on
./tests/update-loading-device-probe/run-wifi.ps1 -CandidateApk D:/dev/ai-project/nikon/dist/huevia-0.21.6-beta-debug.apk
```

`UpdateLoadingProbe` uses production components in a fixture activity, not the real MainActivity. It checks moving pixels, stopped animations when detached or system animations are disabled, update page states, optional/mandatory prompts, complete scrolling notes, button layout, and lifecycle/deduplication. A throwing executor prevents update HTTP/download/installer work. Theme and update preferences are restored; the runner restores the global animation setting.

`WifiSelectionProbe` starts the real MainActivity with the owned emulator's Wi-Fi temporarily disabled. It intercepts the system Wi-Fi intent, verifies that it opens automatically without SSID/password fields, and checks cancellation cleanup. It also verifies the real online-loading branch and update route, and captures those screens. This does not test joining a real hotspot or a camera handshake. The runner restores Wi-Fi, uninstalls the probe, and removes only its exact run directory.

Evidence is stored beneath `docs/validation/loading-update-105/<candidate-sha-prefix>/`. The tested configuration matrix is light/1.0, dark/1.3, light/2.0, and light/1.0 with animations disabled. Failed attempts are retained separately from passing runs. Font scale is applied to the fixture activity, not the emulator's global setting.
