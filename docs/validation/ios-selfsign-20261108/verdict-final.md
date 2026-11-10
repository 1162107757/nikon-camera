## verdict

M1-only correction verdict, 2026-11-08. Build 0.1.0 (3), commit `a05afcb7e18995cb6f8a9e5c3ccfb9150e6831a0`, IPA 8,826,944 bytes, SHA-256 `3c49e6fedfb1fc5b6d42d41a2c001cc3917566ccd3dc81a797df0b3858c2eda9`. Viewed the exact new captures under `.tooling/ios-cloud/42454048494/artifacts/`: `presets-light.png`, `presets-dark-large.png`, `preset-detail-light.png`, `camera-light.png`, and `settings-light.png`. Original review and build2 verdict remain preserved as history.

- **M1 — partial:** actual photographs now visibly render in both preset appearances and detail. The detail image is correctly contained. The loaded grid images expose the direct layout regression R1 below, preventing completion of the photographic card fix.
- **M2/M3 — resolved, retained:** the prior dark accent and persistent connection-field label fixes remain visible in the new captures.
- **R1 — unresolved direct regression:** in both preset grid captures, the image/card content exceeds its column and viewport bounds; the left card title/category are clipped off the left edge, and image regions overlap the intended two-column bounds. Constrain each image/card to the available column width before applying its fill crop, preserving readable labels and grid spacing. This finding is limited to the newly rendered grid content.

## remaining

R1/M1 completion: contain the loaded grid photographs and text within their columns, then recapture light and dark/large-type grids. No fresh whole-surface review was performed. Physical iPhone/camera behavior, signing and installation remain outside this narrow visual verdict.

disposition: fix
