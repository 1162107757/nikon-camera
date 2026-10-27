# Composition dock 110 — final release visual review

Date: 2026-10-27. Final release: `110 / 0.22.1-beta`, APK SHA-256 `5f42f3a9733e86bc472ce56cae0e669609828d1a2027e050db39934e27ae0fe8`.

**Final release conclusion: the five final PNGs directly reviewed here—phone workspace, both font1.3 images, and both landscape images—pass this bounded visual review, with no required product correction. The coordinating task also confirmed final phone dock `01` is free of system teaching hints and its short labels are correctly aligned. The final release's three native reports all pass, with 747 checks and six PNGs in total. The earlier 771-check batch belongs to the UI-only candidate and is retained below as history, not as final release evidence.**

The coordinating task reports that this release rebuild changes only `UpdatePolicy.MAX_APK_BYTES` from 4MiB to 32MiB, with 262 frozen inputs and no drift; UI/RAW inputs otherwise match the previous UI candidate. All three reports below independently identify the final release APK SHA shown above.

Final probe SHA-256, read from `tests/composition-dock-device-probe/.build/provenance.json`: `0c443f4ba491c0f134e7469db24106b2270371235d30eeb9506277bc6a39bfb1`.

## Evidence reviewed

The independent final release review directly opened phone `02-composition-workspace.png`, plus `01-composition-dock.png` and `02-composition-workspace.png` for font1.3 and landscape, five PNGs in total. The coordinating task separately viewed final phone `01-composition-dock.png` and confirmed no system teaching hint or short-label alignment problem. This document does not claim that the independent reviewer directly opened final phone `01`.

| Configuration | Run | Native report | Visual status |
| --- | --- | --- | --- |
| phone | `20261027-232027-phone-0a1bdd50` | PASS, 258 checks, 2 PNGs | Final `02` independently reviewed and clean; final `01` confirmed clean and aligned by the coordinating task. |
| font1.3 | `20261027-232044-font1.3-2967af73` | PASS, 254 checks, 2 PNGs | Both final PNGs directly reviewed; no required correction found. |
| landscape | `20261027-232101-landscape-157392ea` | PASS, 235 checks, 2 PNGs | Both final PNGs directly reviewed; no required correction found. |

Each final release run's PNGs and `report.json` are in `docs/validation/composition-dock/5f42f3a9/<run>/<run>/`. The reports have no failed checks or instrumentation cleanup errors and use the shipping `preset_template` photo, fitted from 1448×1086 to 853×640 without overlaid test text. Its source SHA-256 is `067e391dcb5a61c20021dc9a4a7eb4c324829592a5de747dd1f4a958ce44c8d9`. Frame-wait checks vary by runtime, so the check counts are evidence from these exact runs rather than a fixed test-count requirement.

## Findings from the five directly reviewed final PNGs

- **Short labels and alignment:** 裁剪、旋转、拉直、透视 remain complete on one line. Icons sit consistently above their labels and the four entries are evenly spaced. 原图, the corner reset icon, and the selected 构图 navigation label do not collide with other controls. The former two large horizontal actions are absent.
- **Compact dock and photo space:** the font1.3 dock remains visually compact while preserving its enlarged captions. Its report records a 255px content area and 364px total dock, corresponding to 112fp content plus 48fp navigation at the actual font scale and density. The photo stage grows from 688px to 833px in height when entering composition. In landscape the content remains 196px/112dp in the existing fixed-width side rail; the photo stage retains the same bounds, with no side-rail overlap. The final release measurements match the previous UI candidate.
- **Workspace controls:** Cancel/Apply, the selected ratio, 垂直, `+30`, 旋转 90°, 重置, and the bottom summary are complete and aligned. Crop edges and grid remain clear. The photograph's 90° rotation is the intentional state produced by the preceding rotation test. Controls do not obscure the subject beyond the expected crop overlay.
- **Transient surfaces:** none of the five reviewed images shows the full-screen teaching overlay, a dimmed tutorial surface, or a remaining perspective popup. In the landscape workspace, the last ratio at the far right is partially exposed at the horizontal scroller boundary; this is the existing scrollable ratio row, rather than truncation of a fixed control.

Final release measurements, in physical screenshot pixels:

| Mode | Font scale | Composition content | Measured dock | Photo stage height, filter → composition |
| --- | --- | --- | --- | --- |
| phone | 1.0 | 196px (112dp) | 280px (160dp) | 845px → 957px |
| font1.3 | 1.3 | 255px | 364px | 688px → 833px |
| landscape | 1.0 | 196px (112dp) | 503px in the fill-height side rail | 587px → 587px |

No production layout or copy change is required by these five final PNGs. The phone workspace, large-font pair, and landscape pair are clean of the Android first-use teaching surface and unexplained whole-screen dimming.

## Previous evidence retained

The prior UI-only candidate used APK SHA-256 `852d17a89984f82f4af9d116c7bacb17b3243675299ce07de3bf237692b508c6`. Its clean three-mode batch passed 771 checks and remains on disk under `docs/validation/composition-dock/852d17a8/<run>/<run>/`:

| Configuration | UI-only candidate run | Historical result |
| --- | --- | --- |
| phone | `20261027-220003-phone-f19a046d` | Native PASS, 270 checks, 2 PNGs; `01` confirmed clean by the coordinating task. |
| font1.3 | `20261027-220018-font1.3-f52531b7` | Native PASS, 258 checks, 2 PNGs; both images directly reviewed with no required visual correction. |
| landscape | `20261027-220033-landscape-477e6d62` | Native PASS, 243 checks, 2 PNGs; both images directly reviewed with no required visual correction. |

That 771-check batch is not the final release artifact and must not be used in place of the final release's 747-check batch above. The still earlier screenshot-environment batch is also retained as history:

| Configuration | Previous run | Previous result |
| --- | --- | --- |
| phone | `20261027-213659-phone-6e5bdb8e` | Native PASS, 258 checks, 2 PNGs. The coordinating task found the Android “Viewing full screen” teaching overlay on `01`, so that PNG was rejected as final visual evidence. |
| font1.3 | `20261027-213713-font1.3-fea8ed51` | Native PASS, 264 checks, 2 PNGs. Both PNGs were directly reviewed and had no required visual correction. |
| landscape | `20261027-214449-landscape-9c8c7897` | Native PASS, 243 checks, 2 PNGs. Both PNGs were directly reviewed and had no required visual correction. |

Within the original UI-only candidate, the coordinating task corrected only screenshot test conditions: the runner temporarily records full-screen teaching as confirmed and restores the setting; capture checks for and closes a real `Got it` surface when present. The APK SHA stayed unchanged between that candidate's earlier blocked batch and its clean 771-check batch. The later final release rebuild has the distinct `5f42f3a9…` APK SHA and was revalidated with the separate final runs above.

## Scope

This update was one finite review of the specified final screenshots and their existing native reports. Only this review document was updated. No production or probe files were changed, and no ADB, build, new screenshot capture, or unrelated UI iteration was performed for this review. Pixel screenshots and native layout checks do not certify TalkBack or physical-device behavior.
