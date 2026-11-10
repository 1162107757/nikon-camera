## verdict

Narrow correction verdict, 2026-11-08: only M1/M2/M3 and regressions introduced by that batch. Build 0.1.0 (2), commit `9f84135bdae5d773b8a3c460292581aa857695cd`, IPA 2,609,899 bytes, SHA-256 `51eeb94cad2fe6419bd9ca923f9c093f8361c0b6b6b999d2e05b7a69427230ce`. Viewed the exact new paths under `.tooling/ios-cloud/42453153966/artifacts/`: `presets-light.png`, `presets-dark-large.png`, `camera-light.png`, `settings-light.png`, and `preset-detail-light.png`.

- **M1 — unresolved:** both preset grids still have completely blank photographic regions; the additional detail capture also has a blank photographic region. Bundled JPEG presence and explicit `.jpg` lookup changes have not produced visible photographs. Score is based on the new rendered captures.
- **M2 — resolved:** the dark large-type capture visibly shows the active tab and add control in the lighter warm accent; light-mode controls retain the inherited warm accent. Source uses appearance-aware AccentColor and OnAccent assets.
- **M3 — resolved:** the camera capture visibly retains “相机 IP” and “端口” beside their populated values.
- **Batch regressions — none observed** in the supplied correction captures. This is a narrow fix verdict, not a fresh whole-surface review or hardware certification.

## remaining

M1 remains open: restore actual rendered bundled photography in both preset grid appearances and detail, then provide new captures from the corrected build. Physical iPhone/camera behavior, user signing and installation remain outside this visual verdict.

disposition: fix
