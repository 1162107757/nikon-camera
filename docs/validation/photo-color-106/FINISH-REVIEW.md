# 106 native finish review

## 1. Disposition and inspected scope

**disposition: fix**

Reviewed the code-led curves, HSL, and batch-copy extension against [REQUIREMENTS.md](REQUIREMENTS.md), the pinned photo-first warm-black editor direction, the Impeccable craft floor, and the Android reference. No approved raster comp exists for this extension. No web design detector ran; native conventions and the supplied framebuffer captures form the visual evidence.

This verdict binds candidate 106 / `0.21.7-beta`, [huevia-0.21.7-beta-debug.apk](../../../dist/huevia-0.21.7-beta-debug.apk), SHA-256 `af6ba8e01dcff40b4efb6f077e2e7f12daa4ff52908c7c9ce9dfc2cc06dfa1ad`. The APK hash and all 12 changed production-input hashes match `SOURCE-IDENTITY.json`. Scope includes `PhotoColorDialog`, the editor entry and staging path, the new `AlbumPanel` copy methods, immutable curve/HSL models, preview integration, and draft/recipe/copy storage. It does not judge unrelated UI.

## 2. Capture validity

Opened and inspected every required image in these final-artifact directories:

| Native viewport | Evidence directory | Captures | Report |
| --- | --- | --- | --- |
| Portrait, font 1.0 | [phone](af6ba8e0/20261026-214510-phone-2b4dee/20261026-214510-phone-2b4dee/) | 5 at 1080×2424 | 59 PASS |
| Portrait, actual font 1.3 | [font1.3](af6ba8e0/20261026-214522-font1.3-251256/20261026-214522-font1.3-251256/) | 5 at 1080×2424 | 59 PASS |
| Landscape, font 1.0 | [landscape](af6ba8e0/20261026-214534-landscape-3485e6/20261026-214534-landscape-3485e6/) | 5 at 2424×1080 | 59 PASS |

Each set contains `00-editor-adjustment`, `01-curves-staged`, `02-hsl-staged`, `03-hsl-validation`, and `04-copy-options`. All show the named state, a loaded photo, legible controls, and settled native UI. The dark letterboxing is the intended photo fit, not missing content. All reports name the inspected APK hash; font 1.3 records `1.2999999523162842`. No intermediate `0e9bb433` evidence is used. Evidence is valid; recapture is not the present disposition.

## 3. Product and visual fidelity

The extension preserves the incumbent editor identity: the photograph leads, tools recede into warm black, system type remains consistent, and peach marks selections and actions. Curves show the edited relationship clearly; HSL uses labelled swatches and compact, aligned axes. Native dialogs protect exact input and batch decisions without adding explanatory cards over the photo.

The required views show no material text collision, missing primary action, or accidental clipping. At font 1.3 the working labels and confirmation copy remain readable. Landscape retains a large photo beside the controls; horizontal color choices and the longer curve pane use native scroll containers. Source provides 48dp key control heights, exact-input alternatives to curve dragging, descriptive accessibility labels, safe-area insets, preview retry, and disabled Apply while an edited preview is pending. Cancel dismisses staged changes; commit is guarded and adds one history state. No visual redesign or polish batch is required.

## 4. Material findings

**F1 — P2: Reject saved-version targets whose editable parameters cannot be recovered before batch writes.**

The confirmation promises to retain the target filter, composition, and border (`04-copy-options.png` in every viewport). In [AlbumPanel.java](../../../app/src/main/java/cc/huevia/ui/AlbumPanel.java), lines 3628–3631, a saved-effect target can successfully resolve to a different original file while `visible` becomes null: either no draft exists, or the retained exported draft does not match that historical saved version. The target is still accepted. [PhotoAdjustmentCopy.java](../../../app/src/main/java/cc/huevia/album/PhotoAdjustmentCopy.java), line 36, then creates a neutral base, and line 39 writes the copied adjustments with no filter, geometry, or border. This silently breaks the preservation promise for that target. Originals remain untouched, but the resulting editable draft is wrong.

The existing editor already rejects this unavailable-parameters state in [PhotoFilterEditor.java](../../../app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java), line 297. Apply the same boundary while preparing all copy targets: if a selected saved version resolves to another original and its visible editable parameters are unavailable, stop the entire batch before calling `PhotoAdjustmentCopy.apply`, explain the problem, and direct the user to select the original. Restoring a fully proven saved recipe would also satisfy the contract; substituting neutral settings does not.

Acceptance: cover missing and nonmatching exported draft cases, prove zero writes to every target on rejection, and retain copying for originals and recoverable saved versions. The supplied 177 native assertions cover the ordinary fixture flow; their check list does not cover this historical saved-version state. This finding is established by source inspection, not claimed as an emulator reproduction.

No other material findings at the inspected scope.

## 5. Exact completion and limits

The visual finish review is complete for the 15 supplied native captures. Candidate `af6ba8e0` requires the single F1 correction before a ship verdict. After that batch, rebuild once, bind evidence to the replacement APK hash, recapture the same required matrix, and return for a verdict pass scoring F1 resolved, partial, or unresolved. The approved visual world needs no replacement.

This review inspected supplied emulator evidence and source; it did not run builds, start emulators, rerun tests, edit production code, or publish anything. Reported PASS counts come from the supplied reports. Evidence covers the real `MainActivity`/`AlbumPanel`/`PhotoFilterEditor` flow with owned local JPEG fixtures, draft/recipe storage, and private full-size export. It does not establish real-phone performance, TalkBack operation, camera behavior, MediaStore publication, Nikon/NX color equivalence, or undo after process death.
