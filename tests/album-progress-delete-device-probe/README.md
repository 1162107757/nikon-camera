# Album progress / deletion native component probe

Uses the exact installed candidate's real `AlbumPanel`, catalogue, controller and `GlassBar`. Instrumentation replaces `MainActivity` **before** its `onCreate`, so online update/network/startup code does not run. Navigation height and inset both call the package-private production `MainActivity.floatingNavigationHeightDp(float)` and `floatingNavigationInsetPx(int, float, float)` helpers through reflection. The pixel helper rounds navigation height and bottom margin separately, matching the actual LayoutParams. This component probe is not evidence that all real MainActivity wiring or lifecycle paths passed.

The substitute Activity's navigation contains **text-only placeholders**, with production bar geometry and GlassBar material. Real MainActivity tab icons, icon/label selection backgrounds and navigation click routing are **not covered** by this component probe.

Three independent runs: `phone`, `large-font` (1.3), `rail` (actual width at least 600 dp). The script verifies and records candidate APK SHA, requires owned `emulator-5586` ranchu/goldfish, changes and restores display/font settings, and uninstalls only its own test package. It does not install/replace the product APK.

Checks all transfer bytes, cancel and selected downloaded-photo actions are completely visible and have no ellipsis. On a bottom bar they must end at least 8 dp above the actual navigation top; a rail must have no bottom inset and content must remain beside it. Uses real deletion confirmation and clicks **Cancel only**, verifying App-only wording and unchanged source bytes. One new UUID-named JPEG under App-private external `Pictures/camera-album` is generated and removed precisely; no user fixture is reused, and no production delete, camera socket, HTTP or actual download runs.

Both `beforeSavePhotos` host overloads are guarded. The target overload records and rejects a target other than `APP_ONLY`, then blocks destructive continuation even for the allowed target. Since the probe clicks Cancel only, **neither overload executes**: the production confirmation's `beforeSavePhotos(PhotoSaveTarget.APP_ONLY, ...)` selection must be checked separately in source and is not counted as a dynamic UI result.

Final candidate `4ebc35f9fc5930080ba994a6bffe7538feec5bc8679066c698d8f3001b9e37f0` passed all three configurations: 57 checks and 3 screenshots per configuration, 171 checks / 9 screenshots total. Evidence is under `docs/validation/album-progress-delete-100/4ebc35f9/`.

Earlier `6d9c5578…` candidate showed a one-pixel ordinary-font export/effect gap shortfall caused by rounding a combined dp inset, while bytes / cancel / delete were complete. Root corrected the shared pixel helper to round each LayoutParams term separately; the final runs confirm all boundaries. Initial harness issues (PowerShell stderr capture and main-thread assertion propagation) remain archived as failed runs. One own JPEG left by the assertion process crash was pulled, verified at its exact canonical path with SHA `96ef5f579a19ae95e0eef4b756fa556c72bc6aa7153bc187cd253d691ad4ed97` / 1031 bytes / 240×180, then precisely unlinked and verified absent. Record: `.tooling/album-progress-delete-100/crashed-fixture-cleanup.json`. Final probes uninstall their test package and restore font/display settings.

```powershell
./tests/album-progress-delete-device-probe/build.ps1
# Wait for the root's exact candidate and exclusive device handoff before these:
./tests/album-progress-delete-device-probe/run.ps1 -CandidateApk <immutable100.apk> -Mode phone
./tests/album-progress-delete-device-probe/run.ps1 -CandidateApk <immutable100.apk> -Mode large-font
./tests/album-progress-delete-device-probe/run.ps1 -CandidateApk <immutable100.apk> -Mode rail
```
