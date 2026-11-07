# Portrait tool entry hierarchy · 121

The user clarified that skin/face should appear like the adjustment menu's icon-and-text tool entries, and explicitly rejected a persistent bottom tab switcher. This supersedes the 119/120 tab designs.

The portrait workspace now opens on a compact entry row containing **皮肤** and **面部**. The row uses `PhotoWorkspaceUi.toolEntry`, the same helper now used for the primary adjustment menu's **人像** and **局部** entries: a 26 dp icon, 10.5 sp caption, 4 dp icon/caption gap, font-scaled 56 dp width, and transparent ripple. The existing caption baseline and API 26/27 fallback are retained.

Entering a tool hides both entry controls and opens only its child content. A top back arrow returns to the entry page; the entry page has the original close action. Android Back first handles sampling or an unconfirmed custom-color preview, then returns to the entry page, then closes the workspace. Apply continues to commit the complete portrait recipe once from either level. There are no skin/face tabs in the view hierarchy.

Confirmed edits, the selected face, advanced per-person tone scope and the last face tool survive navigation. A top-level return cancels temporary color previews, clears brush gestures and selection flashes, and finishes an active slider edit into one undo step plus a final preview frame. The entry page allows photo viewing and zooming without face selection or healing/brush commits. Pending recognition may complete and update the recipe while the entry page remains open, without navigating or flashing a face mask. Automatic full-image skin recognition starts on entry to the skin tool and remains independent of selecting a face.

No portrait model, segmentation, renderer, recipe format or persistence code changed from 120. This is a focused native navigation and layout check; unchanged host/model/export tests are not rerun or claimed as new results. All screenshots use the existing public-domain NASA fixture; no user photo is included.

The local candidate and all 288 production inputs are bound by `BUILD-IDENTITY.json`. The independent `PACKAGING-AUDIT.json` confirms the version, signer, APK v2/v3 signatures, ZIP alignment and byte-identical model/native/raw resources. It parses the actual DEX calls to verify that both primary entries and both portrait entries use the shared helper, and confirms the old skin/face tab tags are absent.

Focused native validation passed **730 phone**, **730 font-scale 1.3**, and **747 landscape** assertions: **2207 checks and 18 screenshots** in one batch, with no failures or retries. Coverage includes actual first-level/portrait entry geometry and styling, absence of entries/tabs in children, independent skin/face edits, native Back hierarchy, custom-preview and sampling cancellation, unfinished slider return with exactly one undo step, live rotation, Apply/Cancel and advanced-tone reopen. The root inspected the entry and child layouts across the device modes; no UI correction was required. `NATIVE-SUMMARY.json` binds the report, provenance and cleanup hashes.

Temporary photos, the primary-menu reference JPEG and draft, remote evidence and probe package were removed; personal swatches and system settings were restored and the target app was stopped. The package remains local and unpublished; no automation is created.
