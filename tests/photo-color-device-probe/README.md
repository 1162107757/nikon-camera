# Native colour editing probe

Build and install the exact 106 candidate on the owned `emulator-5588`, then:

```powershell
./tests/photo-color-device-probe/build.ps1
./tests/photo-color-device-probe/run.ps1 -CandidateApk D:/dev/ai-project/nikon/dist/huevia-0.21.7-beta-debug.apk -Mode phone
./tests/photo-color-device-probe/run.ps1 -CandidateApk D:/dev/ai-project/nikon/dist/huevia-0.21.7-beta-debug.apk -Mode font1.3
./tests/photo-color-device-probe/run.ps1 -CandidateApk D:/dev/ai-project/nikon/dist/huevia-0.21.7-beta-debug.apk -Mode landscape
```

This starts the real MainActivity and opens production AlbumPanel / PhotoFilterEditor with three run-owned JPEGs derived from the app's existing template photo. Sources reside in the app's validated completed-photo directory; the probe does not bypass original-source ownership checks. JPEG EXIF includes a random fixture identity so a prior draft cannot be mistaken for the current test.

It checks the actual adjustment entries, curve gesture/staging/cancel/apply, HSL native slider keyboard input and invalid exact values, one-step undo/redo, draft/recipe reload, full-size private JPEG export, batch target and coverage selection, cancellation, copying and restoring target geometry/borders. Original SHA hashes are checked. This does not publish to MediaStore or connect to a camera. MainActivity can perform its normal read-only catalog/update checks.

The F1 regression also renders an owned historical effect, writes its exact completion/model fixture ledger, and binds it through the production source-link validator to a real owned original. A different exported draft is retained to make that historical version's parameters unavailable. The real batch-copy UI must reject the complete selection before any target draft changes, while retaining the original association and later draft. Only the run's exact generated effect key and ledgers are removed afterward.

The runner verifies the installed APK hash, temporarily changes and restores font scale, uninstalls the test package and removes its exact external report directory after pulling evidence. The probe deletes only its own photo, draft, recipe and export fixtures. Failed reports and screenshots remain in local validation history, separate from final passing reports. System immersive-mode guidance is dismissed by its actual accessibility button before screenshots; it is not counted as app UI.
