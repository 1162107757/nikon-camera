# 168 · Local selection workspace

Local candidate: **0.30.14-beta / 168**, not uploaded or published.

The user's approved scope is local adjustment. Circle and ellipse share one bounds-driven tool. Manual brush, rectangle and geometric selection can replace, add to or subtract from coverage; inverse applies to the final region. Existing shapes can be moved and resized. Geometry uses source-photo coordinates and is serialized in PhotoLocalEdits v6, retaining reads of versions 1–5 and older write formats when no new geometry is present.

Manual and automatic coverage persists instead of blinking away. Adjustment gestures temporarily suppress the display; release, cancellation, dismissal and focus interruption restore the user's chosen visibility. The eye action only hides or shows coverage, retaining selection and edit settings. Clearing coverage and deleting a region remain separate undoable operations. This policy covers regional adjustments and their curves/HSL/palette/cleanup dialogs, detected face and skin, manual face coverage, body range and the legacy local mask. Nested precision/HSV input remains deferred until its existing Apply/Preview action.

## Frozen identity

| Artifact | SHA-256 | Bytes |
|---|---|---:|
| Full four-ABI source APK, `dist/huevia-0.30.14-beta-debug.apk` | `57c37922a6150c0e7aa86b8bfb39ad1d041589dbcde34d889f6afd9b7d58aef3` | 34,635,222 |
| Signed upload variant, `dist/upload168/huevia-0.30.14-beta-update.apk` | `d278209b8cd921dddb11e84429cdfe375ff7604c12b34e31e34951010067dd03` | 31,341,757 |

The upload variant removes four obsolete x86 libraries. All 88 retained payloads, including classes, resources, ARM32/ARM64 and x86_64 libraries, are byte-identical to the source APK. Signature v2/v3, existing certificate `04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`, 16KiB ZIP alignment and the backend's offline APK inspection passed. It is below the backend's 32MiB upload limit.

See [source identity](source-candidate.json), [package metadata](package-candidate.json), [retained payload proof](payload-provenance.json), [offline inspection](apk-inspection.json), and [signed-install smoke](upload-smoke.json). The signed variant was installed by its exact SHA on the owned API36 x86_64 emulator and cold-launched successfully. This smoke does not replace the selection matrix.

## Verification

Unchanged core host inputs passed 1,520,101 adjustment-region checks, 43,230 local-edit checks, 548 library checks, 53 editor-catalog checks and 36 image-cache checks. These include independent coverage/ordering/inverse and EXIF/alpha oracles, backward-compatible serialization, real draft payloads, cancellation and bounded-memory cases. Display-only F1–F4 corrections did not modify the tested core classes.

The exact full APK passed **412 checks and 26 original PNGs in each of four configurations**:

- Phone, API37, 1080×2424.
- Tablet, API36, 1600×2560.
- Narrow phone/font1.3, API36 (Android16), 840×1890.
- Landscape/dark, API37, 2424×1080.

Total: **1,648 repeated native assertions and 104 original screenshots**. [Capture index](capture-index.json) links each raw report, per-run provenance, cleanup record, dimensions and image SHA. Reflection instrumentation uses the actual installed application's classes, widgets, masks and saved drafts. It supplies no substitute production implementation. Original fixture photo bytes and personal-tone preferences were preserved. [Device restoration](device-restoration.json) records final settings; the task-owned API36 emulator was closed afterward.

Added F1/F2 cases cover all three palette precision axes and all three HSV axes with coverage initially shown and explicitly hidden, real native window-focus interruption, dismissal while held, deferred edit settings unchanged, and face/skin→group chooser hide/show/restore. The first post-fix attempts read dismissal before Android's asynchronous callback; those failed reports are retained and excluded. The harness now waits for the real callback; no further production change was needed.

The initial `6cf549b0…` candidate and its full review remain frozen historical evidence. Its four material findings were addressed in one production batch: nested gesture suppression, chooser visibility access, existing eye vocabulary plus explicit selection-workspace label, and a dark translucent instruction surface. The final reviewer [verdict](../../../.impeccable/review/selection168/verdict.md) is **ship**: F1–F4 are all resolved, with no direct regression from that fix batch. This verdict scores those four findings and their direct regressions; it is not a new whole-surface or whole-application approval. No HTML/CSS design detector ran against native Java. No production raster was added or replaced; QA screenshots and the public-domain NASA fixture are evidence only.

This evidence does not certify physical Samsung hardware, general segmentation accuracy, all camera models, a new full-export matrix or public update delivery. The mask is a separate display layer and never replaces source, rendered or exported photo pixels.
