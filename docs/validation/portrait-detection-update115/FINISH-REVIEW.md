# 115 · Face detection and update prompt finish review

Decision: **SHIP for these scoped changes and the eight inspected update-prompt screenshots.** No blocking defect was found in the reviewed production code, evidence or changed prompt states. This review does not certify general face-detection accuracy or publication; the root agent owns the final APK identity, signing, public metadata and upload checks. No additional UI polish is requested.

Candidate: `0.23.4-beta (115)`, 9,531,300 bytes. APK SHA-256: `ae2f90cf0580f265a893036b2977c9b36547b2b3000c4a6296e69c43249721c2`.

## Production scope

Compared the 114 production input manifest with the current tree: only `app/build.gradle`, `app/src/main/java/cc/huevia/album/PhotoPortraitDetection.java` and `app/src/main/java/cc/huevia/ui/UpdatePanel.java` changed. The reviewed detector SHA-256 is `1f40455e024bcfa71c24b0f3d4431fbc0ec5ed35269d3441a12c8ad9fd4ab03d`; the reviewed UpdatePanel SHA-256 is `b48b50eaa75482873befd9f2eebed3ac8f81cd85ef1cf057168bcb688736bdcf`.

Detection now requires a mapped mirror match and a matching 0.85-scale view, with a 0.70-scale fallback only when a mirror-supported candidate lacks 0.85 support. All detector inputs originate in ARGB luminance before RGB565 conversion. Mirror eye coordinates and raw roll are mapped back before geometry comparison; confidence remains 0.35, and no fixed skin-colour rejection or largest-face-only selection was introduced. One-to-one nearest matching and conservative almost-coincident eye-pair merging retain separate adjacent people. The stronger primary-confidence proposal survives a duplicate. Cancellation checks and bitmap `finally` cleanup remain in place.

The update prompt hides its positive action while checking, downloading or verifying, leaving the existing status/progress area to communicate progress. Retry and install return as enabled actions with a 48dp minimum height and 12dp corner radius. The click handler, stale-release-key guard, mandatory-update exit path and existing download/install checks were not changed by this presentation patch.

## Exact personal image inspection

Personally viewed one batch of **eight native screenshots**, four states at each font scale. Both evidence runs bind the installed candidate above. The depicted `99.0.1-beta` release and long repeated notes are synthetic component-test data, not the actual published release.

| State | Font scale 1.0 | Font scale 1.3 |
| --- | --- | --- |
| Downloading | [04-downloading](../update-prompt-115/ae2f90cf/20261029-102431-font-1-0-595573/20261029-102431-font-1-0-595573/04-downloading.png) | [04-downloading](../update-prompt-115/ae2f90cf/20261029-102446-font-1-3-f62bf9/20261029-102446-font-1-3-f62bf9/04-downloading.png) |
| Verifying | [06-verifying](../update-prompt-115/ae2f90cf/20261029-102431-font-1-0-595573/20261029-102431-font-1-0-595573/06-verifying.png) | [06-verifying](../update-prompt-115/ae2f90cf/20261029-102446-font-1-3-f62bf9/20261029-102446-font-1-3-f62bf9/06-verifying.png) |
| Retry after error | [05-download-error](../update-prompt-115/ae2f90cf/20261029-102431-font-1-0-595573/20261029-102431-font-1-0-595573/05-download-error.png) | [05-download-error](../update-prompt-115/ae2f90cf/20261029-102446-font-1-3-f62bf9/20261029-102446-font-1-3-f62bf9/05-download-error.png) |
| Ready to install | [07-ready-to-install](../update-prompt-115/ae2f90cf/20261029-102431-font-1-0-595573/20261029-102431-font-1-0-595573/07-ready-to-install.png) | [07-ready-to-install](../update-prompt-115/ae2f90cf/20261029-102446-font-1-3-f62bf9/20261029-102446-font-1-3-f62bf9/07-ready-to-install.png) |

The redundant disabled “正在下载” / “正在校验” filled button is absent in busy states. The progress text and bar remain readable, with the existing recheck and exit actions clearly separated. Retry/install labels fit at both sizes, and the slimmer corners and padding avoid the former capsule appearance. Long notes remain in the scroll area above the action row. No clipping or overlap affecting these changed actions was observed. This personal image verdict is restricted to these eight modal views; it is not a new audit of the dimmed parent screen, other update surfaces, themes or device classes.

## Validation evidence read

- Read both component reports: font 1.0 has 404 passing checks; font 1.3 has 405. Together they record 809 check executions and 14 native screenshots. Their declared scope is production UpdatePanel UI with synthetic validated release/status callbacks; no metadata HTTP, DownloadManager, installer or MainActivity implementation is exercised. The probe reports zero worker tasks and checks hidden busy actions, restored retry/install actions, long-note layout and stale-click rejection.
- The reviewer previously implemented and executed [the production geometry suite](../../../tests/portrait-detection-java/README.md): **87 checks passed**, using the real Android API35 jar while executing only pure production geometry on the host JVM. The stored result binds the detector SHA above. Boundary ratios, spatial distances, raw-roll agreement and angular wrap, one-to-one nearest assignment, distinct nearby faces, malformed/non-finite anchors, input immutability, cancellation and interruption are covered. Android bitmap and native detector stubs are not executed by this suite. It was not rerun during this final screenshot pass.
- Read [PRIVATE-DETECTOR-SUMMARY.json](PRIVATE-DETECTOR-SUMMARY.json): all 16 positive configurations retain their expected faces one-to-one, representing 20 true-face observations; four CC0 texture/object negative cases return zero faces. There are **two independent human subjects**, not twenty people: two supplied screenshots derive from the same private portrait subject, and the public astronaut plus duplicated collage derive from one further subject.
- The reproduced false detection is specifically the supplied tinted display screenshot at width720: baseline114 returned two regions and candidate115 returned one, with the correct face retained. The untinted reference at dialog width960 did not reproduce the reported second detection. The unavailable original camera pixels are not certified by this result.
- Read the final installed portrait phone report at `../portrait-tools/ae2f90cf/20261029-102817-phone-7fa232a7/20261029-102817-phone-7fa232a7/report.json`: pass=true, stage=complete, same candidate SHA, 557 check executions and 13 native screenshots. This retains the a0f9 portrait probe's full pipeline/interaction scope. I did not rerun this probe or personally inspect those thirteen portrait screenshots in this finish pass.

The UpdatePanel probe revision is a13f and the portrait probe revision is a0f9. Test repetitions and screenshots are not independent photographic accuracy cases.

## Limits and performance

The detector uses three native passes, or four when the extra scale is needed. The sanitized emulator measurements are approximately **98–490ms for the positive configurations** and **194–596ms for the negative configurations**. These are observations on the owned emulator, not a physical-phone latency guarantee or a promise that every image finishes within490ms.

The private sources are screenshots, including one with a transient coloured mask, rather than the original photo. The official NASA/CSA four-person group download failed TLS and was not executed; no result or four-person recall claim is inferred from it. The evidence does not establish broad demographic, pose, occlusion or lighting accuracy. User pixels and raw private diagnostics remain outside this review document and the APK.

Existing portrait drafts can retain older saved face regions. They should not be silently rewritten or have independent adjustments deleted; rerunning “自动选脸” is the explicit way to apply the new detector to the same saved photo.

## Handoff

Source review and this bounded image pass found no blocker to shipping the focused detection filtering and prompt presentation changes. Final package/signature verification, beta mandatory policy, public download bytes and publication proof remain with the root agent. No simulator access, production changes, new test run or deployment was performed during this finish pass.
