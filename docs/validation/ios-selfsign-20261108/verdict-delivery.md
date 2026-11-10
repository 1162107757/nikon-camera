## verdict

Delivery correction verdict, 2026-11-08. Narrow scope: remaining M1/R1 and direct regressions only; prior M2/M3 resolution is retained. Build 0.1.0 (4), commit `02edb9878c10428e41f5aa9be9fe7916b4edebb8`, IPA `dist/Huevia-0.1.0-ios-unsigned.ipa`, 8,828,024 bytes, SHA-256 `eb6e5fc1619c11a2f420d07127b896dbb9d440273bbe2ab803badbf442628716`.

Viewed these exact final Simulator captures under `docs/validation/ios-selfsign-20261108/final/`: `presets-light.png`, `presets-dark-large.png`, `preset-detail-light.png`, `camera-light.png`, and `settings-light.png`. Prior build1/build2/build3 captures and reports remain historical evidence.

- **M1 — resolved:** actual photographs visibly render in the light and dark/large-type preset grids and the detail view; detail retains its reference-image disclosure.
- **R1 — resolved:** both preset grids now keep photographs and text inside their separate columns, with visible margins and spacing. Left-side titles/categories are readable, and the long right-side title wraps within its column at large Dynamic Type.
- **M2/M3 — resolved, retained:** the lighter warm dark-mode accent and visible populated IP/port labels remain present.
- **Direct regressions — none observed** in these correction captures. No fresh whole-surface hunt was performed.

## remaining

Clear for the scored visual fixes M1, M2, M3 and direct regression R1. This ship decision covers those fixes only. Physical iPhone/camera behavior, user signing and installation remain unverified; this is not App Store, TestFlight or site publication approval.

disposition: ship
