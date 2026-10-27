disposition: fix

Inputs: the requested hyphenated reviewer Markdown file is absent; this review uses the shipped agents/impeccable_finish_reviewer.toml. No separate QUALITY BAR card was supplied. No native detector ran. A seeded concept roll is inapplicable to this user-approved extension of the incumbent world.

## persistence

PASS for the reviewable persistence inputs. PRODUCT.md exists; DESIGN.md records the incumbent warm Huevia surfaces, native system type, vector icons and dark photo tools. The user’s approved prototype and IMPLEMENTATION-CONTRACT.md record the visual authority and authorization. RemoteCaptureView.java:24–31 contains THESIS, OWN-WORLD, STORY, FIRST VIEWPORT and FORM. Its code-led FORM correctly preserves the approved prototype instead of initiating another identity or concept round. Final remote-capture documentation is explicitly pending this review; no post-review documentation completion is claimed here.

Evidence gate PASS: individually opened all 36 current PNGs named by UI-MATRIX.json, plus the scoped hero and all four named prototype references. Current roots are phone-ae8962d4, font1.3-040024b5, landscape-c534bb91 and dark-b079dac3 under 8bfbc7ba. Every root contains valid ready, entry, options, histogram, histogram-moved, captured, view-lost, unknown and offline captures in its run/ directory. Portrait captures are 1080×2424; landscape captures are 2424×1080. Content and orientation match their names; status/navigation areas are present. Fitted-image letterboxing and dimmed modal backdrops are intentional. The scoped hero is byte-identical to current phone ready.png (SHA-256 7ef59302a2ad2a686d3b3d773d625f2e920a159fd3f4a18903b7c7785c01113a). Historical FAIL/invalid-orientation cohorts were excluded.

Candidate scope: 95 / 0.20.0-beta, APK SHA-256 8bfbc7badae56ac6e65bc0b8452a56a4a8fafebc801cfcdb053f43be2058eea8. The packet records 214 production inputs. This review neither rebuilt the APK nor changed production, tests, other documentation or device state.

## fidelity

Reference inventory: a compact title and small camera identity; a near-black uninterrupted camera workspace; fitted complete frame; small mode strip and three tools; movable lower-left histogram; four prominent readings; centered double-ring peach shutter between recent photo and focus; separate save-target/transfer row; bottom settings and histogram sheets; landscape image-left/217dp-controls-right composition. These are the comparison targets from portrait.png, landscape.png, board-main.png and board-histogram.png, not a replacement concept.

| Salient element / promise | Classification | Evidence and consequence |
| --- | --- | --- |
| TYPE | match | System sans, modest title/model text and large numeric readings preserve the approved character and hierarchy. Native sp scaling at 1.3 remains legible without visible truncation in the required views. The user explicitly requested small model text and icons. |
| MATERIAL | match | The real raster frame remains the focal content; native vector controls, flat dark instruments and peach shutter preserve the prototype’s material language. No imitation glass, decorative physicality or production demo illustration is introduced. |
| GROUND / OWN-WORLD | match | Pixel sampling gives RGB (18,19,19), #121313, in both the approved portrait header at (200,60) and native phone header at (600,200). The near-black temperature and peach #F3B493 world are retained. |
| Synchronization entry and root navigation | adaptation | The new dark entry retains the incumbent native Sync structure and four destinations. Existing “相机照片 / 边拍边传 / 已下载” wording and landscape rail are product truth preserved by BRIEF.md and the explicit parallel-task agreement. |
| Full frame / THESIS | match | All ready captures show the complete reference frame with proportional fit. Device aspect ratio changes the amount of surrounding black; no crop or stretch is visible. |
| Compact model/battery, mode and three tools | match | The small identity and icon treatments remain subordinate to the image; the native targets are larger than their visible glyphs. |
| Tool selected state and toggle off state | contradicted | In every current ready view, the active histogram icon remains white; the approved reference makes it peach. Native settings and transfer switches keep peach thumbs even when off, whereas the approved off state is neutral. See M1. |
| Landscape overlay tools | contradicted | Approved prototype.css explicitly backs the tool-button group with rgba(11,12,12,.82). Native RemoteCaptureView.java:75 makes the row transparent and backs only the mode label. The current 4:3 frame happens to leave black behind the three glyphs, so these captures do not establish contrast on a wider/bright frame. See M2. |
| Four readings and primary shutter / FIRST VIEWPORT | match | Portrait single row and landscape two-by-two readings remain ahead of the large peach double-ring shutter. The 217dp rail and smaller 74dp landscape shutter follow the brief. |
| Movable histogram and expanded luminance/RGB controls | match | Current/moved instrument captures retain the small chart independently of the fitted image; expanded RGB is visibly selected and plotted. Paused frames are explicitly labeled “上次取景 · 已暂停”. |
| Native sheet layout and large type | adaptation | Native Dialog/ScrollView implements the approved bottom/right sheet topology, protected focus and close target. Landscape options/histogram content continues below the viewport in a scroll container, as permitted by the native sizing/insets requirement; no unreachable lower action is inferred from the initial scroll position. |
| Capture/result and interruption / STORY | match within evidence | Confirmed capture shows the filename and recent thumbnail. View loss preserves readable parameter/shutter controls while disabling focus; offline clears readings and disables shutter; unknown result uses distinct warning copy and a disabled shutter. The packet’s 81 checks per mode cover the journal and explicit result check; the counts are repeated configuration checks, not 324 independent scenarios. |
| Optional manual transfer recovery | contradicted | Source inspection establishes an enabled offline action that silently does nothing for a retained, unimported JPEG; the provided offline screenshots have an already-imported photo and do not exercise that branch. See M4. |
| Readable action failure / STORY | contradicted | Source inspection shows IDLE autofocus/shutter rejection messages replaced by the normal ready message on the next short poll. This can erase the explanation before it can be read. See M3. |
| Truth and capability limits | match within evidence | BRIEF.md labels the in-memory Nikon peer and sample image as synthetic test evidence, and the native filenames visibly use QA_REMOTE. The production UI does not label preview histograms as RAW; unavailable readings use —. No real camera, Wi-Fi route, firmware interoperability, sustained performance or full TalkBack certification is established. |

## ceiling

The native ceiling is not reached until state and recovery feedback are reliable. The approved world’s most useful unused device is the bounded dark backing behind overlay tools, which protects visibility without enlarging the icons or competing with the frame. Native selected/unselected colors must communicate the same state as the prototype. Android transient feedback must remain readable through periodic parameter/frame refreshes. No additional decorative treatment, new display face, concept round or animation is needed.

THESIS, OWN-WORLD and FIRST VIEWPORT are kept in the captures except for M1/M2; STORY remains open at the M3/M4 failure paths. FORM is consistent with a native Android extension. The first viewport’s memorable instrument is still the complete frame above the single peach shutter. System Back, lifecycle and capability behavior are supported by the packet/code, not newly exercised by this read-only review. Emulator screenshots and reported checks do not prove hardware gesture quality or performance.

## material_fixes

1. M1 — [P2, fidelity/state] Restore the approved control-state colors: selected histogram/grid glyphs must actually render peach #F3B493, and off switch thumbs must be neutral rather than the same peach as on. RemoteCaptureView.java:129,142,152 and all current ready/options captures show the affected treatment; confirm native selected and unselected states without enlarging the small glyphs.
2. M2 — [P2, fidelity/contrast] Restore the approved bounded dark backing around the three landscape overlay tools; RemoteCaptureView.java:75–80 currently protects only the mode label. Confirm the group over a bright frame whose aspect ratio extends beneath the controls, keeping full-frame fit and the 217dp rail.
3. M3 — [P2, floor/STORY] Preserve actionable autofocus and rejected-shutter errors long enough to read and recover. RemoteCaptureController.java:150–155 rewrites an IDLE message to “已连接，可以拍摄” on the next poll after the error paths at :193/:228 schedule about 250ms; keep action feedback separately or use durable native feedback, and confirm an actual rejection while preview/parameter polling continues.
4. M4 — [P2, floor/STORY] Make manual recent-photo import truthful while disconnected: RemoteCaptureView.java:176 still offers “传入 App” for an unimported JPEG and closes its sheet, but RemoteCaptureController.java:235–236 returns silently when access is null. Retain cached-photo viewing, then disable/explain the unavailable import or provide an explicit reconnect-and-retry route; confirm the transfer-off → capture → disconnect → recent-photo path.

## keep

Keep the complete fitted frame, small identity/icons, peach double-ring shutter, movable frame-coupled histogram with explicit paused state, read-only readings, unknown-result gate, and the existing Huevia navigation/94 behavior while applying these four fixes.
