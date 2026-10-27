# Composition dock native probe

Standalone instrumentation compiled only against Android API35. Production classes are resolved by reflection from the separately installed frozen candidate. This probe does not build, package, install, uninstall or clear the main app and does not use a camera or publish to MediaStore.

Build the instrumentation with `./build.ps1`. Its signed APK and input hashes are written under `.build/`; the build verifies that every compiled class belongs to `cc.huevia.compositiondockqa`.

After the exact candidate has been separately installed on an exclusively owned `ranchu` or `goldfish` emulator, run:

```powershell
./run.ps1 -CandidateApk D:/absolute/path/candidate.apk -ExpectedApkSha256 <64-character-SHA256> -Serial emulator-5586 -Mode phone
```

Repeat with `-Mode font1.3` and `-Mode landscape`. The runner accepts `emulator-5586` or `emulator-5588`. It checks the candidate file SHA, installed APK SHA, actual version code and version name against local APK metadata, plus the instrumentation APK and all recorded source hashes. No target version is hardcoded.

The probe opens the real MainActivity, a JPEG fixture it owns, and the native local photo editor. It clicks the four composition entries, checks staging/cancel/apply/history behavior, verifies reset changes only geometry, and verifies restoring filter/adjustment dock height. At standard font the composition dock is 112dp content plus 48dp navigation (160dp); other modes retain 176dp plus 48dp (224dp). Larger text uses the app's font-scaled dimensions. The probe checks 48dp touch targets, complete single-line tool labels and available photo stage space. Each mode records two PNGs: the dock and actual crop workspace, after committed frames and transient overlays close.

The fixture uses the shipping `drawable/preset_template` photo, fitted inside 960×640 while retaining its aspect ratio, with no text painted over the image. Its run ID and UUID are stored in JPEG EXIF `ImageDescription` to keep each owned file's SHA unique. The source resource is 1448×1086, SHA-256 `067e391dcb5a61c20021dc9a4a7eb4c324829592a5de747dd1f4a958ce44c8d9`, matching the frozen 110 `SOURCE-IDENTITY.json`; each report records this identity and decoded/output dimensions.

The native perspective selector is driven through the actual accessibility menu. A first-use `com.android.systemui` immersive teaching prompt is acknowledged through its real `Got it` accessibility action when present. These checks do not certify TalkBack behavior, physical hardware, camera connectivity, FPS or color accuracy.

Evidence is stored in fresh `docs/validation/composition-dock/{candidate-SHA-prefix}/{run-id}` directories. Private fixtures/drafts are removed individually by instrumentation; shared main-app data and prior evidence stay intact. The runner records the previous font, accelerometer rotation, user rotation, airplane and immersive-confirmation settings, restores each independently with readback, and records cleanup errors in `cleanup.json`. Blank or `null` settings restore via deletion. A failed cleanup cannot prevent another cleanup step or replace the original instrumentation failure.

This delivery compiles/signs the instrumentation only. Device execution must be performed explicitly by the coordinating task.
