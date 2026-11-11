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
