# Portrait selection feedback — 114 transient-mask confirmation

Decision: **SHIP for the requested transient selection feedback.** No blocking issue remains in this bounded source and visual review. This conclusion applies only to the candidate below and replaces the previous persistent-outline/badge proposal. Artifact identity, signing, upload, and publication checks remain the root agent’s responsibility.

Candidate: `0.23.3-beta (114)`, 9,531,300 bytes, APK SHA-256 `ed802564fcd94c368022e588e2d0584ab3d9b2a97d46dc7d36c6ef0d3aa2aecb`.

## Scope and evidence

Read the current `app/src/main/java/cc/huevia/ui/PhotoPortraitDialog.java` selection, mask queue, transient state/timer, comparison, cancellation, drawing, and disposal paths, together with `LatestPreviewQueue.java` generation and completion guards. This reviewer did not modify production code or start device tests.

Personally viewed 12 final images under `docs/validation/portrait-tools/ed802564/`. For each of the following runs, the evidence is inside its same-name nested directory:

- `20261029-094942-phone-2e063e09`
- `20261029-095042-font1.3-05d8f2a7`
- `20261029-095143-landscape-506f5140`

The four personally viewed images in every run are `09-second-face-selected-canvas.png` (exact on-phase drawing of the live PhotoCanvas), `12-feedback-ended-clean.png` (native idle screenshot), `10-clean-hold-comparison.png` (native comparison screenshot), and `11-face-picker-current.png` (native menu screenshot). The precise canvas capture is distinguished from a full-screen native screenshot because the feedback is intentionally brief.

Read all three `report.json` summaries: each reports `pass=true`, `stage=complete`, the exact candidate hash above, no failed checks, and removed fixtures. They contain 557, 557, and 571 check executions respectively, totaling 1,685. The testing agent identifies the compiled probe as `a0f9f690e102d444121ed8b87b1619a48bbf3c54d3ce44e53c1d3fccd470b86f` and reports 39 native screenshots plus 30 precise canvas frames. These tests were performed by that agent; this reviewer personally viewed only the 12 images listed above.

## Confirmed behavior

All three reviewed on-phase canvas captures show a translucent skin mask on the selected second face. The other face stays clear. No persistent face circle, face number badge, or label obscures the photograph. The reviewed idle and comparison screenshots are clean in every mode, while the menu clearly identifies the selected face with its native radio control.

Source timing is two 220ms on phases separated by a 140ms off phase, then idle. Timing starts when the asynchronous actual mask is ready rather than at the original tap. Re-selecting the same face starts the feedback again. The mask is generated through `PortraitPreviewFilter.mask`, using the selected face’s actual skin weights, rather than painting an oval approximation.

The test reports record real 0 → 1 → 2 → idle observations for photo taps, menu selection, same-face menu replay, and rapid switching. They assert exact actual-mask composites during both on phases, exact clean full-canvas pixels during the off phase and idle, and zero changed pixels in the other face’s central region. The reported timer samples include instrumentation scheduling and should not be read as exact touch-to-feedback latency guarantees.

## Cancellation and asynchronous safety

The main-thread flash state and timer are cleared when parameter or size adjustment begins, on relevant keyboard changes, effect selection, Fit, canvas interaction/zoom, comparison, and dismissal. Reported cancellation checks also verify that callbacks do not revive the flash after 700ms.

The mask queue’s epoch/latest guards, current face equality check, disposed check, and active-demand check prevent stale results from replacing the current feedback. Stopping an implicit flash resets its mask demand and releases the cached bitmap. Comparison exits drawing before any mask or healing marker; explicit mask controls and correction tools retain their separately requested overlay behavior. Disposal removes the timer, closes the queues, and schedules analysis bitmap recycling after auxiliary work on its serial executor.

## Limits

This is a focused confirmation of the final transient-mask interaction. It is not an independent device run, a review of every saved frame, a complete export/signing audit, or a certification of backend publication. No further visual polish is requested by this review.
