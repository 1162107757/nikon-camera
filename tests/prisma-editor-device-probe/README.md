# Native Prisma editor probe

This test APK compiles against Android API 35 only. It resolves the installed production application's classes through reflection and rejects any installed APK whose SHA-256 differs from the candidate. No production Java classes are bundled in the test APK.

`build.ps1` packages the existing illustrative portrait from the approved prototype and records input hashes. The five NCP fixtures are hand-authored test bytes. A unique JPEG fixture is placed in the application's already-supported committed camera-album directory; test-owned JPEGs, their source records/drafts and the one test-owned MediaStore row are removed by the test. A restart prepare phase deliberately retains its fixture until the verify phase. The source hash is checked after editing.

`run.ps1` accepts only the emulator recorded as owned by this task. It checks seven configurations by default, restores display and font overrides, stops the application and removes the instrumentation package. It does not clear the application's data or operate a physical device. The task-owned emulator is stopped when validation finishes. Its existing private directory is retained; this task does not retry a previously blocked recursive cleanup.

Coverage includes actual rendered 14dp filter gaps and complete caption bounds, the five tool destinations and target sizes, filename/yellow action, native strength/exposure input, undo/redo, split drag/keyboard/accessibility input, crop/rotate/mirror pixel behavior and draft round trip, unchanged original file, and the preserved preset picker/export entry. These are bounded editor regressions, not full-app or camera acceptance.

```powershell
./tests/prisma-editor-device-probe/build.ps1
./tests/prisma-editor-device-probe/run.ps1 -Modes @('phone')
```

The 152 extension checks close/reopen and explicit saved-version behavior, the app-album route, an actual MediaStore JPEG import through LocalPhotoRepository, Activity recreation, and a two-phase process force-stop recovery with exact draft identity and preview-pixel hashes. It checks concentric normal/pressed/focused reset faces, circular painting inside a rectangular body header target, restored More utilities, real skin/face/body Apply, and sibling tool styling. Face/skin selection metadata is synthetic; this is not an inference accuracy test.

The default candidate is `dist/huevia-0.29.1-beta-debug.apk`. `-Candidate` selects another exact APK and `-Scope` selects a task evidence directory; never treat results from different hashes as interchangeable. Two-stage process recovery, in order:

```powershell
./tests/prisma-editor-device-probe/run.ps1 -Modes @('phone') -Scope editor-continuity152-restart -RestartPhase prepare
./tests/prisma-editor-device-probe/run.ps1 -Modes @('phone') -Scope editor-continuity152-restart -RestartPhase verify
```
