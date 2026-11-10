---
version: 1
slug: native-preset-showcase
primary_target: app/src/main/java/cc/huevia/ui/PresetShowcaseRenderer.java
related_targets:
  - app/src/main/java/cc/huevia/MainActivity.java
  - app/src/main/assets/preset-showcase/manifest.json
---

# Native preset showcase · 155 / 0.30.1-beta

MODE: Operate. This is a narrow photography extension of [154 four homes](native-four-homes.md), preserving the incumbent layout, home-* palette isolation and existing editor paths.

THESIS: Make preset browsing visually varied with real source photographs while preserving truthful phone-simulation labels and same-photo comparison.

OWN-WORLD: Ten licensed Pexels photographs span portraits, landscape, coast, city, night, flowers and still life. Keep author/page/license/hash provenance in the pack manifest and JPEG comments. These sources are not camera/preset-specific reference shots; leave real previewUrl/previewUri records separate. UI material, type and shapes remain the existing scoped native rules.

STORY: MainActivity list and detail freeze a category/SHA-selected Source. Existing custom-template settings take priority. Apply the existing PresetPreviewProfiles approximation, retain the visible “模板模拟” badge, and compare against the identical unmodified photograph. Settings names the ten-photo default, lists actual sources or the single custom template, and opens the selected original with credit. Restore returns to the photography set.

FIRST VIEWPORT: Preserve154alternating photo cards and reachable gallery controls. Loading/failure states remain real. Source-original dialogs preserve full aspect ratio and credit; constrain image height so Close stays reachable in compact landscape and larger text modes.

FORM: One frozen Source owns version, source identity and cache key. Invalidated template requests cannot pair old effects with new originals. Only three bounded unmodified source-pixel entries are retained; image decode/render stays on workers, longest edge960px. Bundle964995JPEGbytes for offline rendering. PhotoFilterEditor, PresetSelectionPage, PresetPreviewRenderer and HoldToCompare source hashes are unchanged; no current-photo processing preview was replaced.

EVIDENCE: Final local APK b7d39e4930ca02a01174dcbdb26b7aa91d57dd84f2ebe20baf17305e44e61beb,34581880bytes; seven configurations167 assertion executions/35 screenshots, plus4 actual online-catalog checks/2 screenshots and10 model-output thumbnails. Asset SHA, ZIPCRC, V2/V3 and complete-file emulator install pass. Initial review FIX remains recorded; the [verdict](../review/preset-showcase155/verdict.md) is limited ship for F1 settings default/source viewer/restore wording plus direct regressions, including landscape Close/custom-template/gallery behavior. No whole-app/editor/154, physical-phone, camera-output or public-APK-release claim.

UPLOAD BOUNDARY: Ten independent private source assets were uploaded and read back byte-for-byte;390existing preset identities/revisions/status/file/sample state remained unchanged. No binding as real samples, public catalog edit, server behavior deployment or APK publication. Full provenance, receipts and source guards are in [155 record](../../docs/preset-showcase155.md).
