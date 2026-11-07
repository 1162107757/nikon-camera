---
version: 1
slug: camera-preset-import
primary_target: app/src/main/java/cc/huevia/MainActivity.java
related_targets:
  - app/src/main/java/cc/huevia/ui/HueTheme.java
---

# Preset import contract

MODE: Operate. Refine the incumbent native Android Huevia surface: neutral layers, charcoal text/actions and orange selection/link accents. Preserve the existing preview, rounded containers, system sans typography and native dialogs; this is a surface record, not a replacement visual world.

STORY: Browse unified online/local presets by style, inspect the preset, then confirm a camera import. Normal browsing removes NCP/NP3 format categories and badges, including stale format filters. Original files, extensions, format metadata and source hashes remain intact internally. Current controlled USB/Wi-Fi import support is Nikon Z6II only; compatibility is checked before writing.

FORM: Keep supporting copy concise at 12–15sp. The confirmation body scrolls above a fixed import footer. C1–C9 use a three-column grid with a distinct selected fill and outline, slot names/empty states, and an explicit overwrite confirmation. “调整 ›” and “选择 ›” keep compact 13sp text with at least 48 × 48dp touch bounds. Preserve native scrolling and reachable actions at large font sizes and in landscape.

ADAPTATION: Separate compatible conversion from partial adaptation. Partial/lossy conversion discloses the retained and omitted effects, with acceptance unchecked by default and import disabled until explicit consent. Changing adaptation values requires renewed consent. Shooting parameters cannot replace discarded colour effects; unknown or damaged inputs are not guessed into a conversion.

PARAMETERS: “拍摄参数 → 选择” is optional and defaults to no changes. White balance and exposure compensation are user choices; Kelvin appears only after explicitly choosing “指定色温”. “全部不调整” clears the choices. Values affect subsequent shooting separately from the C1–C9 Picture Control; import does not switch the camera's active preset.

RESULTS: Show preset registration/readback separately from parameter outcomes. Immediate USB results and connection-status results share the complete parameter detail, including before/target values and adjusted-and-verified, skipped, rejected or unverified states. A saved preset must not imply every parameter succeeded. Uncertain writes lead to explicit read-only checking; no automatic retry or rollback. Preserve the reminder to select the target slot on the camera and test the effect.

TRUTH: Implementation in MainActivity.java (preset detail, renderConfirmation, editCameraParameters and import outcomes) and HueTheme.java governs this brief. Feature scope and conversion/parameter details are in docs/camera-preset-import137.md; PRODUCT.md supplies product context.

EVIDENCE: Frozen 137 / 0.28.0-beta APK SHA-256: 61a9eaa0ffa733e1d9bbf5fb4066090dc933a3e9089615d7d8e6d37e3737dd5a. Native reports in docs/validation/camera-preset137/native/verdict/{phone,font1.3,landscape}/ each pass 36 checks. Representative captures are 03-adaptation.png, 05-kelvin-choice.png and 07-usb-partial-result.png. These emulator probes use synthetic presets, slots and results; they are not camera-write evidence.

REVIEW: Independent fix-list review returned SHIP after M1 (lost immediate USB parameter detail) and M2 (short-link touch widths) were corrected; no remaining item was reported in that scope.

LIMITS: Real-camera parameter/mode behaviour and colour equivalence remain unvalidated. More models, more parameters, recipe-supplied shooting recommendations and one-key restoration of original values are unimplemented. Existing global design-context drift is outside this handoff.
