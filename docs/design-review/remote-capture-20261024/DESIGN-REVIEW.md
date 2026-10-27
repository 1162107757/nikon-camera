disposition: fix

Missing inputs: no QUALITY BAR card or critique-reference comp was supplied. No approved comp exists for this code-led local extension. Large project PRODUCT.md and DESIGN.md were sampled, not exhaustively reviewed.

## persistence

Pass for a design artifact awaiting human approval. PRODUCT.md and DESIGN.md exist; the local BRIEF.md and prototype.html opening contract preserve the existing Huevia identity and explicitly gate native implementation on user review. All 19 PNGs in SCREENSHOTS.json were opened and are valid browser-rendered design evidence for their named states. The intentional black photo workspace and dimmed interruption overlays are valid content. SCREENSHOT-ORIGIN.txt and the visible review disclosures distinguish the synthetic sample and illustrative readings from camera evidence.

REVIEW-CHECKS.json reports 77 browser assertions passing. This review inspected the supplied source and captures; it did not rerun those assertions or operate a browser, phone, or camera. DETECTOR.json is a degraded, pre-histogram regex result, not a clean detector bill. Roboto is appropriate to this Android Operate surface; the current source uses a neutral, offset preview shadow. No global documentation or production code was changed by this review.

## fidelity

| Salient element | Finding | Evidence |
| --- | --- | --- |
| TYPE | Match at default size; contradicted in the advertised 1.3× state | System sans, modest title and tabular exposure values suit the incumbent Android tool. However, landscape parameter labels become smaller when large type is enabled; portrait parameter labels do not scale. See material fix 1. |
| MATERIAL | Match | Complete photographic sample, restrained solid instrument surfaces, authored SVG icons, no imitation physical material. The sample is identified as synthetic; no real live camera or RAW result is claimed. |
| GROUND | Match | Warm review/Sync shell and near-black photo workspace follow the contract; the #F3B493 shutter and selected instruments retain the incumbent accent. |
| Entry, identity and first viewport | Match | board-main.png and entry.png keep the four existing root destinations, a small Nikon identity, an obvious local entry, complete frame, separate current values and dominant shutter. |
| Landscape topology | Adaptation | board-landscape.png and landscape.png move values and shutter to a right control rail, as BRIEF.md requires; the frame retains its ratio. |
| Current histogram | Match | board-histogram.png, histogram-detail.png and histogram-moved.png show Luma/RGB, named RGB channels in detail, small and expanded plots, and a movable instrument. Source keeps it outside image layout; the supplied assertions cover bounds preservation on toggle, mode and movement. histogram-data.js explicitly ties the illustrative bins to the same synthetic sample. |
| State semantics | Match | board-states.png, offline.png, view-lost.png and timeout.png distinguish stream interruption from disconnection and unknown capture result. prototype.js:33–35 gates repeat capture; :45–60 and :70–72 distinguish stale view and paused histogram; disconnect/reconnect retains unknown capture outcome. Disconnected readings are dashes. |
| Settings and modal behavior | Match | options.png and landscape-settings-large-font.png present independent live-view, grid and transfer controls. Source makes the underlying workspace inert, traps the panel focus and restores focus on close; the supplied browser batch covers Escape and landscape scrolling to disconnect. Native Back/insets remain implementation obligations. |
| Contrast | Contradicted in one retained shell label role | Active camera/workspace/settings/histogram text has clear contrast. The inactive Sync tabs use #756D64 on #EEECE7, approximately 4.31:1 for 13px text, below the 4.5:1 floor. See material fix 2. |

## ceiling

Reached for the stated composition and interaction-design scope after the two bounded corrections below. This verdict does not certify a native Android screen, actual system font scaling, predictive Back, TalkBack, safe-area behavior, camera capabilities, live-frame freshness, real capture confirmation or performance. Browser mockups are sufficient for this human design-review stage; the absence of a native build or connected Z6II is not a defect in this delivery.

## material_fixes

1. **[P2] Make the 1.3× review state honestly enlarge the exposed labels.** In prototype.css:3, `.device.large-type .parameter .label` fixes portrait labels at 11px, while `.device[data-orientation=landscape].large-type .parameter .label` reduces landscape labels from 11px to 10px; landscape identity, battery and title also have fixed-size clamps. Preserve the requested scale through spacing/reflow/scrolling instead of reducing it, then replace the same portrait-large-font.png and landscape-large-font.png captures. This is visible in the current captures and is not covered by the batch's bounds/target assertions.
2. **[P2] Raise inactive Sync-tab text contrast.** In prototype.css:3, darken `.sync-tabs span` from #756D64 enough to reach at least 4.5:1 against #EEECE7 while retaining the warm palette, then replace entry.png and board-main.png. The current pair is approximately 4.31:1; the 13px labels are normal-size text under the craft floor.

## keep

Keep the small camera identity, full-frame composition, quiet current-value strip, dominant shutter, independent stream/connection/capture semantics, and histogram that moves without changing the image rectangle.
