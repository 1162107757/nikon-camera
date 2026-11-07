> Superseded: this initial phone-only review was later rejected by the landscape visual review. Draft 113 was not published. See ../portrait-face-selection-114/FINISH-REVIEW.md for final confirmation.

# Face selection feedback review — 113

Decision: **SHIP for this UI fix**, conditional on the root agent completing the final phone, font 1.3, and landscape probe runs successfully before publication.

Reviewed candidate: `0.23.2-beta (113)`, APK SHA-256 `f47b00dc462d4f10d090adb3169ee3c1a8a780e9167df8b7bd569b3882a5ec5e`, 9,531,300 bytes. This is a focused source and visual review; it does not independently certify the APK, the full test suite, or publication.

## Scope and evidence

Read the current `app/src/main/java/cc/huevia/ui/PhotoPortraitDialog.java`, especially face selection, refresh, comparison, canvas markers, and touch selection. Personally viewed these native screenshots from `docs/validation/portrait-tools/f47b00dc/20261029-092204-phone-28468e84/20261029-092204-phone-28468e84/`:

- `08-first-face-selected.png`: the first face has a clear peach outline with dark under-stroke and a readable “人脸 1” badge; the other face remains clear. The header agrees with the selected target.
- `09-second-face-selected.png`: the outline and badge move to the second face, and the header changes to “人脸 2 / 2”. Normal parameter adjustment retains this feedback with the mask hidden.
- `failure.png`: the face popup visibly shows the second face selected through the native radio control. The filename reflects a probe locator failure; the reviewed screen itself displays the correct state. The root agent reports that the probe is being corrected to inspect the radio sibling without weakening the assertion.

## Findings

No blocking defect remains in the reviewed feedback. The badge placement now avoids the stage’s top and bottom 48dp toolbars. The photograph retains its normal colors, and the selected target is explicit through the outline, badge, highlighted header, and popup radio state.

The source returns immediately after drawing the initial image when `compare` is active, before any face, mask, or healing markers are drawn. Selection updates the selected index and refreshes the UI; it does not alter portrait parameters or commit edits. This supports clean comparison and preserves the existing editing boundary, subject to the final runtime probes.

## Limits

Personally reviewed only the three phone screenshots listed above. No independent device run, landscape screenshot review, font-scale screenshot review, export comparison, or backend action was performed in this review. Final release approval remains conditional on the root agent’s completed three-mode regression and artifact checks.
