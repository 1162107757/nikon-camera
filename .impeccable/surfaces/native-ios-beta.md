---
mode: Operate
primaryTarget: ios/Huevia/HueviaApp.swift
relatedTargets:
  - ios/Huevia/AppModel.swift
  - ios/Core/NikonCamera.swift
---

# Native iPhone beta

User request: quickly provide a real unsigned IPA for the user to sign and install. There is no user Mac; build using the existing private repository's macOS CI. No TestFlight, App Store, website release or Android changes are requested.

THESIS: get a preset ready, connect the camera, explicitly choose and confirm a slot, then verify actual camera readback.
OWN-WORLD: inherit Huevia's existing photography and warm accent, while using iOS semantic surfaces, SF text styles, SF Symbols, standard tabs, navigation, sheets and system file sharing.
STORY: browse or add a local preset; pre-download it; switch to the camera connection when required; return directly to the pending import after connecting; confirmation precedes a single guarded write.
FIRST VIEWPORT: real managed online catalog with varied licensed photographic reference images, search, source selector and local file entry. Photos are explicitly reference images, not fabricated camera results.
FORM: compact native iPhone app, three destination tabs (presets, camera, settings), NavigationStack, segmented source picker, file importer, native share and confirmation dialogs. Dynamic Type and light/dark appearances are required.

Scope: iPhone / iOS 16+. NCP/NP3 download and local sharing; Z6II-only bounded Wi-Fi PTP/IP, strict legacy NCP conversion subset, snapshot revalidation and exact registration readback. The native iOS physical camera path remains unverified. Other camera models, NP3 camera writes, photo editing and RAW are not promised in this beta.

Visual authority: existing DESIGN.md and the ten project Pexels photography assets. No new visual identity or approved comp. Native device captures from the exact cloud build are required; browser mockups do not count. This work does not change Android tokens or any existing surface brief.
