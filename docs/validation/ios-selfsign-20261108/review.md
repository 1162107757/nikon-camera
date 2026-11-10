disposition: fix

Initial finish review, 2026-11-08. Scope: the first native iPhone beta UI and clear usable flows, without requiring full Android parity. Build 0.1.0 (1), commit `c7f6cd84822cdc924bedb80289077e98bdb8da15`. Simulator evidence: `.tooling/ios-cloud/42452334812/artifacts/{presets-light.png,presets-dark-large.png,camera-light.png,settings-light.png}`; iPhone 17 Pro / iOS 26.2, light and dark with extra-extra-extra-large Dynamic Type. These original artifacts remain frozen. The blank image regions are rendered resource defects, rather than missing capture files.

No approved comp or quality-bar card applies. Authority: `.impeccable/surfaces/native-ios-beta.md`, relevant existing Huevia product/design roles, native iOS conventions and the Impeccable craft floor. Review covers supplied Simulator captures and sampled UI/model source; physical iPhone, camera, user signing and installation remain unverified. No App Store, TestFlight or site publication was reviewed.

## persistence

Pass. PRODUCT.md and DESIGN.md exist; the scoped native beta contract records the authorized iPhone adaptation. Existing Android records remain historical authority.

## fidelity

| Element | Finding |
|---|---|
| TYPE | Match: system text styles, native large titles, readable large-type wrapping. |
| MATERIAL | Missing: every photographic card region is blank in both preset captures. This is a rendered resource defect. |
| GROUND | Acceptable adaptation: semantic iOS grouped surfaces and black Dark Mode follow the native contract. |
| Navigation | Match: three destinations, native tabs, navigation stacks and grouped lists. |
| First viewport | Contradicted: catalog, search and source controls render, but the promised photography is absent. |
| Import flow | Match in source: explicit slot selection, overwrite warning, confirmation and readback-dependent success. Hardware behavior is unverified. |

## ceiling

Native navigation and layout conventions are established. Finish remains limited by missing photography, dark-mode action contrast and unlabeled populated connection fields.

## material_fixes

1. **M1 — Restore bundled photographs:** fix resource resolution at the original `ios/Huevia/HueviaApp.swift:66` and `:101`; verify actual photos in both preset appearances and detail, then recapture the corrected build.
2. **M2 — Adapt the accent for Dark Mode:** the original fixed tint at `ios/Huevia/HueviaApp.swift:10` becomes too dark for the active tab label and icon; use an appearance-aware warm accent with sufficient foreground contrast.
3. **M3 — Keep connection field identities visible:** the original `ios/Huevia/HueviaApp.swift:132-133` displays `192.168.1.1` and `15740` without visible labels; retain “相机 IP” and “端口” beside their populated values.

## keep

Preserve the compact native structure, clear beta limitations, reference-image disclosure and explicit guarded import confirmation.
