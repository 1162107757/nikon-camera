# Face selection feedback — 114 final confirmation

Decision: **SHIP for this focused UI fix.** No blocking defect remains in the reviewed source and screenshots. This is the confirmation of the corrected label placement; the earlier 113 review is not evidence for this candidate. Release artifact checks and publication remain the root agent’s responsibility.

Candidate: `0.23.3-beta (114)`, 9,531,300 bytes, APK SHA-256 `ec22f079fcc4fc71a4a01b80a83cf8a06e1385768ed0a3f76edb15f4353e77b7`.

## Exact review scope

Read the current `app/src/main/java/cc/huevia/ui/PhotoPortraitDialog.java`, concentrating on selection state, `onDraw`, `drawFaceIndicator`, and `faceLabelBounds`. This review did not modify production code or start device tests.

Personally viewed nine native screenshots under `docs/validation/portrait-tools/ec22f079/`:

- `20261029-093134-phone-1bac50a3/20261029-093134-phone-1bac50a3/`: `08-first-face-selected.png`, `09-second-face-selected.png`, `10-clean-hold-comparison.png`, and `11-face-picker-current.png`.
- `20261029-093244-landscape-84c9537e/20261029-093244-landscape-84c9537e/`: the same four filenames.
- `20261029-093208-font1.3-4c7b7a37/20261029-093208-font1.3-4c7b7a37/`: `09-second-face-selected.png` only.

Also read the three runs’ `report.json` summaries: all report `pass=true`, `stage=complete`, and the exact candidate hash above; check executions are 334, 334, and 348 respectively. These runs were performed by the testing agent, not this reviewer. The unviewed screenshots are outside this reviewer’s personal visual scope.

## Confirmed result

The peach outline, dark under-stroke, and face number identify the selected target while the normal adjustment mask is hidden. Moving selection from face 1 to face 2 moves the feedback, and the top selector agrees. The popup uses a clear native radio selection. In the reviewed phone, large-font, and landscape screenshots, the label sits below the selected face and leaves its eyes, nose, and mouth clear.

The label placement now tries above, below, right, and left. A candidate must fit wholly in the photograph’s visible safe region, avoid the top and bottom 48dp toolbars, and avoid every detected face’s rotated bounding rectangle. If no candidate fits, it omits the label and retains the outline and top selector. This removes the prior landscape obstruction without adding a new layout branch.

The source exits comparison drawing immediately after the initial image, before all face and mask markers. Both reviewed comparison screenshots show clean faces without the selection outline or badge. Changing the selected index refreshes the UI without modifying portrait parameters or committing edits.

## Limits

This is a bounded confirmation of selection feedback and the label obstruction fix. It does not independently validate detection accuracy, all zoom/face positions, export pixels, signing, public download bytes, or backend state. No further visual polish is requested by this review.
