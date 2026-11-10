# Preset photography probe

`build.ps1` compiles a test-only API35 instrumentation APK against android.jar. It embeds generated NCP fixtures, never product classes. `run.ps1` uses only the explicitly handed-off emulator-5588, verifies its installed APK matches the exact155 candidate, and clears that emulator's app data for each mode. Never run it on a physical/user-data device. The base AVD is not wiped.

Phone covers every bundled JPEG's SHA, ten distinct source photos, the production profile's actual pixel output, preserved original pixels, bounded source cache, custom-template priority, invalidation and gallery/detail/original matching. Six other size/theme/font modes cover the real list and comparison path. `-Modes live` reads actual online presets, renders their previews, and verifies their detail comparison source. Native screenshots and JSON reports are saved under docs/validation/preset-showcase/native. The generated recipes are QA data; no Nikon camera or physical phone result is claimed.

```powershell
.\tests\preset-showcase-device-probe\build.ps1
.\tests\preset-showcase-device-probe\run.ps1
.\tests\preset-showcase-device-probe\run.ps1 -Modes live
```
