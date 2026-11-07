# Universal brush adjustment · 122

The user approved the discussed workflow: paint a region with one finger and immediate warm-white selection feedback, add/erase with size and feather controls, navigate with two fingers, finish with two brief mask pulses and a clean photograph while adjusting. The same region can hold multiple adjustments; different regions remain independent. This is an icon/menu interaction and introduces no bottom tab switcher.

## Usage

In 调节, tap the brush beside the parameter caption or the existing 局部 tool. Choose 新增涂抹区域, paint, and finish. The active region name appears beside the parameter; all 17 adjustment sliders and exact values, curves and HSL now address that region. The scope menu selects 全图 or an existing region, views/edits its selection, or deletes it. Viewing an unchanged mask does not create an edit. The original gradient and sampling-repair workspace remains available from 渐变与取样修复.

Human retouching accepts the same independent region. Skin tone and five exposed-skin settings combine the brush with automatic semantic skin detection; face light/shadow settings retain face geometry and protection. Generic exposure/color/detail adjustments remain free to affect clothing or backgrounds. Skin detection does not require a successful face selection. The global portrait-to-brush-to-regional portrait path remains a single transaction until regional Apply; cancelling returns to the original staged portrait editor.

## Model and rendering

`AdjustmentRegion` stores immutable id/name, enable/intensity, ordered additive/subtractive vector strokes, complete `PhotoAdjustments` (17 parameters plus curves/HSL), optional portrait and exposed-skin settings/mask. Brush coverage starts at zero. `PhotoLocalEdits` preserves all old methods and old v1/v2 bytes when no regions exist; regions use v3 with bounded counts, points and total serialized size.

Regions run after existing global/local/portrait effects and before composition/borders. Each region finishes its effect pipeline and blends once against that region's unchanged input. Zero coverage returns the original ARGB, including transparent hidden color. Spatial operators may read outside the brush for neighbors but cannot expand the write range. Grain coordinates and vignette center remain tied to the full oriented source, rather than a brush bounding box.

Point operations use bounded rows. Spatial/portrait region candidates use one private temporary file and bounded row memory instead of another full-size bitmap. Cancellation/failure/final completion removes the temporary candidate. Full export, export preview and detail rendering explicitly provide application-private scratch directories. The 24MP host probe runs with a 96MiB heap and no full-frame backing allocation.

The active editor scope is UI state; persisted regions and parameters belong to the photo/account draft. Undo/redo, previews, exact-value entry, per-parameter reset, curves/HSL, independent region deletion, owner/request invalidation and final export share the same immutable state. Global and regional parameter values are never silently copied or doubled.

## Evidence and publication

`BUILD-IDENTITY.json` binds the exact candidate APK and all production inputs. `INITIAL-CANDIDATE.json` records an earlier untested build before the final delayed-scope-menu request guard. It was never installed or published. Host, package and native evidence are recorded alongside this file after verification.

The final source-bound host matrix passed **152 parameter/EXIF cases and 1,446,177 pixel/state checks**, with **1184 legacy portrait checks**. `HOST-SOURCE-INPUTS.json` records the actual compiler inputs before/after the final verification and matches the production freeze. The 6000×4000 virtual-source test passed with a 96MiB heap, approximately 747KB thread allocation, one-row maximum IO and zero changed pixels outside the brush; its one 96MB scratch file was removed. That desktop test is bounded-memory evidence, not a phone-latency benchmark. `CAPACITY-AUDIT.json` bounds the complete worst-case draft below the existing 2MiB reader limit.

Independent package/DEX auditing passed for the final APK `a8c765ec68debe11611011bb77a890ef695b2bef38f109bdc2657a56ecb60e47` (33,432,332 bytes): 291 frozen inputs, unchanged signer, APK v2/v3 and 16KB ZIP alignment, unchanged 55 raw/native/model/notice entries, actual region-model/v3/renderer/brush definitions and private scratch-factory calls.

Successful installed-device runs passed **1072 phone**, **1072 font-scale 1.3**, and **1072 landscape** assertions: **3216 checks**, **18 UI screenshots** and **9 separately captured real Canvas flash frames**. Coverage includes actual live paint before finger-up, vector/cache agreement, erase/clear/undo, size/feather, two-finger navigation, two pulses with a clean gap, all 17 controls plus curves/HSL, independent regions, draft/history/owner, real full-reference/detail/EXIF6 output, automatic skin plus free clothing edits, a regional face-light example and the global-to-regional portrait transaction. Root reviewed the new layouts and overlay states across all three modes in one batch; no production/UI changes were needed after testing began.

Four historical attempts are retained separately for test-harness issues: native menu/window lookup, signed keyboard steps, and landscape menu animation/scroll targeting. The harness was corrected without changing the APK or skipping assertions. Only the three complete successful runs count toward 3216; each run retains its actual harness provenance. Final native cleanup and hashes are recorded in `NATIVE-SUMMARY.json` and the per-run cleanup files.

This package remains local under the user's manual-upload preference; no upload or automation is part of this task. Native screenshots use public-domain/synthetic fixtures and include no user photograph. Emulator checks do not claim physical-phone latency or general segmentation accuracy.
