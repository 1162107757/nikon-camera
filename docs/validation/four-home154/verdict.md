## verdict

Scored the same seven `.tooling/four-home154/native-final/<mode>/01-presets.png` paths after replacement, for code 154 / `0.30.0-beta`, APK SHA-256 `9636cfe8dde97c1af3863754b16557ddf1620b75e2e6d3b9230a6705cc34b8b9`. All seven captures are valid, show their named viewports/states, and match the frozen copies under `docs/validation/four-home154/native`. The actual APK and six production source hashes match the corrected review-ready manifest.

1. **Resolved — F1, category capsules and hit bounds.** Phone, 1.3 font, narrow, dark, tablet, compact, and tablet-landscape now visibly show complete active/inactive capsules enclosing their centered labels. The explicit 48dp layout height and minimum width preserve the 36dp painted interior; each rendered category's `category-hit-48` and `category-capsule-encloses-text` assertions pass in the supplied corrected reports. Text remains legible and the horizontal category track remains usable.
2. **Resolved — F2, passive local metadata spacing.** The same seven recaptures visibly show compact name/category stacks and a deliberate small gap before the next photograph, with no caption/photo collision. The local category now wraps its content with 3dp/2dp vertical padding. The online metadata/download branch retains a 48dp action parent with the 3dp progress bar overlaid, and the noncompact/detail branch remains preserved in the sampled corrected source.

No material regression introduced by this correction batch is visible in the seven scored recaptures. The corrected native reports record 333 passing assertions; these corroborate the control geometry and bounded interactions, without substituting for visual inspection or certifying hardware behavior.

## remaining

Clear for F1 and F2. This ship covers the scored fixes only, not the whole surface. The original full review remains the historical review record. PRODUCT/DESIGN documentation was still being merged at scoring time and remains the documenter's delivery handoff; no new persistence, whole-app, physical-camera, TalkBack, performance, or publication certification is implied.

disposition: ship
