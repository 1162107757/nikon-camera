# 169 · Selected-source repair

Local **0.30.15-beta / 169** candidate; not uploaded or published.

The user chose selecting a blemish then dragging to a clean sample. The adjustment rail exposes 修补; 修补当前选区 explicitly reuses a local selection. The existing brush/circle–ellipse/rectangle workspace supplies the target. The destination stays fixed while its sample moves. Feather and boundary-colour blending are adjustable; repairs can be added, switched, reselected, deleted and undone. No content is generated or inferred.

The eye changes display only. Coverage persists, hides during slider adjustment and restores the chosen visibility on release. Focus/pointer cancellation restores the tentative operation. Clearing a selection and accepting removes its repair, separately from hiding. Cancel discards the dialog transaction; Apply creates one parent history entry and saves the photo draft/version. Source-photo bytes remain unchanged.

## Frozen identity

| Artifact | SHA-256 | Bytes |
|---|---|---:|
| Full APK, `dist/huevia-0.30.15-beta-debug.apk` | `201b39f735b7067fa306ae2621876a78907f70a4e69020a29cde29ed554fc273` | 34,647,510 |
| Signed upload variant, `dist/upload169/huevia-0.30.15-beta-update.apk` | `ef06853b8025936ce7c972e682855ee7ac1fc55ebda2776864be6bdf94fdaa10` | 31,358,141 |

The upload variant removes only four obsolete x86 libraries. Its 88 retained payloads are byte-identical, including classes/resources and ARM32/ARM64/x86_64 libraries. Signature v2/v3, existing certificate `04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`, 16KiB alignment and backend offline inspection passed. It is below 32MiB. Exact signed bytes were installed on the owned API36 x86_64 emulator and cold-launched in 1,772ms; this smoke covers installation/startup only.

See [source](source-candidate.json), [package](package-candidate.json), [payload proof](payload-provenance.json), [inspection](apk-inspection.json), [signed smoke](upload-smoke.json), and [restoration](device-restoration.json).

## Processing and persistence

`PhotoPatch` stores real selection geometry and normalized source translation. `PhotoLocalEdits` v7 persists repairs, reads v1–v6 and retains old write formats when no repair exists. Immutable copy APIs retain repair data. Global colour and legacy masks/clones precede sampling; portrait/regional effects and body/composition follow through the shared preview/export profile. Display coverage never enters photo pixels.

Each repair samples an immutable disk-backed snapshot, preventing overlap feedback; later repairs sample earlier results. A bounded row cache avoids an extra full-image integer array. Feathered blending preserves destination alpha and zero-mask pixels. Optional boundary colour matching retains sample texture. This is user-directed sampling rather than automatic recognition.

## Verification

- **153,740 repair host checks:** independent canonical EXIF1–8/alpha/ellipse/rectangle feather, overlap/order oracle; v7 round trip and copy retention; colour-match/texture fixture; cancellation/I/O cleanup; 24MP stream under a 64MiB host heap.
- **43,230 existing local-edit** and **1,520,101 region** checks passed.
- **548 library**, **53 editor-catalog**, **36 cache** checks passed.

The exact final full APK passed **278 checks / 13 original PNGs per configuration**: phone/API37 1080×2424; tablet/API36 1600×2560; narrow/font1.3/API36 Android16 840×1890; landscape/dark/API36 2424×1080. Total: **1,112 repeated native assertions / 52 original screenshots**. The same APK separately passed the previous selection workflow's **412 checks / 26 screenshots** on API36 phone.

[Capture index](capture-index.json) binds raw reports, dimensions/hashes, installed APK identity, probe provenance and cleanup. Reflection instrumentation loads the real installed implementation without substitute production classes. Native cases cover source direction, actual rendered pixel changes and exact exterior/alpha, shown/hidden slider/focus/pointer cancellation, source clamping, inner undo/redo/delete/clear, outer transaction/history, real saved-draft reload and region reuse. Window checks use actual Insets and global header/dock bounds. Temporary fixtures/owned drafts were removed; original preferences/settings restored. The task-owned API36 emulator was closed after signed-package smoke.

Initial 38f051a8 functional evidence remains frozen. One batched visual correction added the established system-bar/cutout insets; all four configurations were recaptured. Excluded setup failures identified a dropped rail entry after sorting and a harness call to a nonexistent undo method. The entry is now retained and the harness clicks the real native history button. A transient Windows mapped-file lock on native rebuild succeeded on retry without changing the build script.

Independent finish [review](../../../.impeccable/review/patch169/review.md) returned **ship**, with no material fixes, scoped to the selected-source repair tool and its direct regressions. No HTML/CSS detector ran against native Java. No production raster changed. QA screenshots and the public-domain NASA fixture are evidence only; deliberately unsuitable NASA sample locations exercise copying/direction, while a suitable synthetic textured blemish verifies colour matching in the host oracle. No physical Samsung, real-camera, general segmentation, new full-export matrix or public OTA acceptance is claimed.
