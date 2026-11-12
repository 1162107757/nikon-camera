# Huevia Android / iOS migration

User-approved scope (2026-11-10): migrate the complete Android product to a common Android/iOS application, retain the original projects, match every Android feature, and deliver an APK plus a real unsigned device IPA for self-signing.

Baseline: original Android 0.30.32-beta / 186 and existing native iOS project at Git commit `6fb5003d8be85fcbb0fa3b4d99aef63cc1751f3c` (the exact baseline is recorded in the generated preservation manifest).

Development is isolated on `codex/cross-platform-migration`. Original `app/`, `ios/`, backend, release APKs and validation records remain preserved. Shared logic may read and build the original portable Java sources; it must not silently reimplement validated color math with different results.

Candidate architecture under verification:

- Flutter for common UI, navigation, application state and platform-independent services.
- Existing Java image/preset core shared directly on Android and translated ahead of time for iOS, subject to actual translation and golden-image checks.
- LibRaw / native image processing retained with explicit platform adapters and bounded memory.
- Android device APIs and Apple PhotoKit / ImageCaptureCore / local-network APIs behind the same typed platform contract.

This is an active migration, not a completed full-feature release. A shell, disabled button, fake device response or mock export does not count as feature parity. `docs/migration/` records feature-by-feature implementation and validation. Physical-device verification is distinct from emulators and protocol fixtures. Unsupported platform or signing capabilities must be reported explicitly.

For Windows Android builds, use `python cross-platform/tool/android_build.py --sdk <Android-SDK> --java <JDK-17> --mode release --abi android-arm64` from the repository root. The pinned Android NDK is `28.2.13676358`. The helper stages the original native libraries and builds the migration-only RAW JNI bridge before Gradle. A direct Gradle/Flutter build must first run `python cross-platform/tool/raw_android.py --sdk <Android-SDK> --abi android-arm64` for its selected ABI. Generated native outputs stay under `cross-platform/.build/raw-android/`; the original Android sources and libraries remain unchanged.

Build 189 moves the large LibRaw objects from native thread stacks to the heap on both platforms. This addresses the stack-guard crash observed in the iOS simulator; Android also verifies actual decoding on a thread requesting a 512 KiB stack. It does not establish the cause of the reported Honor Magic crash without that device's logs. See `docs/migration/validation/android12-raw-stack-189-20261111.json` for the exact Android packages and verification scope.

The manual Apple Actions run `42963383351` passed for source `1c424600dd284041ede82fa99a444ac37b94c63b`: 23 Flutter tests, the complete native image/RAW pipeline, and identical JVM/Apple core fingerprints. The verified unsigned build 189 IPA is an iPhoneOS ARM64 release/AOT package for iOS 16 or later. Exact artifact hashes and remaining limitations are recorded in `docs/migration/validation/apple-mobile-189-20261111.json`; an actual iPhone installation and full product parity are still pending.

Build 190 fixes root navigation covering preset filters and album sorting, enables the original managed online catalog, and restores additional original dialog geometry. Android 12 passes 20 UI scenarios, 38 native checks and the live feed/RAW pipeline. Apple Actions `42969015766` passes 27 Flutter tests, 205 shared checks and the real HTTPS feed/native image scenario. Packages in `dist/migration190/` use fixed source `d82c9e478194210af85e08127bdb584d24bb0dd7`; Android was built in an isolated checkout to exclude the concurrent original Android 191 repair. Exact hashes and validation scope are recorded under `docs/migration/validation/controls-online-190/` and `apple-mobile-190-20261111.json`.

Build 207 restores the original quick / advanced export forms, version selection, quality presets and read-only JPEG / pre-encoder review. Sequential system-album saving freezes each selected recipe, persists a unique operation for retries and retains immutable originals. All three packages use source `38594afc49c9deae79e14b46f147bf45d0936225`; Apple Actions `43178284420` passes 151 Flutter tests and the real PhotoKit/image/RAW pipeline. Android release saves both selected versions and reopens the retained border. Full parity, direct original-file saving, complete batch publication and physical Honor/iPhone validation remain pending. See `docs/migration/validation/export-settings-207/README.md` and the feature matrix for exact validation sources and remaining pixel differences.
